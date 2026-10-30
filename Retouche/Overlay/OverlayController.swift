import AppKit
import RetoucheKit
import SwiftUI

/// Shows a short-lived bubble under the word that was just corrected, in any app.
@MainActor
final class OverlayController {
    private let model = OverlayModel()
    private var panel: NSPanel?
    private var sequence: Task<Void, Never>?

    private static let panelSize = CGSize(width: 520, height: 140)
    private static let margin: CGFloat = 18

    /// `wordRect` is in Accessibility coordinates (top-left origin); nil when the app does not expose it.
    func show(_ correction: Correction, at wordRect: CGRect?) {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let placement = place(wordRect: wordRect.map { Self.cocoaRect($0) })
        panel.setFrame(placement.frame, display: false)
        sequence?.cancel()
        model.reset(OverlayModel.Content(
            original: correction.original,
            replacement: correction.replacement,
            language: String(correction.language.prefix(2)).uppercased(),
            usesIntelligence: correction.source == .appleIntelligence,
            highlight: placement.highlight,
            pillOrigin: placement.pillOrigin,
            pillAlignment: placement.pillAlignment
        ))
        panel.orderFrontRegardless()

        sequence = Task { [model] in
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { model.isVisible = true }
            try? await Task.sleep(for: .milliseconds(110))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.35)) { model.isRevealed = true }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.9)) { model.isHighlighted = false }
            try? await Task.sleep(for: .milliseconds(1350))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.22)) { model.isVisible = false }
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }

    func dismiss() {
        sequence?.cancel()
        withAnimation(.easeIn(duration: 0.15)) { model.isVisible = false }
        let panel = panel
        Task {
            try? await Task.sleep(for: .milliseconds(170))
            panel?.orderOut(nil)
        }
    }

    // MARK: - Layout

    private struct Placement {
        var frame: CGRect
        var highlight: CGRect?
        var pillOrigin: CGPoint
        var pillAlignment: Alignment
    }

    private func place(wordRect: CGRect?) -> Placement {
        let size = Self.panelSize
        let margin = Self.margin
        guard let wordRect, let screen = NSScreen.screens.first(where: { $0.frame.intersects(wordRect) }) else {
            // No caret geometry (some web views): hang the bubble under the menu bar icon.
            let anchor = Self.statusItemFrame() ?? CGRect(x: (NSScreen.main?.visibleFrame.maxX ?? 800) - 120, y: NSScreen.main?.visibleFrame.maxY ?? 800, width: 24, height: 0)
            let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main
            var x = anchor.midX - size.width / 2
            if let visible = screen?.visibleFrame { x = min(max(x, visible.minX), visible.maxX - size.width) }
            let frame = CGRect(x: x, y: anchor.minY - size.height - 4, width: size.width, height: size.height)
            return Placement(frame: frame, highlight: nil, pillOrigin: CGPoint(x: anchor.midX - frame.minX, y: margin), pillAlignment: .top)
        }

        let visible = screen.visibleFrame
        let highlight = wordRect.insetBy(dx: -3, dy: -1.5)
        let fitsBelow = highlight.minY - size.height + highlight.height + margin > visible.minY
        var x = highlight.minX - margin
        x = min(max(x, visible.minX), visible.maxX - size.width)
        let y = fitsBelow ? highlight.maxY + margin - size.height : highlight.minY - margin
        let frame = CGRect(x: x, y: y, width: size.width, height: size.height)

        // SwiftUI coordinates: origin at the panel's top-left.
        let localHighlight = CGRect(x: highlight.minX - frame.minX, y: frame.maxY - highlight.maxY, width: highlight.width, height: highlight.height)
        let pillY = fitsBelow ? localHighlight.maxY + 6 : localHighlight.minY - 6
        return Placement(
            frame: frame,
            highlight: localHighlight,
            pillOrigin: CGPoint(x: localHighlight.minX - 4, y: pillY),
            pillAlignment: fitsBelow ? .topLeading : .bottomLeading
        )
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: Self.panelSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
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

    private static func statusItemFrame() -> CGRect? {
        NSApp.windows.first { String(describing: type(of: $0)).contains("StatusBarWindow") && $0.isVisible }?.frame
    }
}

@MainActor
@Observable
final class OverlayModel {
    struct Content: Equatable {
        var id = UUID()
        var original: String
        var replacement: String
        var language: String
        var usesIntelligence: Bool
        var highlight: CGRect?
        var pillOrigin: CGPoint
        var pillAlignment: Alignment

        static func == (lhs: Content, rhs: Content) -> Bool { lhs.id == rhs.id }
    }

    var content: Content?
    var isVisible = false
    var isRevealed = false
    var isHighlighted = false

    func reset(_ content: Content) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            self.content = content
            isVisible = false
            isRevealed = false
            isHighlighted = true
        }
    }
}
