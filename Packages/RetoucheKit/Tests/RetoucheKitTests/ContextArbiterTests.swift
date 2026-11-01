import Testing
@testable import RetoucheKit

struct ContextArbiterTests {
    let fallback = Correction(original: "cafr", replacement: "car", language: "fr", source: .appleSpelling)

    @Test func closeCallsOnlyChooseAmongCandidates() {
        let closeCall = Ambiguity(word: "cafr", candidates: ["car", "café", "car"], language: "fr", sentencePrefix: "Je bois un", fallback: fallback)
        #expect(ContextArbiters.choices(for: closeCall) == ["car", "café"])
        let doubt = Ambiguity(word: "savior", candidates: ["savoir"], language: "fr", sentencePrefix: "Je voulais")
        #expect(ContextArbiters.choices(for: doubt) == ["savior", "savoir"])
    }

    @Test func theEnginePickAppliesWithoutAnAnswer() {
        let closeCall = Ambiguity(word: "cafr", candidates: ["car", "café"], language: "fr", sentencePrefix: "Je bois un", fallback: fallback)
        #expect(closeCall.correction(choosing: nil) == fallback)
        #expect(closeCall.correction(choosing: "car") == fallback)
        #expect(closeCall.correction(choosing: "café") == Correction(original: "cafr", replacement: "café", language: "fr", source: .appleIntelligence))

        let doubt = Ambiguity(word: "savior", candidates: ["savoir"], language: "fr", sentencePrefix: "Je voulais")
        #expect(doubt.correction(choosing: nil) == nil)
    }

    @Test func promptsCarryTheSentence() {
        let closeCall = Ambiguity(word: "cafr", candidates: ["car", "café"], language: "fr", sentencePrefix: "Je bois un", fallback: fallback)
        #expect(ContextArbiters.Question.typo.prompt(for: closeCall).contains("« Je bois un cafr »"))
        #expect(ContextArbiters.Question.blank.prompt(for: closeCall).contains("« Je bois un ___ »"))
    }
}
