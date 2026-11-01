import Foundation

/// Picks the intended word when spelling alone cannot decide, using sentence context.
public protocol ContextArbiter: Sendable {
    var isAvailable: Bool { get }
    func prewarm()
    /// Returns one of `ambiguity.candidates`, or nil to keep the word as typed.
    func resolve(_ ambiguity: Ambiguity) async -> String?
}

public enum ContextArbiters {
    /// True when this build was compiled against an SDK that ships FoundationModels (Xcode 26+).
    public static var isCompiledWithFoundationModels: Bool {
        #if canImport(FoundationModels)
        true
        #else
        false
        #endif
    }

    /// The on-device Apple Intelligence model, when both the SDK and this Mac support it.
    public static func appleIntelligence() -> (any ContextArbiter)? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return AppleIntelligenceArbiter()
        }
        #endif
        return nil
    }

    /// Two ways of asking which word was meant. The on-device model leans toward the word
    /// listed first (the engine's pick), so it only overrules it when both framings agree.
    enum Question: CaseIterable, Sendable {
        /// "Here is the sentence and the typed word: which of these was meant?"
        case typo
        /// "Which of these fills the blank in the sentence?"
        case blank

        var instructions: String {
            switch self {
            case .typo:
                """
                Tu es le correcteur d'un clavier. On te donne une phrase en cours de frappe, en français ou en anglais, \
                dont le dernier mot contient peut-être une faute de frappe. Tu choisis, parmi les mots proposés, \
                celui que l'auteur voulait taper d'après le sens de la phrase. Si le mot tapé est voulu \
                (nom propre, anglicisme, mot d'une autre langue), tu le gardes.
                """
            case .blank:
                """
                Tu corriges les fautes de frappe d'un clavier, en français ou en anglais. \
                Pour chaque phrase, tu choisis le mot que l'auteur voulait vraiment écrire : \
                celui qui a le plus de sens dans la phrase, le plus naturel et le plus courant.
                """
            }
        }

        func prompt(for ambiguity: Ambiguity) -> String {
            let choices = ContextArbiters.choices(for: ambiguity)
            switch self {
            case .typo:
                let sentence = [ambiguity.sentencePrefix, ambiguity.word].filter { !$0.isEmpty }.joined(separator: " ")
                return """
                    Phrase : « \(sentence) »
                    Mot tapé : « \(ambiguity.word) »
                    Mots possibles : \(choices.map { "« \($0) »" }.joined(separator: ", "))
                    """
            case .blank:
                let sentence = [ambiguity.sentencePrefix, "___"].filter { !$0.isEmpty }.joined(separator: " ")
                let slip = ambiguity.fallback == nil ? "peut-être avec une faute" : "avec une faute"
                return """
                    Phrase : « \(sentence) »
                    Le mot manquant a été tapé « \(ambiguity.word) », \(slip). \
                    Lequel complète le mieux la phrase : \(choices.joined(separator: ", ")) ?
                    """
            }
        }
    }

    /// What the model may answer. Without a fallback the typed word is offered first, so keeping
    /// it is always an option; with one the engine already knows a fix is due and asks which.
    static func choices(for ambiguity: Ambiguity) -> [String] {
        var seen = Set<String>()
        let words = ambiguity.fallback == nil ? [ambiguity.word] + ambiguity.candidates : ambiguity.candidates
        return words.filter { seen.insert($0).inserted }
    }
}

#if canImport(FoundationModels)
import FoundationModels

/// Asks Apple's on-device foundation model to choose between candidates. Decoding is
/// constrained to the candidate list, so each reply is one of the words offered.
/// Only compiled with Xcode 26 or later; requires Apple Intelligence to be enabled.
@available(macOS 26.0, *)
final class AppleIntelligenceArbiter: ContextArbiter, @unchecked Sendable {
    typealias Question = ContextArbiters.Question

    /// Past this the user has moved on: the engine's own pick, if any, applies instead.
    private static let timeout: Duration = .milliseconds(1500)

    private let lock = NSLock()
    /// Idle sessions that have already read their instructions. Reusing one answers in ~0.35 s
    /// on an M2, against ~1 s for a fresh one; a word asked while it is busy gets a fresh one.
    private var idle: [Question: LanguageModelSession] = [:]

    var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    func prewarm() {
        let sessions = lock.withLock {
            for question in Question.allCases where idle[question] == nil {
                idle[question] = LanguageModelSession(instructions: question.instructions)
            }
            return Array(idle.values)
        }
        sessions.forEach { $0.prewarm() }
    }

    func resolve(_ ambiguity: Ambiguity) async -> String? {
        guard isAvailable, ContextArbiters.choices(for: ambiguity).count > 1 else { return nil }
        return await withTaskGroup(of: String?.self) { group in
            group.addTask {
                async let typo = self.ask(.typo, about: ambiguity)
                async let blank = self.ask(.blank, about: ambiguity)
                let answers = await (typo, blank)
                return answers.0 == answers.1 ? answers.0 : nil
            }
            group.addTask {
                try? await Task.sleep(for: Self.timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func ask(_ question: Question, about ambiguity: Ambiguity) async -> String? {
        let session = lock.withLock {
            idle.removeValue(forKey: question) ?? LanguageModelSession(instructions: question.instructions)
        }
        defer { recycle(session, for: question) }
        do {
            let schema = try GenerationSchema(
                root: DynamicGenerationSchema(name: "Mot", anyOf: ContextArbiters.choices(for: ambiguity)),
                dependencies: []
            )
            let response = try await session.respond(
                to: question.prompt(for: ambiguity),
                schema: schema,
                includeSchemaInPrompt: false,
                options: GenerationOptions(samplingMode: .greedy)
            )
            let word = try response.content.value(String.self).trimmingCharacters(in: .whitespaces)
            return ambiguity.candidates.contains(word) ? word : nil
        } catch {
            return nil
        }
    }

    /// Forgets the exchange so each word is judged on its own, and keeps the session for the next.
    private func recycle(_ session: LanguageModelSession, for question: Question) {
        guard #available(macOS 27.0, *), !session.isResponding else { return }
        session.transcript.removeLast(max(session.transcript.count - 1, 0))
        lock.withLock { if idle[question] == nil { idle[question] = session } }
    }
}
#endif
