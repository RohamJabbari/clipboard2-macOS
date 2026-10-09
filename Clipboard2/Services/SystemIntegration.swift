import AppKit
import ServiceManagement
import ApplicationServices

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static var requiresApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            Log.app.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

enum AXPermission {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Adds Clipboard2 to the Accessibility list (unchecked) and shows the system prompt once.
    static func requestTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Makes Clipboard2 appear in the Accessibility list without the system "would like to
    /// control this computer" dialog: an active event tap that's denied registers the app.
    static func registerSilently() {
        guard !isTrusted else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        if let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                       eventsOfInterest: mask, callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
                                       userInfo: nil) {
            CFMachPortInvalidate(tap)
        }
    }

    /// Clears this app's Accessibility entry (e.g. one left from an older signature that no
    /// longer matches) and adds it back, unchecked, so the user can turn it on again.
    static func resetAndReRegister() {
        if let bundleID = Bundle.main.bundleIdentifier {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", "Accessibility", bundleID]
            try? process.run()
            process.waitUntilExit()
        }
        registerSilently()
        requestTrust()   // after a reset this is the one moment the system dialog is expected
        openSystemSettings()
    }

    static func openSystemSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }
}

enum AppIconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String?) -> NSImage {
        guard let bundleID else { return genericIcon }
        if let cached = cache[bundleID] { return cached }
        let icon: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            icon = genericIcon
        }
        cache[bundleID] = icon
        return icon
    }

    static func appURL(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    private static let genericIcon = NSWorkspace.shared.icon(for: .applicationBundle)
}
