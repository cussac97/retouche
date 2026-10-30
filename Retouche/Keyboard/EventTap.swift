import CoreGraphics
import Foundation

/// A session-wide keyboard event tap running on its own high-priority thread,
/// so keystrokes are never delayed by UI work on the main thread.
final class EventTap {
    private struct Unchecked<Value>: @unchecked Sendable { let value: Value }

    private(set) var isRunning = false

    /// Requires the Accessibility permission. Returns false if the system refused the tap.
    func start(controller: KeyboardController) -> Bool {
        guard !isRunning else { return true }
        let types: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passRetained(controller).toOpaque()
        ) else { return false }

        controller.tap = tap
        let port = Unchecked(value: tap)
        let thread = Thread {
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port.value, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: port.value, enable: true)
            CFRunLoopRun()
        }
        thread.name = "Retouche event tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        isRunning = true
        return true
    }
}

private func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<KeyboardController>.fromOpaque(refcon).takeUnretainedValue()
    return controller.handle(proxy: proxy, type: type, event: event)
}
