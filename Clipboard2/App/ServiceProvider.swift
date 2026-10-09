import AppKit

/// Handles "Clipboard2 Actions…" from the system Services menu (right-click → Services in apps
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

    /// Services → "Paste Text from Clipboard Image": returns the text recognised in the image on
    /// the clipboard, which the calling app inserts at the cursor. Services are synchronous by
    /// design, so recognition runs inline (typically well under a second).
    @objc func pasteTextFromImage(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let image = ClipboardImage.current(in: .general) else {
            error.pointee = "There's no image on the clipboard." as NSString
            return
        }
        guard let text = try? ScreenTextCapture.recognizeTextNow(in: image), !text.isEmpty else {
            error.pointee = "No text was found in the image." as NSString
            return
        }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let source = AppRef(bundleID: Bundle.main.bundleIdentifier ?? "at.softmaze.Clippy", name: "Text from Image")
        env.store.ingest(.text(text, source: source))
    }
}
