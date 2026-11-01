import SwiftUI

struct OverlayView: View {
    let model: OverlayModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let content = model.content {
                FloatingWord(content: content, lift: model.lift, progress: model.progress, land: model.land)
                    .offset(x: content.margin, y: content.margin)
                    .id(content.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The typed word, lifted just above the line, rearranging into the correction before it lands on it.
private struct FloatingWord: View {
    let content: OverlayModel.Content
    let lift: Double
    let progress: Double
    let land: Double

    var body: some View {
        let font = Font(OverlayModel.font(size: content.fontSize, monospaced: content.isMonospaced) as CTFont)
        let height = lift - land
        let halo = Color(nsColor: .textBackgroundColor)
        ZStack(alignment: .leading) {
            ForEach(content.morph.letters) { letter in
                Text(letter.character)
                    .font(font)
                    .foregroundStyle(letter.motion == .leave ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                    .fixedSize()
                    .modifier(LetterMotion(progress: progress, letter: letter, em: content.fontSize, width: content.size.width))
            }
        }
        .frame(width: content.size.width, height: content.size.height, alignment: .leading)
        // Keeps the letters legible over the text they float across.
        .shadow(color: halo, radius: 1)
        .shadow(color: halo, radius: 2)
        .scaleEffect(1 + 0.06 * height, anchor: .bottomLeading)
        .offset(y: -content.rise * height)
        .opacity(min(lift, 1) * (1 - land))
    }
}

/// Places one letter along its path; `progress` runs from the typed word (0) to the correction (1).
private struct LetterMotion: ViewModifier, Animatable {
    var progress: Double
    let letter: LetterMorph.Letter
    let em: CGFloat
    let width: CGFloat

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        // Springs overshoot past 1: horizontal travel keeps it, the rest settles.
        let travel = max(0, (progress - letter.delay) / (1 - letter.delay))
        let t = min(travel, 1)
        let arc = sin(.pi * t)
        let direction: Double = letter.to >= letter.from ? 1 : -1
        var x = letter.from + (letter.to - letter.from) * travel
        var y: CGFloat = 0
        var opacity = 1.0
        var blur: CGFloat = 0
        var scale: CGFloat = 1
        var angle = 0.0
        switch letter.motion {
        case .slide:
            // A ripple runs through the word from left to right.
            let start = 0.4 * Double(letter.to / max(width, 1))
            let ripple = sin(.pi * min(max((progress - start) / 0.5, 0), 1))
            y = -ripple * em * 0.22
        case .hop:
            y = -arc * em * 0.9
            scale = 1 + 0.3 * arc
            angle = arc * 14 * direction
        case .enter:
            y = -(1 - t) * em * 1.2
            opacity = t
            blur = (1 - t) * 3
            scale = 0.5 + 0.5 * t
        case .leave:
            x = letter.from
            y = t * em * 0.9
            opacity = max(0, 1 - t * 1.6)
            blur = t * 3
            scale = 1 - 0.45 * t
            angle = t * 18
        }
        return content
            .scaleEffect(scale)
            .rotationEffect(.degrees(angle))
            .blur(radius: blur)
            .opacity(opacity)
            .offset(x: x, y: y)
    }
}
