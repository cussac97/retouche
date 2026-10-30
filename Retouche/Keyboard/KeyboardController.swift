import AppKit
import Carbon.HIToolbox
import RetoucheKit

/// Callbacks from the event tap thread. Implementations must hop to the main actor themselves.
struct KeyboardHooks: Sendable {
    var applied: @Sendable (TypingSession.Applied) -> Void
    var reverted: @Sendable (Correction) -> Void
    var languageChanged: @Sendable (String) -> Void
    /// The caret may have moved; the payload is the session generation to seed.
    var caretMoved: @Sendable (UInt64) -> Void
}

/// What the main thread decided about typing right now.
struct KeyboardRuntimeState: Sendable, Equatable {
    var isActive = false
    var usesArbiter = false
    /// False while macOS's own autocorrection is on: it may already have rewritten a word
    /// whose decision arrives late, and rewriting it again could delete the wrong characters.
    var allowsLateCorrections = true
}

/// Runs inside the event tap callback: tracks typing, asks the engine at each
/// word boundary and injects corrections. Everything here is serialised by `lock`
/// because Accessibility seeding and late decisions arrive from other threads.
final class KeyboardController: @unchecked Sendable {
    let engine: CorrectionEngine
    var tap: CFMachPort?

    private let hooks: KeyboardHooks
    private let arbiter: (any ContextArbiter)?
    private let lock = NSLock()
    private let session = TypingSession()
    private let translator = KeyTranslator()
    private let injector = TextInjector()
    private var state = KeyboardRuntimeState()
    private var resolutions: [(id: UInt64, correction: Correction?)] = []
    private var lastReportedLanguage: String?

    /// Time the engine may block a word-ending keystroke before answering asynchronously.
    private static let spaceBudget: TimeInterval = 0.012
    /// Return often sends a message, so it is worth waiting a little longer for.
    private static let returnBudget: TimeInterval = 0.05

