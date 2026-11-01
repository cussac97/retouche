import AppKit

/// How each letter travels when the typed word becomes its correction.
///
/// Letters common to both words, in order, slide to their new place; a letter that changed
/// place (a transposition) hops over the others; missing letters drop in, extra ones fall away.
struct LetterMorph: Sendable {
    enum Motion: Sendable {
        case slide, hop, enter, leave
    }

    struct Letter: Identifiable, Sendable {
        let id: Int
        let character: String
        let motion: Motion
        /// Horizontal positions in the typed word and in the correction.
        let from: CGFloat
        let to: CGFloat
        /// Share of the animation to wait before moving, for staggered entries.
        let delay: Double
    }

    let letters: [Letter]
    /// Width of the wider of the two words.
    let width: CGFloat

    init(from original: String, to replacement: String, font: NSFont) {
        let typed = Array(original)
        let corrected = Array(replacement)
        let typedX = Self.offsets(typed, font: font)
        let correctedX = Self.offsets(corrected, font: font)

        var slides = Self.commonSubsequence(typed, corrected)
        var targets = Set(corrected.indices).subtracting(slides.values)
        var hops: [Int: Int] = [:]
        for index in typed.indices where slides[index] == nil {
            let candidates = targets.filter { corrected[$0] == typed[index] }
            guard let target = candidates.min(by: { abs($0 - index) < abs($1 - index) }) else { continue }
            hops[index] = target
            targets.remove(target)
        }

        var letters: [Letter] = []
        for (index, character) in typed.enumerated() {
            let from = typedX[index]
            if let target = slides.removeValue(forKey: index) {
                letters.append(Letter(id: letters.count, character: String(character), motion: .slide, from: from, to: correctedX[target], delay: 0))
            } else if let target = hops[index] {
                letters.append(Letter(id: letters.count, character: String(character), motion: .hop, from: from, to: correctedX[target], delay: 0))
            } else {
                letters.append(Letter(id: letters.count, character: String(character), motion: .leave, from: from, to: from, delay: 0))
            }
        }
        for (rank, index) in targets.sorted().enumerated() {
            let x = correctedX[index]
            letters.append(Letter(id: letters.count, character: String(corrected[index]), motion: .enter, from: x, to: x, delay: min(Double(rank) * 0.08, 0.3)))
        }
        self.letters = letters
        width = max(typedX.last ?? 0, correctedX.last ?? 0)
    }

    /// Left edge of each character, followed by the total width.
    private static func offsets(_ characters: [Character], font: NSFont) -> [CGFloat] {
        var x: CGFloat = 0
        var result = [x]
        for character in characters {
            x += (String(character) as NSString).size(withAttributes: [.font: font]).width
            result.append(x)
        }
        return result
    }

    /// Longest common subsequence, as typed index → corrected index.
    private static func commonSubsequence(_ a: [Character], _ b: [Character]) -> [Int: Int] {
        var lengths = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in a.indices.reversed() {
            for j in b.indices.reversed() {
                lengths[i][j] = a[i] == b[j] ? lengths[i + 1][j + 1] + 1 : max(lengths[i + 1][j], lengths[i][j + 1])
            }
        }
        var pairs: [Int: Int] = [:]
        var i = 0
        var j = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                pairs[i] = j
                i += 1
                j += 1
            } else if lengths[i + 1][j] >= lengths[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return pairs
    }
}
