import Foundation

nonisolated struct SnippetExpansion: Equatable, Sendable {
    var text: String
    /// Characters between the {cursor} marker and the end of the text (0 = caret at end).
    var cursorOffsetFromEnd: Int
}

/// Expands `{date}`, `{time}`, `{clipboard}`, `{cursor}` and custom `{fields}` in snippet bodies.
/// Anything in braces that isn't a valid placeholder name (e.g. JSON) is left untouched.
nonisolated enum SnippetExpander {
    static let builtIns: Set<String> = ["date", "time", "clipboard", "cursor"]

    private enum Token: Equatable {
        case literal(String)
        case placeholder(String)
    }

    /// Custom placeholder names in order of first appearance.
    static func customFields(in body: String) -> [String] {
        var seen = Set<String>()
        var fields: [String] = []
        for case .placeholder(let name) in tokenize(body) where !builtIns.contains(name.lowercased()) {
            if seen.insert(name).inserted { fields.append(name) }
        }
        return fields
    }

    static func expand(
        _ body: String,
        values: [String: String] = [:],
        clipboard: String?,
        now: Date = .now,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> SnippetExpansion {
        var output = ""
        var cursorIndex: Int?   // character offset from start

        for token in tokenize(body) {
            switch token {
            case .literal(let text):
                output += text
            case .placeholder(let name):
                switch name.lowercased() {
                case "date":
                    output += formatted(now, date: .medium, time: .none, locale: locale, timeZone: timeZone)
                case "time":
                    output += formatted(now, date: .none, time: .short, locale: locale, timeZone: timeZone)
                case "clipboard":
                    output += clipboard ?? ""
                case "cursor":
                    if cursorIndex == nil { cursorIndex = output.count }
                default:
                    output += values[name] ?? ""
                }
            }
        }
        let offset = cursorIndex.map { output.count - $0 } ?? 0
        return SnippetExpansion(text: output, cursorOffsetFromEnd: offset)
    }

    static func formatted(_ date: Date, date dateStyle: DateFormatter.Style, time timeStyle: DateFormatter.Style,
                          locale: Locale, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter.string(from: date)
    }

    private static func isNameStart(_ c: Character) -> Bool { c.isLetter || c == "_" }
    private static func isNameChar(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" || c == "-" || c == " " }

    private static func tokenize(_ body: String) -> [Token] {
        var tokens: [Token] = []
        var literal = ""
        let chars = Array(body)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "{", i + 1 < chars.count, isNameStart(chars[i + 1]) {
                var j = i + 1
                while j < chars.count, j - i <= 40, isNameChar(chars[j]) { j += 1 }
                if j < chars.count, chars[j] == "}" {
                    let name = String(chars[(i + 1)..<j]).trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        if !literal.isEmpty { tokens.append(.literal(literal)); literal = "" }
                        tokens.append(.placeholder(name))
                        i = j + 1
                        continue
                    }
                }
            }
            literal.append(c)
            i += 1
        }
        if !literal.isEmpty { tokens.append(.literal(literal)) }
        return tokens
    }
}
