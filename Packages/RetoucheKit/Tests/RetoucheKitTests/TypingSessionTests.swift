import Testing
@testable import RetoucheKit

/// Simulates a text field: applies the session's rewrites like the event tap would.
private final class Field {
    let session = TypingSession()
    var text: [Character] = []
    var decisions: [String: TypingSession.BoundaryDecision] = [:]
    var deferred: [(id: UInt64, word: String)] = []
    var lastOutput = TypingSession.Output.pass

    init() { session.reset(knownBoundary: true) }

    func type(_ string: String) {
        for character in string { press(.text(String(character)), character: character) }
    }

    func backspace() { press(.backspace, character: nil) }

    func resolve(_ word: String, as replacement: String?) {
        guard let index = deferred.firstIndex(where: { $0.word == word }) else { return }
        let id = deferred.remove(at: index).id
        let correction = replacement.map { Correction(original: word, replacement: $0, language: "fr", source: .appleIntelligence) }
        apply(session.resolve(id: id, correction: correction), character: nil)
    }

    private func press(_ input: TypingSession.Input, character: Character?) {
        let output = session.handle(input) { context, id in
            let decision = decisions[context.word] ?? .keep(language: "fr")
            if decision == .deferred { deferred.append((id, context.word)) }
            return decision
        }
        apply(output, character: character)
        if output.consumesEvent == false, input == .backspace, !text.isEmpty { text.removeLast() }
    }

    private func apply(_ output: TypingSession.Output, character: Character?) {
        lastOutput = output
        if let rewrite = output.rewrite {
            text.removeLast(rewrite.deleteCount)
            text.append(contentsOf: rewrite.insert)
        }
        if let character, !output.consumesEvent { text.append(character) }
    }

    var string: String { String(text) }
}

private func fix(_ original: String, _ replacement: String) -> TypingSession.BoundaryDecision {
    .correct(Correction(original: original, replacement: replacement, language: "fr", source: .appleSpelling))
}

struct TypingSessionTests {
    @Test func correctsOnSpaceWithMinimalEdit() {
        let field = Field()
        field.decisions["continure"] = fix("continure", "continuer")
        field.type("je vais continure ")
        #expect(field.string == "je vais continuer ")
        #expect(field.lastOutput.rewrite == .init(deleteCount: 2, insert: "er"))
    }

    @Test func keepsTrailingPunctuation() {
        let field = Field()
        field.decisions["bonjuor"] = fix("bonjuor", "bonjour")
        field.type("bonjuor, toi")
        #expect(field.string == "bonjour, toi")
    }

    @Test func backspaceRightAfterRevertsAndRemembers() {
        let field = Field()
        field.decisions["continure"] = fix("continure", "continuer")
        field.type("continure ")
        field.backspace()
        #expect(field.string == "continure")
        #expect(field.lastOutput.reverted?.original == "continure")
        field.type(" et continure ")
        #expect(field.string == "continure et continure ")
    }

    @Test func backspaceLaterIsNormal() {
        let field = Field()
        field.decisions["continure"] = fix("continure", "continuer")
        field.type("continure a")
        field.backspace()
        #expect(field.string == "continuer ")
    }

    @Test func deferredDecisionRewritesTextTypedSince() {
        let field = Field()
        field.decisions["demian"] = .deferred
        field.type("on se voit demian mat")
        field.resolve("demian", as: "demain")
        #expect(field.string == "on se voit demain mat")
        field.type("in ")
        #expect(field.string == "on se voit demain matin ")
    }

    @Test func deferredDecisionIsDroppedWhenTheWordChanged() {
        let field = Field()
        field.decisions["demian"] = .deferred
        field.type("demian ")
        field.backspace()
        field.backspace()
        field.type("s ")
        field.resolve("demian", as: "demain")
        #expect(field.string == "demias ")
    }

    @Test func unknownStartIsNeverCorrected() {
        let session = TypingSession()
        var asked: [String] = []
        for character in "ure suite " {
            _ = session.handle(.text(String(character))) { context, _ in
                asked.append(context.word)
                return .keep(language: nil)
            }
        }
        #expect(asked == ["suite"])
    }

    @Test func seedingProvidesContext() {
        let session = TypingSession()
        session.reset()
        #expect(session.seed("Je vais contin", generation: session.generation))
        var words: [String] = []
        for character in "ure " {
            _ = session.handle(.text(String(character))) { context, _ in
                words.append(context.word)
                #expect(context.sentencePrefix == "Je vais")
                return .keep(language: nil)
            }
        }
        #expect(words == ["continure"])
    }

    @Test func urlsAndEmailsAreSkipped() {
        let session = TypingSession()
        session.reset(knownBoundary: true)
        var words: [String] = []
        for character in "voir apple.com/fr et a@b.fr ok " {
            _ = session.handle(.text(String(character))) { context, _ in
                words.append(context.word)
                return .keep(language: nil)
            }
        }
        #expect(words == ["voir", "et", "ok"])
    }

    @Test func newlineSendsNoUndo() {
        let field = Field()
        field.decisions["merci"] = fix("merci", "Merci")
        field.type("merci\n")
        field.backspace()
        #expect(field.lastOutput.reverted == nil)
    }
}
