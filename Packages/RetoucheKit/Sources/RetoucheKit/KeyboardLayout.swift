import Foundation

/// Physical letter layout, used to tell a fat-finger slip from an unrelated letter.
public enum KeyboardLayout: String, CaseIterable, Codable, Hashable, Sendable {
    case azerty, qwerty, qwertz

    /// Maps a Text Input Source identifier such as "com.apple.keylayout.French" to its letter layout.
    public static func inferred(fromInputSourceID identifier: String) -> KeyboardLayout {
        let id = identifier.lowercased()
        if id.contains("canadian") { return .qwerty }
        if ["swiss", "german", "austrian", "czech", "hungarian", "slovak", "slovenian", "croatian"].contains(where: id.contains) {
            return .qwertz
        }
        if id.contains("french") || id.contains("belgian") { return .azerty }
        return .qwerty
    }

    public var displayName: String {
        switch self {
        case .azerty: "AZERTY"
        case .qwerty: "QWERTY"
        case .qwertz: "QWERTZ"
        }
    }

    func areAdjacent(_ a: Character, _ b: Character) -> Bool {
        guard a != b, let table = Self.positions[self], let pa = table[a], let pb = table[b] else { return false }
        let dx = pa.x - pb.x
        let dy = pa.y - pb.y
        return dx * dx + dy * dy <= 1.3 * 1.3
    }

    private struct Point { var x: Double; var y: Double }

    private var rows: [String] {
        switch self {
        case .azerty: ["azertyuiop", "qsdfghjklm", "wxcvbn"]
        case .qwerty: ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
        case .qwertz: ["qwertzuiop", "asdfghjkl", "yxcvbnm"]
        }
    }

    /// Key centers in key-width units, with the usual row stagger.
    private static let positions: [KeyboardLayout: [Character: Point]] = {
        let rowOffsets = [0.0, 0.25, 0.75]
        var result: [KeyboardLayout: [Character: Point]] = [:]
        for layout in KeyboardLayout.allCases {
            var table: [Character: Point] = [:]
            for (row, keys) in layout.rows.enumerated() {
                for (column, key) in keys.enumerated() {
                    table[key] = Point(x: Double(column) + rowOffsets[row], y: Double(row))
                }
            }
            result[layout] = table
        }
        return result
    }()
}
