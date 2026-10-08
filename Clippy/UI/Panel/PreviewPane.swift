import SwiftUI

struct PreviewPane: View {
    let entry: PanelEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            metadata
                .padding(12)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch entry {
        case .clip(let item):
            switch item.kind {
            case .text, .richText:
                TextPreviewView(text: item.text)
            case .image:
                ImagePreviewView(item: item)
            case .file:
                FilePreviewView(urls: item.fileURLs)
            }
        case .snippet(let snippet):
            TextPreviewView(text: snippet.body)
        case .secret(let ref):
            SecretPreviewView(ref: ref)
        }
    }

    @ViewBuilder
    private var metadata: some View {
        switch entry {
        case .clip(let item):
            VStack(alignment: .leading, spacing: 6) {
                if let source = item.source {
                    HStack(spacing: 6) {
                        Image(nsImage: AppIconCache.icon(for: source.bundleID))
                            .resizable()
                            .frame(width: 16, height: 16)
                            .accessibilityHidden(true)
                        Text(source.name)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Copied from \(source.name)")
                }
                LabeledContent("Copied", value: item.lastCopiedAt.formatted(date: .abbreviated, time: .shortened))
                if item.copyCount > 1 {
                    LabeledContent("Times copied", value: "\(item.copyCount)")
                }
                LabeledContent("Type", value: detailType(item))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        case .snippet(let snippet):
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Snippet", value: snippet.name)
                if !snippet.keyword.isEmpty { LabeledContent("Keyword", value: snippet.keyword) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        case .secret(let ref):
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Stored in", value: "Keychain")
                if let created = ref.createdAt {
                    LabeledContent("Added", value: created.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func detailType(_ item: ClipItem) -> String {
        switch item.kind {
        case .text, .richText:
            let chars = item.text.count
            let words = item.text.split { $0.isWhitespace || $0.isNewline }.count
            return "\(item.kind.displayName) · \(chars) characters · \(words) words"
        case .image:
            return "Image · \(item.imageWidth)×\(item.imageHeight) · \(ByteCountFormatter.string(fromByteCount: Int64(item.byteCount), countStyle: .file))"
        case .file:
            return item.fileURLs.count == 1 ? "File" : "\(item.fileURLs.count) Files"
        }
    }
}

struct TextPreviewView: View {
    let text: String
    static let displayLimit = 20_000

    var body: some View {
        ScrollView {
            Text(text.count > Self.displayLimit ? String(text.prefix(Self.displayLimit)) + "\n…" : text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        }
        .accessibilityLabel("Preview")
    }
}

struct ImagePreviewView: View {
    let item: ClipItem
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Image preview, \(item.imageWidth) by \(item.imageHeight) pixels")
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: item.id) {
            image = nil
            guard let name = item.imageFile else { return }
            let url = AppEnvironment.shared.blobs.url(for: name)
            image = await Self.load(url)
        }
    }

    @concurrent
    private static func load(_ url: URL) async -> NSImage? {
        NSImage(contentsOf: url)
    }
}

struct FilePreviewView: View {
    let urls: [URL]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(urls, id: \.self) { url in
                    HStack(spacing: 10) {
                        Image(nsImage: FileIconCache.icon(for: url))
                            .resizable()
                            .frame(width: 32, height: 32)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.lastPathComponent).lineLimit(1)
                            Text(url.deletingLastPathComponent().path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }
}

struct SecretPreviewView: View {
    let ref: SecretRef
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: env.secrets.isUnlocked ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 34))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(ref.name).font(.title3.weight(.semibold))
            Text("••••••••••")
                .font(.title3.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Hidden value")
            Text(hint)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hint: String {
        let clear = env.prefs.secretClearSeconds > 0
            ? " The clipboard clears after \(env.prefs.secretClearSeconds) seconds."
            : ""
        if env.secrets.isUnlocked { return "Unlocked — press Return to paste." + clear }
        return "Press Return to paste. You'll confirm with Touch ID or your password." + clear
    }
}
