import AppKit
import Observation
import OSLog
import RetoucheKit
import ServiceManagement

struct CorrectionRecord: Identifiable, Hashable {
    let id = UUID()
    let correction: Correction
    let appName: String?
    let date: Date
    var wasReverted = false
}

struct FrontmostApp: Equatable {
    var name: String
    var bundleID: String
    var icon: NSImage?
}

enum PermissionState: Equatable {
    case checking, missing, granted
    /// Trusted, but macOS refused the event tap until Retouche is relaunched.
    case needsRelaunch
}

enum IntelligenceStatus: Equatable {
    case available
    /// This build was made with an SDK older than macOS 26 (Xcode < 26).
    case notCompiled
    /// Compiled in, but Apple Intelligence is off or unsupported on this Mac.
    case unavailable
}

@MainActor
@Observable
final class AppModel {
    // MARK: Preferences

    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.enabled); refreshRuntime() }
    }
    var showsAnimation: Bool {
        didSet { defaults.set(showsAnimation, forKey: Keys.animation) }
    }
    var primaryLanguage: String {
        didSet { defaults.set(primaryLanguage, forKey: Keys.primary); refreshEngine() }
    }
    /// Empty when the user writes in a single language.
    var secondaryLanguage: String {
        didSet { defaults.set(secondaryLanguage, forKey: Keys.secondary); refreshEngine() }
    }
    var excludedApps: [String] {
        didSet { defaults.set(excludedApps, forKey: Keys.excluded); refreshRuntime() }
    }
    var ignoredWords: [String] {
        didSet { defaults.set(ignoredWords, forKey: Keys.ignored); refreshEngine() }
    }
    var usesIntelligence: Bool {
        didSet { defaults.set(usesIntelligence, forKey: Keys.intelligence); refreshRuntime() }
    }
    var strength: CorrectionStrength {
        didSet { defaults.set(strength.rawValue, forKey: Keys.strength); refreshEngine() }
    }

    // MARK: State

    private(set) var permission: PermissionState = .checking
    private(set) var recent: [CorrectionRecord] = []
    private(set) var correctionsToday = 0
    private(set) var correctionsTotal = 0
    private(set) var detectedLanguage: String?
    private(set) var frontmostApp: FrontmostApp?
    private(set) var keyboardLayoutName = ""
    private(set) var keyboardLayout: KeyboardLayout = .azerty
    private(set) var isInputMethodActive = false
    /// macOS's built-in autocorrection also rewrites words in native apps.
    private(set) var isSystemAutocorrectEnabled = false
    /// Bumped on every correction; the menu bar icon animates on change.
    private(set) var correctionPulse = 0

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var keyboard: KeyboardService!
    @ObservationIgnored private let overlay = OverlayController()
    @ObservationIgnored private var permissionTimer: Timer?

    init() {
        defaults.register(defaults: [
            Keys.enabled: true,
            Keys.animation: true,
            Keys.primary: "fr",
            Keys.secondary: "en",
            Keys.excluded: Self.defaultExcludedApps,
            Keys.intelligence: true,
        ])
        isEnabled = defaults.bool(forKey: Keys.enabled)
        showsAnimation = defaults.bool(forKey: Keys.animation)
        primaryLanguage = defaults.string(forKey: Keys.primary) ?? "fr"
        secondaryLanguage = defaults.string(forKey: Keys.secondary) ?? "en"
        excludedApps = defaults.stringArray(forKey: Keys.excluded) ?? []
        ignoredWords = defaults.stringArray(forKey: Keys.ignored) ?? []
        usesIntelligence = defaults.bool(forKey: Keys.intelligence)
        strength = defaults.string(forKey: Keys.strength).flatMap(CorrectionStrength.init(rawValue:)) ?? .balanced
        loadStatistics()

        keyboard = KeyboardService(hooks: makeHooks())
        keyboard.inputSources.onChange = { [weak self, controller = keyboard.controller] snapshot in
            controller.updateLayout(snapshot.layoutData)
            controller.reset()
            self?.inputSourceChanged(snapshot)
        }
    }

    // MARK: Lifecycle

    func start() {
        refreshEngine()
        keyboard.start()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.applicationActivated(application) }
        }
        applicationActivated(NSWorkspace.shared.frontmostApplication)
        checkPermission()
    }

    func requestPermission() {
        Accessibility.requestTrust()
        NSWorkspace.shared.open(Accessibility.settingsURL)
        checkPermission()
    }

    /// For an entry left over from an earlier build: checked in System Settings, yet not trusted.
    func repairPermission() {
        Accessibility.resetTrust()
        requestPermission()
    }

    func relaunch() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { @Sendable _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    private func checkPermission() {
        guard Accessibility.isTrusted else {
            permission = .missing
            pollPermission()
            return
        }
        permissionTimer?.invalidate()
        permissionTimer = nil
        permission = keyboard.isTapRunning || keyboard.startTap() ? .granted : .needsRelaunch
        Self.log.notice("Accessibility trusted, keyboard tap \(self.permission == .granted ? "running" : "refused", privacy: .public)")
        refreshRuntime()
    }

    private func pollPermission() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, Accessibility.isTrusted else { return }
                self.checkPermission()
            }
        }
    }

    // MARK: Derived state

    var isPausedForFrontmostApp: Bool {
        guard let bundleID = frontmostApp?.bundleID else { return false }
        return Self.matches(bundleID, excludedApps)
    }

    var isCorrecting: Bool {
        isEnabled && permission == .granted && !isPausedForFrontmostApp && !isInputMethodActive
    }

    var intelligenceStatus: IntelligenceStatus {
        guard ContextArbiters.isCompiledWithFoundationModels else { return .notCompiled }
        return keyboard.arbiter?.isAvailable == true ? .available : .unavailable
    }

    var availableLanguages: [String] {
        keyboard.engine.availableLanguages
    }

    var launchesAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                Self.log.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func toggleFrontmostAppExclusion() {
        guard let bundleID = frontmostApp?.bundleID else { return }
        if isPausedForFrontmostApp {
            excludedApps.removeAll { $0 == bundleID || (bundleID.hasPrefix($0) && $0.hasSuffix(".")) }
        } else {
            excludedApps.append(bundleID)
        }
    }

    func ignore(_ record: CorrectionRecord) {
        let word = record.correction.original.lowercased()
        if !ignoredWords.contains(word) { ignoredWords.append(word) }
        keyboard.controller.reject(word)
    }

    func learn(_ record: CorrectionRecord) {
        keyboard.engine.learn(record.correction.original)
        recent.removeAll { $0.id == record.id }
    }

    func clearHistory() {
        recent.removeAll()
    }

    // MARK: Events

    private func makeHooks() -> KeyboardHooks {
        KeyboardHooks(
            applied: { [weak self] applied in
                Task { @MainActor in self?.didApply(applied) }
            },
            reverted: { [weak self] correction in
                Task { @MainActor in self?.didRevert(correction) }
            },
            languageChanged: { [weak self] language in
                Task { @MainActor in self?.detectedLanguage = language }
            },
            caretMoved: { [weak self] generation in
                Task { @MainActor in self?.keyboard.scheduleSeed(generation: generation) }
            }
        )
    }

    private func didApply(_ applied: TypingSession.Applied) {
        let record = CorrectionRecord(correction: applied.correction, appName: frontmostApp?.name, date: .now)
        recent.insert(record, at: 0)
        if recent.count > 30 { recent.removeLast(recent.count - 30) }
        detectedLanguage = applied.correction.language
        correctionPulse += 1
        countCorrection()
        guard showsAnimation else { return }
        let app = frontmostApp?.bundleID ?? "-"
        keyboard.locate(applied) { [weak self] anchor in
            // Where the bubble went, never what was typed.
            Self.log.notice("Bubble anchor in \(app, privacy: .public): \(anchor?.precision.rawValue ?? "none", privacy: .public)")
            self?.overlay.show(applied.correction, at: anchor)
        }
    }

    private func didRevert(_ correction: Correction) {
        if let index = recent.firstIndex(where: { $0.correction == correction && !$0.wasReverted }) {
            recent[index].wasReverted = true
        }
        let word = correction.original.lowercased()
        if !ignoredWords.contains(word) { ignoredWords.append(word) }
        overlay.dismiss()
    }

    private func applicationActivated(_ application: NSRunningApplication?) {
        guard let application, application.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        frontmostApp = FrontmostApp(
            name: application.localizedName ?? application.bundleIdentifier ?? "",
            bundleID: application.bundleIdentifier ?? "",
            icon: application.icon
        )
        keyboard.focusChanged(to: application)
        // Have the model loaded before the first close call in this app.
        if usesIntelligence, intelligenceStatus == .available { keyboard.arbiter?.prewarm() }
        refreshRuntime()
    }

    private func inputSourceChanged(_ snapshot: InputSourceMonitor.Snapshot) {
        keyboardLayoutName = snapshot.localizedName
        keyboardLayout = snapshot.layout
        isInputMethodActive = !snapshot.isPlainKeyboardLayout
        refreshRuntime()
    }

    private func refreshEngine() {
        guard let keyboard else { return }
        var languages = [primaryLanguage]
        if !secondaryLanguage.isEmpty, secondaryLanguage != primaryLanguage { languages.append(secondaryLanguage) }
        keyboard.engine.update(EngineConfiguration(
            languages: languages,
            layout: keyboardLayout,
            ignoredWords: Set(ignoredWords),
            strength: strength,
            asksContext: usesIntelligence && intelligenceStatus == .available && !isSystemAutocorrectEnabled
        ))
    }

    private func refreshRuntime() {
        guard let keyboard else { return }
        isSystemAutocorrectEnabled = Self.readSystemAutocorrect()
        keyboard.controller.update(KeyboardRuntimeState(
            isActive: isCorrecting,
            usesArbiter: usesIntelligence,
            allowsLateCorrections: !isSystemAutocorrectEnabled
        ))
        // Close calls go to Apple Intelligence only while it can answer late.
        refreshEngine()
    }

    /// macOS's own "Correct spelling automatically" (Keyboard › Text Input), on unless the user turned it off.
    private static func readSystemAutocorrect() -> Bool {
        UserDefaults.standard.object(forKey: "NSAutomaticSpellingCorrectionEnabled") as? Bool ?? true
    }

    static let keyboardSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!

    // MARK: Statistics

    private func loadStatistics() {
        correctionsTotal = defaults.integer(forKey: Keys.total)
        correctionsToday = defaults.string(forKey: Keys.day) == Self.today ? defaults.integer(forKey: Keys.dayCount) : 0
    }

    private func countCorrection() {
        if defaults.string(forKey: Keys.day) != Self.today {
            defaults.set(Self.today, forKey: Keys.day)
            correctionsToday = 0
        }
        correctionsToday += 1
        correctionsTotal += 1
        defaults.set(correctionsToday, forKey: Keys.dayCount)
        defaults.set(correctionsTotal, forKey: Keys.total)
    }

    private static var today: String {
        Date.now.formatted(.iso8601.year().month().day())
    }

    // MARK: Constants

    private static let log = Logger(subsystem: "app.retouche.Retouche", category: "app")

    static func matches(_ bundleID: String, _ rules: [String]) -> Bool {
        rules.contains { $0 == bundleID || ($0.hasSuffix(".") && bundleID.hasPrefix($0)) }
    }

    /// Terminals, code editors and password managers: places where autocorrect does harm.
    static let defaultExcludedApps = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty", "io.alacritty", "com.github.wez.wezterm",
        "com.apple.dt.Xcode", "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92", "dev.zed.Zed", "com.sublimetext.4", "com.panic.Nova", "com.jetbrains.",
        "com.1password.1password", "com.agilebits.onepassword7", "com.apple.keychainaccess",
    ]

    private enum Keys {
        static let enabled = "enabled"
        static let animation = "showsAnimation"
        static let primary = "primaryLanguage"
        static let secondary = "secondaryLanguage"
        static let excluded = "excludedApps"
        static let ignored = "ignoredWords"
        static let intelligence = "usesIntelligence"
        static let strength = "correctionStrength"
        static let day = "stats.day"
        static let dayCount = "stats.dayCount"
        static let total = "stats.total"
    }
}

