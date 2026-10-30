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

    public init(word: String, candidates: [String], language: String, sentencePrefix: String) {
        self.word = word
        self.candidates = candidates
        self.language = language
        self.sentencePrefix = sentencePrefix
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

public struct EngineConfiguration: Hashable, Sendable {
    /// NSSpellChecker language identifiers, primary language first.
    public var languages: [String]
    public var layout: KeyboardLayout
    /// Lowercased words the user does not want corrected.
    public var ignoredWords: Set<String>

    public init(languages: [String] = ["fr", "en"], layout: KeyboardLayout = .azerty, ignoredWords: Set<String> = []) {
        self.languages = languages.isEmpty ? ["en"] : languages
        self.layout = layout
        self.ignoredWords = ignoredWords
    }
}
