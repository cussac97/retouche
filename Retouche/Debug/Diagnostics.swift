#if DEBUG
import AppKit

/// Posting the distributed notification `app.retouche.debug.locate` with a file path as its object
/// writes what the focused text field reveals about its geometry to that file. Appending
/// `|bundle.id` inspects the field focused in that app instead, even in the background:
///
///     osascript -l JavaScript -e 'ObjC.import("Foundation"); $.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately("app.retouche.debug.locate", "/tmp/probe.txt|com.google.Chrome", $(), true)'
enum Diagnostics {
    static func start() {
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("app.retouche.debug.locate"), object: nil, queue: nil) { notification in
            guard let object = notification.object as? String else { return }
            let parts = object.split(separator: "|", maxSplits: 1).map(String.init)
            let path = parts[0]
            let bundleID = parts.count > 1 ? parts[1] : nil
            DispatchQueue.global(qos: .userInitiated).async {
                let application = bundleID.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first } ?? NSWorkspace.shared.frontmostApplication
                let pid = bundleID == nil ? nil : application?.processIdentifier
                let report = "app: \(application?.bundleIdentifier ?? "-")\n\(Accessibility.diagnose(pid: pid))\n"
                try? report.write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
    }
}
#endif
