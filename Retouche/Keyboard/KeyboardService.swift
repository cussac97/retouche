import AppKit
import RetoucheKit

/// Wires the event tap to the rest of macOS: keyboard layouts, app switches and
/// Accessibility lookups that tell the session what is already in the text field.
@MainActor
final class KeyboardService {
    let engine = CorrectionEngine()
    let arbiter = ContextArbiters.appleIntelligence()
    let controller: KeyboardController
    let inputSources = InputSourceMonitor()

    private let tap = EventTap()
    private let accessibilityQueue = DispatchQueue(label: "app.retouche.accessibility", qos: .userInitiated)
    private var seedWork: DispatchWorkItem?

    init(hooks: KeyboardHooks) {
        controller = KeyboardController(engine: engine, arbiter: arbiter, hooks: hooks)
    }

    var isTapRunning: Bool { tap.isRunning }

    func start() {
        inputSources.start()
        engine.warmUp()
        if let arbiter, arbiter.isAvailable { arbiter.prewarm() }
    }

    func startTap() -> Bool {
        tap.start(controller: controller)
    }

    /// The focused field changed: forget what we knew and read the new context shortly after.
    func focusChanged(to application: NSRunningApplication?) {
        let generation = controller.reset()
        if let application {
            accessibilityQueue.async { @Sendable in Accessibility.enableManualAccessibility(for: application) }
        }
        scheduleSeed(generation: generation, delay: 0.25)
    }

    // Closures below run on `accessibilityQueue`, so they must not inherit main-actor isolation.

    /// Reads the text before the caret once the click or arrow key has been processed by the app.
    func scheduleSeed(generation: UInt64, delay: TimeInterval = 0.12) {
        seedWork?.cancel()
        let controller = controller
        let work = DispatchWorkItem { @Sendable in
            guard let text = Accessibility.textBeforeCaret() else { return }
            controller.seed(text, generation: generation)
        }
        seedWork = work
        accessibilityQueue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Finds where the corrected word is drawn, for the overlay.
    func locate(_ applied: TypingSession.Applied, completion: @escaping @MainActor (TextAnchor?) -> Void) {
        let word = applied.correction.replacement
        let tail = applied.tail
        accessibilityQueue.asyncAfter(deadline: .now() + 0.05) { @Sendable in
            let anchor = Accessibility.anchor(forWord: word, followedBy: tail)
            Task { @MainActor in completion(anchor) }
        }
    }
}
