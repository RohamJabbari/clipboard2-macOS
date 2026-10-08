import AppKit
import Observation

nonisolated enum PanelFilter: String, CaseIterable, Identifiable, Sendable {
    case all, pinned, text, images, files, snippets, secrets, thisApp
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .pinned: "Pinned"
        case .text: "Text"
        case .images: "Images"
        case .files: "Files"
        case .snippets: "Snippets"
        case .secrets: "Secrets"
        case .thisApp: "This App"
        }
    }

    var symbol: String {
        switch self {
        case .all: "tray.full"
        case .pinned: "pin"
        case .text: "text.alignleft"
        case .images: "photo"
        case .files: "doc"
        case .snippets: "text.badge.star"
        case .secrets: "key"
        case .thisApp: "app"
        }
    }
}

enum PanelEntry: Identifiable {
    case clip(ClipItem)
    case snippet(Snippet)
    case secret(SecretRef)

    var id: String {
        switch self {
        case .clip(let item): "c-" + item.id.uuidString
        case .snippet(let snippet): "s-" + snippet.id.uuidString
        case .secret(let ref): "k-" + ref.id
        }
    }

    var clip: ClipItem? {
        if case .clip(let item) = self { return item }
        return nil
    }

    var slotTarget: SlotTarget {
        switch self {
        case .clip(let item): .clip(item.id)
        case .snippet(let snippet): .snippet(snippet.id)
        case .secret(let ref): .secret(ref.id)
        }
    }
}

enum PanelMode: Equatable {
    case browse
    case actions
    case snippetForm
    case saveSecret
    case ai
}

enum PanelAction: Identifiable, Hashable {
    case paste
    case pastePlain
    case copy
    case transform(Transform)
    case ai(AIAction)
    case saveAsSecret
    case clearSlot(Int)
    case togglePin
    case delete

    var id: String {
        switch self {
        case .paste: "paste"
        case .pastePlain: "pastePlain"
        case .copy: "copy"
        case .transform(let t): "transform-" + t.rawValue
        case .ai(let a): "ai-" + a.id
        case .saveAsSecret: "saveAsSecret"
        case .clearSlot(let n): "clearSlot-\(n)"
        case .togglePin: "pin"
        case .delete: "delete"
        }
    }

    func section(aiName: String) -> String {
        switch self {
        case .paste, .pastePlain, .copy: "Paste"
        case .transform: "Transform & Paste"
        case .ai: "Ask \(aiName)"
        case .saveAsSecret, .clearSlot, .togglePin, .delete: "Item"
        }
    }

    func title(isPinned: Bool) -> String {
        switch self {
        case .paste: "Paste"
        case .pastePlain: "Paste as Plain Text"
        case .copy: "Copy to Clipboard"
        case .transform(let t): t.title
        case .ai(let a): a.title
        case .saveAsSecret: "Save as Secret…"
        case .clearSlot(let n): "Remove from Quick Slot ⌘\(n)"
        case .togglePin: isPinned ? "Unpin" : "Pin"
        case .delete: "Delete"
        }
    }

    var symbol: String {
        switch self {
        case .paste: "doc.on.clipboard"
        case .pastePlain: "doc.plaintext"
        case .copy: "doc.on.doc"
        case .transform(let t): t.symbol
        case .ai(let a): a.symbol
        case .saveAsSecret: "key"
        case .clearSlot: "number.square"
        case .togglePin: "pin"
        case .delete: "trash"
        }
    }
}

@Observable
final class SnippetFormState {
    let snippet: Snippet
    let fields: [String]
    var values: [String: String]

    init(snippet: Snippet, fields: [String]) {
        self.snippet = snippet
        self.fields = fields
        self.values = Dictionary(uniqueKeysWithValues: fields.map { ($0, "") })
    }
}

@Observable
final class SaveSecretState {
    let item: ClipItem
    var name: String

