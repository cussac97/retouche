import AppKit
import RetoucheKit
import SwiftUI

/// Plays the correction with the word's own letters, in any app, in under a second: they lift off
/// the line, rearrange into the correction, then land on the corrected word and melt into it.
@MainActor
final class OverlayController {
    private let model = OverlayModel()
    private var panel: NSPanel?
    private var sequence: Task<Void, Never>?

    /// Without an anchor the app shows no text geometry at all; the menu bar icon's bounce is then the only feedback.
    func show(_ correction: Correction, at anchor: TextAnchor?) {
        let reducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard let anchor, let layout = Self.layout(correction, at: anchor, reducesMotion: reducesMotion) else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel

        panel.setFrame(layout.frame, display: false)
        sequence?.cancel()
        model.reset(layout.content, settled: reducesMotion)
        panel.orderFrontRegardless()

        sequence = Task { [model] in
            withAnimation(.spring(duration: 0.24, bounce: 0.3)) { model.lift = 1 }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(duration: 0.5, bounce: 0.28)) { model.progress = 1 }
            try? await Task.sleep(for: .milliseconds(560))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) { model.land = 1 }
            try? await Task.sleep(for: .milliseconds(230))
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }

    func dismiss() {
        sequence?.cancel()
        withAnimation(.easeIn(duration: 0.12)) { model.land = 1 }
        let panel = panel
        Task {
            try? await Task.sleep(for: .milliseconds(140))
            panel?.orderOut(nil)
        }
    }

    // MARK: - Layout

    private struct Layout {
        var frame: CGRect
        var content: OverlayModel.Content
    }

    /// Lands on the word when its bounds are known or estimated; below the field when only the field is.
    private static func layout(_ correction: Correction, at anchor: TextAnchor, reducesMotion: Bool) -> Layout? {
        let rect = cocoaRect(anchor.rect)
        let isField = anchor.precision == .field
        let fontSize = isField ? 13 : fittedFontSize(correction.replacement, in: rect, monospaced: anchor.isMonospaced)
        let font = OverlayModel.font(size: fontSize, monospaced: anchor.isMonospaced)
        let content = OverlayModel.Content(
            original: correction.original,
            replacement: correction.replacement,
            fontSize: fontSize,
            isMonospaced: anchor.isMonospaced,
            minimumWidth: anchor.precision == .word ? rect.width : 0,
            lineHeight: isField ? ceil(font.ascender - font.descender) + 2 : rect.height,
            reducesMotion: reducesMotion
        )
        var word = CGRect(origin: rect.origin, size: content.size)
        if isField { word.origin = CGPoint(x: rect.minX + 6, y: rect.minY - content.size.height - 4) }
        guard NSScreen.screens.contains(where: { $0.frame.intersects(word) }) else { return nil }
        return Layout(frame: word.insetBy(dx: -content.margin, dy: -content.margin), content: content)
    }

    /// The size at which `word` spans the real word's width, within what its line height allows.
    private static func fittedFontSize(_ word: String, in rect: CGRect, monospaced: Bool) -> CGFloat {
        let reference: CGFloat = 20
        let width = (word as NSString).size(withAttributes: [.font: OverlayModel.font(size: reference, monospaced: monospaced)]).width
        guard width > 0 else { return rect.height * 0.75 }
        return min(max(reference * rect.width / width, rect.height * 0.55), rect.height * 0.9)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 200, height: 80), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let hosting = NSHostingView(rootView: OverlayView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
        return panel
    }

    private static func cocoaRect(_ rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

@MainActor
@Observable
final class OverlayModel {
    struct Content: Equatable {
        var id = UUID()
        var morph: LetterMorph
        var fontSize: CGFloat
        var isMonospaced: Bool
        /// The real word's size: the letters land exactly there.
        var size: CGSize
        /// How far above the line the letters float while they rearrange.
        var rise: CGFloat
        /// Room around the word for letters that rise, hop or drop in.
        var margin: CGFloat

        init(original: String, replacement: String, fontSize: CGFloat, isMonospaced: Bool, minimumWidth: CGFloat, lineHeight: CGFloat, reducesMotion: Bool = false) {
            morph = LetterMorph(from: original, to: replacement, font: OverlayModel.font(size: fontSize, monospaced: isMonospaced))
            self.fontSize = fontSize
            self.isMonospaced = isMonospaced
            size = CGSize(width: ceil(max(minimumWidth, morph.width)), height: lineHeight)
            rise = reducesMotion ? 0 : lineHeight * 1.1
            margin = ceil(max(24, lineHeight * 2.6))
        }

        static func == (lhs: Content, rhs: Content) -> Bool { lhs.id == rhs.id }
    }

    var content: Content?
    /// The three phases, each from 0 to 1: the typed word lifts off the line,
    /// rearranges into the correction, then lands on it.
    var lift = 0.0
    var progress = 0.0
    var land = 0.0

    /// `settled` skips the rearranging, for Reduce Motion.
    func reset(_ content: Content, settled: Bool = false) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            self.content = content
            lift = 0
            progress = settled ? 1 : 0
            land = 0
        }
    }

    nonisolated static func font(size: CGFloat, monospaced: Bool) -> NSFont {
        monospaced ? .monospacedSystemFont(ofSize: size, weight: .regular) : .systemFont(ofSize: size)
    }
}
