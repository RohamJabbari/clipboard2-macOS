import Foundation
import SwiftData
import Observation

/// All history mutations go through here so blobs and the database stay consistent.
@Observable
final class ClipStore {
    @ObservationIgnored let context: ModelContext
    @ObservationIgnored let blobs: BlobStore

    /// Bumped after every committed change; views observe it to refresh derived lists.
    private(set) var revision = 0

    init(context: ModelContext, blobs: BlobStore) {
        self.context = context
        self.blobs = blobs
    }

    // MARK: Reads

    func allItems() -> [ClipItem] {
        let descriptor = FetchDescriptor<ClipItem>(sortBy: [SortDescriptor(\.lastCopiedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func item(withHash hash: String) -> ClipItem? {
        var descriptor = FetchDescriptor<ClipItem>(predicate: #Predicate { $0.contentHash == hash })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    func count() -> Int {
        (try? context.fetchCount(FetchDescriptor<ClipItem>())) ?? 0
    }

    // MARK: Writes

    /// Inserts a capture, or — if identical content already exists — moves that item to the top.
    @discardableResult
    func ingest(_ capture: ProcessedCapture, now: Date = .now) -> ClipItem {
        if let existing = item(withHash: capture.hash) {
            existing.lastCopiedAt = now
            existing.copyCount += 1
            if let source = capture.source {
                existing.sourceBundleID = source.bundleID
                existing.sourceAppName = source.name
            }
            if capture.rtfData != nil || capture.htmlData != nil {
                existing.rtfData = capture.rtfData ?? existing.rtfData
                existing.htmlData = capture.htmlData ?? existing.htmlData
                existing.kind = .richText
            }
            // The processor already wrote blobs for this capture; they're redundant now.
            if capture.imageFile != existing.imageFile { blobs.delete(capture.imageFile) }
            if capture.thumbnailFile != existing.thumbnailFile { blobs.delete(capture.thumbnailFile) }
            commit()
            return existing
        }

        let item = ClipItem(capture: capture, now: now)
        context.insert(item)
        commit()
        return item
    }

    func touch(_ item: ClipItem, now: Date = .now) {
        item.lastCopiedAt = now
        commit()
    }

    func togglePin(_ item: ClipItem) {
        item.isPinned.toggle()
        item.pinnedAt = item.isPinned ? .now : nil
        commit()
    }

    func delete(_ item: ClipItem) {
        remove(item)
        commit()
    }

    func clearHistory(includingPinned: Bool = false) {
        for item in allItems() where includingPinned || !item.isPinned {
            remove(item)
        }
        commit()
    }

    /// Replaces an item's content with new plain text (e.g. a Claude result).
    func replaceText(of item: ClipItem, with text: String) {
        let hash = ContentHasher.hash(text: text)
        if let duplicate = self.item(withHash: hash), duplicate.id != item.id {
            remove(duplicate)
        }
        blobs.delete(item.imageFile)
        blobs.delete(item.thumbnailFile)
        item.kind = .text
        item.text = text
        item.preview = TextPreview.make(text)
        item.rtfData = nil
        item.htmlData = nil
        item.fileURLStrings = []
        item.imageFile = nil
        item.thumbnailFile = nil
        item.contentHash = hash
        item.byteCount = text.utf8.count
        item.lastCopiedAt = .now
        commit()
    }

    // MARK: Retention

    /// Pinned items are exempt from both limits. `maxAge == nil` means keep forever.
    func enforceRetention(maxItems: Int, maxAge: TimeInterval?, now: Date = .now) {
        var removed = 0

        if let maxAge {
            let cutoff = now.addingTimeInterval(-maxAge)
            let expired = FetchDescriptor<ClipItem>(
                predicate: #Predicate { $0.isPinned == false && $0.lastCopiedAt < cutoff }
            )
            for item in (try? context.fetch(expired)) ?? [] {
                remove(item)
                removed += 1
            }
        }

        var overflow = FetchDescriptor<ClipItem>(
            predicate: #Predicate { $0.isPinned == false },
            sortBy: [SortDescriptor(\.lastCopiedAt, order: .reverse)]
        )
        overflow.fetchOffset = max(0, maxItems)
        for item in (try? context.fetch(overflow)) ?? [] {
            remove(item)
            removed += 1
        }

        if removed > 0 {
            Log.store.info("Retention removed \(removed) items")
            commit()
        }
    }

    /// Deletes blob files no item references (e.g. after a crash mid-capture).
    func removeOrphanedBlobs() {
        var referenced = Set<String>()
        for item in allItems() {
            if let f = item.imageFile { referenced.insert(f) }
            if let f = item.thumbnailFile { referenced.insert(f) }
        }
        for name in blobs.allFileNames() where !referenced.contains(name) {
            blobs.delete(name)
        }
    }

    // MARK: Private

    private func remove(_ item: ClipItem) {
        blobs.delete(item.imageFile)
        blobs.delete(item.thumbnailFile)
        context.delete(item)
    }

    private func commit() {
        do {
            try context.save()
        } catch {
            Log.store.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
        revision &+= 1
    }
}
