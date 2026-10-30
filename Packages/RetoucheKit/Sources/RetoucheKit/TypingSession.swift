import Foundation

/// Mirrors the text the user is typing in the focused field and turns
/// engine decisions into minimal keyboard edits.
///
/// The session only knows what it has seen typed since the last reset (a
/// click, an arrow key, a shortcut, an app switch). Every edit it returns is
/// expressed as "press backspace N times, then type this", which works in any
/// app. It is not thread-safe: drive it from the event tap thread.
public final class TypingSession {
    public struct Rewrite: Equatable, Sendable {
        public var deleteCount: Int
        public var insert: String
    }

    public struct Applied: Equatable, Sendable {
        public var correction: Correction
        /// Text between the end of the replacement and the caret, e.g. ", ".
        public var tail: String
    }

    public enum Input: Equatable, Sendable {
        case text(String)
        case backspace
    }

    public enum BoundaryDecision: Equatable, Sendable {
        case correct(Correction)
        case keep(language: String?)
        /// Not known yet; `resolve(id:correction:)` will be called later.
        case deferred
    }

    public struct Output: Equatable, Sendable {
        /// Edits to perform before the key event that produced this output.
        public var rewrite: Rewrite?
        /// When true the key event must be swallowed (the rewrite replaces it).
        public var consumesEvent = false
        public var applied: Applied?
        public var reverted: Correction?

        public static let pass = Output()
    }

    private struct Token {
        var start: Int
        var core: [Character]
        var trailing: [Character]
        var context: WordContext
    }

    private struct Pending {
        var id: UInt64
        var start: Int
        var core: [Character]
        var trailing: [Character]
    }

    private struct UndoRecord {
        var start: Int
        var original: [Character]
        var replacement: [Character]
        var correction: Correction
    }

    static let capacity = 1000
    static let maximumRewriteLength = 64
    static let contextLength = 160

    public private(set) var text: [Character] = []
    /// True when the character before `text` is known to be a word boundary.
    public private(set) var knowsStart = false
    /// Incremented on every reset, so late information about an old caret position can be ignored.
    public private(set) var generation: UInt64 = 0
    public private(set) var lastLanguage: String?
    private var undo: UndoRecord?
    private var pendings: [Pending] = []
    private var nextID: UInt64 = 1
    private var rejected: Set<String> = []

    public init() {}

    // MARK: - State

    /// Forgets the buffer, e.g. after a click or an arrow key moved the caret.
    public func reset(knownBoundary: Bool = false) {
        text.removeAll(keepingCapacity: true)
        knowsStart = knownBoundary
        undo = nil
        pendings.removeAll()
        generation &+= 1
    }

    /// Fills an empty buffer with the text before the caret, read through Accessibility.
    @discardableResult
    public func seed(_ textBeforeCaret: String, generation: UInt64) -> Bool {
        guard generation == self.generation, text.isEmpty else { return false }
        let characters = Array(textBeforeCaret)
        text = Array(characters.suffix(Self.capacity / 2))
        knowsStart = characters.count <= Self.capacity / 2
        return true
    }

    /// Words the user reverted in this session are left alone afterwards.
    public func reject(_ word: String) {
        rejected.insert(word.lowercased())
    }

    /// The word currently being typed, for speculative evaluation.
    public func currentWordContext() -> WordContext? {
        currentToken()?.context
    }

    // MARK: - Input

    public func handle(_ input: Input, decide: (WordContext, UInt64) -> BoundaryDecision) -> Output {
        switch input {
        case .backspace:
            return handleBackspace()
        case .text(let string):
            undo = nil
            if string.count == 1, let character = string.first, Lexicon.isBoundary(character) {
                return handleBoundary(character, decide: decide)
            }
            append(string)
            return .pass
        }
    }

    /// Applies a decision that arrived after the word's boundary was typed.
    public func resolve(id: UInt64, correction: Correction?) -> Output {
        guard let index = pendings.firstIndex(where: { $0.id == id }) else { return .pass }
        let pending = pendings.remove(at: index)
        guard let correction else { return .pass }

        let coreEnd = pending.start + pending.core.count
        let trailingEnd = coreEnd + pending.trailing.count
        guard trailingEnd < text.count,
              Array(text[pending.start..<coreEnd]) == pending.core,
              Array(text[coreEnd..<trailingEnd]) == pending.trailing,
              Lexicon.isBoundary(text[trailingEnd]) else { return .pass }

        let old = Array(text[pending.start...])
        guard old.count <= Self.maximumRewriteLength else { return .pass }
        let tail = Array(text[coreEnd...])
        let new = Array(correction.replacement) + tail
        text.replaceSubrange(pending.start..., with: new)
        let shift = new.count - old.count
        for later in pendings.indices where pendings[later].start > pending.start {
            pendings[later].start += shift
        }
        lastLanguage = correction.language
        undo = UndoRecord(start: pending.start, original: old, replacement: new, correction: correction)
        return Output(rewrite: Self.diff(from: old, to: new), applied: Applied(correction: correction, tail: String(tail)))
    }

