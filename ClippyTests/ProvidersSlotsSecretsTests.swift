import Testing
import Foundation
import SwiftData
@testable import Clippy

struct ProviderParsingTests {
    @Test func openAIStreamDeltasAndDone() {
        let delta = #"data: {"id":"x","choices":[{"index":0,"delta":{"content":"Hallo"},"finish_reason":null}]}"#
        #expect(SSEParser.parseOpenAI(line: delta) == .textDelta("Hallo"))
        #expect(SSEParser.parseOpenAI(line: "data: [DONE]") == .done)
        #expect(SSEParser.parseOpenAI(line: #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#) == .stop(reason: "stop"))
        #expect(SSEParser.parseOpenAI(line: #"data: {"error":{"message":"Rate limited"}}"#) == .error("Rate limited"))
        #expect(SSEParser.parseOpenAI(line: ": keep-alive") == nil)
    }

    @Test func openAICompatibleRequest() throws {
        let client = OpenAICompatibleClient(baseURL: "https://api.deepseek.com/", apiKey: "sk-x", model: "deepseek-flash")
        let request = try client.makeRequest(system: "sys", user: "hi")
        #expect(request.url?.absoluteString == "https://api.deepseek.com/chat/completions")
        #expect(request.value(forHTTPHeaderField: "authorization") == "Bearer sk-x")
        let json = try #require(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(messages.map { $0["role"] } == ["system", "user"])
        #expect(json["stream"] as? Bool == true)
    }

    @Test func customEndpointWithoutKeyHasNoAuthHeader() throws {
        let request = try OpenAICompatibleClient(baseURL: "http://localhost:11434/v1", apiKey: nil, model: "llama3")
            .makeRequest(system: "s", user: "u")
        #expect(request.value(forHTTPHeaderField: "authorization") == nil)
        #expect(throws: AIError.badURL) {
            try OpenAICompatibleClient(baseURL: "not a url", apiKey: nil, model: "m").makeRequest(system: "s", user: "u")
        }
    }

    @Test func claudeCodeStreamJSON() {
        let delta = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Guten"}}}"#
        #expect(ClaudeCodeCLIClient.parse(line: delta) == .delta("Guten"))
        let error = #"{"type":"result","subtype":"success","is_error":true,"result":"Not logged in · Please run /login"}"#
        #expect(ClaudeCodeCLIClient.parse(line: error) == .result(isError: true, text: "Not logged in · Please run /login"))
        let message = #"{"type":"assistant","message":{"content":[{"type":"text","text":"Hallo"}]}}"#
        #expect(ClaudeCodeCLIClient.parse(line: message) == .message("Hallo"))
    }

    @Test func claudeCodeArgumentsDisableToolsAndSessions() {
        let args = ClaudeCodeCLIClient(model: "sonnet").arguments(system: "S")
        #expect(args.contains("-p"))
        #expect(args.firstIndex(of: "--tools").map { args[$0 + 1] } == "")
        #expect(args.contains("--no-session-persistence"))
        #expect(args.firstIndex(of: "--model").map { args[$0 + 1] } == "sonnet")
    }

    @Test func providersNeedingKeysFailFastWithoutOne() {
        // The debug keychain has no DeepSeek key in CI/test runs.
        if AIProviderKind.deepSeek.apiKey == nil {
            #expect(throws: AIError.missingAPIKey(.deepSeek)) {
                _ = try AIClientFactory.make(provider: .deepSeek, model: "deepseek-flash", customBaseURL: "")
            }
        }
        #expect(throws: AIError.missingModel) {
            _ = try AIClientFactory.make(provider: .custom, model: " ", customBaseURL: "http://localhost:1/v1")
        }
    }
}

@MainActor
struct QuickSlotTests {
    let store: ClipStore
    let snippets: SnippetStore
    let secrets: SecretStore
    let slots: QuickSlots
    let defaults: UserDefaults
    let container: ModelContainer   // ModelContext doesn't retain its container

