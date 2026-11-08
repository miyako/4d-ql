import XCTest
@testable import FourDRender

final class SourceHighlighterTests: XCTestCase {
    private func source(_ text: String, language: Block.CodeLanguage) throws -> (html: String, plain: String) {
        var report = Report(title: "Source")
        report.sections = [Section("Contents", [.sourceCode(text, language: language)])]
        let html = HTMLRenderer().render(report)
        let start = try XCTUnwrap(html.range(of: "<code>")?.upperBound)
        let end = try XCTUnwrap(html.range(of: "</code>", range: start..<html.endIndex)?.lowerBound)
        let code = String(html[start..<end])
        let plain = code.replacingOccurrences(of: #"<span class="syntax-[a-z]+">|</span>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
        return (code, plain)
    }

    func testJSONTokensAndEscapedStrings() throws {
        let text = #"{"escaped\"key" : "a\\\"b", "n": -1.25e+3, "b": true, "f": false, "x": null, "a": [0, 2]}"#
        let result = try source(text, language: .json)
        XCTAssertEqual(result.plain, text)
        XCTAssertTrue(result.html.contains(#"<span class="syntax-key">&quot;escaped\&quot;key&quot;</span>"#))
        XCTAssertTrue(result.html.contains(#"<span class="syntax-string">&quot;a\\\&quot;b&quot;</span>"#))
        XCTAssertTrue(result.html.contains(#"<span class="syntax-number">-1.25e+3</span>"#))
        for literal in ["true", "false", "null"] {
            XCTAssertTrue(result.html.contains("<span class=\"syntax-literal\">\(literal)</span>"))
        }
    }

    func testXMLTokensCommentsAndCDATA() throws {
        let text = "<?xml version=\"1.0\"?>\n<!-- <fake a='x'> -->\n<ns:settings enabled='true' path=\"a>b\"/>\n<text>&amp;&#x41;<![CDATA[<script>&text]]></text>"
        let result = try source(text, language: .xml)
        XCTAssertEqual(result.plain, text)
        XCTAssertTrue(result.html.contains(#"<span class="syntax-tag">ns:settings</span>"#))
        XCTAssertTrue(result.html.contains(#"<span class="syntax-attribute">enabled</span>"#))
        XCTAssertTrue(result.html.contains(#"<span class="syntax-string">'true'</span>"#))
        XCTAssertTrue(result.html.contains(#"<span class="syntax-string">&quot;a&gt;b&quot;</span>"#))
        XCTAssertTrue(result.html.contains(#"<span class="syntax-comment">&lt;!-- &lt;fake a='x'&gt; --&gt;</span>"#))
        XCTAssertTrue(result.html.contains(#"<span class="syntax-entity">&amp;amp;</span>"#))
        XCTAssertTrue(result.html.contains(#"<span class="syntax-entity">&amp;#x41;</span>"#))
        XCTAssertTrue(result.html.contains(#"<span class="syntax-string">&lt;![CDATA[&lt;script&gt;&amp;text]]&gt;</span>"#))
        XCTAssertFalse(result.html.contains("<script>"))
    }

    func testIncompleteDocumentsPreserveAllText() throws {
        for (text, language) in [
            ("{\"value\": \"unfinished\\", Block.CodeLanguage.json),
            ("<settings name='unfinished", .xml),
            ("<!-- unfinished <tag>", .xml),
            ("<![CDATA[unfinished &", .xml),
            ("<text>&unfinished", .xml),
            ("<!DOCTYPE settings", .xml),
            ("", .json),
            ("日本語 & <text>", .plain),
        ] {
            XCTAssertEqual(try source(text, language: language).plain, text)
        }
    }

    func testMarkupInTokensCannotCreateHTML() throws {
        for language in [Block.CodeLanguage.json, .xml, .plain] {
            let text = "\"</code><script>alert(1)</script>&lt;\""
            let result = try source(text, language: language)
            XCTAssertEqual(result.plain, text)
            XCTAssertFalse(result.html.contains("<script>"))
            XCTAssertFalse(result.html.contains("</code>"))
        }
    }
}
