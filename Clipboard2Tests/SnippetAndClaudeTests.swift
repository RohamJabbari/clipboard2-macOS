import Testing
import Foundation
@testable import Clipboard2

struct SnippetExpanderTests {
    let now = Date(timeIntervalSince1970: 1_791_460_800)   // 2026-10-08 12:00 UTC
    let locale = Locale(identifier: "en_US")
    let utc = TimeZone(identifier: "UTC") ?? .gmt

    @Test func detectsCustomFieldsInOrderWithoutDuplicatesOrBuiltIns() {
        let body = "Hi {name}, {date} — see {link}. Bye {name}{cursor}{clipboard}{time}"
        #expect(SnippetExpander.customFields(in: body) == ["name", "link"])
    }

    @Test func expandsBuiltInsAndCustomValues() {
        let result = SnippetExpander.expand(
            "Hi {name}! Today is {date} at {time}. Clip: {clipboard}",
            values: ["name": "Roham"], clipboard: "XYZ", now: now, locale: locale, timeZone: utc
        )
        #expect(result.text == "Hi Roham! Today is Oct 8, 2026 at 12:00\u{202F}PM. Clip: XYZ")
        #expect(result.cursorOffsetFromEnd == 0)
    }

    @Test func cursorMarkerIsRemovedAndOffsetComputed() {
        let result = SnippetExpander.expand("<b>{cursor}</b>", clipboard: nil)
        #expect(result.text == "<b></b>")
        #expect(result.cursorOffsetFromEnd == 4)
    }

    @Test func onlyFirstCursorCounts() {
        let result = SnippetExpander.expand("a{cursor}b{cursor}c", clipboard: nil)
        #expect(result.text == "abc")
        #expect(result.cursorOffsetFromEnd == 2)
    }

    @Test func leavesNonPlaceholderBracesAlone() {
        let json = #"{"key": 1} and { spaced } and {} and {9lives}"#
        #expect(SnippetExpander.customFields(in: json).isEmpty)
        #expect(SnippetExpander.expand(json, clipboard: nil).text == json)
    }

    @Test func missingValuesAndClipboardBecomeEmpty() {
        #expect(SnippetExpander.expand("[{who}][{clipboard}]", clipboard: nil).text == "[][]")
    }

    @Test func builtInsAreCaseInsensitive() {
        #expect(SnippetExpander.expand("{CLIPBOARD}", clipboard: "x").text == "x")
    }

    @Test func multiWordFieldNames() {
        #expect(SnippetExpander.customFields(in: "Dear {first name},") == ["first name"])
        #expect(SnippetExpander.expand("Dear {first name},", values: ["first name": "Ana"], clipboard: nil).text == "Dear Ana,")
    }
}

struct ClaudeClientTests {
    @Test func requestHasRequiredHeadersAndFallbackForSonnet55() throws {
        let client = ClaudeClient(apiKey: "sk-test", model: "claude-sonnet-5-5")
        let request = try client.makeRequest(system: "sys", user: "hello")
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == ClaudeClient.fallbackBeta)

        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "claude-sonnet-5-5")
        #expect(json["stream"] as? Bool == true)
        #expect(json["fallbacks"] as? String == "default")
        #expect((json["output_config"] as? [String: Any])?["effort"] as? String == "low")
        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(messages.first?["content"] as? String == "hello")
    }

    @Test func olderModelsGetNoBetaOrEffort() throws {
        let request = try ClaudeClient(apiKey: "k", model: "claude-haiku-4-5").makeRequest(system: "s", user: "u")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == nil)
        let json = try #require(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        #expect(json["fallbacks"] == nil)
        #expect(json["output_config"] == nil)
    }

    @Test func parsesTextDeltas() {
        let line = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hallo"}}"#
        #expect(SSEParser.parse(line: line) == .textDelta("Hallo"))
    }

    @Test func ignoresThinkingAndNonDataLines() {
        #expect(SSEParser.parse(line: "event: content_block_delta") == nil)
        let thinking = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":""}}"#
        #expect(SSEParser.parse(line: thinking) == .other)
    }

    @Test func parsesStopAndErrors() {
        #expect(SSEParser.parse(line: #"data: {"type":"message_delta","delta":{"stop_reason":"refusal"}}"#) == .stop(reason: "refusal"))
        #expect(SSEParser.parse(line: #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#) == .error("Overloaded"))
        #expect(SSEParser.errorMessage(fromBody: Data(#"{"type":"error","error":{"message":"invalid x-api-key"}}"#.utf8)) == "invalid x-api-key")
    }

    @Test func userMessageWrapsInput() {
        #expect(AIAction.userMessage(for: "hi") == "<text>\nhi\n</text>")
        #expect(AIAction.translate(language: "Farsi").systemPrompt.contains("Farsi"))
    }
}
