import AppKit
import CoreGraphics

/// Writes items to the pasteboard and, when Accessibility is granted, sends ⌘V to the target app.
final class PasteService {
    private let store: ClipStore
    private let prefs: Preferences
    private let tracker: FrontmostAppTracker
    private let pasteboard: NSPasteboard

    /// Called when a paste needed Accessibility but it isn't granted (the item is still copied).
    var onAccessibilityMissing: (() -> Void)?

    init(store: ClipStore, prefs: Preferences, tracker: FrontmostAppTracker, pasteboard: NSPasteboard = .general) {
        self.store = store
        self.prefs = prefs
        self.tracker = tracker
        self.pasteboard = pasteboard
    }

    // MARK: Pasteboard writes

    /// Writes an item. `transform` (or the target app's default transform) applies to text items.
    func write(_ item: ClipItem, transform explicit: Transform? = nil, targetBundleID: String? = nil) {
        let transform = explicit ?? prefs.defaultTransform(for: targetBundleID)
        pasteboard.clearContents()

        switch item.kind {
        case .text, .richText:
            if let transform, transform != .plainText {
                pasteboard.setString(transform.apply(item.text) ?? item.text, forType: .string)
            } else {
                if transform == nil {
                    if let rtf = item.rtfData { pasteboard.setData(rtf, forType: .rtf) }
                    if let html = item.htmlData { pasteboard.setData(html, forType: .html) }
                }
                pasteboard.setString(item.text, forType: .string)
            }

        case .image:
            if let name = item.imageFile, let data = try? Data(contentsOf: store.blobs.url(for: name)) {
                pasteboard.setData(data, forType: .png)
                if let tiff = NSImage(data: data)?.tiffRepresentation {
                    pasteboard.setData(tiff, forType: .tiff)
                }
            }

        case .file:
            let urls = item.fileURLs
            if !urls.isEmpty {
                pasteboard.writeObjects(urls as [NSURL])
            }
            if transform != nil {
                pasteboard.setString(item.text, forType: .string)
            }
        }
        markAsOwnWrite()
    }

    /// Several items at once: text is joined with line breaks (what nearly every app expects),
    /// files become one multi-file drag, and mixed selections become separate pasteboard items.
    func write(_ items: [ClipItem], transform: Transform?) {
        if items.count == 1, let item = items.first {
            write(item, transform: transform)
            return
        }
        pasteboard.clearContents()
        if items.allSatisfy(\.kind.isTextual) {
            let text = items.map { transform?.apply($0.text) ?? $0.text }.joined(separator: "\n")
            pasteboard.setString(text, forType: .string)
        } else if items.allSatisfy({ $0.kind == .file }) {
            pasteboard.writeObjects(items.flatMap(\.fileURLs) as [NSURL])
        } else {
            let pbItems: [NSPasteboardItem] = items.compactMap { item in
                let pbItem = NSPasteboardItem()
                switch item.kind {
                case .text, .richText:
                    pbItem.setString(item.text, forType: .string)
                case .image:
                    guard let name = item.imageFile,
                          let data = try? Data(contentsOf: store.blobs.url(for: name)) else { return nil }
                    pbItem.setData(data, forType: .png)
                case .file:
                    guard let url = item.fileURLs.first else { return nil }
                    pbItem.setString(url.absoluteString, forType: .fileURL)
                }
                return pbItem
            }
            pasteboard.writeObjects(pbItems)
        }
        markAsOwnWrite()
    }

    func paste(_ items: [ClipItem], transform: Transform? = nil, into target: NSRunningApplication? = nil) {
        let target = target ?? tracker.targetApp
        write(items, transform: transform)
        sendPasteKeystroke(to: target)
    }

    func write(text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        markAsOwnWrite()
    }

    /// Writes a secret marked concealed + transient so clipboard managers (Clippy included) skip it,
    /// then clears the clipboard after `clearAfter` seconds unless something else was copied since.
    func writeSecret(_ value: String, clearAfter seconds: Int) {
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType(ClipboardFilter.concealedType))
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType(ClipboardFilter.transientType))
        markAsOwnWrite()
        guard seconds > 0 else { return }
        let changeCount = pasteboard.changeCount
        let pasteboard = self.pasteboard
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if pasteboard.changeCount == changeCount { pasteboard.clearContents() }
        }
    }

    func pasteSecret(_ value: String, into target: NSRunningApplication?, clearAfter seconds: Int) {
        writeSecret(value, clearAfter: seconds)
        sendPasteKeystroke(to: target)
    }

    private func markAsOwnWrite() {
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType(ClipboardFilter.internalMarkerType))
    }

    // MARK: Copy / paste

    func copy(_ item: ClipItem) {
        write(item)
        store.touch(item)
    }

    /// Copies the item and pastes it into `target` (defaults to the last non-Clippy app).
    func paste(_ item: ClipItem, transform: Transform? = nil, into target: NSRunningApplication? = nil) {
        let target = target ?? tracker.targetApp
        write(item, transform: transform, targetBundleID: target?.bundleIdentifier)
        store.touch(item)
        sendPasteKeystroke(to: target)
    }

    /// Pastes arbitrary text; `cursorOffsetFromEnd` moves the caret left afterwards ({cursor}).
    func paste(text: String, into target: NSRunningApplication? = nil, cursorOffsetFromEnd: Int = 0) {
        let target = target ?? tracker.targetApp
        write(text: text)
        sendPasteKeystroke(to: target, cursorOffsetFromEnd: cursorOffsetFromEnd)
    }

    private func sendPasteKeystroke(to target: NSRunningApplication?, cursorOffsetFromEnd: Int = 0) {
        guard AXPermission.isTrusted else {
            Log.paste.info("Accessibility not granted; copied only")
            onAccessibilityMissing?()
            return
        }
        if let target, !target.isActive {
            target.activate()
        }
        Task {
            // Give the target app a moment to become key after our panel/popover closes.
            try? await Task.sleep(for: .milliseconds(90))
            Self.postKey(9, flags: .maskCommand)            // kVK_ANSI_V
            if cursorOffsetFromEnd > 0 {
                try? await Task.sleep(for: .milliseconds(60))
                for _ in 0..<min(cursorOffsetFromEnd, 5_000) {
                    Self.postKey(123, flags: [])            // kVK_LeftArrow
                }
            }
        }
    }

    private static func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }
}
