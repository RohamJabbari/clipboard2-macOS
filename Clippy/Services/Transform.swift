import Foundation

/// Text transforms applied at paste time. All pure, so they're cheap to unit test.
nonisolated enum Transform: String, CaseIterable, Codable, Identifiable, Sendable {
    case plainText
    case trimWhitespace
    case uppercase
    case lowercase
    case titleCase
    case jsonPrettify
    case jsonMinify
    case urlEncode
    case urlDecode
    case base64Encode
    case base64Decode
    case removeLineBreaks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plainText: "Paste as Plain Text"
        case .trimWhitespace: "Trim Whitespace"
        case .uppercase: "UPPERCASE"
        case .lowercase: "lowercase"
        case .titleCase: "Title Case"
        case .jsonPrettify: "Prettify JSON"
        case .jsonMinify: "Minify JSON"
        case .urlEncode: "URL Encode"
        case .urlDecode: "URL Decode"
        case .base64Encode: "Base64 Encode"
        case .base64Decode: "Base64 Decode"
        case .removeLineBreaks: "Remove Line Breaks"
        }
    }

    var symbol: String {
        switch self {
        case .plainText: "doc.plaintext"
        case .trimWhitespace: "scissors"
        case .uppercase: "textformat.size.larger"
        case .lowercase: "textformat.size.smaller"
        case .titleCase: "textformat"
        case .jsonPrettify: "curlybraces"
        case .jsonMinify: "curlybraces.square"
        case .urlEncode: "link.badge.plus"
        case .urlDecode: "link"
        case .base64Encode: "lock.doc"
        case .base64Decode: "lock.open"
        case .removeLineBreaks: "arrow.left.and.right.text.vertical"
        }
    }

    /// Returns nil when the input isn't valid for this transform (e.g. malformed JSON).
    func apply(_ input: String) -> String? {
        switch self {
        case .plainText:
            return input
        case .trimWhitespace:
            return input.trimmingCharacters(in: .whitespacesAndNewlines)
        case .uppercase:
            return input.uppercased()
        case .lowercase:
            return input.lowercased()
        case .titleCase:
            return Self.titleCased(input)
        case .jsonPrettify:
            return JSONFormatter.format(input, pretty: true)
        case .jsonMinify:
            return JSONFormatter.format(input, pretty: false)
        case .urlEncode:
            return input.addingPercentEncoding(withAllowedCharacters: Self.urlUnreserved)
        case .urlDecode:
            return input.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
        case .base64Encode:
            return Data(input.utf8).base64EncodedString()
        case .base64Decode:
            return Self.decodeBase64(input)
        case .removeLineBreaks:
            return input
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
    }

    private static let urlUnreserved: CharacterSet = {
        var set = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        set.insert(charactersIn: "-._~")
        return set
    }()

    /// Capitalises the first letter of every word and lowercases the rest, keeping
    /// apostrophes inside words ("don't" → "Don't").
    private static func titleCased(_ input: String) -> String {
        var result = ""
        result.reserveCapacity(input.count)
        var atWordStart = true
        for ch in input {
            if ch.isLetter || ch.isNumber {
                result += atWordStart ? ch.uppercased() : ch.lowercased()
                atWordStart = false
            } else {
                result.append(ch)
                if ch != "'" && ch != "’" { atWordStart = true }
            }
        }
        return result
    }

    private static func decodeBase64(_ input: String) -> String? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = s.count % 4
        if remainder > 0 { s += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: s) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Reformats JSON without reordering keys or touching number formatting (JSONSerialization
/// would do both), by re-emitting the token stream with new whitespace.
nonisolated enum JSONFormatter {
    static func format(_ input: String, pretty: Bool, indent: String = "  ") -> String? {
        guard let data = input.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
        else { return nil }

        let chars = Array(input)
        var out = ""
        out.reserveCapacity(chars.count)
        var level = 0
        var inString = false
        var escaped = false
        var i = 0

        func newline() {
            out.append("\n")
            out.append(String(repeating: indent, count: max(0, level)))
        }

        while i < chars.count {
            let c = chars[i]
            if inString {
                out.append(c)
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
                i += 1
                continue
            }
            switch c {
            case "\"":
                inString = true
                out.append(c)
            case "{", "[":
                var j = i + 1
                while j < chars.count, chars[j].isWhitespace { j += 1 }
                let closer: Character = c == "{" ? "}" : "]"
                if j < chars.count, chars[j] == closer {
                    out.append(c)
                    out.append(closer)
                    i = j + 1
                    continue
                }
                out.append(c)
                if pretty { level += 1; newline() }
            case "}", "]":
                if pretty { level -= 1; newline() }
                out.append(c)
            case ",":
                out.append(c)
                if pretty { newline() }
            case ":":
                out.append(c)
                if pretty { out.append(" ") }
            default:
                if !c.isWhitespace { out.append(c) }
            }
            i += 1
        }
        return out
    }
}
