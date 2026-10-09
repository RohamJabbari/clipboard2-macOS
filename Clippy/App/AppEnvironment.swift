import AppKit
import SwiftData
import Observation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleQuickPanel = Self("toggleQuickPanel", default: .init(.v, modifiers: [.command, .shift]))
}

/// Owns every long-lived service. Created once at launch and injected into SwiftUI via `.environment`.
@Observable
final class AppEnvironment {
    static let shared = AppEnvironment()

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    let prefs: Preferences
    let container: ModelContainer
    let blobs: BlobStore
    let store: ClipStore
    let appTracker: FrontmostAppTracker
    let monitor: ClipboardMonitor
    let paste: PasteService
    let snippets: SnippetStore
    let secrets: SecretStore
    let slots: QuickSlots
    let claudeAccount = ClaudeCodeAccount()

    @ObservationIgnored private(set) lazy var panel = QuickPanelController(env: self)
    @ObservationIgnored private let onboarding = AccessibilityOnboardingController()

    @ObservationIgnored private var maintenanceTimer: Timer?
    #if DEBUG
    @ObservationIgnored private var stressMonitor: ClipboardMonitor?
    #endif

    private init() {
        prefs = Preferences(defaults: .standard)
        blobs = BlobStore(directory: AppPaths.blobsDirectory)
        container = Self.makeContainer(url: AppPaths.storeURL)
        store = ClipStore(context: container.mainContext, blobs: blobs)
        appTracker = FrontmostAppTracker()
        monitor = ClipboardMonitor(store: store, prefs: prefs, tracker: appTracker, blobs: blobs)
        paste = PasteService(store: store, prefs: prefs, tracker: appTracker)
        snippets = SnippetStore(context: container.mainContext)
        secrets = SecretStore(prefs: prefs)
        slots = QuickSlots(defaults: .standard, store: store, snippets: snippets, secrets: secrets)
    }

    private static func makeContainer(url: URL) -> ModelContainer {
        let schema = Schema([ClipItem.self, Snippet.self])
        do {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        } catch {
            Log.store.error("Failed to open store at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public). Falling back to in-memory.")
            do {
                return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
            } catch {
                fatalError("SwiftData is unavailable: \(error)")
            }
        }
    }

    // MARK: Lifecycle

    func start() {
        applyAppearance()
        monitor.start()
        runMaintenance()

        let timer = Timer(timeInterval: 60 * 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.runMaintenance() }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        maintenanceTimer = timer

        KeyboardShortcuts.onKeyDown(for: .toggleQuickPanel) { [weak self] in
            self?.panel.toggle()
        }
        for (index, name) in KeyboardShortcuts.Name.quickSlots.enumerated() {
            KeyboardShortcuts.onKeyDown(for: name) { [weak self] in
                self?.pasteSlot(index + 1)
            }
        }
        paste.onAccessibilityMissing = { [weak self] in
            self?.showAccessibilityOnboarding()
        }

        if !prefs.hasLaunchedBefore {
            prefs.hasLaunchedBefore = true
            LoginItem.setEnabled(true)
        }
        if !AXPermission.isTrusted && !prefs.hasShownAccessibilityOnboarding {
            prefs.hasShownAccessibilityOnboarding = true
            showAccessibilityOnboarding()
        }
    }

    func showAccessibilityOnboarding() {
        onboarding.show()
    }

    func runMaintenance() {
        store.enforceRetention(maxItems: prefs.maxItems, maxAge: prefs.maxAge)
        store.removeOrphanedBlobs()
    }

    func applyAppearance() {
        NSApp.appearance = prefs.appearance.nsAppearance
    }

    // MARK: Shared paste flows (quick panel, popover and global slot shortcuts)

    func pasteSnippet(_ snippet: Snippet, values: [String: String], into target: NSRunningApplication?) {
        let expansion = SnippetExpander.expand(
            snippet.body,
            values: values,
            clipboard: NSPasteboard.general.string(forType: .string)
        )
        paste.paste(text: expansion.text, into: target, cursorOffsetFromEnd: expansion.cursorOffsetFromEnd)
    }

    /// Touch ID (unless recently unlocked), then a concealed paste that clears itself.
    func pasteSecret(_ ref: SecretRef, into target: NSRunningApplication?) {
        Task {
            guard let value = await secrets.reveal(ref, reason: "paste “\(ref.name)”") else { return }
            paste.pasteSecret(value, into: target ?? appTracker.targetApp, clearAfter: prefs.secretClearSeconds)
        }
    }

    func copySecret(_ ref: SecretRef) {
        Task {
            guard let value = await secrets.reveal(ref, reason: "copy “\(ref.name)”") else { return }
            paste.writeSecret(value, clearAfter: prefs.secretClearSeconds)
        }
    }

    /// Global quick-slot shortcut: paste straight into the frontmost app.
    func pasteSlot(_ number: Int) {
        guard let entry = slots.entry(for: number) else {
            NSSound.beep()
            return
        }
        let target = appTracker.targetApp
        switch entry {
        case .clip(let item):
            paste.paste(item, into: target)
        case .snippet(let snippet):
            if SnippetExpander.customFields(in: snippet.body).isEmpty {
                pasteSnippet(snippet, values: [:], into: target)
            } else {
                panel.show()
                panel.model.activate(entry)
            }
        case .secret(let ref):
            pasteSecret(ref, into: target)
        }
    }

    func showQuickPanel() {
        panel.show()
    }

    func handle(url: URL) {
        guard url.scheme == "clippy" else { return }
        switch url.host() {
        case "settings": SettingsOpener.open()
        case "panel": panel.show()
        case "accessibility": showAccessibilityOnboarding()
        #if DEBUG
        case "stress":
            // Debug aid: drives the capture pipeline through a private pasteboard, so memory can
            // be measured without touching the user's real clipboard.
            let count = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "count" }?.value.flatMap(Int.init) ?? 300
            let pasteboard = NSPasteboard(name: NSPasteboard.Name("at.softmaze.clippy.stress"))
            let monitor = ClipboardMonitor(store: store, prefs: prefs, tracker: appTracker, blobs: blobs, pasteboard: pasteboard)
            stressMonitor = monitor
            monitor.start()
            Task {
                for i in 0..<count {
                    pasteboard.clearContents()
                    pasteboard.setString("stress \(i) " + String(repeating: "x", count: 300), forType: .string)
                    try? await Task.sleep(for: .milliseconds(550))
                }
                monitor.stop()
                stressMonitor = nil
                Log.app.notice("stress done: \(count) writes, store has \(self.store.count()) items")
            }
        case "snapshot":
            // Debug aid: renders the quick panel to a PNG (no Screen Recording permission needed).
            let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "path" }?.value ?? "/tmp/clippy-panel.png"
            panel.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.panel.writeSnapshot(to: URL(fileURLWithPath: path))
            }
        #endif
        default: break
        }
    }
}
