import Testing
import AppKit
@testable import Clippy

@MainActor
struct PanelKeyboardTests {
    let env = AppEnvironment.shared
    let model: PanelViewModel

    init() {
        model = PanelViewModel(env: env)
    }

    private func key(_ code: UInt16, _ chars: String = "", flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                         windowNumber: 0, context: nil, characters: chars,
                         charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
    }

    @Test func tabCyclesFiltersBothWays() {
        model.filter = .all
        #expect(model.handleKeyDown(key(KeyCode.tab, "\t")))
        #expect(model.filter == .pinned)
        #expect(model.handleKeyDown(key(KeyCode.tab, "\t", flags: .shift)))
        #expect(model.filter == .all)
        #expect(model.handleKeyDown(key(KeyCode.tab, "\t", flags: .shift)))
        #expect(model.filter == .thisApp)
    }

    @Test func escapeCloses() {
        var closed = false
        model.onClose = { closed = true }
        #expect(model.handleKeyDown(key(KeyCode.escape, "\u{1b}")))
        #expect(closed)
    }

    @Test func plainTypingIsNotIntercepted() {
        #expect(model.handleKeyDown(key(0, "a")) == false)
    }

    @Test func deleteOnlyInterceptedWhenSearchIsEmpty() {
        model.query = "abc"
        #expect(model.handleKeyDown(key(KeyCode.delete, "\u{7f}")) == false)
    }

    @Test func shiftArrowsExtendAndPlainArrowCollapses() {
        let store = env.store
        let a = store.ingest(.text("multi-a \(UUID())"))
        let b = store.ingest(.text("multi-b \(UUID())"))
        let c = store.ingest(.text("multi-c \(UUID())"))
        defer { [a, b, c].forEach(store.delete) }
        model.query = "multi-"
        model.refresh(resetSelection: true)
        #expect(model.entries.count >= 3)

        #expect(model.handleKeyDown(key(KeyCode.downArrow, "", flags: .shift)))
        #expect(model.handleKeyDown(key(KeyCode.downArrow, "", flags: .shift)))
        #expect(model.selectedIDs.count == 3)
        #expect(model.isMultiSelecting)

        #expect(model.handleKeyDown(key(KeyCode.upArrow, "")))
        #expect(model.selectedIDs.count == 1)
    }

    @Test func toggleAndRangeSelection() {
        let store = env.store
        let items = (0..<4).map { store.ingest(.text("range-\($0) \(UUID())")) }
        defer { items.forEach(store.delete) }
        model.query = "range-"
        model.refresh(resetSelection: true)
        let ids = model.entries.prefix(4).map(\.id)

        model.selectedID = ids[0]
        model.toggleSelection(ids[2])
        #expect(model.selectedIDs == [ids[0], ids[2]])
        model.toggleSelection(ids[0])
        #expect(model.selectedIDs == [ids[2]])

        model.selectedID = ids[1]
        model.extendSelection(to: ids[3])
        #expect(model.selectedIDs == Set(ids[1...3]))
        #expect(model.selectedClips.count == 3)
    }
}