    private static let navigationKeys: Set<Int> = [
        kVK_Tab, kVK_Escape, kVK_ForwardDelete, kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown,
        kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Help,
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    init(engine: CorrectionEngine, arbiter: (any ContextArbiter)?, hooks: KeyboardHooks) {
        self.engine = engine
        self.arbiter = arbiter
        self.hooks = hooks
    }

    // MARK: - Main thread API

    func update(_ newState: KeyboardRuntimeState) {
        lock.withLock {
            guard newState != state else { return }
            state = newState
            if !newState.isActive { resetTyping() }
        }
    }

    func updateLayout(_ data: Data?) {
        lock.withLock { translator.update(layoutData: data) }
    }

    /// Forgets the typing context (app switch, focus change). Returns the new generation.
    @discardableResult
    func reset() -> UInt64 {
        lock.withLock {
            resetTyping()
            return session.generation
        }
    }

    func seed(_ textBeforeCaret: String, generation: UInt64) {
        lock.withLock { _ = session.seed(textBeforeCaret, generation: generation) }
    }

    func reject(_ word: String) {
        lock.withLock { session.reject(word) }
    }

    // MARK: - Event tap

    func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        case .flagsChanged:
            guard event.getIntegerValueField(.eventSourceUserData) == EventMarker.sentinel else { return pass }
            lock.withLock { drainResolutions(proxy: proxy) }
            return nil
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            let generation = reset()
            hooks.caretMoved(generation)
            return pass
        case .keyDown:
            guard event.getIntegerValueField(.eventSourceUserData) != EventMarker.injected else { return pass }
            return lock.withLock { handleKeyDown(event, proxy: proxy) }
        default:
            return pass
        }
    }

    private func handleKeyDown(_ event: CGEvent, proxy: CGEventTapProxy) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        guard state.isActive else { return pass }
        // A late correction is typed before this key reaches the app, keeping the text in order.
        drainResolutions(proxy: proxy)

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            resetTyping()
            return pass
        }
        if Self.navigationKeys.contains(keyCode) {
            resetTyping()
            hooks.caretMoved(session.generation)
            return pass
        }

        switch keyCode {
        case kVK_Delete:
            translator.reset()
            if flags.contains(.maskAlternate) {
                resetTyping()
                return pass
            }
            return perform(session.handle(.backspace, decide: decide(within: 0)), event: event, proxy: proxy)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            translator.reset()
            return perform(session.handle(.text("\n"), decide: decide(within: Self.returnBudget)), event: event, proxy: proxy)
        default:
            break
        }

        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0, keyCode != kVK_Space {
            // Holding a letter opens the accent picker: what gets inserted is unknowable here.
            resetTyping()
            return pass
        }
        let keyboardType = UInt32(event.getIntegerValueField(.keyboardEventKeyboardType))
        guard let characters = translator.translate(keyCode: UInt16(keyCode), flags: flags, keyboardType: keyboardType) else {
            resetTyping()
            return pass
        }
        if characters.isEmpty { return pass }
        if characters.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) {
            resetTyping()
            return pass
        }

        let result = perform(session.handle(.text(characters), decide: decide(within: Self.spaceBudget)), event: event, proxy: proxy)
        if let context = session.currentWordContext() {
            engine.speculate(context)
        }
        return result
    }

    private func perform(_ output: TypingSession.Output, event: CGEvent, proxy: CGEventTapProxy) -> Unmanaged<CGEvent>? {
        if let rewrite = output.rewrite { injector.post(rewrite, proxy: proxy) }
        if let applied = output.applied { hooks.applied(applied) }
        if let reverted = output.reverted { hooks.reverted(reverted) }
        if output.consumesEvent { return nil }
        guard output.rewrite != nil else { return Unmanaged.passUnretained(event) }
        // Re-post the key behind the rewrite so it lands after the corrected word.
        event.copy()?.tapPostEvent(proxy)
        return nil
    }

    private func resetTyping() {
        session.reset()
        translator.reset()
    }

    // MARK: - Decisions

    private func decide(within budget: TimeInterval) -> (WordContext, UInt64) -> TypingSession.BoundaryDecision {
        { [self] context, id in
            let decision = engine.decide(context, timeout: budget) { [weak self] late in
                self?.receiveLate(late, id: id)
            }
            guard let decision else { return .deferred }
            return route(decision, id: id)
        }
    }

    /// Called with `lock` held.
    private func route(_ decision: Decision, id: UInt64) -> TypingSession.BoundaryDecision {
        report(decision.language)
        switch decision {
        case .correct(let correction):
            return .correct(correction)
        case .keep(let language):
            return .keep(language: language)
        case .ambiguous(let ambiguity):
            guard state.usesArbiter, state.allowsLateCorrections, let arbiter, arbiter.isAvailable else {
                return .keep(language: ambiguity.language)
            }
            consult(arbiter, about: ambiguity, id: id)
            return .deferred
        }
    }

    /// Called on the engine queue when a decision missed its keystroke budget.
    private func receiveLate(_ decision: Decision, id: UInt64) {
        switch decision {
        case .correct(let correction):
            enqueue(id: id, correction: correction)
        case .keep:
            enqueue(id: id, correction: nil)
        case .ambiguous(let ambiguity):
            let arbiter = lock.withLock { state.usesArbiter ? self.arbiter : nil }
            if let arbiter, arbiter.isAvailable {
                consult(arbiter, about: ambiguity, id: id)
            } else {
                enqueue(id: id, correction: nil)
            }
        }
    }

    private func consult(_ arbiter: any ContextArbiter, about ambiguity: Ambiguity, id: UInt64) {
        Task.detached(priority: .userInitiated) { [weak self] in
            let choice = await arbiter.resolve(ambiguity)
            let correction = choice.map {
                Correction(original: ambiguity.word, replacement: $0, language: ambiguity.language, source: .appleIntelligence)
            }
            self?.enqueue(id: id, correction: correction)
        }
    }

    private func enqueue(id: UInt64, correction: Correction?) {
        let accepted: Correction? = lock.withLock {
            let accepted = state.allowsLateCorrections ? correction : nil
            resolutions.append((id, accepted))
            return accepted
        }
        if accepted != nil { injector.postSentinel() }
    }

    /// Called with `lock` held, inside the tap callback.
    private func drainResolutions(proxy: CGEventTapProxy) {
        guard !resolutions.isEmpty else { return }
        let pending = resolutions
        resolutions.removeAll()
        for item in pending {
            let output = session.resolve(id: item.id, correction: item.correction)
            if let rewrite = output.rewrite { injector.post(rewrite, proxy: proxy) }
            if let applied = output.applied { hooks.applied(applied) }
        }
    }

    private func report(_ language: String?) {
        guard let language, language != lastReportedLanguage else { return }
        lastReportedLanguage = language
        hooks.languageChanged(language)
    }
}
