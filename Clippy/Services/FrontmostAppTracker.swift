import AppKit
import Observation

/// Remembers the last app that wasn't Clippy, so pastes and "This app" filtering target the
/// app the user was actually working in — even after our popover or Settings took focus.
@Observable
final class FrontmostAppTracker {
    private(set) var lastExternalApp: NSRunningApplication?
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private let ownPID = ProcessInfo.processInfo.processIdentifier

    init() {
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ownPID {
            lastExternalApp = app
        }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                guard let self, let pid, pid != self.ownPID else { return }
                self.lastExternalApp = NSRunningApplication(processIdentifier: pid)
            }
        }
    }

    /// The app a paste should go to right now.
    var targetApp: NSRunningApplication? {
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ownPID {
            return front
        }
        return lastExternalApp
    }

    /// The app that owns the current pasteboard change (best effort: the frontmost app).
    var currentSource: AppRef? {
        if let front = NSWorkspace.shared.frontmostApplication {
            if front.processIdentifier == ownPID { return Self.ref(for: front) }
            return Self.ref(for: front)
        }
        return lastExternalApp.flatMap(Self.ref(for:))
    }

    static func ref(for app: NSRunningApplication) -> AppRef? {
        guard let bundleID = app.bundleIdentifier else { return nil }
        return AppRef(bundleID: bundleID, name: app.localizedName ?? bundleID)
    }
}
