import AppKit

/// Handles "Clippy Actions…" from the system Services menu (right-click → Services in apps
/// that support it). Declared under NSServices in project.yml.
final class ServiceProvider: NSObject {
    private unowned let env: AppEnvironment

    init(env: AppEnvironment) {
        self.env = env
    }

    @objc func clippyActions(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            error.pointee = "No text was selected." as NSString
            return
        }
        env.showSelectionActions(text: text)
    }
}
