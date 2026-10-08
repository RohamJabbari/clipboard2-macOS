import AppKit
import Observation

nonisolated enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "Follow System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

extension AppearanceMode {
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

nonisolated enum PanelSize: String, CaseIterable, Identifiable, Sendable {
    case compact, regular, large
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var size: CGSize {
        switch self {
        case .compact: CGSize(width: 660, height: 400)
        case .regular: CGSize(width: 780, height: 480)
        case .large: CGSize(width: 920, height: 580)
        }
    }
}

nonisolated struct AppTransformRule: Codable, Hashable, Identifiable, Sendable {
    var app: AppRef
    var transform: Transform
    var id: String { app.bundleID }
}

nonisolated struct CustomPrompt: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var prompt: String
}

/// UserDefaults-backed settings. Secrets (the Claude API key) never live here — see `Keychain`.
@Observable
final class Preferences {
    nonisolated enum Key {
        static let maxItems = "maxItems"
        static let maxAgeDays = "maxAgeDays"
        static let isPaused = "isPaused"
        static let appearance = "appearance"
        static let panelSize = "panelSize"
        static let ignoredApps = "ignoredApps"
        static let appTransforms = "appTransforms"
        static let claudeModel = "claudeModel"          // legacy, migrated into aiModels
        static let aiProvider = "aiProvider"
        static let aiModels = "aiModels"
        static let customBaseURL = "customBaseURL"
        static let secretGraceMinutes = "secretGraceMinutes"
        static let secretClearSeconds = "secretClearSeconds"
        static let customPrompts = "customPrompts"
        static let hasLaunchedBefore = "hasLaunchedBefore"
        static let hasShownAccessibilityOnboarding = "hasShownAccessibilityOnboarding"
    }

    /// 0 means "ask every time".
    static let secretGraceChoices = [0, 1, 5, 15, 60]
    /// 0 means "never clear".
    static let secretClearChoices = [15, 30, 60, 120, 0]
    /// 0 means "keep forever".
    static let maxAgeChoices = [1, 7, 30, 90, 365, 0]
    static let maxItemChoices = [100, 250, 500, 1000, 2500, 5000]

    @ObservationIgnored private let defaults: UserDefaults

    var maxItems: Int { didSet { defaults.set(maxItems, forKey: Key.maxItems) } }
    var maxAgeDays: Int { didSet { defaults.set(maxAgeDays, forKey: Key.maxAgeDays) } }
    var isPaused: Bool { didSet { defaults.set(isPaused, forKey: Key.isPaused) } }
    var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) } }
    var panelSize: PanelSize { didSet { defaults.set(panelSize.rawValue, forKey: Key.panelSize) } }
    var ignoredApps: [AppRef] { didSet { store(ignoredApps, Key.ignoredApps) } }
    var appTransforms: [AppTransformRule] { didSet { store(appTransforms, Key.appTransforms) } }
    var aiProvider: AIProviderKind { didSet { defaults.set(aiProvider.rawValue, forKey: Key.aiProvider) } }
    /// Model per provider, so switching providers keeps each one's choice.
    var aiModels: [String: String] { didSet { defaults.set(aiModels, forKey: Key.aiModels) } }
    var customBaseURL: String { didSet { defaults.set(customBaseURL, forKey: Key.customBaseURL) } }
    var secretGraceMinutes: Int { didSet { defaults.set(secretGraceMinutes, forKey: Key.secretGraceMinutes) } }
    var secretClearSeconds: Int { didSet { defaults.set(secretClearSeconds, forKey: Key.secretClearSeconds) } }
    var customPrompts: [CustomPrompt] { didSet { store(customPrompts, Key.customPrompts) } }
    var hasLaunchedBefore: Bool { didSet { defaults.set(hasLaunchedBefore, forKey: Key.hasLaunchedBefore) } }
    var hasShownAccessibilityOnboarding: Bool {
        didSet { defaults.set(hasShownAccessibilityOnboarding, forKey: Key.hasShownAccessibilityOnboarding) }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.maxItems: 500,
            Key.maxAgeDays: 30,
            Key.isPaused: false,
            Key.appearance: AppearanceMode.system.rawValue,
            Key.panelSize: PanelSize.regular.rawValue,
            Key.aiProvider: AIProviderKind.anthropic.rawValue,
            Key.customBaseURL: AIProviderKind.custom.defaultBaseURL,
            Key.secretGraceMinutes: 15,
            Key.secretClearSeconds: 30,
        ])
        maxItems = max(10, defaults.integer(forKey: Key.maxItems))
        maxAgeDays = max(0, defaults.integer(forKey: Key.maxAgeDays))
        isPaused = defaults.bool(forKey: Key.isPaused)
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        panelSize = PanelSize(rawValue: defaults.string(forKey: Key.panelSize) ?? "") ?? .regular
        ignoredApps = Self.load([AppRef].self, defaults, Key.ignoredApps) ?? AppRef.defaultIgnored
        appTransforms = Self.load([AppTransformRule].self, defaults, Key.appTransforms) ?? []
        aiProvider = AIProviderKind(rawValue: defaults.string(forKey: Key.aiProvider) ?? "") ?? .anthropic
        var models = defaults.dictionary(forKey: Key.aiModels) as? [String: String] ?? [:]
        if models[AIProviderKind.anthropic.rawValue] == nil, let legacy = defaults.string(forKey: Key.claudeModel) {
            models[AIProviderKind.anthropic.rawValue] = legacy
        }
        aiModels = models
        customBaseURL = defaults.string(forKey: Key.customBaseURL) ?? AIProviderKind.custom.defaultBaseURL
        secretGraceMinutes = max(0, defaults.integer(forKey: Key.secretGraceMinutes))
        secretClearSeconds = max(0, defaults.integer(forKey: Key.secretClearSeconds))
        customPrompts = Self.load([CustomPrompt].self, defaults, Key.customPrompts) ?? []
        hasLaunchedBefore = defaults.bool(forKey: Key.hasLaunchedBefore)
        hasShownAccessibilityOnboarding = defaults.bool(forKey: Key.hasShownAccessibilityOnboarding)
    }

    var maxAge: TimeInterval? {
        maxAgeDays > 0 ? TimeInterval(maxAgeDays) * 86_400 : nil
    }

    /// The selected model for the active provider (falls back to the provider's default).
    var aiModel: String {
        get { aiModels[aiProvider.rawValue] ?? aiProvider.defaultModel }
        set { aiModels[aiProvider.rawValue] = newValue }
    }

    var ignoredBundleIDs: Set<String> { Set(ignoredApps.map(\.bundleID)) }

    func defaultTransform(for bundleID: String?) -> Transform? {
        guard let bundleID else { return nil }
        return appTransforms.first { $0.app.bundleID == bundleID }?.transform
    }

    private func store<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, _ defaults: UserDefaults, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
