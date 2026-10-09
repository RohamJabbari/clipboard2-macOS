import SwiftUI
import SwiftData

// MARK: - Snippets

struct SnippetsSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(sort: \Snippet.name) private var snippets: [Snippet]
    @State private var selection: Snippet.ID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(snippets) { snippet in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snippet.name.isEmpty ? "Untitled" : snippet.name)
                            if !snippet.keyword.isEmpty {
                                Text(snippet.keyword).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tag(snippet.id)
                    }
                }
                .listStyle(.sidebar)
                Divider()
                HStack(spacing: 0) {
                    Button {
                        let snippet = env.snippets.create()
                        selection = snippet.id
                    } label: {
                        Image(systemName: "plus").frame(width: 24, height: 20)
                    }
                    .accessibilityLabel("Add snippet")
                    Button {
                        if let snippet = selectedSnippet {
                            env.snippets.delete(snippet)
                            selection = nil
                        }
                    } label: {
                        Image(systemName: "minus").frame(width: 24, height: 20)
                    }
                    .disabled(selection == nil)
                    .accessibilityLabel("Delete snippet")
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(width: 200)

            Divider()

            if let snippet = selectedSnippet {
                SnippetEditor(snippet: snippet)
                    .id(snippet.id)
            } else {
                ContentUnavailableView {
                    Label("No Snippet Selected", systemImage: "text.badge.star")
                } description: {
                    Text("Snippets show up in the quick panel when you search or pick the Snippets filter.")
                } actions: {
                    Button("New Snippet") { selection = env.snippets.create().id }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minHeight: 420)
    }

    private var selectedSnippet: Snippet? {
        snippets.first { $0.id == selection }
    }
}

private struct SnippetEditor: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable var snippet: Snippet

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $snippet.name)
                TextField("Keyword", text: $snippet.keyword, prompt: Text("e.g. ;sig"))
            }
            Section {
                TextEditor(text: $snippet.body)
                    .font(.body.monospaced())
                    .frame(minHeight: 150)
                    .accessibilityLabel("Snippet body")
            } header: {
                Text("Body")
            } footer: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("{date}, {time} — current date and time")
                    Text("{clipboard} — what's on the clipboard right now")
                    Text("{cursor} — where the caret ends up after pasting")
                    Text("{anything} — asks you for a value before pasting, e.g. {name}")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: snippet.name) { env.snippets.didEdit(snippet) }
        .onChange(of: snippet.keyword) { env.snippets.didEdit(snippet) }
        .onChange(of: snippet.body) { env.snippets.didEdit(snippet) }
    }
}

// MARK: - Transforms