    init() throws {
        let schema = Schema([ClipItem.self, Snippet.self])
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        store = ClipStore(context: container.mainContext,
                          blobs: BlobStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)))
        snippets = SnippetStore(context: container.mainContext)
        defaults = try #require(UserDefaults(suiteName: "ClippyTests-\(UUID().uuidString)"))
        secrets = SecretStore(prefs: Preferences(defaults: defaults))
        slots = QuickSlots(defaults: defaults, store: store, snippets: snippets, secrets: secrets)
    }

    @Test func assigningAClipPinsItAndResolves() {
        let item = store.ingest(.text("db password"))
        slots.assign(.clip(item), to: 1)
        #expect(item.isPinned)
        #expect(slots.entry(for: 1)?.id == PanelEntry.clip(item).id)
        #expect(slots.slot(for: .clip(item.id)) == 1)
    }

    @Test func reassigningMovesTheItemToTheNewSlot() {
        let item = store.ingest(.text("x"))
        slots.assign(.clip(item), to: 1)
        slots.assign(.clip(item), to: 4)
        #expect(slots.target(for: 1) == nil)
        #expect(slots.slot(for: .clip(item.id)) == 4)
    }

    @Test func deletedItemsDropOutOfTheirSlot() {
        let item = store.ingest(.text("gone"))
        slots.assign(.clip(item), to: 2)
        store.delete(item)
        #expect(slots.entry(for: 2) == nil)
        #expect(slots.target(for: 2) == nil)
    }

    @Test func assignmentsPersist() {
        let snippet = snippets.create(name: "sig", body: "Best, R")
        slots.assign(.snippet(snippet), to: 9)
        let reloaded = QuickSlots(defaults: defaults, store: store, snippets: snippets, secrets: secrets)
        #expect(reloaded.target(for: 9) == .snippet(snippet.id))
    }

    @Test func outOfRangeSlotsAreIgnored() {
        let item = store.ingest(.text("y"))
        slots.assign(.clip(item), to: 10)
        #expect(slots.slot(for: .clip(item.id)) == nil)
    }
}

struct SecretVaultTests {
    @Test func keychainRoundTrip() throws {
        let ref = try #require(SecretVault.add(name: "Clippy test secret", value: "hunter2"))
        defer { SecretVault.delete(id: ref.id) }

        #expect(SecretVault.value(id: ref.id) == "hunter2")
        #expect(SecretVault.list().contains { $0.id == ref.id && $0.name == "Clippy test secret" })

        SecretVault.update(id: ref.id, name: "Renamed", value: "correct horse")
        #expect(SecretVault.value(id: ref.id) == "correct horse")
        #expect(SecretVault.list().first { $0.id == ref.id }?.name == "Renamed")

        SecretVault.delete(id: ref.id)
        #expect(SecretVault.value(id: ref.id) == nil)
    }
}

struct ClaudeAccountTests {
    @Test func parsesSignedOutStatus() {
        let json = #"{"loggedIn": false, "authMethod": "none", "apiProvider": "firstParty"}"#
        #expect(ClaudeCodeAccount.parseStatus(json) == .signedOut)
    }

    @Test func parsesSignedInStatusWithEmailAndNoise() {
        let output = "warning: something\n{\"loggedIn\": true, \"authMethod\": \"claudeai\", \"email\": \"admin@softmaze.at\"}\n"
        #expect(ClaudeCodeAccount.parseStatus(output) == .signedIn(account: "admin@softmaze.at"))
    }

    @Test func garbageIsNotAStatus() {
        #expect(ClaudeCodeAccount.parseStatus("command not found") == nil)
    }

    @Test func extractsHTTPSLoginURL() {
        let line = "Browser didn't open? Use: https://claude.ai/oauth/authorize?code=true&client_id=x"
        #expect(ClaudeCodeAccount.firstURL(in: line)?.host() == "claude.ai")
        #expect(ClaudeCodeAccount.firstURL(in: "no url here") == nil)
    }

    @Test func notLoggedInMapsToSignInError() {
        #expect(AIError.notSignedIn.needsSettings)
    }
}
