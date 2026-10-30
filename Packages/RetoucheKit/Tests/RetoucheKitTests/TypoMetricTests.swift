import Testing
@testable import RetoucheKit

struct TypoMetricTests {
    let azerty = TypoMetric(layout: .azerty)

    @Test func swappedLettersAreCheap() {
        #expect(azerty.distance(typed: "continure", candidate: "continuer") == TypoMetric.Cost.transposition)
        #expect(TypoMetric.isSingleTransposition(typed: "savior", candidate: "savoir"))
        #expect(!TypoMetric.isSingleTransposition(typed: "game", candidate: "gamme"))
    }

    @Test func accentsAndApostrophesAreCheaper() {
        #expect(azerty.distance(typed: "etre", candidate: "être") == TypoMetric.Cost.accent)
        #expect(azerty.distance(typed: "jai", candidate: "j'ai") == TypoMetric.Cost.separatorInsertion)
        #expect(azerty.distance(typed: "coeur", candidate: "cœur") == 0)
    }

    @Test func neighbouringKeysDependOnLayout() {
        // On AZERTY, z sits next to e; on QWERTY it does not.
        #expect(azerty.distance(typed: "zt", candidate: "et") == TypoMetric.Cost.neighbourKey)
        #expect(TypoMetric(layout: .qwerty).distance(typed: "zt", candidate: "et") == TypoMetric.Cost.otherSubstitution)
    }

    @Test func unrelatedWordsAreFar() {
        #expect(azerty.distance(typed: "maison", candidate: "voiture") > 3)
    }

    @Test func layoutIsInferredFromInputSource() {
        #expect(KeyboardLayout.inferred(fromInputSourceID: "com.apple.keylayout.French") == .azerty)
        #expect(KeyboardLayout.inferred(fromInputSourceID: "com.apple.keylayout.SwissFrench") == .qwertz)
        #expect(KeyboardLayout.inferred(fromInputSourceID: "com.apple.keylayout.CanadianFrench-PC") == .qwerty)
        #expect(KeyboardLayout.inferred(fromInputSourceID: "com.apple.keylayout.ABC") == .qwerty)
    }
}

struct LexiconTests {
    @Test func eligibility() {
        #expect(Lexicon.isEligible("continure", isSentenceStart: false))
        #expect(Lexicon.isEligible("Bonjuor", isSentenceStart: true))
        #expect(!Lexicon.isEligible("Dupont", isSentenceStart: false))
        #expect(!Lexicon.isEligible("SNCF", isSentenceStart: false))
        #expect(!Lexicon.isEligible("iPhone", isSentenceStart: false))
        #expect(!Lexicon.isEligible("h2o", isSentenceStart: false))
        #expect(!Lexicon.isEligible("mdr", isSentenceStart: false))
        #expect(!Lexicon.isEligible("ouiiii", isSentenceStart: false))
        #expect(Lexicon.isEligible("reallly", isSentenceStart: false))
    }

    @Test func elision() {
        #expect(Lexicon.splitElision("l'appartemnet")! == ("l'", "appartemnet"))
        #expect(Lexicon.splitElision("qu’il")! == ("qu’", "il"))
        #expect(Lexicon.splitElision("aujourd'hui") == nil)
    }

    @Test func casing() {
        #expect(CasePattern("Etre").apply(to: "être") == "Être")
        #expect(CasePattern("etre").apply(to: "être") == "être")
    }
}
