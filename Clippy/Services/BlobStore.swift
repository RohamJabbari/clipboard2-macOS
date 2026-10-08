import Foundation

/// Image blobs and thumbnails live on disk next to the database, never inside it.
nonisolated final class BlobStore: Sendable {
    let directory: URL

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func url(for name: String) -> URL {
        directory.appending(path: name, directoryHint: .notDirectory)
    }

    func write(_ data: Data, name: String) throws {
        try data.write(to: url(for: name), options: .atomic)
    }

    func delete(_ name: String?) {
        guard let name, !name.isEmpty, !name.contains("/") else { return }
        try? FileManager.default.removeItem(at: url(for: name))
    }

    func allFileNames() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    }
}
