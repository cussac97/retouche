#if DEBUG
import RetoucheKit
import SwiftUI

/// Renders the main views to PNG files when RETOUCHE_SNAPSHOTS=<directory> is set (Debug builds only).
@MainActor
enum Snapshots {
    static func renderIfRequested(model: AppModel) -> Bool {
        guard let directory = ProcessInfo.processInfo.environment["RETOUCHE_SNAPSHOTS"] else { return false }
        model.loadSampleContent()
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            render(MenuContentView(model: model), size: CGSize(width: 330, height: 470), appearance: appearance, to: "\(directory)/menu-\(suffix).png")
            render(overlaySample(), size: CGSize(width: 420, height: 110), appearance: appearance, to: "\(directory)/overlay-\(suffix).png")
        }
        render(SettingsView(model: model), size: CGSize(width: 520, height: 430), appearance: .aqua, to: "\(directory)/settings.png")
        return true
    }

    private static func overlaySample() -> some View {
        let overlay = OverlayModel()
        overlay.content = OverlayModel.Content(
            original: "continure", replacement: "continuer", language: "FR", usesIntelligence: false,
            highlight: CGRect(x: 92, y: 22, width: 74, height: 19), pillOrigin: CGPoint(x: 88, y: 47), pillAlignment: .topLeading
        )
        overlay.isVisible = true
        overlay.isRevealed = true
        overlay.isHighlighted = true
        return ZStack(alignment: .topLeading) {
            Text("Je vais continuer demain")
                .font(.system(size: 15))
                .offset(x: 34, y: 22)
            OverlayView(model: overlay)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private static func render(_ view: some View, size: CGSize, appearance: NSAppearance.Name, to path: String) {
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor)))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: .now + 0.4)
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
#endif
