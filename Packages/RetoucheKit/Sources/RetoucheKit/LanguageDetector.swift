import Foundation
import NaturalLanguage

struct LanguageGuess: Equatable {
    /// NSSpellChecker language identifier.
    var language: String
    /// 0…1, how sure we are that the sentence is in `language`.
    var confidence: Double
    /// Number of words of context the guess is based on.
    var contextWordCount: Int
}

/// Decides, sentence by sentence, which of the user's languages they are typing in.
///
/// Combines Apple's NaturalLanguage recognizer (reliable from ~3 words), a
/// dictionary vote (words that exist in only one language), and a prior: the
/// language of the previous sentence, or the primary language at the start of
/// a text. The prior fades as the sentence grows.
struct LanguageDetector {
    var languages: [String]
    var spell: SpellService

    func detect(sentencePrefix: String, previous: String?) -> LanguageGuess {
        let words = sentencePrefix
            .split(whereSeparator: { !($0.isLetter || Lexicon.apostrophes.contains($0) || $0 == "-") })
            .map(String.init)
        guard languages.count > 1 else {
            return LanguageGuess(language: languages.first ?? "en", confidence: 1, contextWordCount: words.count)
        }

        var votes: [String: Double] = [:]
        for word in words.suffix(6) where word.count >= 2 {
            let validIn = languages.filter { spell.isValid(word, language: $0) }
            if validIn.count == 1 { votes[validIn[0], default: 0] += 1 }
        }
        let voteTotal = votes.values.reduce(0, +)

        let weights: (recognizer: Double, vote: Double) = switch words.count {
        case 0: (0, 0)
        case 1: (0.3, 0.35)
        case 2: (0.5, 0.3)
        case 3: (0.65, 0.25)
        default: (0.8, 0.2)
        }
        let voteWeight = voteTotal > 0 ? weights.vote : 0
        let priorWeight = max(0, 1 - weights.recognizer - voteWeight)

        let recognized = weights.recognizer > 0 ? recognizerScores(sentencePrefix) : [:]
        let favourite = previous.flatMap { languages.contains($0) ? $0 : nil } ?? languages[0]
        let favouriteShare = previous == nil ? 0.75 : 0.85

        var scores: [String: Double] = [:]
        for language in languages {
            let prior = language == favourite ? favouriteShare : (1 - favouriteShare) / Double(languages.count - 1)
            let vote = voteTotal > 0 ? (votes[language] ?? 0) / voteTotal : 0
            scores[language] = weights.recognizer * (recognized[language] ?? 0) + voteWeight * vote + priorWeight * prior
        }
        let best = languages.max { (scores[$0] ?? 0) < (scores[$1] ?? 0) } ?? languages[0]
        return LanguageGuess(language: best, confidence: scores[best] ?? 0, contextWordCount: words.count)
    }

    /// NaturalLanguage's probability for each of the user's languages.
    func recognizerScores(_ text: String) -> [String: Double] {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = languages.map(Self.naturalLanguage)
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: languages.count)
        var scores: [String: Double] = [:]
        for language in languages {
            scores[language] = hypotheses[Self.naturalLanguage(language)] ?? 0
        }
        return scores
    }

    static func naturalLanguage(_ spellLanguage: String) -> NLLanguage {
        NLLanguage(rawValue: String(spellLanguage.prefix { $0 != "_" && $0 != "-" }))
    }
}