struct TransformsSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var prefs = env.prefs
        Form {
            Section {
                if prefs.appTransforms.isEmpty {
                    Text("No per-app rules. Items paste with their original formatting everywhere.")
                        .foregroundStyle(.secondary)
                }
                ForEach($prefs.appTransforms) { $rule in
                    HStack {
                        AppRow(app: rule.app)
                        Picker("Transform for \(rule.app.name)", selection: $rule.transform) {
                            ForEach(Transform.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 190)
                        Button {
                            prefs.appTransforms.removeAll { $0.id == rule.id }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove rule for \(rule.app.name)")
                    }
                }
                AppPickerMenu(title: "Add App…", exclude: Set(prefs.appTransforms.map(\.app.bundleID))) { app in
                    prefs.appTransforms.append(AppTransformRule(app: app, transform: .plainText))
                }
            } header: {
                Text("Default transform per app")
            } footer: {
                Text("Applied automatically when pasting from Clippy into that app — for example, always paste plain text into Mail. Pick a different transform any time with ⌘K in the quick panel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Available transforms") {
                ForEach(Transform.allCases) { transform in
                    Label(transform.title, systemImage: transform.symbol)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - AI

struct AISettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var keyInput = ""
    @State private var hasKey = false
    @State private var testState: TestState = .idle
    @State private var models: [String] = []
    @State private var modelsError: String?
    @State private var loadingModels = false

    enum TestState: Equatable {
        case idle, running, ok, failed(String)
    }

    var body: some View {
        @Bindable var prefs = env.prefs
        let provider = prefs.aiProvider
        Form {
            Section {
                Picker("Provider", selection: $prefs.aiProvider) {
                    Text(AIProviderKind.claudeCode.title).tag(AIProviderKind.claudeCode)
                    Divider()
                    ForEach(AIProviderKind.allCases.filter { $0 != .claudeCode }) { Text($0.title).tag($0) }
                }
                if provider == .claudeCode {
                    ClaudeAccountRow(account: env.claudeAccount)
                } else if provider == .anthropic && !hasKey {
                    LabeledContent("Have Claude Pro or Max?") {
                        Button("Use My Claude Subscription") {
                            prefs.aiProvider = .claudeCode
                            if !env.claudeAccount.isSignedIn { env.claudeAccount.signIn() }
                        }
                    }
                }
                if provider.hasEditableBaseURL {
                    TextField("Base URL", text: $prefs.customBaseURL, prompt: Text("http://localhost:11434/v1"))
                        .frame(minWidth: 300)
                }
                if provider.usesAPIKey {
                    if hasKey {
                        LabeledContent("API key") {
                            HStack {
                                Label("Stored in Keychain", systemImage: "key.fill")
                                    .foregroundStyle(.secondary)
                                Button("Remove", role: .destructive) {
                                    Keychain.delete(account: provider.keychainAccount)
                                    refreshKeyState()
                                }
                            }
                        }
                    } else {
                        LabeledContent("API key") {
                            HStack {
                                SecureField("API key", text: $keyInput, prompt: Text(provider.keyPlaceholder))
                                    .labelsHidden()
                                    .frame(minWidth: 300)
                                    .onSubmit { saveKey(for: provider) }
                                Button("Save") { saveKey(for: provider) }
                                    .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                    }
                }
                LabeledContent("Model") {
                    HStack {
                        TextField("Model", text: $prefs.aiModel, prompt: Text(provider.defaultModel.isEmpty ? "model-id" : provider.defaultModel))
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(minWidth: 220)
                        Menu {
                            if models.isEmpty {
                                Text(modelsError ?? "No models loaded")
                            }
                            ForEach(models, id: \.self) { model in
                                Button(model) { prefs.aiModel = model }
                            }
                            Divider()
                            Button("Fetch Models") { fetchModels() }
                        } label: {
                            if loadingModels { ProgressView().controlSize(.small) } else { Image(systemName: "list.bullet") }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Fetch the provider's current models")
                        .accessibilityLabel("Choose a model")
                    }
                }
                HStack {
                    Button("Test Connection") { test() }
                        .disabled(testState == .running || (provider.requiresAPIKey && !hasKey))
                    switch testState {
                    case .idle: EmptyView()
                    case .running: ProgressView().controlSize(.small)
                    case .ok: Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .failed(let message):
                        Label(message, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                            .lineLimit(3)
                    }
                }
            } header: {
                Text("Provider")
            } footer: {
                Text("Keys are stored in the macOS Keychain. Text is sent to the provider only when you run an action with ⌘K. OpenRouter gives you Gemini, Llama, Mistral and more with one key; “OpenAI-Compatible” works with Ollama, LM Studio, Groq and similar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach($prefs.customPrompts) { $prompt in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField("Name", text: $prompt.name, prompt: Text("Prompt name"))
                                .labelsHidden()
                                .font(.headline)
                            Button {
                                prefs.customPrompts.removeAll { $0.id == prompt.id }
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove prompt \(prompt.name)")
                        }
                        TextField("Instructions", text: $prompt.prompt,
                                  prompt: Text("e.g. Rewrite as a friendly email reply"), axis: .vertical)
                            .labelsHidden()
                            .lineLimit(2...6)
                    }
                    .padding(.vertical, 2)
                }
                Button("Add Prompt") {
                    prefs.customPrompts.append(CustomPrompt(name: "New Prompt", prompt: ""))
                }
            } header: {
                Text("Custom prompts")
            } footer: {
                Text("Built-in: Translate (English, German, Farsi), Summarize, Fix Grammar, Explain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshKeyState() }
        .onChange(of: prefs.aiProvider) {
            refreshKeyState()
            models = []
            modelsError = nil
            testState = .idle
        }
    }

    private func refreshKeyState() {
        hasKey = env.prefs.aiProvider.apiKey != nil
        keyInput = ""
    }

    private func saveKey(for provider: AIProviderKind) {
        let key = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        Keychain.save(key, account: provider.keychainAccount, label: "Clippy – \(provider.title) API key")
        refreshKeyState()
    }

    private func fetchModels() {
        let provider = env.prefs.aiProvider
        let base = env.prefs.customBaseURL
        loadingModels = true
        Task {
            do {
                models = try await AIModelLister.fetch(provider: provider, customBaseURL: base)
                modelsError = models.isEmpty ? "The provider returned no models" : nil
            } catch {
                models = []
                modelsError = error.localizedDescription
            }
            loadingModels = false
        }
    }

    private func test() {
        let prefs = env.prefs
        testState = .running
        Task {
            do {
                let client = try AIClientFactory.make(provider: prefs.aiProvider, model: prefs.aiModel, customBaseURL: prefs.customBaseURL)
                var output = ""
                for try await chunk in client.stream(system: "Reply with the single word OK.", user: "Ping") {
                    output += chunk
                }
                testState = output.isEmpty ? .failed("Empty response") : .ok
            } catch {
                testState = .failed(error.localizedDescription)
            }
        }
    }
}

// MARK: - Claude subscription account

struct ClaudeAccountRow: View {
    let account: ClaudeCodeAccount
    @State private var code = ""

    var body: some View {
        Group {
            LabeledContent("Account") {
                HStack(spacing: 8) {
                    status
                    actions
                }
            }
            if account.state == .signingIn {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Finish signing in in your browser, then come back here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if let url = account.signInURL {
                        Button("Open Sign-In Page Again") { NSWorkspace.shared.open(url) }
                    }
                    if account.needsCode {
                        HStack {
                            TextField("Code", text: $code, prompt: Text("Paste the code from the browser"))
                            Button("Continue") {
                                account.submitCode(code)
                                code = ""
                            }
                            .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
            }
            Text("Uses your Claude Pro or Max plan, with no API key and no API billing. Requests take a few seconds longer to start than with an API key.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task { await account.refresh() }
    }

    @ViewBuilder
    private var status: some View {
        switch account.state {
        case .checking:
            ProgressView().controlSize(.small)
        case .notInstalled:
            Label("Not set up", systemImage: "circle.dashed").foregroundStyle(.secondary)
        case .installing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Installing…").foregroundStyle(.secondary)
            }
        case .signedOut:
            Label("Signed out", systemImage: "person.crop.circle.badge.xmark").foregroundStyle(.secondary)
        case .signingIn:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Waiting for browser…").foregroundStyle(.secondary)
            }
        case .signedIn(let name):
            Label(name ?? "Signed in", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch account.state {
        case .notInstalled:
            Button("Set Up Claude") { Task { await account.install(); if case .signedOut = account.state { account.signIn() } } }
                .help("Installs Anthropic's Claude Code (no admin rights needed), then signs you in")
        case .signedOut, .failed:
            Button("Sign in with Claude") { account.signIn() }
                .buttonStyle(.borderedProminent)
        case .signingIn:
            Button("Cancel") { account.cancelSignIn(); Task { await account.refresh() } }
        case .signedIn:
            Button("Sign Out") { Task { await account.signOut() } }
        case .checking, .installing:
            EmptyView()
        }
    }
}

// MARK: - Secrets

struct SecretsSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var newName = ""
    @State private var newValue = ""
    @State private var editing: SecretRef?
    @State private var editValue = ""
    @State private var confirmDelete: SecretRef?
    @State private var revealed: [String: String] = [:]

    var body: some View {
        @Bindable var prefs = env.prefs
        Form {
            Section {
                if env.secrets.secrets.isEmpty {
                    Text("No secrets yet. Add one here, or select a copied password in the quick panel and choose ⌘K → Save as Secret.")
                        .foregroundStyle(.secondary)
                }
                ForEach(env.secrets.secrets) { ref in
                    HStack {
                        Image(systemName: "key.fill").foregroundStyle(.tint).accessibilityHidden(true)
                        TextField("Name", text: Binding(
                            get: { ref.name },
                            set: { env.secrets.rename(ref, to: $0) }
                        ))
                        .labelsHidden()
                        Text(revealed[ref.id] ?? "••••••••")
                            .font(.body.monospaced())
                            .foregroundStyle(revealed[ref.id] == nil ? .secondary : .primary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .frame(maxWidth: 180, alignment: .leading)
                        Button {
                            if revealed[ref.id] != nil {
                                revealed[ref.id] = nil
                            } else {
                                Task { revealed[ref.id] = await env.secrets.reveal(ref, reason: "show “\(ref.name)”") }
                            }
                        } label: {
                            Image(systemName: revealed[ref.id] == nil ? "eye" : "eye.slash")
                        }
                        .buttonStyle(.borderless)
                        .help(revealed[ref.id] == nil ? "Show value (Touch ID)" : "Hide value")
                        .accessibilityLabel(revealed[ref.id] == nil ? "Show \(ref.name)" : "Hide \(ref.name)")
                        if let slot = env.slots.slot(for: .secret(ref.id)) {
                            Text("⌘\(slot)").font(.caption.monospacedDigit()).foregroundStyle(.tint)
                        }
                        Button("Change Value…") {
                            editValue = ""
                            editing = ref
                        }
                        Button {
                            confirmDelete = ref
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Delete \(ref.name)")
                    }
                }
            } header: {
                Text("Secrets")
            } footer: {
                Text("Values are stored only in your login Keychain — never in Clippy's history, never synced, and never sent to AI or transforms.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Add a secret") {
                TextField("Name", text: $newName, prompt: Text("e.g. Prod DB password"))
                SecureField("Value", text: $newValue)
                HStack {
                    Spacer()
                    Button("Add Secret") {
                        env.secrets.add(name: newName.trimmingCharacters(in: .whitespaces), value: newValue)
                        newName = ""
                        newValue = ""
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || newValue.isEmpty)
                }
            }

            Section("Security") {
                Picker("Ask for Touch ID", selection: $prefs.secretGraceMinutes) {
                    ForEach(Preferences.secretGraceChoices, id: \.self) { minutes in
                        Text(minutes == 0 ? "Every time" : minutes == 1 ? "Once per minute" : "Once per \(minutes) minutes").tag(minutes)
                    }
                }
                Picker("Clear clipboard after pasting", selection: $prefs.secretClearSeconds) {
                    ForEach(Preferences.secretClearChoices, id: \.self) { seconds in
                        Text(seconds == 0 ? "Never" : "\(seconds) seconds").tag(seconds)
                    }
                }
                Text("The unlock window ends when your Mac sleeps or locks. Pasted secrets are marked concealed, so clipboard managers don't record them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Unlock") {
                    SecretUnlockControl(secrets: env.secrets)
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear { revealed = [:] }
        .sheet(item: $editing) { ref in
            VStack(alignment: .leading, spacing: 14) {
                Text("New value for “\(ref.name)”").font(.headline)
                SecureField("Value", text: $editValue)
                HStack {
                    Spacer()
                    Button("Cancel") { editing = nil }
                        .keyboardShortcut(.cancelAction)
                    Button("Save") {
                        env.secrets.setValue(editValue, for: ref)
                        editing = nil
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(editValue.isEmpty)
                }
            }
            .padding(20)
            .frame(width: 360)
        }
        .confirmationDialog("Delete “\(confirmDelete?.name ?? "")”?", isPresented: Binding(
            get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let ref = confirmDelete {
                    env.slots.remove(target: .secret(ref.id))
                    env.secrets.delete(ref)
                }
                confirmDelete = nil
            }
        } message: {
            Text("The value is removed from your Keychain.")
        }
    }
}
