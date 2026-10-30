import AppKit
import Carbon.HIToolbox
import RetoucheKit

/// Follows the selected keyboard layout. Text Input Sources must be read on the main thread.
@MainActor
final class InputSourceMonitor {
    struct Snapshot: Equatable {
        var layoutData: Data?
        var layout: KeyboardLayout
        var identifier: String
        var localizedName: String
        /// False for input methods (Japanese, Chinese…) whose output cannot be predicted from keys.
        var isPlainKeyboardLayout: Bool
    }

    var onChange: ((Snapshot) -> Void)?
    private(set) var current: Snapshot?
    private var observer: NSObjectProtocol?

    func start() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    func refresh() {
        let snapshot = Self.read()
        guard snapshot != current else { return }
        current = snapshot
        onChange?(snapshot)
    }

    private static func read() -> Snapshot {
        let layoutSource = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        var data: Data?
        if let pointer = TISGetInputSourceProperty(layoutSource, kTISPropertyUnicodeKeyLayoutData) {
            data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        }
        let identifier = string(layoutSource, kTISPropertyInputSourceID) ?? ""
        let name = string(layoutSource, kTISPropertyLocalizedName) ?? identifier

        let inputSource = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let type = string(inputSource, kTISPropertyInputSourceType) ?? ""
        return Snapshot(
            layoutData: data,
            layout: KeyboardLayout.inferred(fromInputSourceID: identifier),
            identifier: identifier,
            localizedName: name,
            isPlainKeyboardLayout: type == (kTISTypeKeyboardLayout as String)
        )
    }

    private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}
