import Foundation

/// Decides whether a just-typed word should be replaced, and by what.
///
/// The policy is deliberately conservative: a word that exists in any of the
/// user's languages is never touched unless it is an obvious letter swap in a
/// sentence whose language is certain, and every candidate must be a plausible
/// slip on the user's physical keyboard. When in doubt the word is kept, or
/// handed to a context arbiter as an `Ambiguity`.
///
/// Evaluation runs on a private serial queue. `speculate(_:)` evaluates the
/// word while it is being typed so the answer is usually cached by the time
/// the space bar is pressed; `decide(_:timeout:late:)` waits only briefly and
/// otherwise reports the answer later.
public final class CorrectionEngine: @unchecked Sendable {
    private let spell = SpellService()
    private let queue = DispatchQueue(label: "app.retouche.engine", qos: .userInteractive)
    private let lock = NSLock()
    private var currentConfiguration: EngineConfiguration
    private var cache: [WordContext: Decision] = [:]
    private var pendingSpeculation: WordContext?
    private var speculationScheduled = false

    public init(configuration: EngineConfiguration = EngineConfiguration()) {
        currentConfiguration = configuration
    }

    public var configuration: EngineConfiguration {
        lock.withLock { currentConfiguration }
    }

    public func update(_ configuration: EngineConfiguration) {
        lock.withLock {
            guard configuration != currentConfiguration else { return }
            currentConfiguration = configuration
            cache.removeAll()
        }
    }

    public var availableLanguages: [String] {
        spell.availableLanguages
    }

    public func warmUp() {
        let languages = configuration.languages
        queue.async { [spell] in spell.warmUp(languages: languages) }
    }

    /// Adds a word to the macOS user dictionary so neither Retouche nor any app flags it again.
    public func learn(_ word: String) {
        queue.async { [self] in
            spell.learn(word)
            lock.withLock { cache.removeAll() }
        }
    }

    public func unlearn(_ word: String) {
        queue.async { [self] in
            spell.unlearn(word)
            lock.withLock { cache.removeAll() }
        }
    }

    // MARK: - Scheduling

    public func cachedDecision(for context: WordContext) -> Decision? {
        lock.withLock { cache[context] }
    }

    /// Starts evaluating a word that is still being typed. Only the latest request is kept.
    public func speculate(_ context: WordContext) {
        let shouldSchedule: Bool = lock.withLock {
            guard cache[context] == nil else { return false }
            pendingSpeculation = context
            defer { speculationScheduled = true }
            return !speculationScheduled
        }
        guard shouldSchedule else { return }
        queue.async { [self] in
            let next: WordContext? = lock.withLock {
                defer { pendingSpeculation = nil; speculationScheduled = false }
                return pendingSpeculation
            }
            if let next, cachedDecision(for: next) == nil {
                _ = evaluateAndCache(next)
            }
        }
    }

    /// Returns the decision if it is ready within `timeout`; otherwise returns nil
    /// and delivers it later through `late`, on the engine queue.
    public func decide(_ context: WordContext, timeout: TimeInterval, late: @escaping @Sendable (Decision) -> Void) -> Decision? {
        if let cached = cachedDecision(for: context) { return cached }

        final class Handoff: @unchecked Sendable {
            let lock = NSLock()
            let semaphore = DispatchSemaphore(value: 0)
            var result: Decision?
            var abandoned = false
        }
        let handoff = Handoff()
        queue.async { [self] in
            let decision = cachedDecision(for: context) ?? evaluateAndCache(context)
            let abandoned: Bool = handoff.lock.withLock {
                handoff.result = decision
                return handoff.abandoned
            }
            if abandoned { late(decision) } else { handoff.semaphore.signal() }
        }
        _ = handoff.semaphore.wait(timeout: .now() + timeout)
        return handoff.lock.withLock {
            if let result = handoff.result { return result }
            handoff.abandoned = true
            return nil
        }
    }

    private func evaluateAndCache(_ context: WordContext) -> Decision {
        let decision = evaluate(context)
        lock.withLock {
            if cache.count > 2000 { cache.removeAll(keepingCapacity: true) }
            cache[context] = decision
        }
        return decision
    }

    // MARK: - Policy

