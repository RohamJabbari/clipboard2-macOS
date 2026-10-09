import SwiftUI
import SwiftData

struct MenuBarLabel: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Image(systemName: env.prefs.isPaused ? "clipboard" : "list.clipboard")
            .accessibilityLabel(env.prefs.isPaused ? "Clippy, capture paused" : "Clippy")
            .onAppear { SettingsOpener.register(openSettings) }
    }
}

/// The menu bar popover: recent history, search, pinned items and quick actions.
struct MenuBarContentView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @Query(Self.recentDescriptor) private var recentItems: [ClipItem]
    @Query(filter: #Predicate<ClipItem> { $0.isPinned }, sort: \ClipItem.lastCopiedAt, order: .reverse)
    private var pinnedItems: [ClipItem]

    /// The popover only renders recent history; search falls back to the full store.
    private static var recentDescriptor: FetchDescriptor<ClipItem> {
        var descriptor = FetchDescriptor<ClipItem>(
            predicate: #Predicate { $0.isPinned == false },
            sortBy: [SortDescriptor(\.lastCopiedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 200
        return descriptor
    }

    @State private var search = ""
    @State private var confirmClear = false
    @FocusState private var searchFocused: Bool

    private var filtered: [ClipItem] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return pinnedItems + recentItems }
        return env.store.allItems()
            .compactMap { item in FuzzyMatcher.score(query: query, in: item.searchableText).map { (item, $0) } }
            .sorted { $0.1 > $1.1 }
            .prefix(200)
            .map(\.0)
    }

    var body: some View {
        let results = filtered
        let pinned = results.filter(\.isPinned)
        let recent = results.filter { !$0.isPinned }.prefix(100)

        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 8)

            Divider()

            if results.isEmpty {
                ContentUnavailableView {
                    Label(search.isEmpty ? "No Clipboard History" : "No Results", systemImage: search.isEmpty ? "list.clipboard" : "magnifyingglass")
                } description: {
                    Text(search.isEmpty ? "Copy something and it shows up here." : "Try a different search.")
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1, pinnedViews: [.sectionHeaders]) {
                        if !pinned.isEmpty {
                            Section { rows(pinned) } header: { sectionHeader("Pinned") }
                        }
                        if !recent.isEmpty {
                            Section { rows(Array(recent)) } header: { sectionHeader("Recent") }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                }
            }

            Divider()
            if confirmClear {
                clearConfirmation
            } else {
                footer
            }
        }
        .frame(width: 380, height: 520)
        .onAppear { searchFocused = true }
        .onDisappear { confirmClear = false }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search History", text: $search)
                .textFieldStyle(.plain)
                .focused($searchFocused)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 3)
            .background(.bar)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func rows(_ items: [ClipItem]) -> some View {
        ForEach(items) { item in
            MenuBarRow(item: item) {
                dismiss()
                env.paste.paste(item)
            }
            .contextMenu {
                Button("Paste") { dismiss(); env.paste.paste(item) }
                Button("Paste as Plain Text") { dismiss(); env.paste.paste(item, transform: .plainText) }
                Button("Copy") { env.paste.copy(item) }
                Divider()
                Button(item.isPinned ? "Unpin" : "Pin") { env.store.togglePin(item) }
                Menu("Assign to Quick Slot") {
                    ForEach(QuickSlots.range, id: \.self) { n in
                        Button("⌘\(n)\(env.slots.title(for: n).map { " — " + $0 } ?? "")") {
                            env.slots.assign(.clip(item), to: n)
                        }
                    }
                }
                Button("Delete", role: .destructive) { env.store.delete(item) }
            }
        }
    }

    /// Inline instead of a dialog: a modal sheet steals focus from the menu bar window,
    /// which closes the popover before the click lands.
    private var clearConfirmation: some View {
        HStack(spacing: 8) {
            Text("Clear history? Pinned items are kept.")
                .font(.callout)
                .lineLimit(1)
            Spacer()
            Button("Cancel") { confirmClear = false }
                .keyboardShortcut(.cancelAction)
            Button("Clear", role: .destructive) {
                env.store.clearHistory()
                confirmClear = false
            }
            .keyboardShortcut(.defaultAction)
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private var footer: some View {
        HStack(spacing: 2) {
            footerButton("Open Quick Panel", symbol: "rectangle.and.text.magnifyingglass") {
                dismiss()
                env.showQuickPanel()
            }
            Spacer()
            footerButton(env.prefs.isPaused ? "Resume Capture" : "Pause Capture",
                         symbol: env.prefs.isPaused ? "play.fill" : "pause.fill") {
                env.prefs.isPaused.toggle()
            }
            footerButton("Clear History", symbol: "trash") { confirmClear = true }
            footerButton("Settings", symbol: "gearshape") {
                dismiss()
                NSApp.activate()
                openSettings()
            }
            footerButton("Quit Clippy", symbol: "power") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func footerButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct MenuBarRow: View {
    let item: ClipItem
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ClipIconView(item: item, size: 22)
                Text(item.preview.isEmpty ? item.kind.displayName : item.preview)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if item.isPinned {
                    Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary)
                }
                Text(item.lastCopiedAt.shortRelative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? AnyShapeStyle(.selection.opacity(0.35)) : AnyShapeStyle(.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(item.accessibilityDescription)
        .accessibilityHint("Pastes into the previous app")
    }
}
