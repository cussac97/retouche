import RetoucheKit
import SwiftUI

extension CorrectionStrength {
    var title: String {
        switch self {
        case .cautious: "Prudente"
        case .balanced: "Équilibrée"
        case .bold: "Audacieuse"
        }
    }

    var summary: String {
        switch self {
        case .cautious: "Seulement les fautes évidentes : lettres inversées ou doublées, touche voisine, accent ou apostrophe oubliés."
        case .balanced: "Corrige aussi les mots plus abîmés quand une seule correction est plausible. Recommandé."
        case .bold: "Tente davantage de corrections, y compris les mots collés (« alot » → « a lot »). Plus de corrections, un peu plus de risques."
        }
    }
}

/// The app's own icon, grayed out while correction is paused.
struct AppIcon: View {
    var isActive: Bool
    var size: CGFloat = 28

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: size, height: size)
            .saturation(isActive ? 1 : 0)
            .opacity(isActive ? 1 : 0.6)
            .animation(.smooth, value: isActive)
    }
}

enum Symbol {
    /// Apple Intelligence's own mark, for what its model decided.
    static var intelligence: String {
        if #available(macOS 15.1, *) { "apple.intelligence" } else { "text.quote" }
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
                .font(.system(size: 13))
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