    /// Synchronous, uncached evaluation. Safe to call from any thread.
    public func evaluate(_ context: WordContext) -> Decision {
        let configuration = self.configuration
        let word = context.word
        guard !configuration.ignoredWords.contains(word.lowercased()) else { return .keep(language: nil) }

        let detector = LanguageDetector(languages: configuration.languages, spell: spell)
        let guess = detector.detect(sentencePrefix: context.sentencePrefix, previous: context.previousLanguage)
        var language = guess.language

        if word == "i", language.hasPrefix("en") {
            return .correct(Correction(original: word, replacement: "I", language: language, source: .appleSpelling))
        }
        guard word.count >= 2, Lexicon.isEligible(word, isSentenceStart: context.isSentenceStart), !spell.hasLearned(word) else {
            return .keep(language: language)
        }

        var head = ""
        var body = word
        if language.hasPrefix("fr"), let split = Lexicon.splitElision(word) {
            head = split.head
            body = split.body
        }
        let pattern = CasePattern(body)
        let lookup = pattern == .capitalized ? body.lowercased() : body
        guard lookup.count >= 2 else { return .keep(language: language) }
        if spell.isValid(lookup, language: language) { return .keep(language: language) }

        let metric = TypoMetric(layout: configuration.layout)
        let correct = { (candidate: String, source: Correction.Source) -> Decision in
            let replacement = head + pattern.apply(to: candidate)
            guard replacement != word else { return .keep(language: language) }
            return .correct(Correction(original: word, replacement: replacement, language: language, source: source))
        }

        if lookup != body, spell.isValid(body, language: language) {
            // Only valid with its capital: either a proper noun ("Lyon") or an unaccented
            // capital that French tolerates ("Etre", "Ecole"). Fix only the latter.
            guard let apple = spell.correction(for: lookup, sentencePrefix: context.sentencePrefix, language: language),
                  TypoMetric.isOrthographicVariant(typed: lookup, candidate: apple) else { return .keep(language: language) }
            return correct(apple, .appleSpelling)
        }

        let validElsewhere = configuration.languages.contains {
            $0 != language && (spell.isValid(word, language: $0) || spell.isValid(lookup, language: $0))
        }

        var search = candidate(for: lookup, pattern: pattern, language: language, context: context, metric: metric)
        if !validElsewhere, guess.confidence < 0.75 {
            // Short or mixed sentence and a word that exists nowhere: the language whose
            // fix is clearly closer to what was typed is the one being written.
            for other in configuration.languages where other != language {
                let alternative = candidate(for: lookup, pattern: pattern, language: other, context: context, metric: metric)
                if let found = alternative.choice, found.distance + 0.3 <= (search.choice?.distance ?? .infinity) {
                    search = alternative
                    language = other
                }
            }
        }

        guard let choice = search.choice else {
            let plausible = search.plausible.map { head + pattern.apply(to: $0) }
            guard !plausible.isEmpty else { return .keep(language: language) }
            return .ambiguous(Ambiguity(word: word, candidates: plausible, language: language, sentencePrefix: context.sentencePrefix))
        }

        if validElsewhere {
            // A real word in another language the user writes in ("deja", "savior", "game").
            // Restoring accents or an apostrophe is safe in a sentence that is clearly in this
            // language; a letter swap needs a long, unambiguous sentence; anything else is left alone.
            let isVariant = TypoMetric.isOrthographicVariant(typed: lookup, candidate: choice.word)
            let isSwap = TypoMetric.isSingleTransposition(typed: lookup, candidate: choice.word)
            let fitsSentence = guess.contextWordCount < 2
                || (detector.recognizerScores(context.sentencePrefix + " " + word)[language] ?? 0) >= 0.5
            let accepted = (isVariant && guess.confidence >= 0.7 && fitsSentence)
                || (isSwap && guess.confidence >= 0.9 && guess.contextWordCount >= 3)
            guard accepted else {
                return .ambiguous(Ambiguity(word: word, candidates: [head + pattern.apply(to: choice.word)], language: language, sentencePrefix: context.sentencePrefix))
            }
        }
        return correct(choice.word, choice.source)
    }

    private struct Choice {
        var word: String
        var distance: Double
        var source: Correction.Source
    }

    /// Apple's autocorrection if it is a plausible slip, otherwise an unambiguous spelling guess.
    private func candidate(for lookup: String, pattern: CasePattern, language: String, context: WordContext, metric: TypoMetric) -> (choice: Choice?, plausible: [String]) {
        let ceiling = Self.maximumDistance(forLength: lookup.count)
        var apple: Choice?
        if let word = spell.correction(for: lookup, sentencePrefix: context.sentencePrefix, language: language), word != lookup {
            let distance = metric.distance(typed: lookup, candidate: word)
            if distance <= ceiling { apple = Choice(word: word, distance: distance, source: .appleSpelling) }
        }
        if let apple, apple.distance <= 0.5 { return (apple, []) }

        let ranked = spell.guesses(for: lookup, language: language)
            .filter { pattern == .capitalized || !($0.first?.isUppercase ?? false) }
            .enumerated()
            .map { (word: $0.element, score: metric.distance(typed: lookup, candidate: $0.element) + 0.1 * Double($0.offset)) }
            .sorted { $0.score < $1.score }
        if let apple {
            // Apple's pick is not an obvious slip ("adress" → "dress"); prefer a guess that is
            // clearly easier to explain on this keyboard ("address").
            if let better = ranked.first(where: { $0.word != apple.word }),
               metric.distance(typed: lookup, candidate: better.word) + 0.4 <= apple.distance {
                return (Choice(word: better.word, distance: metric.distance(typed: lookup, candidate: better.word), source: .keyboardModel), [])
            }
            return (apple, [])
        }
        if let best = ranked.first, best.score <= min(ceiling, 0.7) {
            let runnerUp = ranked.dropFirst().first?.score ?? .infinity
            if runnerUp - best.score >= 0.3 {
                return (Choice(word: best.word, distance: metric.distance(typed: lookup, candidate: best.word), source: .keyboardModel), [])
            }
        }
        return (nil, ranked.filter { $0.score <= ceiling }.prefix(4).map(\.word))
    }

    /// How far a candidate may be from what was typed, by length of the typed word.
    static func maximumDistance(forLength length: Int) -> Double {
        switch length {
        case ...3: 0.5
        case 4...5: 1.0
        case 6...8: 1.5
        default: 2.0
        }
    }
}
