# Retouche

Correction automatique façon iPhone pour tout le Mac. Retouche vit dans la barre des menus, corrige les fautes de frappe dans toutes les apps au moment où vous tapez espace, et reconnaît à chaque phrase si vous écrivez en français ou en anglais.

- `continure` → `continuer`, `etre` → `être`, `jai` → `j'ai`, `parceque` → `parce que`
- `teh` → `the`, `definately` → `definitely`, `adress` → `address`
- Ne touche jamais à un mot qui existe dans l'une de vos langues, aux noms propres, sigles, URLs, e-mails, chiffres ni à l'argot (`mdr`, `jsp`, `btw`…).
- ⌫ juste après une correction l'annule, et le mot n'est plus jamais corrigé.
- Une bulle animée apparaît sous le mot corrigé.

## Comment ça marche

```
Touches ──► Event tap (thread dédié) ──► TypingSession ──► CorrectionEngine ──► backspaces + texte
               │                         (buffer, undo,     │
               │                          corrections        ├─ NSSpellChecker : moteur d'autocorrection d'Apple
               │                          différées)         ├─ NaturalLanguage : langue de la phrase
               │                                             ├─ TypoMetric : distance de frappe (AZERTY/QWERTY)
               └─ Accessibilité : texte avant le curseur      └─ Apple Intelligence : cas ambigus (Xcode 26+)
                  et position du mot pour la bulle
```

- **Moteur d'Apple, garde-fous à nous.** Les candidats viennent du correcteur système de macOS (le même que TextEdit, Mail et Notes, avec votre dictionnaire personnel). Retouche ajoute une distance de frappe pondérée : lettres inversées, accents oubliés, touches voisines sur votre clavier réel. Une correction n'est appliquée que si elle s'explique par une faute de frappe.
- **Bilingue par phrase.** La langue est estimée à partir de NaturalLanguage, d'un vote des dictionnaires et de la phrase précédente. Un mot qui existe dans une autre de vos langues n'est corrigé que si la seule différence est un accent ou une apostrophe (`deja` → `déjà` dans une phrase clairement française), ou une simple inversion de lettres dans une longue phrase sans ambiguïté.
- **Aucun ralentissement.** Le mot est évalué pendant que vous le tapez. Quand vous appuyez sur espace, la réponse est presque toujours prête. Sinon, la correction arrive un instant plus tard, sans jamais bloquer la frappe.
- **Rien ne sort du Mac.** Pas de réseau, pas de journal de frappe.

## Lancer

Prérequis : macOS 14 ou plus récent, Xcode 16 ou plus récent.

```bash
make run
```

Au premier lancement, autorisez Retouche dans **Réglages Système › Confidentialité et sécurité › Accessibilité**. L'app est signée « ad hoc » : macOS considère chaque nouveau build comme une nouvelle app, il faut donc renouveler cette autorisation après chaque recompilation. Pour l'éviter, choisissez votre équipe (un Apple ID gratuit suffit) dans Xcode, onglet *Signing & Capabilities*.

Ouvrez `Retouche.xcodeproj` dans Xcode pour développer.

```bash
make test       # tests unitaires du moteur
make eval       # tape ~100 phrases FR/EN à travers le vrai moteur : précision et latence
make snapshots  # rendu PNG du menu, de la bulle et des réglages
```

## Apple Intelligence

`Packages/RetoucheKit/Sources/RetoucheKit/ContextArbiter.swift` fait appel au modèle de langage on-device d'Apple (framework `FoundationModels`) lorsque l'orthographe ne suffit pas à trancher entre plusieurs candidats. Ce code n'est compilé qu'avec Xcode 26 ou plus récent (SDK macOS 26). Avec un Xcode plus ancien, il est simplement exclu et l'onglet Intelligence l'indique.

## Correction automatique de macOS

Si « Corriger l'orthographe automatiquement » est activé dans Réglages Système › Clavier › Saisie de texte, macOS corrige aussi les mots dans les apps natives. Retouche continue de fonctionner, mais n'applique alors que les corrections instantanées. Pour lui laisser la main partout, désactivez l'option de macOS.

## Structure

- `Retouche/` : l'app (SwiftUI + AppKit) : barre des menus, réglages, bulle, event tap, Accessibilité.
- `Packages/RetoucheKit/` : moteur testable sans interface : `CorrectionEngine`, `TypingSession`, `LanguageDetector`, `TypoMetric`.
