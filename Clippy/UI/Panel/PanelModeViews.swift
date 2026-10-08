import SwiftUI

/// ⌘K menu: paste variants, transforms, Claude actions and item actions for the selection.
struct ActionMenuView: View {
    @Bindable var model: PanelViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let actions = model.filteredActions
        let isPinned = model.selectedEntry?.clip?.isPinned ?? false

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "command")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(model.actionQuery.isEmpty ? "Type to filter actions" : model.actionQuery)
                    .foregroundStyle(model.actionQuery.isEmpty ? .tertiary : .primary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(model.actionQuery.isEmpty ? "Actions" : "Actions matching \(model.actionQuery)")

            Divider()

            if actions.isEmpty {
                ContentUnavailableView("No Matching Actions", systemImage: "magnifyingglass")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                                if index == 0 || actions[index - 1].section(aiName: model.aiName) != action.section(aiName: model.aiName) {
                                    Text(action.section(aiName: model.aiName))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.top, index == 0 ? 2 : 10)
                                        .padding(.bottom, 2)
                                        .accessibilityAddTraits(.isHeader)
                                }
                                ActionRow(action: action, title: action.title(isPinned: isPinned),
                                          isSelected: index == model.actionSelection)
                                    .id(action.id)
                                    .onTapGesture { model.perform(action) }
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: model.actionSelection) { _, index in
                        guard actions.indices.contains(index) else { return }
                        if reduceMotion { proxy.scrollTo(actions[index].id) } else {
                            withAnimation(.snappy(duration: 0.12)) { proxy.scrollTo(actions[index].id) }
                        }
                    }
                }
            }
        }
    }
}

private struct ActionRow: View {
    let action: PanelAction
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: action.symbol)
                .frame(width: 20)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .accessibilityHidden(true)
            Text(title)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear))
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Small form for custom snippet placeholders like {name}.
struct SnippetFormView: View {
    @Bindable var form: SnippetFormState
    let onSubmit: () -> Void
    @FocusState private var focused: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(form.snippet.name.isEmpty ? "Snippet" : form.snippet.name, systemImage: "text.badge.star")
                .font(.headline)
            Text("Fill in the fields, then press Return to paste.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Form {
                ForEach(form.fields, id: \.self) { field in
                    TextField(field.capitalized, text: binding(for: field))
                        .focused($focused, equals: field)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            HStack {
                Spacer()
                Button("Paste", action: onSubmit)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .onAppear { focused = form.fields.first }
    }

    private func binding(for field: String) -> Binding<String> {
        Binding(
            get: { form.values[field] ?? "" },
            set: { form.values[field] = $0 }
        )
    }
}

/// Names a history item and moves it into the keychain-backed Secrets vault.
struct SaveSecretView: View {
    @Bindable var form: SaveSecretState
    let onSubmit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Save as Secret", systemImage: "key.fill")
                .font(.headline)
            Text("Stores the value in your Keychain and removes it from clipboard history. Pasting it asks for Touch ID, and the clipboard is cleared again afterwards.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Form {
                TextField("Name", text: $form.name, prompt: Text("e.g. Prod DB password"))
                    .focused($focused)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            HStack {
                Spacer()
                Button("Save", action: onSubmit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(form.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .onAppear { focused = true }
    }
}

/// Streaming AI output with Paste / Copy / Replace actions.
struct AIResultView: View {
    let run: AIRun
    let model: PanelViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: run.action.symbol)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(run.action.title).font(.headline)
                Text(run.providerName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if run.isStreaming {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("Waiting for the response")
                }
            }
            .padding(14)

            Divider()

            ScrollView {
                Group {
                    if let error = run.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    } else if run.output.isEmpty {
                        Text("Thinking…").foregroundStyle(.secondary)
                    } else {
                        Text(run.output)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
            .accessibilityLabel("AI result")

            Divider()

            HStack {
                if run.error?.needsSettings == true {
                    Button("Open Settings…") {
                        model.onClose()
                        SettingsOpener.open()
                    }
                }
                Spacer()
                Button("Replace Item") { model.replaceItemWithAIOutput() }
                    .disabled(!run.isFinished)
                    .help("⌘R")
                Button("Copy") { model.copyAIOutput() }
                    .disabled(run.output.isEmpty)
                    .help("⌘C")
                Button("Paste") { model.pasteAIOutput() }
                    .disabled(!run.isFinished)
                    .buttonStyle(.borderedProminent)
                    .help("Return")
            }
            .padding(12)
        }
    }
}
