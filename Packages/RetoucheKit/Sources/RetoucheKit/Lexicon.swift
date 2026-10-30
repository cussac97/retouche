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

    private static let elisionHeads: Set<String> = [
        "l", "d", "j", "m", "t", "s", "c", "n", "qu", "jusqu", "lorsqu", "puisqu", "quoiqu",
    ]

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