    init(item: ClipItem) {
        self.item = item
        self.name = item.sourceAppName.map { "Password from \($0)" } ?? "New Secret"
    }
}

@Observable
final class PanelViewModel {
    @ObservationIgnored let env: AppEnvironment
    @ObservationIgnored var onClose: () -> Void = {}

    var query = "" { didSet { if query != oldValue { refresh(resetSelection: true) } } }
    var filter: PanelFilter = .all { didSet { if filter != oldValue { refresh(resetSelection: true) } } }
    private(set) var entries: [PanelEntry] = []
    var selectedID: String?
    /// Bumped each time the panel opens so the view can refocus the search field.
    private(set) var focusToken = 0

    private(set) var mode: PanelMode = .browse
    var actionQuery = ""
    var actionSelection = 0
    private(set) var snippetForm: SnippetFormState?
    private(set) var saveSecretForm: SaveSecretState?
    private(set) var aiRun: AIRun?
    /// Transient status line ("Copied", "Not valid JSON", …).
    private(set) var notice: String?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    /// The app that was frontmost when the panel opened — pastes go here.
    private(set) var targetApp: NSRunningApplication?
    var targetRef: AppRef? { targetApp.flatMap(FrontmostAppTracker.ref(for:)) }

    static let maxEntries = 300

    init(env: AppEnvironment) {
        self.env = env
    }

    // MARK: Lifecycle

    func prepareForOpen(target: NSRunningApplication?) {
        resetMode()
        notice = nil
        targetApp = target
        query = ""
        filter = .all
        refresh(resetSelection: true)
        focusToken &+= 1
    }

    func didClose() {
        resetMode()
    }

    func resetMode() {
        aiRun?.cancel()
        aiRun = nil
        snippetForm = nil
        saveSecretForm = nil
        actionQuery = ""
        actionSelection = 0
        mode = .browse
        focusToken &+= 1
    }

    func showNotice(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    func refresh(resetSelection: Bool = false) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetBundle = targetApp?.bundleIdentifier

        var clips: [ClipItem] = []
        if filter != .snippets && filter != .secrets {
            clips = env.store.allItems().filter { item in
                switch filter {
                case .all: true
                case .pinned: item.isPinned
                case .text: item.kind.isTextual
                case .images: item.kind == .image
                case .files: item.kind == .file
                case .snippets, .secrets: false
                case .thisApp: targetBundle != nil && item.sourceBundleID == targetBundle
                }
            }
        }
        // Snippets and secrets join "All" only while searching, so history stays uncluttered.
        let searchingAll = filter == .all && !q.isEmpty
        let snippets = (filter == .snippets || searchingAll) ? env.snippets.all() : []
        let secrets = (filter == .secrets || searchingAll) ? env.secrets.secrets : []

        var result: [PanelEntry]
        if q.isEmpty {
            result = clips.map(PanelEntry.clip) + snippets.map(PanelEntry.snippet) + secrets.map(PanelEntry.secret)
        } else {
            var scored: [(PanelEntry, Int, Date)] = []
            for item in clips {
                if let s = FuzzyMatcher.score(query: q, in: item.searchableText) {
                    scored.append((.clip(item), s, item.lastCopiedAt))
                }
            }
            let lowered = q.lowercased()
            for snippet in snippets {
                let keywordHit = !snippet.keyword.isEmpty && snippet.keyword.lowercased() == lowered
                let haystack = snippet.name + " " + snippet.keyword + " " + snippet.body
                if let s = FuzzyMatcher.score(query: q, in: haystack) {
                    scored.append((.snippet(snippet), s + (keywordHit ? 10_000 : 0), snippet.updatedAt))
                } else if keywordHit {
                    scored.append((.snippet(snippet), 10_000, snippet.updatedAt))
                }
            }
            for secret in secrets {
                // Only names are searchable — values never leave the keychain for search.
                if let s = FuzzyMatcher.score(query: q, in: secret.name) {
                    scored.append((.secret(secret), s + 500, secret.createdAt ?? .distantPast))
                }
            }
            scored.sort { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 > $1.2 }
            result = scored.map(\.0)
        }

        entries = Array(result.prefix(Self.maxEntries))
        if resetSelection || !entries.contains(where: { $0.id == selectedID }) {
            selectedID = entries.first?.id
        }
    }

