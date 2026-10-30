import SwiftUI

struct AppGlyph: View {
    var isActive: Bool
    var size: CGFloat = 30

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(isActive ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.secondary.opacity(0.35)))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "character.cursor.ibeam")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: isActive ? Color.accentColor.opacity(0.35) : .clear, radius: 6, y: 2)
            .animation(.smooth, value: isActive)
    }
}

struct StatTile: View {
    var value: String
    var label: String
    var systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.gradient)
                Text(value)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                    .lineLimit(1)
            }
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.045)))
    }
}

struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuRowButton(configuration: configuration)
    }

    private struct MenuRowButton: View {
        let configuration: Configuration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .font(.system(size: 12.5))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(isHovered || configuration.isPressed ? 0.08 : 0)))
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
        }
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 20)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(configuration.isPressed ? 0.14 : 0.07)))
            .contentShape(Rectangle())
    }
}

enum LanguageName {
    /// "Français", "English (UK)"…
    static func full(_ identifier: String) -> String {
        let name = Locale.current.localizedString(forIdentifier: identifier) ?? identifier
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// "FR", "EN"
    static func short(_ identifier: String) -> String {
        String(identifier.prefix(2)).uppercased()
    }
}
