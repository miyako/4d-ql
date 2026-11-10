import XCTest
@testable import FourDFileKit
@testable import FourDRender

final class ViewProTests: XCTestCase {
    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "4vp", subdirectory: "Fixtures/ViewPro"))
    }

    private func native(_ name: String) throws -> ViewProFileInfo {
        try XCTUnwrap(try AnalyzerRegistry.default.analyze(url: fixture(name)) as? ViewProFileInfo)
    }

    private func cell(_ row: Int, _ column: Int, _ value: ViewProValue? = nil,
                      formula: String? = nil, formattedText: String? = nil, style: ViewProStyle = ViewProStyle()) -> ViewProCell {
        ViewProCell(row: row, column: column, value: value, formula: formula, formattedText: formattedText, style: style)
    }

    private func sheet(_ cells: [ViewProCell], name: String = "Sheet1", index: Int = 0) -> ViewProSheet {
        ViewProSheet(name: name, index: index, visible: true, rowCount: 1_000_000, columnCount: 100_000,
                     cells: cells, rows: [:], columns: [:], defaultRowHeight: 20, defaultColumnWidth: 64,
                     defaultStyle: ViewProStyle(), spans: [], showGridLines: true, warnings: [])
    }

    private func document(_ sheets: [ViewProSheet], active: Int = 0) -> ViewProFileInfo {
        ViewProFileInfo(fileName: "test.4vp", activeSheet: active, sheets: sheets, warnings: [])
    }

    private func html(_ document: ViewProFileInfo) -> String {
        HTMLRenderer().render(try! XCTUnwrap(ViewProPresenter().report(for: document)))
    }

    func testStaticHTMLUsesSavedValuesAndNeverExecutesCode() {
        var link = cell(0, 0, .text("<script>alert(1)</script>"))
        link.link = "https://example.com/?a=\" onclick=\"alert(1)"
        let output = html(document([sheet([link, cell(1, 0, .number(42), formula: "MY_4D_FUNCTION()"),
                                          cell(2, 0, formula: "WEBSERVICE(\"https://example.com\")")])]))
        XCTAssertTrue(output.contains("&lt;script&gt;"))
        XCTAssertFalse(output.contains("<script"))
        XCTAssertFalse(output.contains("href="))
        XCTAssertFalse(output.contains("src=\"http"))
        XCTAssertTrue(output.contains("Content-Security-Policy"))
        XCTAssertTrue(output.contains(">42</div>"))
        XCTAssertTrue(output.contains("=WEBSERVICE("))
        XCTAssertTrue(output.contains("1 formula cells have no saved result"))
        XCTAssertTrue(output.contains("Formula: MY_4D_FUNCTION()"))
    }

    func testHiddenAxesMergedCellsAndStyleInheritance() {
        var valueStyle = ViewProStyle()
        valueStyle.foreground = "#112233"
        var columnStyle = ViewProStyle()
        columnStyle.background = "#abcdef"
        var rowStyle = ViewProStyle()
        rowStyle.wordWrap = true
        var merged = sheet([cell(0, 0, .text("Merged"), style: valueStyle),
                            cell(1, 0, .text("HIDDEN_ROW")), cell(2, 1, .text("HIDDEN_COLUMN"))])
        merged.rows[0] = ViewProAxis(size: 36, visible: true, style: rowStyle)
        merged.rows[1] = ViewProAxis(size: 20, visible: false, style: ViewProStyle())
        merged.columns[0] = ViewProAxis(size: 160, visible: true, style: columnStyle)
        merged.columns[1] = ViewProAxis(size: 64, visible: false, style: ViewProStyle())
        merged.spans = [ViewProSpan(row: 0, column: 0, rowCount: 1, columnCount: 3)]
        let output = html(document([merged]))
        XCTAssertTrue(output.contains("colspan=\"2\""))
        XCTAssertTrue(output.contains("color:#112233"))
        XCTAssertTrue(output.contains("background-color:#abcdef"))
        XCTAssertTrue(output.contains("white-space:pre-wrap"))
        XCTAssertTrue(output.contains("width:160.00px"))
        XCTAssertTrue(output.contains("height:36.00px"))
        XCTAssertFalse(output.contains("HIDDEN_ROW"))
        XCTAssertFalse(output.contains("HIDDEN_COLUMN"))
    }

    func testSheetOrderSelectionAndHiddenSheets() {
        var hidden = sheet([cell(0, 0, .text("SECRET_CELL"))], name: "Hidden", index: 1)
        hidden.visible = false
        let doc = document([sheet([cell(0, 0, .text("First"))]), hidden,
                            sheet([cell(0, 0, .text("Second"))], name: "Second", index: 2)], active: 2)
        let output = html(doc)
        XCTAssertTrue(output.contains("aria-label=\"Second\" checked"))
        XCTAssertFalse(output.contains("SECRET_CELL"))
        XCTAssertTrue(output.contains("Hidden</td>"))
        XCTAssertEqual(output.components(separatedBy: "class=\"vp-panel vp-panel-").count - 1, 2)
    }

    func testHugeSparseSheetIsBoundedButDistantDataRemainsVisible() {
        let output = html(document([sheet([cell(900_000, 90_000, .text("Far away"))])]))
        XCTAssertTrue(output.contains("Far away"))
        XCTAssertTrue(output.contains(">900001</th>"))
        XCTAssertTrue(output.contains("Bounded preview"))
        XCTAssertLessThan(output.utf8.count, 100_000)
        let denseExtent = html(document([sheet([cell(0, 0, .text("Start")), cell(900_000, 90_000, .text("Outside"))])]))
        XCTAssertTrue(denseExtent.contains("1 saved cells outside"))
        XCTAssertFalse(denseExtent.contains(">Outside</div>"))
        XCTAssertLessThan(denseExtent.utf8.count, 2_000_000)
    }

    func testNativeFormattedTextTakesPrecedenceAndCSSIsValidated() {
        var style = ViewProStyle()
        style.formatter = "unsupported"
        style.foreground = "red;background-image:url(https://example.com)"
        style.font = "12px Arial;position:fixed"
        let output = html(document([sheet([cell(0, 0, .number(123), formattedText: "$123.00", style: style)])]))
        XCTAssertTrue(output.contains(">$123.00</div>"))
        XCTAssertFalse(output.contains("background-image"))
        XCTAssertFalse(output.contains("position:fixed"))
        XCTAssertFalse(output.contains("unsupported number formats"))
    }

    func testUnresolvedThemeColorsAreReportedInsteadOfGuessed() {
        var style = ViewProStyle()
        style.foreground = "Accent 1 0"
        let output = html(document([sheet([cell(0, 0, .text("Theme color"), style: style)])]))
        XCTAssertTrue(output.contains("Theme or unsupported color references could not be resolved"))
        XCTAssertFalse(output.contains("color:Accent 1"))
    }

    func testColumnLabels() {
        for (index, label) in [(0, "A"), (25, "Z"), (26, "AA"), (701, "ZZ"), (702, "AAA"), (16_383, "XFD")] {
            XCTAssertEqual(ViewProPreviewRenderer.columnName(index), label)
        }
    }

    func testEveryNativeExportIsRecognizedAndRendersWithoutRuntime() throws {
        for name in ["typed", "layout", "roundtrip", "values-only", "enriched", "no-format-info", "xlsx-roundtrip", "enriched-xlsx-roundtrip"] {
            let doc = try native(name)
            XCTAssertEqual(doc.version, "1")
            XCTAssertEqual(doc.spreadVersion, "18.2.0")
            XCTAssertFalse(doc.sheets.isEmpty)
            let output = PreviewPipeline().html(for: try fixture(name))
            XCTAssertTrue(output.contains("vp-grid"), name)
            XCTAssertFalse(output.contains("No preview available"), name)
            XCTAssertFalse(output.contains("<script"), name)
            XCTAssertFalse(output.contains("href="), name)
        }
    }

    func testNativeLayoutRoundtripRetainsCellsAndStyles() throws {
        let before = try native("layout")
        let after = try native("roundtrip")
        XCTAssertEqual(before.sheets.map(\.name), after.sheets.map(\.name))
        XCTAssertEqual(before.sheets.map(\.cells.count), after.sheets.map(\.cells.count))
        let data = try XCTUnwrap(before.sheets.first { $0.name == "Data" })
        let number = try XCTUnwrap(data.cells.first { $0.row == 0 && $0.column == 1 })
        XCTAssertEqual(number.value, .number(1234.5))
        XCTAssertEqual(number.formattedText, "1,234.50")
        XCTAssertEqual(number.style.font, "bold 14pt Arial")
        let date = try XCTUnwrap(data.cells.first { $0.row == 0 && $0.column == 3 })
        XCTAssertEqual(date.value, .dateSerial(45351))
        XCTAssertEqual(date.formattedText, "2/29/2024")
        let formula = try XCTUnwrap(data.cells.first { $0.row == 0 && $0.column == 4 })
        XCTAssertEqual(formula.formula, "B1*2")
        XCTAssertEqual(formula.value, .number(2469))
        XCTAssertEqual(before.sheets.filter(\.visible).count, 4)
        XCTAssertEqual(try native("enriched").sheets.filter(\.visible).count, 2)
    }

    func testMalformedAndExcessiveDocumentsProduceExplicitErrors() throws {
        for source in [
            "{}", #"{"version":2,"spreadJS":{"sheets":{}}}"#,
            #"{"version":1,"spreadJS":{"sheets":[]}}"#,
            #"{"version":1,"spreadJS":{"sheets":{"A":{"rowCount":-1}}}}"#,
            #"{"version":1,"spreadJS":{"sheets":{"A":{"data":{"dataTable":{"-1":{"0":{"value":1}}}}}}}}"#,
            #"{"version":1,"spreadJS":{"sheets":{"A":{"data":{"dataTable":{"0":{"200":{"value":1}}}}}}}}"#,
            #"{"version":1,"version":1,"spreadJS":{"sheets":{}}}"#
        ] {
            XCTAssertThrowsError(try ViewProFileAnalyzer.parse(Data(source.utf8), fileName: "bad.4vp"), source)
        }
        XCTAssertThrowsError(try ViewProFileAnalyzer.parse(Data(repeating: 32, count: 16 * 1024 * 1024 + 1), fileName: "big.4vp"))
        let deep = String(repeating: "[", count: 66) + "0" + String(repeating: "]", count: 66)
        XCTAssertThrowsError(try ViewProFileAnalyzer.parse(Data(deep.utf8), fileName: "deep.4vp"))
    }

    func testRegistrySelectsUppercaseExtensionAndExplicitUTI() {
        let registry = AnalyzerRegistry.default
        let url = URL(fileURLWithPath: "/sample.4VP")
        XCTAssertEqual(registry.candidates(contentType: nil, url: url).map(\.identifier), ["4vp"])
        XCTAssertEqual(registry.candidates(contentType: "com.4d.4d.ViewProDocument", url: URL(fileURLWithPath: "/sample")).map(\.identifier), ["4vp"])
    }

    func testNativeRichTextLinksErrorsAndInheritedStyles() throws {
        let doc = try native("enriched")
        XCTAssertEqual(doc.activeSheet, 1)
        let first = try XCTUnwrap(doc.sheets.first { $0.name == "First" })
        let rich = try XCTUnwrap(first.cells.first { $0.row == 2 && $0.column == 0 })
        XCTAssertEqual(rich.runs.map(\.text), ["Bold", " plain"])
        XCTAssertEqual(rich.runs.first?.style.foreground, "#ff0000")
        let data = try XCTUnwrap(doc.sheets.first { $0.name == "Data" })
        XCTAssertEqual(data.cells.first { $0.row == 1 && $0.column == 4 }?.value, .error("#DIV/0!"))
        XCTAssertEqual(data.cells.first { $0.row == 12 && $0.column == 0 }?.link, "https://example.com/fixture")
        XCTAssertEqual(data.columns[2]?.visible, false)
        XCTAssertEqual(data.rows[9]?.visible, false)
        XCTAssertEqual(data.columns[1]?.style.foreground, "#7030a0")
        XCTAssertEqual(data.rows[7]?.style.background, "#fff2cc")
        XCTAssertEqual(data.spans.first?.rowCount, 2)
        XCTAssertEqual(data.spans.first?.columnCount, 4)
        let output = html(doc)
        XCTAssertTrue(output.contains("color:#ff0000"))
        XCTAssertTrue(output.contains(">Bold</span>"))
        XCTAssertTrue(output.contains("#DIV/0!"))
        XCTAssertTrue(output.contains("border-bottom:2px solid #ff0000"))
        let withoutInfo = html(try native("no-format-info"))
        XCTAssertTrue(withoutInfo.contains(">1,234.50</div>"))
        XCTAssertTrue(withoutInfo.contains(">2/29/2024</div>"))
        XCTAssertTrue(withoutInfo.contains(">1899-12-30</div>"))
        XCTAssertTrue(withoutInfo.contains(">-12.5%</div>"))
    }

    func testNamedStyleReferencesAreResolvedAndCyclesRejected() throws {
        let source = """
        {"version":1,"spreadJS":{"namedStyles":[{"name":"Base","foreColor":"#123456"},{"name":"Child","parentName":"Base","font":"bold 12pt Arial"}],
        "sheets":{"A":{"data":{"dataTable":{"0":{"0":{"value":"Named","style":"Child"}}}}}}}}
        """
        let doc = try ViewProFileAnalyzer.parse(Data(source.utf8), fileName: "named.4vp")
        XCTAssertEqual(doc.sheets.first?.cells.first?.style.foreground, "#123456")
        XCTAssertEqual(doc.sheets.first?.cells.first?.style.font, "bold 12pt Arial")
        let cyclic = source.replacingOccurrences(of: "\"name\":\"Base\",\"foreColor\":\"#123456\"",
                                                 with: "\"name\":\"Base\",\"parentName\":\"Child\"")
        XCTAssertThrowsError(try ViewProFileAnalyzer.parse(Data(cyclic.utf8), fileName: "cyclic.4vp"))
        let unresolved = source.replacingOccurrences(of: "\"style\":\"Child\"", with: "\"style\":\"Unknown\"")
        XCTAssertThrowsError(try ViewProFileAnalyzer.parse(Data(unresolved.utf8), fileName: "unknown.4vp"))
    }

    func testSheetLimitIncludesActiveSheetAndReportsOmissions() {
        let sheets = (0..<20).map { sheet([cell(0, 0, .text("Cell \($0)"))], name: "Sheet \($0)", index: $0) }
        let output = html(document(sheets, active: 19))
        XCTAssertTrue(output.contains("aria-label=\"Sheet 19\" checked"))
        XCTAssertTrue(output.contains("Showing 16 of 20 visible sheets"))
        XCTAssertEqual(output.components(separatedBy: "class=\"vp-panel vp-panel-").count - 1, 16)
    }
}
