import SwiftUI
import AppKit

/// Leading icon for a clip row: thumbnail for images, file icon for files, source app icon otherwise.
struct ClipIconView: View {
    let item: ClipItem
    var size: CGFloat = 28

    var body: some View {
        Group {
            switch item.kind {
            case .image:
                if let thumb = ThumbnailCache.image(for: item.thumbnailFile) {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.separator))
                } else {
                    Image(systemName: "photo").font(.system(size: size * 0.6))
                }
            case .file:
                Image(nsImage: FileIconCache.icon(for: item.fileURLs.first))
                    .resizable()
                    .frame(width: size, height: size)
            default:
                Image(nsImage: AppIconCache.icon(for: item.sourceBundleID))
                    .resizable()
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

enum ThumbnailCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 300
        return cache
    }()

    static func image(for name: String?) -> NSImage? {
        guard let name else { return nil }
        if let cached = cache.object(forKey: name as NSString) { return cached }
        let url = AppEnvironment.shared.blobs.url(for: name)
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }
}

enum FileIconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for url: URL?) -> NSImage {
        guard let url else { return NSWorkspace.shared.icon(for: .data) }
        if let cached = cache[url.path] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        if cache.count > 500 { cache.removeAll() }
        cache[url.path] = icon
        return icon
    }
}

extension Date {
    var shortRelative: String {
        let seconds = Date.now.timeIntervalSince(self)
        if seconds < 60 { return "now" }
        return formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
    }
}

/// "Leave Unlocked For…" menu, or the remaining unlock time with a Lock Now button.
struct SecretUnlockControl: View {
    let secrets: SecretStore

    var body: some View {
        // Re-render every 30 s so the countdown and expiry stay current.
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            if secrets.isManuallyUnlocked, let until = secrets.unlockedUntil {
                HStack(spacing: 8) {
                    Label("Unlocked until \(until.formatted(until.timeIntervalSinceNow > 82_800 ? .dateTime.weekday().hour().minute() : .dateTime.hour().minute()))",
                          systemImage: "lock.open.fill")
                        .foregroundStyle(.secondary)
                    Button("Lock Now") { secrets.lock() }
                }
            } else {
                Menu("Leave Unlocked For…") {
                    ForEach(UnlockDuration.allCases) { duration in
                        Button(duration.title) { Task { await secrets.unlock(for: duration) } }
                    }
                }
                .fixedSize()
                .help("Confirm once with Touch ID, then paste secrets without being asked until the time runs out")
            }
        }
    }
}
