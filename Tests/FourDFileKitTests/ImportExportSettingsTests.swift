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

    func testSampleUsesOrderedCardsAndPreservesSelectedFieldOrder() throws {
        let url = try file(sample)
        let info = try XCTUnwrap(try AnalyzerRegistry.default.analyze(url: url) as? ImportExportSettingsInfo)
        XCTAssertEqual(info.root.children.filter { $0.name == "field" }.map { $0.attributes["field_no"] }, ["2", "3", "4", "5", "1"])
        let report = PresenterRegistry.default.report(for: info)
        XCTAssertEqual(report.stats.map(\.label), ["Table", "Fields", "Format", "Encoding"])
        XCTAssertEqual(report.stats.map(\.value), ["Table_1", "5", "4D", "UTF-8"])
        XCTAssertEqual(report.sections.map(\.title), ["Fields in import/export order", "Settings", "Options"])
        guard case .orderedCards(let fields) = report.sections[0].blocks[0] else { return XCTFail("Expected field cards") }
        XCTAssertEqual(fields.map(\.title), ["Field_2", "Field_3", "Field_4", "Field_5", "ID"])
        XCTAssertEqual(fields.last?.subtitle, "Long integer (32-bit)")
        XCTAssertEqual(fields.last?.details.map(\.value), ["1", "1"])
        guard case .keyValues(let options) = report.sections[2].blocks[0] else { return XCTFail("Expected borderless options") }
        XCTAssertEqual(options.map(\.value), ["No"])
        let html = PreviewPipeline().html(for: url)
        XCTAssertTrue(html.contains("4D Import/Export Settings"))
        XCTAssertTrue(html.contains("Text settings / Include column titles"))
        XCTAssertTrue(html.contains(">No</dd>"))
        XCTAssertTrue(html.contains("Table_1"))
        XCTAssertFalse(html.contains("<pre"))
        XCTAssertFalse(html.contains("<table>"))
        XCTAssertTrue(html.contains("<ol class=\"ordered-cards\">"))
        XCTAssertFalse(html.contains("<span class=\"query-connector\""))
        XCTAssertTrue(html.contains("aria-label=\"Long integer (32-bit)\""))
        XCTAssertFalse(html.contains("criterion "))
        let summaryPosition = try XCTUnwrap(html.range(of: "<div class=\"stats\">"))
        let fieldsPosition = try XCTUnwrap(html.range(of: "<h2>Fields in import/export order</h2>"))
        let settingsPosition = try XCTUnwrap(html.range(of: "<h2>Settings</h2>"))
        XCTAssertLessThan(summaryPosition.lowerBound, fieldsPosition.lowerBound)
        XCTAssertLessThan(fieldsPosition.lowerBound, settingsPosition.lowerBound)
        XCTAssertTrue(html.contains("<div class=\"pair\">"))
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
        XCTAssertTrue(html.contains("<ol class=\"ordered-cards\">"))
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
        guard case .orderedCards(let fields) = report.sections[0].blocks[0] else { return XCTFail("Expected field cards") }
        XCTAssertEqual(fields[0].details[0].value, "7")
        XCTAssertEqual(fields[0].details[1].value, "Not specified")
        XCTAssertEqual(fields[0].subtitle, "future-type")
        XCTAssertTrue(fields[0].details.contains { $0.key == "Width" && $0.value == "12" })
        XCTAssertTrue(fields[0].details.contains { $0.value == "a&b" })
        let html = HTMLRenderer().render(report)
        XCTAssertEqual(report.stats.first?.value, "false")
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
        let info = try XCTUnwrap(try AnalyzerRegistry.default.analyze(url: url) as? ImportExportSettingsInfo)
        XCTAssertEqual(PresenterRegistry.default.report(for: info).stats.map(\.value), ["日本語", "0", "Not specified", "Not specified"])
    }

    func testMaximumLengthNamesAndAllTypeSymbols() throws {
        let name = String(repeating: "界", count: 31)
        let kinds = ["alpha", "text", "int16", "int32", "int64", "real", "boolean", "date", "time", "picture", "blob", "object", "collection", "future-type"]
        let fields = kinds.map { "<field name='\(name)' kind='\($0)'/>" }.joined()
        let url = try file("<settings-import-export table_name='\(name)'>\(fields)</settings-import-export>")
        let info = try XCTUnwrap(try AnalyzerRegistry.default.analyze(url: url) as? ImportExportSettingsInfo)
        let report = PresenterRegistry.default.report(for: info)
        guard case .orderedCards(let cards) = report.sections[0].blocks[0] else { return XCTFail("Expected cards") }
        XCTAssertEqual(cards.count, kinds.count)
        XCTAssertTrue(cards.dropLast().allSatisfy { $0.icon != nil && $0.title == name })
        XCTAssertNil(cards.last?.icon)
        let html = HTMLRenderer().render(report)
        XCTAssertTrue(html.contains("<span class=\"field-card-name\">\(name)</span>"))
        XCTAssertTrue(html.contains("<span class=\"field-type-label\">future-type</span>"))
        XCTAssertFalse(html.contains("query-connector\""))
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
        XCTAssertEqual(report.stats[1].value, "501")
        guard case .orderedCards(let cards) = report.sections[0].blocks[0],
              case .keyValues(let settings) = report.sections[1].blocks[0] else { return XCTFail("Expected cards and settings") }
        XCTAssertEqual(cards.count, 500)
        XCTAssertEqual(settings.count, 500)
        XCTAssertEqual(report.sections[0].blocks.count, 2)
        XCTAssertEqual(report.sections[1].blocks.count, 2)
        let html = HTMLRenderer().render(report)
        XCTAssertFalse(html.contains(">Field_501<"))
        XCTAssertTrue(html.contains("1 more field"))
        XCTAssertTrue(html.contains("1 more setting"))
    }
}
