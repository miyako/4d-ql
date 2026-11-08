import XCTest
@testable import FourDFileKit
@testable import FourDRender

final class TextFileTests: XCTestCase {
    private func withoutHighlighting(_ html: String) -> String {
        html.replacingOccurrences(of: #"<span class="syntax-[a-z]+">|</span>"#, with: "", options: .regularExpression)
    }

    private func file(_ text: String, extension ext: String, encoding: String.Encoding = .utf8) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
        try text.write(to: url, atomically: true, encoding: encoding)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    func testSettingsXMLPreviewPreservesSourceAndEscapesMarkup() throws {
        let text = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<settings>\n\t<name>日本語 &amp; text</name>\n</settings>\n"
        let url = try file(text, extension: "4DSettings")
        let info = try XCTUnwrap(try AnalyzerRegistry.default.analyze(url: url) as? TextFileInfo)
        XCTAssertEqual(info.format, .xml)
        XCTAssertEqual(info.text, text)
        XCTAssertEqual(info.fileName, url.lastPathComponent)
        let html = PreviewPipeline().html(for: url)
        XCTAssertTrue(html.contains("4D Settings (XML)"))
        XCTAssertTrue(html.contains("<pre class=\"source mono\"><code>"))
        XCTAssertTrue(withoutHighlighting(html).contains("\n\t&lt;name&gt;日本語 &amp;amp; text&lt;/name&gt;\n"))
        XCTAssertTrue(html.contains("<span class=\"syntax-tag\">name</span>"))
        XCTAssertFalse(html.contains("<settings>"))
    }

    func testProjectJSONPreviewAndJSONOutput() throws {
        let text = "{\n  \"name\": \"日本語\",\n  \"value\": \"<script>alert(1)</script>\"\n}\n"
        let url = try file(text, extension: "4DProject")
        let info = try XCTUnwrap(try AnalyzerRegistry.default.analyze(url: url) as? TextFileInfo)
        XCTAssertEqual(info.format, .json)
        XCTAssertEqual(info.text, text)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: info.jsonData()) as? [String: String])
        XCTAssertEqual(json["text"], text)
        XCTAssertEqual(json["format"], "json")
        let html = PreviewPipeline().html(for: url)
        XCTAssertTrue(html.contains("4D Project (JSON)"))
        XCTAssertTrue(withoutHighlighting(html).contains("\n  &quot;name&quot;: &quot;日本語&quot;,"))
        XCTAssertTrue(html.contains("<span class=\"syntax-key\">&quot;name&quot;</span>"))
        XCTAssertTrue(html.contains("<span class=\"syntax-string\">&quot;日本語&quot;</span>"))
        XCTAssertTrue(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
        XCTAssertFalse(html.contains("<script>"))
    }

    func testTypeAndCaseInsensitiveExtensionRouting() throws {
        for (ext, type, format) in [
            ("4DSETTINGS", "com.4d.4d.settings", TextFileInfo.Format.xml),
            ("4dproject", "com.4d.4d.project", TextFileInfo.Format.json),
        ] {
            let url = try file("test", extension: ext)
            XCTAssertEqual(try (AnalyzerRegistry.default.analyze(url: url) as? TextFileInfo)?.format, format)
            let untagged = try file("test", extension: "txt")
            XCTAssertEqual(try (AnalyzerRegistry.default.analyze(url: untagged, contentType: type) as? TextFileInfo)?.format, format)
            XCTAssertTrue(AnalyzerRegistry.default.allContentTypes.contains(type))
        }
    }

    func testUTF16Settings() throws {
        let text = "<?xml version=\"1.0\" encoding=\"UTF-16\"?>\n<settings>日本語</settings>"
        let url = try file(text, extension: "4DSettings", encoding: .utf16)
        XCTAssertEqual(try (AnalyzerRegistry.default.analyze(url: url) as? TextFileInfo)?.text, text)
    }

    func testSourcePreviewPreservesWindowsAndClassicMacLineBreaks() throws {
        for newline in ["\r\n", "\r"] {
            let text = "<settings>\(newline)\t<name>test</name>\(newline)</settings>"
            let url = try file(text, extension: "4DSettings")
            XCTAssertEqual(try (AnalyzerRegistry.default.analyze(url: url) as? TextFileInfo)?.text, text)
            XCTAssertTrue(withoutHighlighting(PreviewPipeline().html(for: url)).contains("&lt;settings&gt;\n\t&lt;name&gt;test&lt;/name&gt;\n&lt;/settings&gt;"))
        }
    }

    func testEmptyFile() throws {
        let url = try file("", extension: "4DProject")
        XCTAssertEqual(try (AnalyzerRegistry.default.analyze(url: url) as? TextFileInfo)?.text, "")
        XCTAssertFalse(PreviewPipeline().html(for: url).contains("No preview available"))
    }

    func testUnreadableFileShowsError() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".4DSettings")
        XCTAssertThrowsError(try AnalyzerRegistry.default.analyze(url: url))
        XCTAssertTrue(PreviewPipeline().html(for: url).contains("No preview available"))
    }
}
