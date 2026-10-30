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
        #endif
        model.start()
    }
}

private struct MenuBarIcon: View {
    let model: AppModel

    var body: some View {
        Image(systemName: symbol)
            .symbolEffect(.bounce, value: model.correctionPulse)
            .accessibilityLabel("Retouche")
    }

    private var symbol: String {
        switch model.permission {
        case .missing, .needsRelaunch: "exclamationmark.triangle"
        case .checking, .granted: model.isCorrecting ? "character.cursor.ibeam" : "pause.circle"
        }
    }
}
