import RetoucheKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            GeneralSettings(model: model)
                .tabItem { Label("Général", systemImage: "gearshape") }
            LanguageSettings(model: model)
                .tabItem { Label("Langues", systemImage: "globe") }
            AppsSettings(model: model)
                .tabItem { Label("Apps", systemImage: "square.grid.2x2") }
            WordsSettings(model: model)
                .tabItem { Label("Mots", systemImage: "character.book.closed") }
            IntelligenceSettings(model: model)
                .tabItem { Label("Intelligence", systemImage: "sparkles") }
        }
        .frame(width: 520, height: 430)
        .onAppear { NSApp.activate() }
    }
}

private struct GeneralSettings: View {
    @Bindable var model: AppModel
    @State private var launchesAtLogin = false

    var body: some View {
        Form {
            Section {
                Toggle("Correction automatique", isOn: $model.isEnabled)
                Toggle("Animer chaque correction", isOn: $model.showsAnimation)
                Toggle("Ouvrir Retouche à l'ouverture de session", isOn: $launchesAtLogin)
                    .onChange(of: launchesAtLogin) { _, newValue in model.launchesAtLogin = newValue }
            }
            if model.isSystemAutocorrectEnabled {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("La correction automatique de macOS est aussi active")
                            Text("Dans les apps natives, les deux correcteurs agissent sur les mêmes mots. Pour laisser Retouche décider seul, désactivez « Corriger l'orthographe automatiquement » dans Clavier › Saisie de texte › Modifier.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    Button("Ouvrir les réglages Clavier…") { NSWorkspace.shared.open(AppModel.keyboardSettingsURL) }
                }
            }
            Section("Annuler une correction") {
                LabeledContent("Juste après la correction", value: "⌫")
                Text("La correction est annulée et le mot n'est plus corrigé ensuite. Vous le retrouvez dans l'onglet Mots.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Autorisation") {
                LabeledContent("Accessibilité") {
                    switch model.permission {
                    case .granted: Label("Accordée", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .missing: Button("Autoriser…") { model.requestPermission() }
                    case .needsRelaunch: Button("Relancer") { model.relaunch() }
                    case .checking: ProgressView().controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { launchesAtLogin = model.launchesAtLogin }
    }
}

private struct LanguageSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                Picker("Langue principale", selection: $model.primaryLanguage) {
                    ForEach(model.availableLanguages, id: \.self) { Text(LanguageName.full($0)).tag($0) }
                }
                Picker("Deuxième langue", selection: $model.secondaryLanguage) {
                    Text("Aucune").tag("")
                    ForEach(model.availableLanguages.filter { $0 != model.primaryLanguage }, id: \.self) {
                        Text(LanguageName.full($0)).tag($0)
                    }
                }
            } footer: {
                Text("Retouche reconnaît la langue de chaque phrase et ne corrige jamais un mot qui existe dans l'une de vos langues. Vous pouvez passer du français à l'anglais au milieu d'un message.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Clavier") {
                LabeledContent("Disposition", value: model.keyboardLayoutName.isEmpty ? "—" : model.keyboardLayoutName)
                LabeledContent("Touches voisines", value: model.keyboardLayout.displayName)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppsSettings: View {
    @Bindable var model: AppModel
    @State private var selection: String?

    var body: some View {
        Form {
            Section {
                List(selection: $selection) {
                    ForEach(model.excludedApps, id: \.self) { bundleID in
                        AppRow(bundleID: bundleID).tag(bundleID)
                    }
                }
                .frame(minHeight: 230)
                HStack(spacing: 6) {
                    Button { addApp() } label: { Image(systemName: "plus") }
                    Button {
                        if let selection { model.excludedApps.removeAll { $0 == selection } }
                        selection = nil
                    } label: { Image(systemName: "minus") }
                    .disabled(selection == nil)
                    Spacer()
                    Button("Réinitialiser") { model.excludedApps = AppModel.defaultExcludedApps }
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Retouche ne corrige pas dans ces apps")
            } footer: {
                Text("Par défaut : terminaux, éditeurs de code et gestionnaires de mots de passe.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !model.excludedApps.contains(id) {
                model.excludedApps.append(id)
            }
        }
    }
}

private struct AppRow: View {
    let bundleID: String

    var body: some View {
        HStack(spacing: 8) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 18, height: 18)
                Text(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
            } else {
                Image(systemName: "app.dashed")
                    .frame(width: 18, height: 18)
                    .foregroundStyle(.tertiary)
                Text(bundleID.hasSuffix(".") ? "\(bundleID)*" : bundleID)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct WordsSettings: View {
    @Bindable var model: AppModel
    @State private var selection: String?

    var body: some View {
        Form {
            Section {
                if model.ignoredWords.isEmpty {
                    Text("Aucun mot pour l'instant. Annulez une correction avec ⌫ pour que Retouche ne corrige plus ce mot.")
                        .foregroundStyle(.secondary)
                } else {
                    List(selection: $selection) {
                        ForEach(model.ignoredWords.sorted(), id: \.self) { Text($0).tag($0) }
                    }
                    .frame(minHeight: 230)
                    HStack {
                        Button { model.ignoredWords.removeAll { $0 == selection }; selection = nil } label: { Image(systemName: "minus") }
                            .disabled(selection == nil)
                        Spacer()
                    }
                    .buttonStyle(.borderless)
                }
            } header: {
                Text("Mots jamais corrigés")
            }
        }
        .formStyle(.grouped)
    }
}

private struct IntelligenceSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Utiliser Apple Intelligence pour les cas ambigus", isOn: $model.usesIntelligence)
                    .disabled(model.intelligenceStatus != .available)
                LabeledContent("État") {
                    switch model.intelligenceStatus {
                    case .available:
                        Label("Disponible", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .unavailable:
                        Label("Apple Intelligence désactivé", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                    case .notCompiled:
                        Label("Nécessite Xcode 26", systemImage: "hammer").foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Quand l'orthographe seule ne suffit pas à trancher, le modèle d'Apple Intelligence intégré à macOS choisit le mot voulu d'après le contexte de la phrase, entièrement sur votre Mac. La correction arrive alors une fraction de seconde plus tard.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Moteur") {
                LabeledContent("Orthographe", value: "Correcteur de macOS")
                LabeledContent("Détection de langue", value: "NaturalLanguage")
                LabeledContent("Fautes de frappe", value: "Modèle clavier \(model.keyboardLayout.displayName)")
            }
        }
        .formStyle(.grouped)
    }
}
