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
        if language.hasPrefix("fr"), let phrase = Self.fusedPhrase(word, after: context.sentencePrefix) {
            return .correct(Correction(original: word, replacement: phrase, language: language, source: .keyboardModel))
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

        let tuning = Tuning.of(configuration.strength)
        // A word of another of the user's languages only loses its apostrophe before a core
        // French word ("dun" → "d'un"), never before any word ("call" is not "c'all").
        let generated = { (language: String) -> [String] in
            var candidates = language.hasPrefix("fr") && head.isEmpty ? self.elisions(of: lookup, language: language) : []
            if validElsewhere {
                candidates.removeAll { !Lexicon.elidedCoreWords.contains(String($0.drop { $0 != "'" }.dropFirst())) }
            } else if tuning.splitsWords {
                candidates += self.splits(of: lookup, language: language)
            }
            return candidates
        }
        var search = candidate(for: lookup, pattern: pattern, language: language, context: context, metric: metric, generated: generated(language), tuning: tuning)
        if !validElsewhere, guess.confidence < 0.75 {
            // Short or mixed sentence and a word that exists nowhere: the language whose
            // fix is clearly closer to what was typed is the one being written.
            for other in configuration.languages where other != language {
                let alternative = candidate(for: lookup, pattern: pattern, language: other, context: context, metric: metric, generated: generated(other), tuning: tuning)
                if let found = alternative.choice, found.distance + 0.3 <= (search.choice?.distance ?? .infinity) {
                    search = alternative
                    language = other
                }
            }
        }

        guard let choice = search.choice else {
            let plausible = search.plausible.map { head + pattern.apply(to: $0) }
            guard !plausible.isEmpty, !validElsewhere else { return .keep(language: language) }
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
                || (isSwap && guess.confidence >= tuning.swapConfidence && guess.contextWordCount >= tuning.swapContext)
            // Only an accent or a swap is worth asking about: "gentil" is never "lentil".
            guard accepted else {
                guard isVariant || isSwap else { return .keep(language: language) }
                return .ambiguous(Ambiguity(word: word, candidates: [head + pattern.apply(to: choice.word)], language: language, sentencePrefix: context.sentencePrefix))
            }
        }
        if configuration.asksContext, !search.rivals.isEmpty, case .correct(let fallback) = correct(choice.word, choice.source) {
            let candidates = ([choice.word] + search.rivals).map { head + pattern.apply(to: $0) }
            return .ambiguous(Ambiguity(word: word, candidates: candidates, language: language, sentencePrefix: context.sentencePrefix, fallback: fallback))
        }
        return correct(choice.word, choice.source)
    }

    private struct Choice {
        var word: String
        var distance: Double
        var source: Correction.Source
    }

    private struct Search {
        var choice: Choice?
        /// Other words about as easy to explain as `choice`, for a context arbiter to weigh.
        var rivals: [String] = []
        /// Without a choice: the candidates worth asking an arbiter about.
        var plausible: [String] = []
    }

    /// How much harder to explain than the engine's pick a word may be and still be worth asking about.
    private static let rivalMargin = 0.5

    /// Apple's autocorrection if it is a plausible slip, otherwise an unambiguous spelling guess.
    /// `generated` are Retouche's own candidates (elisions, split words), ranked with Apple's guesses.
    private func candidate(for lookup: String, pattern: CasePattern, language: String, context: WordContext, metric: TypoMetric, generated: [String], tuning: Tuning) -> Search {
        let ceiling = max(Self.maximumDistance(forLength: lookup.count) * tuning.ceilingScale, 0.5)
        var apple: Choice?
        if let word = spell.correction(for: lookup, sentencePrefix: context.sentencePrefix, language: language), word != lookup {
            let distance = metric.distance(typed: lookup, candidate: word)
            if distance <= ceiling { apple = Choice(word: word, distance: distance, source: .appleSpelling) }
        }
        let guesses = spell.guesses(for: lookup, language: language)
            .filter { pattern == .capitalized || !($0.first?.isUppercase ?? false) }

        // Keeping every typed letter and only adding an apostrophe or an accent ("dexemples" →
        // "d'exemples", "dun" → "d'un") explains a slip better than dropping or changing one
        // ("exemples", "duo").
        if !(apple.map { Self.restoresMarks(typed: lookup, candidate: $0.word) } ?? false),
           let marked = (guesses + generated)
               .filter({ Self.restoresMarks(typed: lookup, candidate: $0) })
               .map({ Choice(word: $0, distance: metric.distance(typed: lookup, candidate: $0), source: .keyboardModel) })
               .min(by: { $0.distance < $1.distance }),
           marked.distance <= ceiling {
            return Search(choice: marked)
        }

        // A split word ranks behind a doubled letter: "adress" is "address", not "a dress".
        let ranked = (guesses.enumerated().map { (word: $0.element, rank: 0.1 * Double($0.offset)) }
            + generated.map { (word: $0, rank: $0.contains(" ") ? 0.25 : 0.05) })
            .map { (word: $0.word, score: metric.distance(typed: lookup, candidate: $0.word) + $0.rank) }
            .sorted { $0.score < $1.score }
        // A swap or a missing accent explains a slip on its own; anything else may have rivals.
        let settled = { (choice: Choice) -> Search in
            guard !TypoMetric.isSingleTransposition(typed: lookup, candidate: choice.word),
                  !TypoMetric.isOrthographicVariant(typed: lookup, candidate: choice.word) else { return Search(choice: choice) }
            let rivals = ranked.filter {
                $0.word != choice.word && $0.score <= min(ceiling, choice.distance + Self.rivalMargin)
                    && Self.joins($0.word) == Self.joins(choice.word)
            }
            return Search(choice: choice, rivals: rivals.prefix(3).map(\.word))
        }
        if let apple, apple.distance <= tuning.obviousSlip { return settled(apple) }

        if let apple {
            // Apple's pick is not an obvious slip ("adress" → "dress"); prefer a guess that is
            // clearly easier to explain on this keyboard ("address").
            if let better = ranked.first(where: { $0.word != apple.word }),
               metric.distance(typed: lookup, candidate: better.word) + 0.4 <= apple.distance {
                return settled(Choice(word: better.word, distance: metric.distance(typed: lookup, candidate: better.word), source: .keyboardModel))
            }
            return settled(apple)
        }
        if let best = ranked.first, best.score <= min(ceiling, tuning.guessLimit) {
            let runnerUp = ranked.dropFirst().first?.score ?? .infinity
            if runnerUp - best.score >= tuning.guessLead {
                return settled(Choice(word: best.word, distance: metric.distance(typed: lookup, candidate: best.word), source: .keyboardModel))
            }
        }
        return Search(plausible: ranked.filter { $0.score <= ceiling }.prefix(4).map(\.word))
    }

    /// Same letters, with only apostrophes or accents added or changed: no new space or hyphen ("a-dress").
    private static func restoresMarks(typed: String, candidate: String) -> Bool {
        TypoMetric.isOrthographicVariant(typed: typed, candidate: candidate) && joins(candidate) == joins(typed)
    }

    /// Spaces and hyphens: "a-dress" and "a dress" are not rivals of "address".
    private static func joins(_ text: String) -> Int {
        text.filter { $0 == " " || $0 == "-" }.count
    }

    /// "dun" → "d'un", "lhomme" → "l'homme": an elided article or pronoun typed without its apostrophe.
    private func elisions(of word: String, language: String) -> [String] {
        Lexicon.elisionHeads.compactMap { head in
            guard word.count > head.count, word.hasPrefix(head) else { return nil }
            let rest = String(word.dropFirst(head.count))
            guard let first = rest.first, "aeiouyhàâäéèêëîïôöùûü".contains(first),
                  rest.count >= 2 || rest == "y", !Lexicon.informalWords.contains(rest),
                  spell.isValid(rest, language: language) else { return nil }
            return head + "'" + rest
        }
    }

    /// "alot" → "a lot", "parcontre" → "par contre": a small function word glued to its neighbour.
    /// Compounds of two content words ("username", "frontend") are left alone.
    private func splits(of word: String, language: String) -> [String] {
        let characters = Array(word)
        guard characters.count >= 4, characters.allSatisfy(\.isLetter) else { return [] }
        let functionWords = Lexicon.functionWords(for: language)
        return (1..<characters.count).compactMap { index in
            let left = String(characters[..<index])
            let right = String(characters[index...])
            guard functionWords.contains(left) || functionWords.contains(right) else { return nil }
            let isWord = { (part: String) in
                functionWords.contains(part) || (part.count >= 2 && !Lexicon.informalWords.contains(part) && self.spell.isValid(part, language: language))
            }
            return isWord(left) && isWord(right) ? left + " " + right : nil
        }
    }

    /// "il ya", "n'ya", "ilya": "y a" fused by fast typing. Alone, "ya" is deliberate slang and stays.
    private static func fusedPhrase(_ word: String, after prefix: String) -> String? {
        if let split = Lexicon.splitElision(word), split.head.dropLast().lowercased() == "n",
           let phrase = Lexicon.fusedAfterSubject[split.body] {
            return split.head + phrase
        }
        if let phrase = Lexicon.fusedAfterSubject[word], Lexicon.lastWord(of: prefix)?.lowercased() == "il" {
            return phrase
        }
        return Lexicon.fusedPhrases[word]
    }

    /// Thresholds behind each `CorrectionStrength`.
    private struct Tuning {
        /// Scales how far a candidate may be from what was typed.
        var ceilingScale: Double
        /// Apple's pick is taken outright at or under this distance.
        var obviousSlip: Double
        /// Without Apple's pick, the best guess must score under `guessLimit` and lead the next by `guessLead`.
        var guessLimit: Double
        var guessLead: Double
        /// A letter swap that makes a word of another of the user's languages needs this much certainty.
        var swapConfidence: Double
        var swapContext: Int
        var splitsWords: Bool

        static func of(_ strength: CorrectionStrength) -> Tuning {
            switch strength {
            case .cautious:
                Tuning(ceilingScale: 0.75, obviousSlip: 0.45, guessLimit: 0.5, guessLead: 0.4, swapConfidence: 0.95, swapContext: 4, splitsWords: false)
            case .balanced:
                Tuning(ceilingScale: 1, obviousSlip: 0.5, guessLimit: 0.7, guessLead: 0.3, swapConfidence: 0.9, swapContext: 3, splitsWords: false)
            case .bold:
                Tuning(ceilingScale: 1.3, obviousSlip: 0.6, guessLimit: 1.0, guessLead: 0.2, swapConfidence: 0.8, swapContext: 2, splitsWords: true)
            }
        }
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
