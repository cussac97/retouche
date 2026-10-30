import Foundation
import RetoucheKit

// Types each sentence character by character through TypingSession and the
// real CorrectionEngine (macOS spell checker), then compares the result with
// the expected text. Run: swift run -c release retouche-eval

struct Case {
    var typed: String
    var expected: String
}

let mustFix: [Case] = [
    // French: swapped letters, missing accents, AZERTY slips
    .init(typed: "Je vais continure demain.", expected: "Je vais continuer demain."),
    .init(typed: "Il faut etre patient.", expected: "Il faut être patient."),
    .init(typed: "Je suis deja parti.", expected: "Je suis déjà parti."),
    .init(typed: "Comment ca va ?", expected: "Comment ça va ?"),
    .init(typed: "Merci beaucuop pour ton aide.", expected: "Merci beaucoup pour ton aide."),
    .init(typed: "C'est vraimetn super.", expected: "C'est vraiment super."),
    .init(typed: "On se voit demian matin.", expected: "On se voit demain matin."),
    .init(typed: "Je pense que tu as raiosn.", expected: "Je pense que tu as raison."),
    .init(typed: "Bonjour, je voulais savior si tu es libre.", expected: "Bonjour, je voulais savoir si tu es libre."),
    .init(typed: "Je n'ai pas recu ton message.", expected: "Je n'ai pas reçu ton message."),
    .init(typed: "C'est tres bien.", expected: "C'est très bien."),
    .init(typed: "Il est peut-etre en retard.", expected: "Il est peut-être en retard."),
    .init(typed: "Je suis en retard parceque le train est bloqué.", expected: "Je suis en retard parce que le train est bloqué."),
    .init(typed: "L'appartemnet est grand.", expected: "L'appartement est grand."),
    .init(typed: "Il faut que je travialle.", expected: "Il faut que je travaille."),
    .init(typed: "Je t'envoie le docuemnt ce soir.", expected: "Je t'envoie le document ce soir."),
    .init(typed: "Jai fini.", expected: "J'ai fini."),
    .init(typed: "Mainetnant on y va.", expected: "Maintenant on y va."),
    .init(typed: "C'est quelqeu chose.", expected: "C'est quelque chose."),
    .init(typed: "J'ai oublié mon odrinateur.", expected: "J'ai oublié mon ordinateur."),
    .init(typed: "Ne t'inqiuète pas.", expected: "Ne t'inquiète pas."),
    .init(typed: "Je suis daccord avec toi.", expected: "Je suis d'accord avec toi."),
    .init(typed: "On a un probleme avec le serveur.", expected: "On a un problème avec le serveur."),
    .init(typed: "Je suis trés content.", expected: "Je suis très content."),
    .init(typed: "Il fait beua aujourd'hui.", expected: "Il fait beau aujourd'hui."),
    .init(typed: "Je suis contzent de te voir.", expected: "Je suis content de te voir."),
    .init(typed: "Tu peux m'appeler quand tu veux, je suis dispnible.", expected: "Tu peux m'appeler quand tu veux, je suis disponible."),
    .init(typed: "Le rendez-vosu est à 15h.", expected: "Le rendez-vous est à 15h."),
    .init(typed: "Il a commencé a pleuvoir, c'est dommgae.", expected: "Il a commencé a pleuvoir, c'est dommage."),
    .init(typed: "Etre ou ne pas être.", expected: "Être ou ne pas être."),
    // English
    .init(typed: "I will definately come.", expected: "I will definitely come."),
    .init(typed: "Thanks for teh update.", expected: "Thanks for the update."),
    .init(typed: "This is reallly cool.", expected: "This is really cool."),
    .init(typed: "We shoudl talk tomorrow.", expected: "We should talk tomorrow."),
    .init(typed: "See you at the meeting tomorow.", expected: "See you at the meeting tomorrow."),
    .init(typed: "I recieve a lot of emails.", expected: "I receive a lot of emails."),
    .init(typed: "That is so wierd.", expected: "That is so weird."),
    .init(typed: "Please keep them seperate.", expected: "Please keep them separate."),
    .init(typed: "It happened becuase of the rain.", expected: "It happened because of the rain."),
    .init(typed: "Yes and i think so.", expected: "Yes and I think so."),
    // Switching language mid-text
    .init(typed: "Merci pour ton aide. I really apprecaite it.", expected: "Merci pour ton aide. I really appreciate it."),
    .init(typed: "That's great. Je vais regarder ça demian.", expected: "That's great. Je vais regarder ça demain."),
]

