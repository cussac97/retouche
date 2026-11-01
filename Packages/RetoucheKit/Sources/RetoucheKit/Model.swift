import Foundation

/// Everything the engine needs to judge a word the user just finished typing.
public struct WordContext: Hashable, Sendable {
    /// The word as typed, without surrounding punctuation.
    public var word: String
    /// Text of the current sentence before the word, used for language detection.
    public var sentencePrefix: String
    /// True when the word opens a sentence, so a capital letter is not a hint of a proper noun.
    public var isSentenceStart: Bool
    /// Language of the previous decision in the same text, a tie-breaker for short sentences.
    public var previousLanguage: String?

    public init(word: String, sentencePrefix: String = "", isSentenceStart: Bool = false, previousLanguage: String? = nil) {
        self.word = word
        self.sentencePrefix = sentencePrefix
        self.isSentenceStart = isSentenceStart
        self.previousLanguage = previousLanguage
    }
}

public struct Correction: Hashable, Sendable {
    public enum Source: String, Hashable, Sendable {
        /// Apple's own autocorrection candidate (NSSpellChecker).
        case appleSpelling
        /// A spelling guess that our keyboard-aware model found unambiguous.
        case keyboardModel
        /// Picked among candidates by the on-device Apple Intelligence model.
        case appleIntelligence
    }

    public var original: String
    public var replacement: String
    /// NSSpellChecker language identifier, e.g. "fr" or "en_GB".
    public var language: String
    public var source: Source

    public init(original: String, replacement: String, language: String, source: Source) {
        self.original = original
        self.replacement = replacement
        self.language = language
        self.source = source
    }
}

/// A misspelled word with several plausible fixes, left to a context-aware arbiter.
public struct Ambiguity: Hashable, Sendable {
    public var word: String
    public var candidates: [String]
    public var language: String
    public var sentencePrefix: String
    /// The engine's own pick when it has one: applied if no arbiter answers. With a
    /// fallback the arbiter only chooses among `candidates`; without one it may keep the word.
    public var fallback: Correction?

    public init(word: String, candidates: [String], language: String, sentencePrefix: String, fallback: Correction? = nil) {
        self.word = word
        self.candidates = candidates
        self.language = language
        self.sentencePrefix = sentencePrefix
        self.fallback = fallback
    }

    /// The correction to apply once the arbiter chose `choice` (nil: no answer, or keep the word).
    public func correction(choosing choice: String?) -> Correction? {
        guard let choice, choice != fallback?.replacement else { return fallback }
        return Correction(original: word, replacement: choice, language: language, source: .appleIntelligence)
    }
}

public enum Decision: Hashable, Sendable {
    case keep(language: String?)
    case correct(Correction)
    case ambiguous(Ambiguity)

    public var language: String? {
        switch self {
        case .keep(let language): language
        case .correct(let correction): correction.language
        case .ambiguous(let ambiguity): ambiguity.language
        }
    }
}

/// How readily the engine replaces a word it does not know.
public enum CorrectionStrength: String, CaseIterable, Hashable, Sendable {
    /// Only clear slips: swapped or doubled letters, a neighbouring key, accents, apostrophes.
    case cautious
    case balanced
    /// Also less certain guesses, and two words typed without the space ("alot" → "a lot").
    case bold
}

public struct EngineConfiguration: Hashable, Sendable {
    /// NSSpellChecker language identifiers, primary language first.
    public var languages: [String]
    public var layout: KeyboardLayout
    /// Lowercased words the user does not want corrected.
    public var ignoredWords: Set<String>
    public var strength: CorrectionStrength
    /// A context arbiter will be consulted: when another word is about as easy to explain
    /// as the engine's pick ("cafr": "car" or "café"), report an `Ambiguity` with that pick as fallback.
    public var asksContext: Bool

    public init(languages: [String] = ["fr", "en"], layout: KeyboardLayout = .azerty, ignoredWords: Set<String> = [], strength: CorrectionStrength = .balanced, asksContext: Bool = false) {
        self.languages = languages.isEmpty ? ["en"] : languages
        self.layout = layout
        self.ignoredWords = ignoredWords
        self.strength = strength
        self.asksContext = asksContext
    }
}