    // MARK: Selection

    var selectedIndex: Int? { entries.firstIndex { $0.id == selectedID } }

    var selectedEntry: PanelEntry? {
        selectedIndex.map { entries[$0] }
    }

    func moveSelection(by delta: Int) {
        guard !entries.isEmpty else { return }
        let current = selectedIndex ?? (delta > 0 ? -1 : entries.count)
        let next = min(max(current + delta, 0), entries.count - 1)
        selectedID = entries[next].id
    }

    func cycleFilter(forward: Bool) {
        let all = PanelFilter.allCases
        guard let index = all.firstIndex(of: filter) else { return }
        filter = all[(index + (forward ? 1 : all.count - 1)) % all.count]
    }

    // MARK: Quick slots

    /// The ⌘-number shown on a row: its assigned slot, or its position if that number is unassigned.
    func shortcutNumber(for entry: PanelEntry, at index: Int) -> (number: Int, isSlot: Bool)? {
        if let slot = env.slots.slot(for: entry.slotTarget) { return (slot, true) }
        let position = index + 1
        guard position <= 9, env.slots.target(for: position) == nil else { return nil }
        return (position, false)
    }

    /// ⌘N: the item assigned to slot N, otherwise the Nth row.
    func activateShortcut(_ number: Int, transform: Transform? = nil) {
        if let entry = env.slots.entry(for: number) {
            activate(entry, transform: transform)
        } else if entries.indices.contains(number - 1) {
            activate(entries[number - 1], transform: transform)
        }
    }

    func assignSelection(toSlot number: Int) {
        guard let entry = selectedEntry else { return }
        env.slots.assign(entry, to: number)
        refresh()
        showNotice("Assigned to ⌘\(number)")
    }

    // MARK: Activation

    func activate(_ entry: PanelEntry?, transform: Transform? = nil) {
        guard let entry else { return }
        switch entry {
        case .clip(let item):
            let target = targetApp
            onClose()
            env.paste.paste(item, transform: transform, into: target)
        case .snippet(let snippet):
            let fields = SnippetExpander.customFields(in: snippet.body)
            if fields.isEmpty {
                let target = targetApp
                onClose()
                env.pasteSnippet(snippet, values: [:], into: target)
            } else {
                snippetForm = SnippetFormState(snippet: snippet, fields: fields)
                mode = .snippetForm
            }
        case .secret(let ref):
            let target = targetApp
            onClose()
            env.pasteSecret(ref, into: target)
        }
    }

    func submitSnippetForm() {
        guard let form = snippetForm else { return }
        let target = targetApp
        onClose()
        env.pasteSnippet(form.snippet, values: form.values, into: target)
    }

    func submitSaveSecret() {
        guard let form = saveSecretForm else { return }
        let name = form.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, env.secrets.add(name: name, value: form.item.text) != nil else {
            showNotice("Couldn't save to the Keychain")
            return
        }
        env.store.delete(form.item)
        resetMode()
        refresh()
        showNotice("Saved “\(name)” to Secrets and removed it from history")
    }

    // MARK: Action menu

    func openActions() {
        guard selectedEntry != nil else { return }
        actionQuery = ""
        actionSelection = 0
        mode = .actions
    }

    var aiName: String { env.prefs.aiProvider.shortName }

