import RetoucheKit
import SwiftUI

struct MenuContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(14)
            Divider()
            switch model.permission {
            case .granted, .checking:
                summary
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                Divider()
                RecentCorrectionsList(model: model)
                if let app = model.frontmostApp {
                    Divider()
                    FrontmostAppRow(app: app, isPaused: model.isPausedForFrontmostApp) {
                        model.toggleFrontmostAppExclusion()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            case .missing:
                PermissionCard(model: model)
                    .padding(14)
            case .needsRelaunch:
                RelaunchCard(model: model)
                    .padding(14)
            }
            Divider()
            footer
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
        .frame(width: 330)
    }

    private var header: some View {
        HStack(spacing: 10) {
            AppIcon(isActive: model.isCorrecting)
            VStack(alignment: .leading, spacing: 1) {
                Text("Retouche")
                    .font(.system(size: 13, weight: .semibold))
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            Spacer()
            Toggle("Correction automatique", isOn: $model.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .disabled(model.permission != .granted)
        }
    }

    private var statusText: String {
        switch model.permission {
        case .checking: return "Démarrage…"
        case .missing: return "Autorisation requise"
        case .needsRelaunch: return "Redémarrage nécessaire"
        case .granted:
            if !model.isEnabled { return "En pause" }
            if model.isInputMethodActive { return "En pause avec cette méthode de saisie" }
            if model.isPausedForFrontmostApp, let app = model.frontmostApp { return "Désactivé dans \(app.name)" }
            return "Correction active"
        }
    }

    /// One number leads; the language of the current sentence sits quietly beside it.
    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(model.correctionsToday.formatted())
                .font(.system(size: 28, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(model.correctionsToday > 1 ? "corrections aujourd'hui" : "correction aujourd'hui")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Label(LanguageName.full(model.detectedLanguage ?? model.primaryLanguage), systemImage: "globe")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .help("Langue de la phrase en cours")
                .contentTransition(.opacity)
                .animation(.smooth, value: model.detectedLanguage)
        }
        .lineLimit(1)
    }

    private var footer: some View {
        HStack {
            SettingsLink {
                Label("Réglages…", systemImage: "gearshape")
            }
            .buttonStyle(MenuRowButtonStyle())
            .keyboardShortcut(",")
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quitter")
            }
            .buttonStyle(MenuRowButtonStyle())
            .keyboardShortcut("q")
        }
    }
}

private struct RecentCorrectionsList: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Récemment")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !model.recent.isEmpty {
                    Button("Effacer") { model.clearHistory() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            if model.recent.isEmpty {
                Text("Vos corrections apparaîtront ici. Appuyez sur ⌫ juste après une correction pour l'annuler.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .padding(.top, 2)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.recent.prefix(12)) { record in
                            CorrectionRow(record: record, model: model)
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .frame(maxHeight: 220)
                .padding(.bottom, 6)
            }
        }
    }
}

private struct CorrectionRow: View {
    let record: CorrectionRecord
    let model: AppModel
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(record.wasReverted ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint))
                .frame(width: 14)
                .help(record.correction.source == .appleIntelligence ? "Choisi par Apple Intelligence d'après la phrase" : "")
            HStack(spacing: 5) {
                Text(record.correction.original)
                    .foregroundStyle(.secondary)
                Text("→")
                    .foregroundStyle(.tertiary)
                Text(record.correction.replacement)
                    .fontWeight(.medium)
                    .strikethrough(record.wasReverted, color: .secondary)
            }
            .font(.system(size: 13))
            .lineLimit(1)
            Spacer(minLength: 4)
            if isHovered && !record.wasReverted {
                HStack(spacing: 2) {
                    Button { model.ignore(record) } label: { Image(systemName: "hand.raised") }
                        .help("Ne plus corriger « \(record.correction.original) »")
                    Button { model.learn(record) } label: { Image(systemName: "text.book.closed") }
                        .help("Ajouter « \(record.correction.original) » au dictionnaire de macOS")
                }
                .buttonStyle(IconButtonStyle())
                .transition(.opacity)
            } else {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(isHovered ? Color.primary.opacity(0.06) : .clear))
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering } }
    }

    private var icon: String {
        if record.wasReverted { return "arrow.uturn.backward" }
        return record.correction.source == .appleIntelligence ? Symbol.intelligence : "checkmark"
    }

    private var caption: String {
        let time = record.date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        guard let app = record.appName else { return time }
        return "\(app) · \(time)"
    }
}

private struct FrontmostAppRow: View {
    let app: FrontmostApp
    let isPaused: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
            }
            Text(isPaused ? "Désactivé dans \(app.name)" : "Actif dans \(app.name)")
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer()
            Toggle("", isOn: Binding(get: { !isPaused }, set: { _ in toggle() }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
        }
    }
}

struct PermissionCard: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Autoriser l'accès à l'accessibilité")
                    .font(.system(size: 13, weight: .semibold))
            } icon: {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.tint)
            }
            Text("Retouche a besoin de cette autorisation pour voir les mots que vous tapez et les corriger dans toutes vos apps. Tout reste sur votre Mac : rien n'est enregistré ni envoyé.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                model.requestPermission()
            } label: {
                Text("Ouvrir les Réglages Système")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("En attente de l'autorisation…")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Divider()
                .padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text("Retouche est déjà coché mais rien ne se passe ?")
                    .font(.system(size: 11, weight: .medium))
                Text("macOS a gardé l'autorisation d'une version précédente de l'app. Réinitialisez-la, puis cochez Retouche à nouveau.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Réinitialiser l'autorisation") {
                    model.repairPermission()
                }
                .controlSize(.small)
            }
        }
    }
}

private struct RelaunchCard: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Autorisation accordée")
                .font(.system(size: 13, weight: .semibold))
            Text("macOS demande de relancer Retouche pour activer la correction.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Button {
                model.relaunch()
            } label: {
                Text("Relancer Retouche").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}
