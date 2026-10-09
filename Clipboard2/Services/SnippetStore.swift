import Foundation
import SwiftData
import Observation

@Observable
final class SnippetStore {
    @ObservationIgnored let context: ModelContext
    private(set) var revision = 0

    init(context: ModelContext) {
        self.context = context
    }

    func all() -> [Snippet] {
        let descriptor = FetchDescriptor<Snippet>(sortBy: [SortDescriptor(\.name)])
        return (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    func create(name: String = "New Snippet", keyword: String = "", body: String = "") -> Snippet {
        let snippet = Snippet(name: name, keyword: keyword, body: body)
        context.insert(snippet)
        commit()
        return snippet
    }

    func delete(_ snippet: Snippet) {
        context.delete(snippet)
        commit()
    }

    func didEdit(_ snippet: Snippet) {
        snippet.updatedAt = .now
        commit()
    }

    private func commit() {
        do { try context.save() } catch {
            Log.store.error("Snippet save failed: \(error.localizedDescription, privacy: .public)")
        }
        revision &+= 1
    }
}
