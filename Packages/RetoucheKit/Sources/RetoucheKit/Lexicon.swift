import Foundation

/// Character classes and word-level heuristics shared by the session and the engine.
enum Lexicon {
    static let apostrophes: Set<Character> = ["'", "’"]
    static let openingPunctuation: Set<Character> = ["«", "‹", "(", "[", "{", "\"", "'", "“", "‘", "¿", "¡", "*", "_"]
    static let closingPunctuation: Set<Character> = ["»", "›", ")", "]", "}", "\"", "'", "”", "’", ".", ",", ";", ":", "!", "?", "…", "*", "_"]
    static let sentenceTerminators: Set<Character> = [".", "!", "?", "…", "\n", "\r"]

    /// Whitespace that ends a word and triggers a correction.
    static func isBoundary(_ character: Character) -> Bool {
        switch character {
        case " ", "\u{00A0}", "\u{202F}", "\n", "\r", "\t": true
        default: false
        }
    }

    static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || apostrophes.contains(character) || character == "-"
    }

    static let elisionHeads: Set<String> = [
        "l", "d", "j", "m", "t", "s", "c", "n", "qu", "jusqu", "lorsqu", "puisqu", "quoiqu",
    ]

    /// "il y a" and friends, fused by fast typing.
    static let fusedPhrases: [String: String] = [
        "ilya": "il y a", "ilyen": "il y en", "ilyavait": "il y avait", "ilyaura": "il y aura", "ilyaurait": "il y aurait",
    ]

    /// The same without "il". Alone they are deliberate slang ("ya un souci");
    /// after "il" or "n'" they are a missing space ("il ya", "n'ya").
    static let fusedAfterSubject: [String: String] = [
        "ya": "y a", "yen": "y en", "yavait": "y avait", "yaura": "y aura", "yaurait": "y aurait",
    ]

    /// Words so common after an elided article or pronoun that "dun" is "d'un" even though "dun" is English.
    static let elidedCoreWords: Set<String> = [
        "un", "une", "il", "ils", "elle", "elles", "en", "y", "on", "ai", "as", "a", "est", "es", "était", "avait",
        "ont", "avoir", "être", "autre", "autres", "eux", "abord", "accord", "habitude", "ici",
    ]

    /// Short grammatical words that people glue to the next or previous word ("alot", "parcontre").
    static func functionWords(for language: String) -> Set<String> {
        language.hasPrefix("fr")
            ? ["a", "à", "y", "de", "du", "des", "la", "le", "les", "un", "une", "en", "et", "ou", "par", "pour", "sur",
               "dans", "avec", "sans", "ne", "pas", "que", "qui", "se", "ce", "il", "on", "je", "tu", "me", "te", "plus", "tout"]
            : ["a", "i", "an", "the", "of", "to", "in", "on", "at", "as", "is", "it", "be", "by", "for", "and", "or",
               "so", "not", "each", "any", "some", "every", "all", "up", "no"]
    }

    /// The last word of `text`, if any.
    static func lastWord(of text: String) -> String? {
        text.split(whereSeparator: { !isWordCharacter($0) }).last.map(String.init)
    }

    /// Splits a French elision such as "l'appartemnet" into "l'" and "appartemnet".
    static func splitElision(_ word: String) -> (head: String, body: String)? {
        guard let index = word.firstIndex(where: { apostrophes.contains($0) }) else { return nil }
        guard elisionHeads.contains(word[..<index].lowercased()) else { return nil }
        let body = word[word.index(after: index)...]
        guard !body.isEmpty else { return nil }
        return (String(word[...index]), String(body))
    }

    /// Abbreviations, interjections and slang people type on purpose.
    static let informalWords: Set<String> = [
        // French
        "mdr", "ptdr", "jpp", "jsp", "jsuis", "chui", "stp", "svp", "bcp", "tkt", "tqt", "pk", "pq", "pcq",
        "slt", "cc", "dsl", "rdv", "msg", "bjr", "bsr", "mrc", "jtm", "oklm", "wesh", "ouais", "ouai", "nan",
        "bah", "beh", "hein", "euh", "ah", "oh", "eh", "hmm", "mmh", "mouais", "ptn", "tg", "vrmt",
        "jcrois", "jvais", "jpense", "chais", "ya", "yen", "ok", "okay", "okk", "oki", "dacc", "dac", "re",
        "auj", "ajd", "pr", "ds", "tt", "tte", "tts", "qq", "qqn", "qqch", "cad", "ex", "etc",
        // English
        "btw", "imo", "imho", "tbh", "omg", "wtf", "asap", "idk", "fyi", "lmk", "brb", "afaik", "irl", "thx",
        "pls", "plz", "ty", "np", "gg", "yep", "nope", "yeah", "yup", "ugh", "lmao", "rofl", "ikr", "smh",
        "tho", "gonna", "wanna", "gotta", "kinda", "sorta", "dunno", "lol", "haha", "hehe", "ok",
    ]

    /// True for "noooon", "ouiiii", "mdrrrr": stretched words are intentional.
    static func hasExpressiveRepetition(_ word: String) -> Bool {
        let characters = Array(word.lowercased())
        guard characters.count > 2 else { return false }
        var run = 1
        for index in 1..<characters.count {
            run = characters[index] == characters[index - 1] ? run + 1 : 1
            if run >= 4 { return true }
            if run == 3, "aeiouyéèêàùîôû".contains(characters[index]) || index == characters.count - 1 { return true }
        }
        return false
    }

    /// Words we never try to correct: acronyms, camelCase, names mid-sentence, numbers, slang.
    static func isEligible(_ word: String, isSentenceStart: Bool) -> Bool {
        guard word.count <= 32, word.allSatisfy(isWordCharacter), !word.contains(where: \.isNumber) else { return false }
        guard let first = word.first, first.isLetter, let last = word.last, last.isLetter else { return false }
        let letterCount = word.filter(\.isLetter).count
        switch CasePattern(word) {
        case .upper where letterCount >= 2: return false
        case .mixed: return false
        case .capitalized where !isSentenceStart: return false
        default: break
        }
        if informalWords.contains(word.lowercased()) || hasExpressiveRepetition(word) { return false }
        return true
    }
}

enum CasePattern: Equatable {
    case lower, capitalized, upper, mixed

    init(_ text: String) {
        let letters = text.filter(\.isLetter)
        guard let first = letters.first else { self = .lower; return }
        if letters.allSatisfy(\.isLowercase) {
            self = .lower
        } else if letters.count > 1, letters.allSatisfy(\.isUppercase) {
            self = .upper
        } else if first.isUppercase, letters.dropFirst().allSatisfy(\.isLowercase) {
            self = .capitalized
        } else {
            self = .mixed
        }
    }

    func apply(to candidate: String) -> String {
        switch self {
        case .capitalized: candidate.prefix(1).uppercased() + candidate.dropFirst()
        case .upper: candidate.uppercased()
        case .lower, .mixed: candidate
        }
    }
}