let mustKeep: [String] = [
    "On a fait un meeting avec l'équipe produit.",
    "J'ai push le commit sur la branche main.",
    "Nicolas et Camille arrivent à Lyon demain.",
    "Envoie-moi un mail à contact@exemple.fr stp.",
    "Le site est https://www.apple.com/fr et c'est top.",
    "Mdr t'es trop drôle, jsp quoi dire.",
    "Le PDG de la SNCF a parlé à la TV.",
    "J'utilise SwiftUI et AppKit sur macOS.",
    "C'est un vrai game changer pour nous.",
    "Ouiiii trop bien !!!",
    "Il a dit « bonjour » puis il est parti.",
    "Je suis à Paris, où il fait beau.",
    "Let's grab a coffee at Starbucks later.",
    "The API returns JSON with a userId field.",
    "Pour info, the deadline is Friday.",
    "Je suis au bureau, but I'll be home soon.",
    "On se fait un call avec le client à 14h ?",
    "Le feedback de l'équipe était top.",
    "J'ai lu the Guardian ce matin.",
    "Il faut checker le dashboard avant la release.",
    "Rendez-vous chez Mme Dupont à 9h30.",
    "Je t'envoie le lien sur Slack et Notion.",
    "Ok, merci ! À plus.",
    "The cat sat on the mat.",
    "I'm going to the café near the gare.",
]

// Held-out cases, never used to tune the policy.
let heldOutFix: [Case] = [
    .init(typed: "Je te rapelle dans cinq minutes.", expected: "Je te rappelle dans cinq minutes."),
    .init(typed: "Il est vraiment tres fatigué.", expected: "Il est vraiment très fatigué."),
    .init(typed: "On peut se voir aprés le travail ?", expected: "On peut se voir après le travail ?"),
    .init(typed: "Je ne sais pas pourquio il est parti.", expected: "Je ne sais pas pourquoi il est parti."),
    .init(typed: "C'est une trés bonne idee.", expected: "C'est une très bonne idée."),
    .init(typed: "Nous avons recu votre demande.", expected: "Nous avons reçu votre demande."),
    .init(typed: "Il faut prendre une decision rapidement.", expected: "Il faut prendre une décision rapidement."),
    .init(typed: "Je vous remercie pour votre resonse.", expected: "Je vous remercie pour votre réponse."),
    .init(typed: "Le meme jour, il est venu.", expected: "Le même jour, il est venu."),
    .init(typed: "Je suis desole pour le retard.", expected: "Je suis désolé pour le retard."),
    .init(typed: "Elle travaille dans une entrepirse de conseil.", expected: "Elle travaille dans une entreprise de conseil."),
    .init(typed: "Tu as vu le mesage que je t'ai envoyé ?", expected: "Tu as vu le message que je t'ai envoyé ?"),
    .init(typed: "We need to schedlue a call.", expected: "We need to schedule a call."),
    .init(typed: "I would like to konw more.", expected: "I would like to know more."),
    .init(typed: "Can you send me the adress please?", expected: "Can you send me the address please?"),
    .init(typed: "It was a great experiance overall.", expected: "It was a great experience overall."),
    .init(typed: "Let me knwo if you need anything.", expected: "Let me know if you need anything."),
    .init(typed: "This is probaly the best option.", expected: "This is probably the best option."),
]

