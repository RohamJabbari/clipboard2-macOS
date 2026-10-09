import Testing
import Foundation
@testable import Clipboard2

struct TransformTests {
    @Test func trim() {
        #expect(Transform.trimWhitespace.apply("  hi there \n") == "hi there")
    }

    @Test func caseTransforms() {
        #expect(Transform.uppercase.apply("Grüß Gott") == "GRÜSS GOTT")
        #expect(Transform.lowercase.apply("HeLLo") == "hello")
        #expect(Transform.titleCase.apply("the QUICK brown fox's tail") == "The Quick Brown Fox's Tail")
        #expect(Transform.titleCase.apply("don't-stop") == "Don't-Stop")
    }

    @Test func jsonPrettifyPreservesKeyOrder() {
        let input = #"{"z":1,"a":[1,2,{"k":"v, with: punctuation {}"}],"e":{}}"#
        let expected = """
        {
          "z": 1,
          "a": [
            1,
            2,
            {
              "k": "v, with: punctuation {}"
            }
          ],
          "e": {}
        }
        """
        #expect(Transform.jsonPrettify.apply(input) == expected)
    }

    @Test func jsonMinify() {
        let input = """
        {
          "a" : [ 1, 2 ],
          "b" : "x y"
        }
        """
        #expect(Transform.jsonMinify.apply(input) == #"{"a":[1,2],"b":"x y"}"#)
    }

    @Test func invalidJSONReturnsNil() {
        #expect(Transform.jsonPrettify.apply("{nope") == nil)
        #expect(Transform.jsonMinify.apply("") == nil)
    }

    @Test func jsonEscapedQuotes() {
        #expect(Transform.jsonMinify.apply(#"{ "a" : "say \"hi\" " }"#) == #"{"a":"say \"hi\" "}"#)
    }

    @Test func urlRoundTrip() {
        let s = "a b&c=d/é?"
        let encoded = Transform.urlEncode.apply(s)
        #expect(encoded == "a%20b%26c%3Dd%2F%C3%A9%3F")
        #expect(Transform.urlDecode.apply(encoded ?? "") == s)
        #expect(Transform.urlDecode.apply("a+b") == "a b")
    }

    @Test func base64RoundTrip() {
        #expect(Transform.base64Encode.apply("Hello, Wien!") == "SGVsbG8sIFdpZW4h")
        #expect(Transform.base64Decode.apply("SGVsbG8sIFdpZW4h") == "Hello, Wien!")
        #expect(Transform.base64Decode.apply("SGVsbG8") == "Hello")          // missing padding
        #expect(Transform.base64Decode.apply("not base64!!") == nil)
    }

    @Test func removeLineBreaks() {
        #expect(Transform.removeLineBreaks.apply("one\n  two\r\n\nthree ") == "one two three")
    }

    @Test func plainTextIsIdentity() {
        #expect(Transform.plainText.apply("x\ny") == "x\ny")
    }
}

struct FuzzyMatcherTests {
    @Test func subsequenceMatches() {
        #expect(FuzzyMatcher.score(query: "hlo", in: "hello") != nil)
        #expect(FuzzyMatcher.score(query: "xyz", in: "hello") == nil)
    }

    @Test func substringBeatsScattered() throws {
        let exact = try #require(FuzzyMatcher.score(query: "port", in: "import report"))
        let scattered = try #require(FuzzyMatcher.score(query: "port", in: "p o r t"))
        #expect(exact > scattered)
    }

    @Test func everyTokenMustMatch() {
        #expect(FuzzyMatcher.score(query: "foo bar", in: "foo and bar") != nil)
        #expect(FuzzyMatcher.score(query: "foo baz", in: "foo and bar") == nil)
    }
}
