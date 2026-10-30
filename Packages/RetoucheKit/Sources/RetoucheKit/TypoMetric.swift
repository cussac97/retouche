import Foundation

/// Weighted Damerau–Levenshtein distance tuned for typing slips.
///
/// Swapped letters, missing accents, doubled letters and neighbouring keys are
/// cheap; replacing a letter with one across the keyboard is expensive. A
/// distance under 0.5 is an "obvious" typo, above 1.5 a different word.
public struct TypoMetric: Sendable {
    public var layout: KeyboardLayout

    public init(layout: KeyboardLayout) {
        self.layout = layout
    }

    enum Cost {
        static let accent = 0.2
        static let separatorInsertion = 0.25
        static let separatorDeletion = 0.3
        static let doubledLetter = 0.35
        static let transposition = 0.45
        static let neighbourKey = 0.6
        static let otherInsertion = 0.85
        static let otherSubstitution = 1.0
    }

    public func distance(typed: String, candidate: String) -> Double {
        let a = Self.normalized(typed)
        let b = Self.normalized(candidate)
        let fa = a.map(Self.folded)
        let fb = b.map(Self.folded)
        let n = a.count
        let m = b.count
        if n == 0 { return (0..<m).reduce(0) { $0 + insertionCost(fb, $1) } }
        if m == 0 { return (0..<n).reduce(0) { $0 + deletionCost(fa, $1) } }

        var d = Array(repeating: Array(repeating: 0.0, count: m + 1), count: n + 1)
        for i in 1...n { d[i][0] = d[i - 1][0] + deletionCost(fa, i - 1) }
        for j in 1...m { d[0][j] = d[0][j - 1] + insertionCost(fb, j - 1) }
        for i in 1...n {
            for j in 1...m {
                var best = d[i - 1][j - 1] + substitutionCost(a[i - 1], b[j - 1], fa[i - 1], fb[j - 1])
                best = min(best, d[i - 1][j] + deletionCost(fa, i - 1))
                best = min(best, d[i][j - 1] + insertionCost(fb, j - 1))
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1], a[i - 1] != a[i - 2] {
                    best = min(best, d[i - 2][j - 2] + Cost.transposition)
                }
                d[i][j] = best
            }
        }
        return d[n][m]
    }

    /// True when `candidate` is `typed` with exactly two neighbouring letters swapped.
    public static func isSingleTransposition(typed: String, candidate: String) -> Bool {
        let a = normalized(typed)
        let b = normalized(candidate)
        guard a.count == b.count else { return false }
        let diffs = a.indices.filter { a[$0] != b[$0] }
        guard diffs.count == 2, diffs[1] == diffs[0] + 1 else { return false }
        return a[diffs[0]] == b[diffs[1]] && a[diffs[1]] == b[diffs[0]]
    }

    /// True when the two spellings differ only by accents, apostrophes, hyphens or spaces:
    /// "deja" → "déjà", "jai" → "j'ai", "dont" → "don't", "parceque" → "parce que".
    public static func isOrthographicVariant(typed: String, candidate: String) -> Bool {
        let a = normalized(typed)
        let b = normalized(candidate)
        guard a != b else { return false }
        let skeleton: ([Character]) -> [Character] = { $0.filter { !isSeparator($0) }.map(folded) }
        return skeleton(a) == skeleton(b)
    }

    // MARK: - Costs

    private func substitutionCost(_ x: Character, _ y: Character, _ fx: Character, _ fy: Character) -> Double {
        if x == y { return 0 }
        if fx == fy { return Cost.accent }
        if Self.isSeparator(fx) && Self.isSeparator(fy) { return Cost.separatorDeletion }
        if layout.areAdjacent(fx, fy) { return Cost.neighbourKey }
        return Cost.otherSubstitution
    }

    /// Cost of a character that was typed but does not belong to the candidate.
    private func deletionCost(_ typed: [Character], _ i: Int) -> Double {
        let c = typed[i]
        if Self.isSeparator(c) { return Cost.separatorDeletion }
        let previous = i > 0 ? typed[i - 1] : nil
        let next = i + 1 < typed.count ? typed[i + 1] : nil
        if previous == c || next == c { return Cost.doubledLetter }
        if let previous, layout.areAdjacent(previous, c) { return Cost.neighbourKey }
        if let next, layout.areAdjacent(c, next) { return Cost.neighbourKey }
        return Cost.otherInsertion
    }

    /// Cost of a candidate character the user did not type.
    private func insertionCost(_ candidate: [Character], _ j: Int) -> Double {
        let c = candidate[j]
        if Self.isSeparator(c) { return Cost.separatorInsertion }
        let previous = j > 0 ? candidate[j - 1] : nil
        let next = j + 1 < candidate.count ? candidate[j + 1] : nil
        if previous == c || next == c { return Cost.doubledLetter }
        return Cost.otherInsertion
    }

    // MARK: - Normalisation

    private static func isSeparator(_ c: Character) -> Bool {
        c == "'" || c == "-" || c == " "
    }

    static func normalized(_ text: String) -> [Character] {
        var result: [Character] = []
        for character in text.lowercased() {
            switch character {
            case "œ": result.append(contentsOf: ["o", "e"])
            case "æ": result.append(contentsOf: ["a", "e"])
            case "’", "‘": result.append("'")
            default: result.append(character)
            }
        }
        return result
    }

    private static func folded(_ c: Character) -> Character {
        String(c).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).first ?? c
    }
}
