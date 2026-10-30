import SwiftUI

struct OverlayView: View {
    let model: OverlayModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let content = model.content {
                if let highlight = content.highlight {
                    WordHighlight(isVisible: model.isVisible, isHighlighted: model.isHighlighted)
                        .frame(width: highlight.width, height: highlight.height)
                        .offset(x: highlight.minX, y: highlight.minY)
                }
                CorrectionPill(content: content, isRevealed: model.isRevealed)
                    .fixedSize()
                    .alignmentGuide(.leading) { dimensions in
                        content.pillAlignment == .top ? dimensions.width / 2 : 0
                    }
                    .alignmentGuide(.top) { dimensions in
                        content.pillAlignment == .bottomLeading ? dimensions.height : 0
                    }
                    .offset(x: content.pillOrigin.x, y: content.pillOrigin.y)
                    .opacity(model.isVisible ? 1 : 0)
                    .scaleEffect(model.isVisible ? 1 : 0.86, anchor: content.pillAlignment == .bottomLeading ? .bottomLeading : .topLeading)
                    .offset(y: model.isVisible ? 0 : (content.pillAlignment == .bottomLeading ? 6 : -6))
                    .id(content.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A soft tint over the corrected word that fades out, like the iOS keyboard.
private struct WordHighlight: View {
    var isVisible: Bool
    var isHighlighted: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        shape
            .fill(Color.accentColor.opacity(isHighlighted ? 0.22 : 0))
            .overlay(shape.strokeBorder(Color.accentColor.opacity(isHighlighted ? 0.55 : 0), lineWidth: 1))
            .shadow(color: Color.accentColor.opacity(isHighlighted ? 0.45 : 0), radius: 8)
            .scaleEffect(isVisible ? 1 : 1.25)
            .opacity(isVisible ? 1 : 0)
    }
}

private struct CorrectionPill: View {
    let content: OverlayModel.Content
    let isRevealed: Bool

    var body: some View {
        HStack(spacing: 6) {
            if content.usesIntelligence {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.gradient)
            }
            Text(content.original)
                .strikethrough(isRevealed, color: .secondary)
                .foregroundStyle(.secondary)
                .opacity(isRevealed ? 0.55 : 1)
            Image(systemName: "arrow.forward")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.tertiary)
                .opacity(isRevealed ? 1 : 0)
                .scaleEffect(isRevealed ? 1 : 0.5)
            RevealingText(text: content.replacement, isRevealed: isRevealed)
            Text(content.language)
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(.quaternary))
                .foregroundStyle(.secondary)
            Image(systemName: "delete.left")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.tertiary)
                .help("Appuyez sur ⌫ pour annuler")
        }
        .font(.system(size: 13, weight: .medium, design: .rounded))
        .padding(.leading, 11)
        .padding(.trailing, 9)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.gradient.opacity(0.4), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
    }
}

/// The corrected word, materialising letter by letter.
private struct RevealingText: View {
    let text: String
    let isRevealed: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { index, character in
                Text(String(character))
                    .opacity(isRevealed ? 1 : 0)
                    .blur(radius: isRevealed ? 0 : 4)
                    .offset(y: isRevealed ? 0 : 5)
                    .animation(.spring(response: 0.34, dampingFraction: 0.8).delay(Double(index) * 0.022), value: isRevealed)
            }
        }
        .fontWeight(.semibold)
        .foregroundStyle(Theme.gradient)
    }
}

enum Theme {
    static let gradient = LinearGradient(
        colors: [Color(red: 0.24, green: 0.48, blue: 1.0), Color(red: 0.56, green: 0.36, blue: 0.98)],
        startPoint: .leading,
        endPoint: .trailing
    )
}
