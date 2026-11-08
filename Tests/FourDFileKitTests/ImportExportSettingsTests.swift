import XCTest
@testable import FourDFileKit
@testable import FourDRender

final class ImportExportSettingsTests: XCTestCase {
    private let sample = """
    <?xml version="1.0" encoding="UTF-8"?>
    <settings-import-export table_no="1" format="4D" encoding="UTF-8" char_display_format="decimal" platform="automatic" table_name="Table_1">
        <field table_no="1" field_no="2" name="Field_2" kind="alpha"/>
        <field table_no="1" field_no="3" name="Field_3" kind="alpha"/>
        <field table_no="1" field_no="4" name="Field_4" kind="alpha"/>
        <field table_no="1" field_no="5" name="Field_5" kind="alpha"/>
        <field table_no="1" field_no="1" name="ID" kind="int32"/>
        <text_settings with_column_title="false"/>
    </settings-import-export>
    """

    private func file(_ text: String, extension ext: String = "4si", encoding: String.Encoding = .utf8) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
        try text.write(to: url, atomically: true, encoding: encoding)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    func testSampleUsesTablesAndPreservesSelectedFieldOrder() throws {
        let url = try file(sample)
        let info = try XCTUnwrap(try AnalyzerRegistry.default.analyze(url: url) as? ImportExportSettingsInfo)
        XCTAssertEqual(info.root.children.filter { $0.name == "field" }.map { $0.attributes["field_no"] }, ["2", "3", "4", "5", "1"])
        let report = PresenterRegistry.default.report(for: info)
        guard case .table(let fields) = report.sections[1].blocks[0] else { return XCTFail("Expected a field table") }
        XCTAssertEqual(fields.columns.map(\.0), ["Order", "Table #", "Field #", "Field", "Type"])
        XCTAssertEqual(fields.rows.last, ["5", "1", "1", "ID", "Long integer (32-bit)"])
        let html = PreviewPipeline().html(for: url)
        XCTAssertTrue(html.contains("4D Import/Export Settings"))
        XCTAssertTrue(html.contains("Text settings / Include column titles"))
        XCTAssertTrue(html.contains(">No</td>"))
        XCTAssertTrue(html.contains("Table_1"))
        XCTAssertFalse(html.contains("<pre"))
        XCTAssertTrue(html.contains("<table>"))
    }

    func testUTIAndCaseInsensitiveExtensionRouting() throws {
        let url = try file(sample, extension: "4SI")
        XCTAssertTrue(try AnalyzerRegistry.default.analyze(url: url) is ImportExportSettingsInfo)
        let untagged = try file(sample, extension: "txt")
        XCTAssertTrue(try AnalyzerRegistry.default.analyze(url: untagged, contentType: "com.4d.4d.ie-settings") is ImportExportSettingsInfo)
        XCTAssertTrue(AnalyzerRegistry.default.allContentTypes.contains("com.4d.4d.ie-settings"))
    }

    func testWhitespaceBeforeDeclarationInAttachedSample() throws {
        let url = try file(" " + sample)
        let info = try XCTUnwrap(try AnalyzerRegistry.default.analyze(url: url) as? ImportExportSettingsInfo)
        XCTAssertEqual(info.warnings, ["Ignored whitespace before the XML declaration."])
        let html = PreviewPipeline().html(for: url)
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertFalse(html.contains("No preview available"))
        XCTAssertFalse(html.contains("Ignored whitespace"))
        XCTAssertFalse(html.contains("Parser notes"))
        XCTAssertFalse(html.contains("Formatting notes"))
    }

