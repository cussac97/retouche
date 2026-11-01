import SwiftUI

@main
struct RetoucheApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: appDelegate.model)
        } label: {
            MenuBarIcon(model: appDelegate.model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: appDelegate.model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if Snapshots.renderIfRequested(model: model) {
            NSApp.terminate(nil)
            return
        }
        Diagnostics.start()
        #endif
        model.start()
    }
}

struct MenuBarIcon: View {
    let model: AppModel

    var body: some View {
        Self.image(permission: model.permission, isCorrecting: model.isCorrecting)
            .symbolEffect(.bounce, value: model.correctionPulse)
            .accessibilityLabel("Retouche")
    }

    /// The app icon's "é" and I-beam while correcting, a custom symbol so it bounces like the others.
    static func image(permission: PermissionState, isCorrecting: Bool) -> Image {
        switch permission {
        case .missing, .needsRelaunch: Image(systemName: "exclamationmark.triangle")
        case .checking, .granted: isCorrecting ? Image("retouche.cursor") : Image(systemName: "pause.circle")
        }
    }
}