let heldOutKeep: [String] = [
    "J'ai fait un brainstorming avec la team marketing.",
    "On a un daily à 10h sur Teams.",
    "Le build a fail sur la CI, je relance.",
    "Tu peux me forward le mail de Jean-Pierre ?",
    "Je bosse sur le front en React et TypeScript.",
    "Il habite à Saint-Étienne depuis 2019.",
    "J'ai acheté un MacBook Pro chez Fnac.",
    "C'est le best-seller de l'année.",
    "Bon week-end à tous !",
    "Ça marche, on fait comme ça.",
    "Il m'a dit : « on verra bien ».",
    "Le meeting est reporté à jeudi, sorry.",
    "Thanks a lot, c'est super gentil.",
    "We're meeting at the Louvre on Monday.",
    "Our KPIs look good this quarter.",
    "I'll ping Marie about the onboarding.",
    "She said it was a déjà vu moment.",
    "Hmm je sais pas trop, on verra.",
]

let engine = CorrectionEngine(configuration: EngineConfiguration(languages: ["fr", "en"], layout: .azerty))
engine.warmUp()
Thread.sleep(forTimeInterval: 1)

var latencies: [Double] = []

@MainActor
func type(_ sentence: String) -> (result: String, corrections: [Correction]) {
    let session = TypingSession()
    session.reset(knownBoundary: true)
    var document: [Character] = []
    var corrections: [Correction] = []
    for character in sentence + " " {
        let output = session.handle(.text(String(character))) { context, _ in
            let start = DispatchTime.now()
            let decision = engine.evaluate(context)
            latencies.append(Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e6)
            switch decision {
            case .correct(let correction): return .correct(correction)
            case .keep(let language): return .keep(language: language)
            case .ambiguous(let ambiguity): return .keep(language: ambiguity.language)
            }
        }
        if let rewrite = output.rewrite {
            document.removeLast(rewrite.deleteCount)
            document.append(contentsOf: rewrite.insert)
        }
        if let applied = output.applied { corrections.append(applied.correction) }
        if !output.consumesEvent { document.append(character) }
    }
    return (String(document).trimmingCharacters(in: .whitespaces), corrections)
}

@MainActor
func run(_ title: String, fix: [Case], keep: [String]) {
    var fixed = 0
    var falsePositives = 0
    print("\n===== \(title) =====\n— Phrases avec fautes —")
    for test in fix {
        let (result, corrections) = type(test.typed)
        let ok = result == test.expected
        if ok { fixed += 1 }
        let detail = corrections.map { "\($0.original)→\($0.replacement) [\($0.language), \($0.source.rawValue)]" }.joined(separator: ", ")
        print(ok ? "✅" : "❌", result, ok ? "" : "   (attendu : \(test.expected))", "  ", detail)
    }
    print("— Phrases correctes (ne doivent pas bouger) —")
    for sentence in keep {
        let (result, corrections) = type(sentence)
        let ok = result == sentence
        if !ok { falsePositives += 1 }
        let detail = corrections.map { "\($0.original)→\($0.replacement) [\($0.language)]" }.joined(separator: ", ")
        print(ok ? "✅" : "⚠️", result, detail)
    }
    print("\(title) — corrigées : \(fixed)/\(fix.count), fausses corrections : \(falsePositives)/\(keep.count) phrases")
}

run("Jeu de réglage", fix: mustFix, keep: mustKeep)
run("Jeu de validation (jamais vu)", fix: heldOutFix, keep: heldOutKeep)

let sorted = latencies.sorted()
func percentile(_ p: Double) -> Double { sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))] }
print("""

Latence par mot (non mise en cache) : médiane \(String(format: "%.2f", percentile(0.5))) ms, p95 \(String(format: "%.2f", percentile(0.95))) ms, max \(String(format: "%.2f", sorted.last ?? 0)) ms
""")
