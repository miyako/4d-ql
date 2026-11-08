import XCTest
@testable import FourDFileKit
@testable import FourDRender

final class MethodTests: XCTestCase {
    private func file(_ data: Data, extension ext: String = "4dm") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func analyze(_ text: String) throws -> MethodFileInfo {
        try XCTUnwrap(AnalyzerRegistry.default.analyze(url: file(Data(text.utf8))) as? MethodFileInfo)
    }

    private func assertToken(_ text: String, _ kind: MethodToken.Kind,
                             in tokens: [MethodToken], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(tokens.contains { $0.text == text && $0.kind == kind },
                      "Missing \(kind) token: \(text)", file: file, line: line)
    }

    func testRegistrationAndCaseInsensitiveExtension() throws {
        XCTAssertTrue(AnalyzerRegistry.default.allContentTypes.contains("com.4d.4d.method"))
        let url = try file(Data("var $x : Text".utf8), extension: "4DM")
        XCTAssertEqual(try AnalyzerRegistry.default.analyze(url: url, contentType: "public.text").kind, "4dm.source")
        let noExtension = try file(Data("Function hello()".utf8), extension: "txt")
        XCTAssertEqual(try AnalyzerRegistry.default.analyze(url: noExtension, contentType: "com.4d.4d.method").kind,
                       "4dm.source")
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Support/Host-Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let declarations = try XCTUnwrap(plist["UTImportedTypeDeclarations"] as? [[String: Any]])
        let method = try XCTUnwrap(declarations.first { $0["UTTypeIdentifier"] as? String == "com.4d.4d.method" })
        let tags = try XCTUnwrap(method["UTTypeTagSpecification"] as? [String: Any])
        XCTAssertEqual(tags["public.filename-extension"] as? [String], ["4dm"])
    }

    func testTokenCategoriesAndSourcePreservation() throws {
        let source = """
        //%attributes = {"invisible":true}
        shared Function hello($name : Text) -> $result : Text
        var $count : Integer
        If ($count>=0xFF)
            $result:="Hello \\"world\\" // not a comment"
            <>sharedValue:=String:C10($count)+Is text:K6:2
            [Employees:1]Name:2:=$name
            $table:=[Employees:1]
            $date:=!2026-11-08!+!08/11/26!+!08.11.26!
            $time:=?123:45:06?
            $number:=1.5e-3
            TEXT TO BLOB($result; $blob)
        End if
        """
        let info = try analyze(source)
        XCTAssertEqual(info.source, source)
        XCTAssertFalse(info.truncated)
        assertToken("//%attributes = {\"invisible\":true}", .processing, in: info.tokens)
        assertToken("shared", .keyword, in: info.tokens)
        assertToken("Function", .keyword, in: info.tokens)
        assertToken("End if", .keyword, in: info.tokens)
        assertToken("$name", .variable, in: info.tokens)
        assertToken("<>sharedValue", .variable, in: info.tokens)
        assertToken("Text", .type, in: info.tokens)
        assertToken("\"Hello \\\"world\\\" // not a comment\"", .string, in: info.tokens)
        assertToken("String:C10", .command, in: info.tokens)
        assertToken("Is text:K6:2", .constant, in: info.tokens)
        assertToken("[Employees:1]Name:2", .property, in: info.tokens)
        assertToken("[Employees:1]", .type, in: info.tokens)
        for literal in ["0xFF", "1.5e-3", "!2026-11-08!", "!08/11/26!", "!08.11.26!", "?123:45:06?"] {
            assertToken(literal, .number, in: info.tokens)
        }
        assertToken("TEXT TO BLOB", .command, in: info.tokens)
        assertToken("hello", .command, in: info.tokens)
        assertToken(":=", .operator, in: info.tokens)
    }

    func testCommentsTakePrecedenceAndContinueAcrossLines() throws {
        let source = "// If \"text\" \\\ncontinued $x:=1\n/* Function\n$name */\nvar $real : Text"
        let info = try analyze(source)
        XCTAssertEqual(info.source, source)
        assertToken("// If \"text\" \\\ncontinued $x:=1", .comment, in: info.tokens)
        assertToken("/* Function\n$name */", .comment, in: info.tokens)
        XCTAssertFalse(info.tokens.contains { $0.kind == .variable && $0.text == "$name" })
        assertToken("$real", .variable, in: info.tokens)
    }

    func testIncompleteSourceAndUnknownIdentifiersArePreserved() throws {
        for source in ["/* unclosed $x", "\"unclosed // string\nvar $x", "00_Start 123abc IfSomething $日本語 ds.If"] {
            let info = try analyze(source)
            XCTAssertEqual(info.source, source)
        }
        let tokens = try analyze("00_Start 123abc IfSomething $日本語 ds.If").tokens
        assertToken("00_Start", .plain, in: tokens)
        assertToken("123abc", .plain, in: tokens)
        assertToken("IfSomething", .plain, in: tokens)
        assertToken("$日本語", .variable, in: tokens)
        XCTAssertFalse(tokens.contains { $0.kind == .keyword })
    }

