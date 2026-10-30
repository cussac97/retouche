import AppKit

/// Thread-safe, cached access to macOS's system spell checker (AppleSpell).
///
/// This is the same engine, dictionaries and learned words that power
/// autocorrection in TextEdit, Notes and Mail. Each call is an IPC round trip
/// of 0.1–100 ms, so results are memoised.
final class SpellService: @unchecked Sendable {
    private let checker = NSSpellChecker.shared
    private let documentTag = NSSpellChecker.uniqueSpellDocumentTag()
    private let lock = NSLock()
    private var validity: [String: Bool] = [:]
    private var corrections: [String: String] = [:]
    private var guessLists: [String: [String]] = [:]
    private static let cacheLimit = 4000

    var availableLanguages: [String] {
        lock.withLock { checker.availableLanguages }
    }

    func isValid(_ word: String, language: String) -> Bool {
        let key = language + "|" + word
        return lock.withLock {
            if let cached = validity[key] { return cached }
            let range = checker.checkSpelling(of: word, startingAt: 0, language: language, wrap: false, inSpellDocumentWithTag: documentTag, wordCount: nil)
            let valid = range.location == NSNotFound || checker.hasLearnedWord(word)
            Self.store(valid, for: key, in: &validity)
            return valid
        }
    }

    /// Apple's autocorrection for `word`, or nil when it would leave the word alone.
    func correction(for word: String, sentencePrefix: String, language: String) -> String? {
        let key = language + "|" + word
        return lock.withLock {
            if let cached = corrections[key] { return cached.isEmpty ? nil : cached }
            let context = sentencePrefix.split(separator: " ").suffix(4).joined(separator: " ")
            let text = context.isEmpty ? word : context + " " + word
            let length = (word as NSString).length
            let range = NSRange(location: (text as NSString).length - length, length: length)
            let result = checker.correction(forWordRange: range, in: text, language: language, inSpellDocumentWithTag: documentTag)
            Self.store(result ?? "", for: key, in: &corrections)
            return result
        }
    }

    /// Spelling suggestions, most likely first.
    func guesses(for word: String, language: String) -> [String] {
        let key = language + "|" + word
        return lock.withLock {
            if let cached = guessLists[key] { return cached }
            let range = NSRange(location: 0, length: (word as NSString).length)
            let result = checker.guesses(forWordRange: range, in: word, language: language, inSpellDocumentWithTag: documentTag) ?? []
            Self.store(result, for: key, in: &guessLists)
            return result
        }
    }

    func hasLearned(_ word: String) -> Bool {
        lock.withLock { checker.hasLearnedWord(word) }
    }

    /// Adds the word to the user's macOS dictionary, shared with every app.
    func learn(_ word: String) {
        lock.withLock {
            checker.learnWord(word)
            validity.removeAll()
            corrections.removeAll()
        }
    }

    func unlearn(_ word: String) {
        lock.withLock {
            checker.unlearnWord(word)
            validity.removeAll()
            corrections.removeAll()
        }
    }

    /// Loads the dictionaries so the first real keystroke does not pay for it.
    func warmUp(languages: [String]) {
        for language in languages {
            _ = isValid("bonjour", language: language)
            _ = correction(for: "bonjuor", sentencePrefix: "", language: language)
            _ = guesses(for: "bonjuor", language: language)
        }
    }

    private static func store<Value>(_ value: Value, for key: String, in cache: inout [String: Value]) {
        if cache.count >= cacheLimit { cache.removeAll(keepingCapacity: true) }
        cache[key] = value
    }
}
