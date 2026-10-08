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
}