    func testBOMAndLineEndings() throws {
        let info = try analyze("\u{FEFF}\u{FEFF}var $日本語 : Text\r\n\r$return:=\"😀\"\r")
        XCTAssertEqual(info.source, "var $日本語 : Text\n\n$return:=\"😀\"\n")
        XCTAssertEqual(info.lineCount, 3)
        let html = HTMLRenderer().render(try XCTUnwrap(MethodPresenter().report(for: info)))
        XCTAssertEqual(html.components(separatedBy: "class=\"source-line\"").count - 1, 3)
        XCTAssertTrue(html.contains("😀"))
    }

    func testLineLimitAndVisibleNotice() throws {
        let info = try analyze(String(repeating: "var $x : Text\n", count: 1_001))
        XCTAssertTrue(info.truncated)
        XCTAssertEqual(info.lineCount, 1_000)
        XCTAssertEqual(info.source.components(separatedBy: "\n").count, 1_000)
        let html = HTMLRenderer().render(try XCTUnwrap(MethodPresenter().report(for: info)))
        XCTAssertTrue(html.contains("Preview limited"))
        XCTAssertEqual(html.components(separatedBy: "class=\"source-line\"").count - 1, 1_000)
        let exact = try analyze(String(repeating: "\n", count: 1_000))
        XCTAssertEqual(exact.lineCount, 1_000)
        XCTAssertFalse(exact.truncated)
    }

    func testByteLimitAndSplitUTF8Scalar() throws {
        for prefixLength in (MethodFileAnalyzer.maximumBytes - 3)..<MethodFileAnalyzer.maximumBytes {
            let text = String(repeating: " ", count: prefixLength) + "😀more"
            let url = try file(Data(text.utf8))
            let info = try XCTUnwrap(AnalyzerRegistry.default.analyze(url: url, options: .thorough) as? MethodFileInfo)
            XCTAssertTrue(info.truncated)
            XCTAssertEqual(info.source, String(repeating: " ", count: prefixLength))
            XCTAssertLessThanOrEqual(info.source.utf8.count, MethodFileAnalyzer.maximumBytes)
        }
        let exact = try analyze(String(repeating: " ", count: MethodFileAnalyzer.maximumBytes))
        XCTAssertFalse(exact.truncated)
    }

    func testLongUntokenizedLineStaysWithinPreviewBudget() throws {
        let source = String(repeating: "identifier ", count: 20_000)
        let start = Date()
        let info = try analyze(source)
        XCTAssertEqual(info.source, source)
        XCTAssertLessThan(Date().timeIntervalSince(start), AnalysisOptions.preview.timeBudget)
    }

    func testInvalidUTF8AndBinaryAreReported() throws {
        for data in [Data([0xFF, 0xFE, 0x61, 0]), Data([0x61, 0xF0, 0x9F]), Data([0x61, 0, 0x62])] {
            let url = try file(data)
            XCTAssertThrowsError(try AnalyzerRegistry.default.analyze(url: url))
            let html = PreviewPipeline().html(for: url)
            XCTAssertTrue(html.contains("No preview available"))
            XCTAssertTrue(html.contains("not valid UTF-8"))
        }
    }

    func testEmptyMethodAndJSONShape() throws {
        let info = try analyze("")
        XCTAssertEqual(info.lineCount, 0)
        XCTAssertEqual(info.source, "")
        XCTAssertFalse(info.truncated)
        let html = HTMLRenderer().render(try XCTUnwrap(MethodPresenter().report(for: info)))
        XCTAssertTrue(html.contains("This source file is empty"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: info.jsonData()) as? [String: Any])
        XCTAssertEqual(json["kind"] as? String, "4dm.source")
        XCTAssertEqual(json["source"] as? String, "")
        XCTAssertEqual(json["lineCount"] as? Int, 0)
        XCTAssertNotNil(json["tokens"])
    }

    func testHTMLSourceEscapingAndMultilineSpans() throws {
        let source = "// <script>alert(\"x\")</script>&\n/* first\nsecond */\n$x:=\"<img src='https://example.com'>&\""
        let html = PreviewPipeline().html(for: try file(Data(source.utf8)))
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertFalse(html.contains("<img "))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        XCTAssertTrue(html.contains("&amp;"))
        XCTAssertTrue(html.contains("class=\"syntax-comment\""))
        XCTAssertTrue(html.contains("class=\"syntax-string\""))
        XCTAssertEqual(html.components(separatedBy: "class=\"source-line\"").count - 1, 4)
    }

    func testExistingFixtureMethods() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/encfixture/Project/Sources/Methods")
        let urls = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "4dm" }
        XCTAssertFalse(urls.isEmpty)
        for url in urls {
            let info = try XCTUnwrap(AnalyzerRegistry.default.analyze(url: url) as? MethodFileInfo)
            XCTAssertFalse(info.truncated)
            XCTAssertEqual(info.source, try String(contentsOf: url, encoding: .utf8))
            XCTAssertTrue(PreviewPipeline().html(for: url).contains("class=\"source\""))
        }
    }
}
