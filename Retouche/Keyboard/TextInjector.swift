import Carbon.HIToolbox
import CoreGraphics
import RetoucheKit

enum EventMarker {
    /// Stamped on every event we synthesise, so the tap lets them through untouched.
    static let injected: Int64 = 0x5245_544F_5543_4845
    /// A no-op modifier event that wakes the tap so a late correction is applied in order.
    static let sentinel: Int64 = 0x5245_544F_5543_4853
}

/// Types corrections into the focused app as backspaces followed by Unicode text.
///
/// Events are inserted with `tapPostEvent` from inside the tap callback, so they
/// land exactly between the keystroke being processed and the next one the user
/// typed — no race with fast typists.
struct TextInjector: @unchecked Sendable {
    private let source = CGEventSource(stateID: .privateState)

    func post(_ rewrite: TypingSession.Rewrite, proxy: CGEventTapProxy) {
        for _ in 0..<rewrite.deleteCount {
            postKey(CGKeyCode(kVK_Delete), proxy: proxy)
        }
        for character in rewrite.insert {
            postText(String(character), proxy: proxy)
        }
    }

    /// Posts the sentinel through the HID stream; the tap receives it after any keys already queued.
    func postSentinel() {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Function), keyDown: true) else { return }
        event.type = .flagsChanged
        event.flags = CGEventSource.flagsState(.combinedSessionState)
        event.setIntegerValueField(.eventSourceUserData, value: EventMarker.sentinel)
        event.post(tap: .cghidEventTap)
    }

    private func postKey(_ keyCode: CGKeyCode, proxy: CGEventTapProxy) {
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown) else { continue }
            event.flags = []
            event.setIntegerValueField(.eventSourceUserData, value: EventMarker.injected)
            event.tapPostEvent(proxy)
        }
    }

    private func postText(_ text: String, proxy: CGEventTapProxy) {
        let units = Array(text.utf16)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: isDown) else { continue }
            event.flags = []
            event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            event.setIntegerValueField(.eventSourceUserData, value: EventMarker.injected)
            event.tapPostEvent(proxy)
        }
    }
}