#if DEBUG
extension AppModel {
    /// Sample data for offscreen snapshot renders.
    func loadSampleContent() {
        permission = .granted
        isSystemAutocorrectEnabled = Self.readSystemAutocorrect()
        correctionsToday = 12
        detectedLanguage = "fr"
        frontmostApp = FrontmostApp(name: "Messages", bundleID: "com.apple.MobileSMS", icon: NSWorkspace.shared.icon(forFile: "/System/Applications/Messages.app"))
        let samples: [(String, String, String, Correction.Source, TimeInterval, Bool, String)] = [
            ("continure", "continuer", "fr", .appleSpelling, 40, false, "Messages"),
            ("cafr", "café", "fr", .appleIntelligence, 95, false, "Messages"),
            ("teh", "the", "en", .appleSpelling, 180, false, "Slack"),
            ("deja", "déjà", "fr", .appleSpelling, 420, false, "Mail"),
            ("adress", "address", "en", .keyboardModel, 900, false, "Safari"),
            ("Jai", "J'ai", "fr", .appleSpelling, 1500, true, "Notes"),
        ]
        recent = samples.map {
            CorrectionRecord(
                correction: Correction(original: $0.0, replacement: $0.1, language: $0.2, source: $0.3),
                appName: $0.6,
                date: .now.addingTimeInterval(-$0.4),
                wasReverted: $0.5
            )
        }
    }
}
#endif
