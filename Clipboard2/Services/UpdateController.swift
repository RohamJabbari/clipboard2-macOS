import AppKit
import Observation
import Sparkle

/// In-place updates from GitHub (Sparkle). Checks hourly; when a newer version is published it
/// tells the user, and "Install Update" downloads, verifies (EdDSA + Apple notarization), replaces
/// the app and relaunches — no installer involved.
@Observable
final class UpdateController: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    /// Version string of an update that's waiting for the user, for the menu bar badge.
    private(set) var availableVersion: String?
    @ObservationIgnored private var controller: SPUStandardUpdaterController?

    func start() {
        guard controller == nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
    }

    var updater: SPUUpdater? { controller?.updater }

    func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    var automaticallyChecks: Bool {
        get { updater?.automaticallyChecksForUpdates ?? true }
        set { updater?.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyInstalls: Bool {
        get { updater?.automaticallyDownloadsUpdates ?? false }
        set { updater?.automaticallyDownloadsUpdates = newValue }
    }

    var lastCheck: Date? { updater?.lastUpdateCheckDate }

    // MARK: SPUStandardUserDriverDelegate — menu bar apps get "gentle" reminders

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        // Let Sparkle show its "A new version is available" window; Clipboard2 adds a badge too.
        true
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        availableVersion = update.displayVersionString
        if !state.userInitiated { NSApp.activate() }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        availableVersion = update.displayVersionString
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
    }
}
