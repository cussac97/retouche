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

    static func prompt(for ambiguity: Ambiguity) -> String {
        let options = ambiguity.candidates.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
        return """
        Texte en cours de frappe : « \(ambiguity.sentencePrefix) \(ambiguity.word) »
        Le dernier mot, « \(ambiguity.word) », contient peut-être une faute de frappe.
        0. \(ambiguity.word) (le laisser tel quel)
        \(options)
        Réponds uniquement par le numéro du mot que l'auteur voulait écrire.
        """
    }

    /// Reads the leading number of a model reply and maps it to a candidate.
    static func candidate(fromReply reply: String, in ambiguity: Ambiguity) -> String? {
        let digits = reply.trimmingCharacters(in: .whitespacesAndNewlines).prefix(while: \.isNumber)
        guard let index = Int(digits), index >= 1, index <= ambiguity.candidates.count else { return nil }
        return ambiguity.candidates[index - 1]
    }
}

#if canImport(FoundationModels)
import FoundationModels

/// Asks Apple's on-device foundation model to choose between candidates.
/// Only compiled with Xcode 26 or later; requires Apple Intelligence to be enabled.
@available(macOS 26.0, *)
final class AppleIntelligenceArbiter: ContextArbiter {
    var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    func prewarm() {
        makeSession().prewarm()
    }

    func resolve(_ ambiguity: Ambiguity) async -> String? {
        guard isAvailable else { return nil }
        do {
            let options = GenerationOptions(sampling: .greedy, maximumResponseTokens: 4)
            let response = try await makeSession().respond(to: ContextArbiters.prompt(for: ambiguity), options: options)
            return ContextArbiters.candidate(fromReply: response.content, in: ambiguity)
        } catch {
            return nil
        }
    }

    private func makeSession() -> LanguageModelSession {
        LanguageModelSession(instructions: "Tu es le correcteur orthographique d'un clavier. Tu choisis le mot que l'auteur voulait taper, en français ou en anglais, sans jamais réécrire la phrase.")
    }
}
#endif
