import XCTest
@testable import FourDFileKit
@testable import FourDRender

final class QuickReportTests: XCTestCase {
    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "4qr", subdirectory: "Fixtures/QuickReport"))
    }

    private func analyze(_ name: String) throws -> QuickReportFileInfo {
        try XCTUnwrap(try AnalyzerRegistry.default.analyze(url: fixture(name)) as? QuickReportFileInfo)
    }

    private func temporary(_ data: Data, ext: String = "4qr") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
        try data.write(to: url)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    private func word(_ value: UInt32) -> Data {
        Data((0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }

    private func chunk(_ tag: String, _ payload: Data) -> Data {
        Data(tag.utf8.reversed()) + word(UInt32(payload.count)) + payload + Data(repeating: 0, count: payload.count % 2)
    }

    private func appending(_ extra: Data, to data: Data) -> Data {
        var result = data
        result.append(extra)
        result.replaceSubrange(8..<12, with: word(UInt32(result.count - 12)))
        return result
    }

    func testNativeSalesOracleAndAllSupportedStreams() throws {
        let oracleURL = try XCTUnwrap(Bundle.module.url(forResource: "sales-native", withExtension: "json",
                                                       subdirectory: "Fixtures/QuickReport"))
        let oracle = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: oracleURL)) as? [String: Any])
        let expected = try XCTUnwrap(oracle["columns"] as? [[String: Any]])
        for name in ["sales", "sales-be", "sales-stream25", "sales-stream26", "sales-stream27"] {
            let report = try analyze(name)
            XCTAssertFalse(report.crossTable, name)
            XCTAssertEqual(report.tableNumber, oracle["table"] as? Int)
            XCTAssertEqual(report.columns.count, expected.count)
            XCTAssertEqual(report.rowCount, 3)
            XCTAssertEqual(report.sorts, [1, -3])
            XCTAssertEqual(report.formatVersion, 0x10000)
            XCTAssertEqual(report.header.left, "Sales report")
            XCTAssertEqual(report.header.center, "Quarterly summary")
            XCTAssertEqual(report.header.right, "2026")
            XCTAssertEqual(report.header.height, 40)
            XCTAssertEqual(report.footer.left, "Confidential")
            XCTAssertEqual(report.footer.right, "Page #")
            XCTAssertEqual(report.footer.height, 30)
            XCTAssertEqual(report.printerSettingsBytes, 0)
            XCTAssertTrue(report.notes.isEmpty)
            for (index, column) in report.columns.enumerated() {
                let native = expected[index]
                XCTAssertEqual(column.title, native["title"] as? String)
                XCTAssertEqual(column.width, native["width"] as? Int)
                XCTAssertEqual(column.hidden, (native["hidden"] as? Int) == 1)
                XCTAssertEqual(column.repeatedValues, (native["repeated"] as? Int) == 1)
                XCTAssertEqual(column.displayFormat, native["format"] as? String)
                XCTAssertEqual(column.titleStyle.fontSize, native["titleSize"] as? Int)
                XCTAssertEqual(Int(column.titleStyle.face & 1), native["titleBold"] as? Int)
                XCTAssertEqual(column.titleStyle.background, "#DDEEFF")
                XCTAssertEqual(Int(column.cells[2].operators), native["totalOperators"] as? Int)
                XCTAssertEqual(column.cells[2].text, native["totalText"] as? String)
                XCTAssertEqual(column.tableNumber, 1)
            }
            XCTAssertEqual(report.columns.map(\.fieldNumber), [3, 1, 2])
            XCTAssertEqual(report.columns[2].detailStyle.justification, 9)
            XCTAssertEqual(Int(report.columns[2].titleBorders[5].thickness), expected[2]["bottomBorderThickness"] as? Int)
            XCTAssertEqual(report.columns[2].titleBorders[5].color, "#123456")
        }
        XCTAssertFalse(try analyze("sales-be").littleEndian)
        XCTAssertEqual(try analyze("sales-stream25").streamVersion, 25)
        XCTAssertEqual(try analyze("sales-stream26").streamVersion, 26)
        XCTAssertEqual(try analyze("sales-stream27").streamVersion, 27)
        XCTAssertEqual(try analyze("sales").streamVersion, 28)
    }

    func testSingleVariableProbes() throws {
        XCTAssertEqual(try analyze("title").columns[0].title, "TITLE MARKER")
        XCTAssertEqual(try analyze("unicode").columns[0].title, "日本語 café 😀")
        XCTAssertEqual(try analyze("width").columns[0].width, 173)
        XCTAssertTrue(try analyze("hidden").columns[0].hidden)
        XCTAssertFalse(try analyze("repeat").columns[0].repeatedValues)
        XCTAssertTrue(try analyze("column").columns[0].automaticWidth)
        XCTAssertEqual(try analyze("format").columns[0].displayFormat, "###,##0.00")
        XCTAssertEqual(try analyze("font").columns[0].titleStyle.fontName, "Courier New")
        XCTAssertEqual(try analyze("size").columns[0].titleStyle.fontSize, 23)
        XCTAssertEqual(try analyze("bold").columns[0].titleStyle.face, 1)
        XCTAssertEqual(try analyze("italic").columns[0].detailStyle.face, 2)
        XCTAssertEqual(try analyze("underline").columns[0].titleStyle.face, 4)
        XCTAssertEqual(try analyze("textcolor").columns[0].titleStyle.foreground, "#123456")
        XCTAssertEqual(try analyze("background").columns[0].titleStyle.background, "#654321")
        XCTAssertEqual(try analyze("alternate").columns[0].detailStyle.alternateBackground, "#123456")
        XCTAssertEqual(try analyze("left").columns[0].titleStyle.justification, 10)
        XCTAssertEqual(try analyze("center").columns[0].titleStyle.justification, 11)
        XCTAssertEqual(try analyze("justify").columns[0].titleStyle.justification, 9)
        XCTAssertTrue(try analyze("hidetitle").columns[0].titleHidden)
        XCTAssertTrue(try analyze("hidedetail").columns[0].detailHidden)
        XCTAssertTrue(try analyze("hidetotal").columns[0].cells[0].hidden)
        XCTAssertEqual(try analyze("sum").columns[0].cells[0].operators, 1)
        XCTAssertEqual(try analyze("totaltext").columns[0].cells[0].text, "TOTAL ##S")
        XCTAssertEqual(try analyze("header").header.center, "CENTER")
        XCTAssertEqual(try analyze("footer").footer.height, 41)
        XCTAssertEqual(try analyze("border").columns[0].titleBorders[0].color, "#123456")
        for (name, index) in [("bordertop", 3), ("borderright", 2), ("borderhorizontal", 4), ("bordervertical", 1)] {
            XCTAssertEqual(try analyze(name).columns[0].titleBorders[index].color, "#123456", name)
        }
        XCTAssertGreaterThan(try analyze("formula").columns[0].formulaBytes, 0)
        XCTAssertFalse(try analyze("formula").notes.isEmpty)
        XCTAssertTrue(try analyze("picture").header.hasPicture)
        XCTAssertTrue(try analyze("picture").notes.contains(where: { $0.contains("pictures are not rendered") }))
    }

    func testListAndCrossTableHTML() throws {
        let html = PreviewPipeline().html(for: try fixture("sales"))
        for text in ["4D Quick Report", "Report template", "Sales report", "Quarterly summary",
                     "Confidential", "Region", "Customer", "Table 1 / Field 3", "Amount", "Subtotal #",
                     "Grand total", "Sum", "Count", "#DDEEFF", "#123456", "font-weight:bold",
                     "descending", "###,##0.00", "not executed"] {
            XCTAssertTrue(html.contains(text), text)
        }
        XCTAssertEqual(html.components(separatedBy: "class=\"qr-row-label\"").count - 1, 3)
        for name in ["crosstab", "crosstab-stream25", "crosstab-stream26", "crosstab-stream27"] {
            let info = try analyze(name)
            XCTAssertTrue(info.crossTable)
            XCTAssertEqual(info.columns.count, 3)
            XCTAssertEqual(info.columns[1].cells[1].operators, 1)
            let html = PreviewPipeline().html(for: try fixture(name))
            for text in ["Cross-table", "Row total", "Column total", "Table 1 / Field 2", "Sum"] {
                XCTAssertTrue(html.contains(text), "\(name): \(text)")
            }
            let grid = try XCTUnwrap(html.components(separatedBy: "<table class=\"qr-grid\"><tbody>").last?
                .components(separatedBy: "</tbody></table>").first)
            XCTAssertEqual(grid.components(separatedBy: "<tr>").count - 1, 3)
            XCTAssertEqual(grid.components(separatedBy: "<td style=").count - 1, 9)
        }
    }

    func testEmptyHiddenAndFormulaTemplates() throws {
        XCTAssertTrue(try analyze("empty").columns.isEmpty)
        XCTAssertTrue(PreviewPipeline().html(for: try fixture("empty")).contains("No columns are saved"))
        XCTAssertTrue(PreviewPipeline().html(for: try fixture("hidden")).contains("All columns are hidden"))
        XCTAssertTrue(PreviewPipeline().html(for: try fixture("formula")).contains("Formula (tokenized)"))
        XCTAssertFalse(PreviewPipeline().html(for: try fixture("hidetotal")).contains("class=\"qr-row-label\""))
        let alternate = PreviewPipeline().html(for: try fixture("alternate"))
        XCTAssertEqual(alternate.components(separatedBy: "class=\"qr-detail\"").count - 1, 2)
        XCTAssertTrue(alternate.contains("background:#123456"))
    }

    func testUTIRoutingAndUppercaseExtension() throws {
        let bytes = try Data(contentsOf: fixture("sales"))
        let upper = try temporary(bytes, ext: "4QR")
        XCTAssertTrue(try AnalyzerRegistry.default.analyze(url: upper) is QuickReportFileInfo)
        let noExtension = try temporary(bytes, ext: "bin")
        XCTAssertTrue(try AnalyzerRegistry.default.analyze(url: noExtension, contentType: "com.4d.4d.quickReport") is QuickReportFileInfo)
        XCTAssertTrue(AnalyzerRegistry.default.allContentTypes.contains("com.4d.4d.quickReport"))
        let hostURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Support/Host-Info.plist")
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: hostURL),
                                                                        format: nil) as? [String: Any])
        let types = try XCTUnwrap(plist["UTImportedTypeDeclarations"] as? [[String: Any]])
        let declaration = try XCTUnwrap(types.first { $0["UTTypeIdentifier"] as? String == "com.4d.4d.quickReport" })
        let tags = try XCTUnwrap(declaration["UTTypeTagSpecification"] as? [String: Any])
        XCTAssertEqual(tags["public.filename-extension"] as? [String], ["4qr", "4QR"])
    }

    func testOpaquePrinterDataAndUnknownChunksAreNeverRendered() throws {
        let bytes = try Data(contentsOf: fixture("sales"))
        let extra = chunk("PRPF", Data("<script>printer-secret</script>".utf8)) +
            chunk("NEW!", Data([1, 2, 3]))
        let url = try temporary(appending(extra, to: bytes))
        let info = try XCTUnwrap(try AnalyzerRegistry.default.analyze(url: url) as? QuickReportFileInfo)
        XCTAssertEqual(info.printerSettingsBytes, 31)
        XCTAssertTrue(info.notes.contains(where: { $0.contains("NEW!") }))
        let html = PreviewPipeline().html(for: url)
        XCTAssertFalse(html.contains("printer-secret"))
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertFalse(String(decoding: try info.jsonData(), as: UTF8.self).contains("printer-secret"))
    }

    func testTextAndFontAreEscaped() throws {
        let base = try analyze("sales")
        let style = QuickReportTextStyle(fontName: "';}body{color:red}/*", fontSize: 12, face: 0,
                                        justification: 0, foreground: "#000000", background: "#FFFFFF",
                                        alternateBackground: nil)
        let band = QuickReportPageBand(height: 40, left: "<script>alert(1)</script>", center: "&\"",
                                      right: "", style: style, hasPicture: false)
        let info = QuickReportFileInfo(fileName: base.fileName, littleEndian: true, formatVersion: base.formatVersion,
                                      streamVersion: base.streamVersion, crossTable: false, tableNumber: 1,
                                      rowCount: base.rowCount, sorts: base.sorts, header: band, footer: base.footer,
                                      columns: base.columns, printerSettingsBytes: 0, notes: [])
        let html = HTMLRenderer().render(try XCTUnwrap(QuickReportPresenter().report(for: info)))
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        XCTAssertFalse(html.contains(";}body{color:red}"))
        XCTAssertTrue(html.contains("\\27 "))
    }

    func testTruncationAndCorruptLengthsNeverProducePartialPreviews() throws {
        let bytes = try Data(contentsOf: fixture("sales"))
        let url = try temporary(Data())
        for length in stride(from: 0, to: bytes.count, by: 17) {
            try bytes.prefix(length).write(to: url)
            XCTAssertThrowsError(try AnalyzerRegistry.default.analyze(url: url), "length \(length)")
        }
        for offset in [8, 20, 32, 44, 80, 90] {
            var corrupt = bytes
            corrupt.replaceSubrange(offset..<offset + 4, with: word(UInt32.max))
            try corrupt.write(to: url)
            XCTAssertThrowsError(try AnalyzerRegistry.default.analyze(url: url), "offset \(offset)")
        }
        try Data([0, 1, 2, 3]).write(to: url)
        XCTAssertTrue(PreviewPipeline().html(for: url).contains("No preview available"))
    }

    func testUnknownVersionsDuplicateChunksAndDepthLimitFailExplicitly() throws {
        let bytes = try Data(contentsOf: fixture("sales"))
        for offset in [24, 36] {
            var data = bytes
            data.replaceSubrange(offset..<offset + 4, with: word(99))
            let url = try temporary(data)
            XCTAssertThrowsError(try AnalyzerRegistry.default.analyze(url: url))
            XCTAssertTrue(PreviewPipeline().html(for: url).contains("unsupported"))
        }

        let duplicate = try temporary(appending(chunk("Vers", word(0x10000)), to: bytes))
        XCTAssertThrowsError(try AnalyzerRegistry.default.analyze(url: duplicate))
        var nested = chunk("DATA", Data())
        for _ in 0..<10 { nested = chunk("FORM", Data("TSET".utf8) + nested) }
        let deep = try temporary(appending(nested, to: bytes))
        XCTAssertThrowsError(try AnalyzerRegistry.default.analyze(url: deep)) { error in
            XCTAssertTrue(String(describing: error).contains("complexity"))
        }
    }

    func testInvalidUTF16AndSortReferencesFailExplicitly() throws {
        let bytes = try Data(contentsOf: fixture("sales"))
        var invalidText = bytes
        let strings = try XCTUnwrap(bytes.range(of: Data("srtS".utf8)))
        let textStart = strings.lowerBound + 16
        invalidText.replaceSubrange(textStart..<textStart + 2, with: [0x00, 0xD8])
        let textURL = try temporary(invalidText)
        XCTAssertThrowsError(try AnalyzerRegistry.default.analyze(url: textURL))
        var invalidSort = bytes
        let sort = try XCTUnwrap(bytes.range(of: Data("troS".utf8)))
        invalidSort.replaceSubrange(sort.lowerBound + 8..<sort.lowerBound + 10, with: [0xFF, 0x7F])
        let sortURL = try temporary(invalidSort)
        XCTAssertThrowsError(try AnalyzerRegistry.default.analyze(url: sortURL))
    }

    func testFileSizeLimit() throws {
        let url = try temporary(Data())
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 32 * 1024 * 1024 + 1)
        try handle.close()
        XCTAssertThrowsError(try AnalyzerRegistry.default.analyze(url: url)) { error in
            XCTAssertTrue(String(describing: error).contains("32 MiB"))
        }
    }
}
