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
            render(overlayFrames(), size: CGSize(width: 640, height: 300), appearance: appearance, to: "\(directory)/overlay-\(suffix).png")
        }
        render(SettingsView(model: model), size: CGSize(width: 520, height: 430), appearance: .aqua, to: "\(directory)/settings.png")
        return true
    }

    /// The letter animation frozen along its timeline, over the corrected text it lands on.
    private static func overlayFrames() -> some View {
        let samples = [("continure", "continuer", false), ("Jai", "J'ai", false), ("etre", "être", false), ("shoudl", "should", true)]
        // (lift, progress, land)
        let steps: [(Double, Double, Double)] = [(0.5, 0, 0), (1, 0, 0), (1, 0.3, 0), (1, 0.6, 0), (1, 1, 0), (1, 1, 0.6)]
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(samples, id: \.0) { original, replacement, monospaced in
                HStack(spacing: 0) {
                    ForEach(steps.indices, id: \.self) { index in
                        let (lift, progress, land) = steps[index]
                        let overlay = OverlayModel()
                        let content = OverlayModel.Content(original: original, replacement: replacement, fontSize: 15, isMonospaced: monospaced, minimumWidth: 0, lineHeight: 19)
                        let _ = overlay.reset(content)
                        let _ = { overlay.lift = lift; overlay.progress = progress; overlay.land = land }()
                        ZStack(alignment: .topLeading) {
                            Text(replacement)
                                .font(Font(OverlayModel.font(size: 15, monospaced: monospaced) as CTFont))
                                .frame(height: 19)
                                .offset(x: content.margin, y: content.margin)
                            OverlayView(model: overlay)
                        }
                        .frame(width: 106, height: 80, alignment: .topLeading)
                        .offset(x: -content.margin + 16, y: -content.margin + 44)
                        .frame(width: 106, height: 80, alignment: .topLeading)
                        .clipped()
                    }
                }
            }
        }
        .padding(4)
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