    func testUnknownOptionsNestedContentAndEscapingArePreserved() throws {
        let url = try file("""
        <settings-import-export table_name="false" table_no="7" future_option="custom">
          <field name="日本語 &amp; &lt;script&gt;" kind="future-type" width="12"><extra value="a&amp;b"/></field>
          <future><delimiter><![CDATA[<script>]]></delimiter><empty/></future>
        </settings-import-export>
        """)
        let info = try XCTUnwrap(try AnalyzerRegistry.default.analyze(url: url) as? ImportExportSettingsInfo)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: info.jsonData()) as? [String: Any])
        let root = try XCTUnwrap(json["root"] as? [String: Any])
        XCTAssertEqual((root["attributes"] as? [String: String])?["future_option"], "custom")
        XCTAssertEqual(info.root.children[1].children[0].text, "<script>")
        let report = PresenterRegistry.default.report(for: info)
        guard case .table(let fields) = report.sections[1].blocks[0] else { return XCTFail("Expected a field table") }
        XCTAssertEqual(fields.rows[0][1], "7")
        XCTAssertEqual(fields.rows[0][2], "Not specified")
        XCTAssertEqual(fields.rows[0][4], "future-type")
        XCTAssertTrue(fields.rows[0][5].contains("Width: 12"))
        XCTAssertTrue(fields.rows[0][5].contains("a&b"))
        let html = HTMLRenderer().render(report)
        XCTAssertTrue(html.contains("<dd>false</dd>"))
        XCTAssertTrue(html.contains("日本語 &amp; &lt;script&gt;"))
        XCTAssertTrue(html.contains("Future Option"))
        XCTAssertTrue(html.contains("(empty)"))
        XCTAssertFalse(html.contains("<script>"))
    }

    func testEmptySelectionAndUTF16XML() throws {
        let url = try file("""
        <?xml version="1.0" encoding="UTF-16"?>
        <settings-import-export table_name="日本語"/>
        """, encoding: .utf16)
        let html = PreviewPipeline().html(for: url)
        XCTAssertTrue(html.contains("日本語"))
        XCTAssertTrue(html.contains("No fields are selected"))
    }

    func testMalformedWrongRootAndCustomEntitiesAreRejected() throws {
        for text in [
            "", "<settings-import-export>", "<settings/>",
            "<!DOCTYPE settings-import-export [<!ENTITY custom 'expanded'>]><settings-import-export table_name='&custom;'/>",
            "<!DOCTYPE settings-import-export [<!ENTITY custom SYSTEM 'file:///etc/passwd'>]><settings-import-export>&custom;</settings-import-export>",
        ] {
            let url = try file(text)
            XCTAssertThrowsError(try AnalyzerRegistry.default.analyze(url: url), text)
            XCTAssertTrue(PreviewPipeline().html(for: url).contains("No preview available"), text)
        }
    }

    func testSizeElementAndNestingLimits() throws {
        for text in [
            String(repeating: " ", count: 4 * 1024 * 1024 + 1),
            "<settings-import-export>" + String(repeating: "<field/>", count: 20_000) + "</settings-import-export>",
            "<settings-import-export>" + String(repeating: "<nested>", count: 32) + String(repeating: "</nested>", count: 32) + "</settings-import-export>",
        ] {
            let url = try file(text)
            XCTAssertThrowsError(try AnalyzerRegistry.default.analyze(url: url))
        }
    }

    func testPreviewLimitsDoNotTruncateJSONModel() throws {
        let fields = (1...501).map { "<field field_no='\($0)' name='Field_\($0)' kind='alpha'/>" }.joined()
        let options = (1...501).map { "<option value='\($0)'/>" }.joined()
        let url = try file("<settings-import-export>\(fields)\(options)</settings-import-export>")
        let info = try XCTUnwrap(try AnalyzerRegistry.default.analyze(url: url) as? ImportExportSettingsInfo)
        XCTAssertEqual(info.root.children.count, 1002)
        let report = PresenterRegistry.default.report(for: info)
        for section in report.sections.dropFirst() {
            guard case .table(let table) = section.blocks[0] else { return XCTFail("Expected a table") }
            XCTAssertEqual(table.rows.count, 500)
            XCTAssertNotNil(table.more)
        }
        let html = HTMLRenderer().render(report)
        XCTAssertFalse(html.contains(">Field_501<"))
        XCTAssertTrue(html.contains("1 more field"))
        XCTAssertTrue(html.contains("1 more setting"))
    }
}