    private func handleBoundary(_ boundary: Character, decide: (WordContext, UInt64) -> BoundaryDecision) -> Output {
        var output = Output.pass
        if let token = currentToken(), !rejected.contains(String(token.core).lowercased()) {
            let id = nextID
            nextID &+= 1
            switch decide(token.context, id) {
            case .keep(let language):
                if let language { lastLanguage = language }
            case .deferred:
                pendings.append(Pending(id: id, start: token.start, core: token.core, trailing: token.trailing))
            case .correct(let correction):
                let old = token.core + token.trailing
                let new = Array(correction.replacement) + token.trailing
                text.replaceSubrange(token.start..., with: new)
                lastLanguage = correction.language
                undo = UndoRecord(start: token.start, original: old + [boundary], replacement: new + [boundary], correction: correction)
                output.rewrite = Self.diff(from: old, to: new)
                output.applied = Applied(correction: correction, tail: String(token.trailing + [boundary]))
            }
        }
        if boundary == "\n" || boundary == "\r" {
            // A new line often sends a message: never rewrite or undo across it.
            reset(knownBoundary: true)
        } else {
            append(String(boundary))
        }
        return output
    }

    private func handleBackspace() -> Output {
        defer { undo = nil }
        if let undo, text.count == undo.start + undo.replacement.count, Array(text[undo.start...]) == undo.replacement {
            let restored = Array(undo.original.dropLast())
            text.replaceSubrange(undo.start..., with: restored)
            rejected.insert(undo.correction.original.lowercased())
            return Output(rewrite: Self.diff(from: undo.replacement, to: restored), consumesEvent: true, reverted: undo.correction)
        }
        if text.isEmpty {
            knowsStart = false
        } else {
            text.removeLast()
        }
        return .pass
    }

    // MARK: - Helpers

    private func append(_ string: String) {
        text.append(contentsOf: string)
        guard text.count > Self.capacity else { return }
        let dropped = text.count - Self.capacity / 2
        text.removeFirst(dropped)
        knowsStart = false
        pendings = pendings.compactMap { pending in
            var pending = pending
            pending.start -= dropped
            return pending.start >= 0 ? pending : nil
        }
        if var record = undo {
            record.start -= dropped
            undo = record.start >= 0 ? record : nil
        }
    }

    private func currentToken() -> Token? {
        var tokenStart = text.count
        while tokenStart > 0, !Lexicon.isBoundary(text[tokenStart - 1]) { tokenStart -= 1 }
        guard tokenStart < text.count, tokenStart > 0 || knowsStart else { return nil }

        var start = tokenStart
        while start < text.count, Lexicon.openingPunctuation.contains(text[start]) { start += 1 }
        var end = text.count
        while end > start, Lexicon.closingPunctuation.contains(text[end - 1]) { end -= 1 }
        guard start < end else { return nil }
        let core = Array(text[start..<end])
        guard core.allSatisfy(Lexicon.isWordCharacter) else { return nil }

        var sentenceStart = tokenStart
        while sentenceStart > 0, !Lexicon.sentenceTerminators.contains(text[sentenceStart - 1]) { sentenceStart -= 1 }
        let lowerBound = max(sentenceStart, tokenStart - Self.contextLength)
        let prefix = String(text[lowerBound..<tokenStart]).trimmingCharacters(in: .whitespacesAndNewlines)
        let atSentenceStart = prefix.isEmpty && (sentenceStart > 0 || knowsStart)
        let context = WordContext(word: String(core), sentencePrefix: prefix, isSentenceStart: atSentenceStart, previousLanguage: lastLanguage)
        return Token(start: start, core: core, trailing: Array(text[end...]), context: context)
    }

    static func diff(from old: [Character], to new: [Character]) -> Rewrite {
        var common = 0
        while common < old.count, common < new.count, old[common] == new[common] { common += 1 }
        return Rewrite(deleteCount: old.count - common, insert: String(new[common...]))
    }
}