    var availableActions: [PanelAction] {
        guard let entry = selectedEntry else { return [] }
        var actions: [PanelAction] = [.paste]
        switch entry {
        case .clip(let item):
            if item.kind.isTextual { actions.append(.pastePlain) }
            actions.append(.copy)
            if item.kind.isTextual {
                actions += Transform.allCases.filter { $0 != .plainText }.map(PanelAction.transform)
                actions += AIAction.builtIn.map(PanelAction.ai)
                actions += env.prefs.customPrompts.map { PanelAction.ai(.custom($0)) }
                actions.append(.saveAsSecret)
            }
            actions.append(.togglePin)
        case .snippet:
            break
        case .secret:
            actions.append(.copy)
        }
        if let slot = env.slots.slot(for: entry.slotTarget) {
            actions.append(.clearSlot(slot))
        }
        if entry.clip != nil || { if case .secret = entry { return true } else { return false } }() {
            actions.append(.delete)
        }
        return actions
    }

    var filteredActions: [PanelAction] {
        let isPinned = selectedEntry?.clip?.isPinned ?? false
        let q = actionQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return availableActions }
        return availableActions
            .compactMap { action in
                FuzzyMatcher.score(query: q, in: action.title(isPinned: isPinned) + " " + action.section(aiName: aiName))
                    .map { (action, $0) }
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    func perform(_ action: PanelAction) {
        guard let entry = selectedEntry else { return }
        switch action {
        case .paste:
            activate(entry)
        case .pastePlain:
            activate(entry, transform: .plainText)
        case .copy:
            switch entry {
            case .clip(let item): env.paste.copy(item)
            case .secret(let ref): env.copySecret(ref)
            case .snippet: break
            }
            onClose()
        case .transform(let transform):
            guard let item = entry.clip else { return }
            guard let result = transform.apply(item.text) else {
                showNotice("Can't apply “\(transform.title)” to this item")
                return
            }
            let target = targetApp
            env.store.touch(item)
            onClose()
            env.paste.paste(text: result, into: target)
        case .ai(let aiAction):
            guard let item = entry.clip else { return }
            let run = AIRun(action: aiAction, item: item, providerName: env.prefs.aiProvider.title)
            aiRun = run
            mode = .ai
            run.start(prefs: env.prefs)
        case .saveAsSecret:
            guard let item = entry.clip else { return }
            saveSecretForm = SaveSecretState(item: item)
            mode = .saveSecret
        case .clearSlot(let number):
            env.slots.clear(number)
            mode = .browse
            refresh()
        case .togglePin:
            togglePinOnSelection()
            mode = .browse
        case .delete:
            mode = .browse
            deleteSelection(includingSecrets: true)
        }
    }

    // MARK: AI result

    func pasteAIOutput() {
        guard let run = aiRun, !run.output.isEmpty else { return }
        let target = targetApp
        let text = run.output
        onClose()
        env.paste.paste(text: text, into: target)
    }

    func copyAIOutput() {
        guard let run = aiRun, !run.output.isEmpty else { return }
        env.paste.write(text: run.output)
        showNotice("Copied")
    }

    func replaceItemWithAIOutput() {
        guard let run = aiRun, run.isFinished else { return }
        env.store.replaceText(of: run.item, with: run.output)
        resetMode()
        refresh()
        selectedID = PanelEntry.clip(run.item).id
        showNotice("Item replaced")
    }

    // MARK: Item actions

    func togglePinOnSelection() {
        guard let item = selectedEntry?.clip else { return }
        env.store.togglePin(item)
        refresh()
    }

    /// ⌫ never deletes secrets (too easy to hit by accident); ⌘K → Delete does.
    func deleteSelection(includingSecrets: Bool = false) {
        guard let entry = selectedEntry, let index = selectedIndex else { return }
        switch entry {
        case .clip(let item):
            env.slots.remove(target: entry.slotTarget)
            env.store.delete(item)
        case .secret(let ref):
            guard includingSecrets else { return }
            env.slots.remove(target: entry.slotTarget)
            env.secrets.delete(ref)
        case .snippet:
            return   // snippets are edited in Settings
        }
        refresh()
        if !entries.isEmpty {
            selectedID = entries[min(index, entries.count - 1)].id
        }
    }

    // MARK: Keyboard

    /// Returns true when the event was handled and must not reach the search field.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        switch mode {
        case .browse: handleBrowseKey(event)
        case .actions: handleActionKey(event)
        case .snippetForm, .saveSecret: handleFormKey(event)
        case .ai: handleAIKey(event)
        }
    }

    private func handleBrowseKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        let option = flags.contains(.option)
        let shift = flags.contains(.shift)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        switch event.keyCode {
        case KeyCode.escape:
            onClose()
            return true
        case KeyCode.upArrow:
            moveSelection(by: -1)
            return true
        case KeyCode.downArrow:
            moveSelection(by: 1)
            return true
        case KeyCode.pageUp:
            moveSelection(by: -8)
            return true
        case KeyCode.pageDown:
            moveSelection(by: 8)
            return true
        case KeyCode.returnKey, KeyCode.keypadEnter:
            activate(selectedEntry, transform: option ? .plainText : nil)
            return true
        case KeyCode.tab:
            cycleFilter(forward: !shift)
            return true
        case KeyCode.delete, KeyCode.forwardDelete:
            if command || query.isEmpty {
                deleteSelection()
                return true
            }
            return false
        default:
            break
        }

        if command {
            // Digits by key code so ⌘⇧1 works on every keyboard layout.
            if let digit = KeyCode.digit(for: event.keyCode) {
                if shift {
                    assignSelection(toSlot: digit)
                } else {
                    activateShortcut(digit, transform: option ? .plainText : nil)
                }
                return true
            }
            switch chars {
            case "p":
                togglePinOnSelection()
                return true
            case "k":
                openActions()
                return true
            case ",":
                onClose()
                SettingsOpener.open()
                return true
            default:
                break
            }
        }
        return false
    }

    private func handleActionKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let actions = filteredActions
        switch event.keyCode {
        case KeyCode.escape:
            mode = .browse
        case KeyCode.upArrow:
            actionSelection = max(0, actionSelection - 1)
        case KeyCode.downArrow:
            actionSelection = min(max(0, actions.count - 1), actionSelection + 1)
        case KeyCode.returnKey, KeyCode.keypadEnter:
            if actions.indices.contains(actionSelection) { perform(actions[actionSelection]) }
        case KeyCode.delete:
            if !actionQuery.isEmpty { actionQuery.removeLast(); actionSelection = 0 }
        default:
            if flags.contains(.command) {
                if event.charactersIgnoringModifiers?.lowercased() == "k" { mode = .browse }
            } else if let chars = event.characters, !chars.isEmpty,
                      chars.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
                actionQuery += chars
                actionSelection = 0
            }
        }
        return true
    }

    private func handleFormKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case KeyCode.escape:
            resetMode()
            return true
        case KeyCode.returnKey, KeyCode.keypadEnter:
            if mode == .saveSecret { submitSaveSecret() } else { submitSnippetForm() }
            return true
        default:
            return false
        }
    }

    private func handleAIKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch event.keyCode {
        case KeyCode.escape:
            resetMode()
        case KeyCode.returnKey, KeyCode.keypadEnter:
            if aiRun?.isFinished == true { pasteAIOutput() }
        default:
            if flags.contains(.command) {
                if chars == "c" { copyAIOutput() }
                if chars == "r" { replaceItemWithAIOutput() }
            }
        }
        return true
    }
}

nonisolated enum KeyCode {
    static let returnKey: UInt16 = 36
    static let tab: UInt16 = 48
    static let delete: UInt16 = 51
    static let escape: UInt16 = 53
    static let keypadEnter: UInt16 = 76
    static let pageUp: UInt16 = 116
    static let forwardDelete: UInt16 = 117
    static let pageDown: UInt16 = 121
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126

    /// kVK_ANSI_1 … kVK_ANSI_9 (positional, layout independent).
    private static let digits: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]
    static func digit(for keyCode: UInt16) -> Int? { digits[keyCode] }
}
