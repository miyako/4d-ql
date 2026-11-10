import XCTest
@testable import FourDFileKit
@testable import FourDRender

final class WriteProTests: XCTestCase {
    // MARK: Helpers

    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "4wp", subdirectory: "Fixtures/WritePro"))
    }

    private func analyze(_ url: URL) throws -> WriteProFileInfo {
        try XCTUnwrap(try AnalyzerRegistry.default.analyze(url: url) as? WriteProFileInfo)
    }

    private func renderer(_ name: String) throws -> WriteProDocumentRenderer {
        WriteProDocumentRenderer(try analyze(try fixture(name)))
    }

    private func write(_ data: Data, extension ext: String = "4wp") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// Builds a ZIP with stored entries.
    private func zip(_ files: [(String, Data)], corruptCRC: Bool = false) -> Data {
        var out = Data(), central = Data()
        func le16(_ v: Int) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)]) }
        func le32(_ v: UInt32) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 24 & 0xFF)]) }
        for (name, data) in files {
            let offset = out.count
            let crc = CRC32.checksum([UInt8](data)) ^ (corruptCRC ? 1 : 0)
            let nameData = Data(name.utf8)
            out += le32(0x04034B50) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0) + le32(crc)
            out += le32(UInt32(data.count)) + le32(UInt32(data.count)) + le16(nameData.count) + le16(0) + nameData + data
            central += le32(0x02014B50) + le16(20) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0) + le32(crc)
            central += le32(UInt32(data.count)) + le32(UInt32(data.count)) + le16(nameData.count) + le16(0) + le16(0)
            central += le16(0) + le16(0) + le32(0) + le32(UInt32(offset)) + nameData
        }
        let centralOffset = out.count
        out += central
        out += le32(0x06054B50) + le16(0) + le16(0) + le16(files.count) + le16(files.count)
        out += le32(UInt32(central.count)) + le32(UInt32(centralOffset)) + le16(0)
        return out
    }

    private func xhtml(_ body: String, style: String = "") -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:d4="http://www.4D.com"><head><title>T</title>\
        <style type="text/css">body { -d4-version:2.20 }p,li { white-space:pre-wrap;border-width:2pt;margin:0pt }\(style)</style></head><body>\(body)</body></html>
        """
    }

    private func html(_ body: String, style: String = "") throws -> String {
        let info = try WriteProFileAnalyzer.parse(Data(xhtml(body, style: style).utf8), fileName: "t.4wp")
        return WriteProDocumentRenderer(info).render()
    }

    // MARK: Archive

    func testInflaterDecodesFixedDynamicAndStoredBlocks() throws {
        let fixed = try XCTUnwrap(Data(base64Encoded: "y0jNyclXyEAiTVwUAQ=="))
        XCTAssertEqual(String(decoding: try Inflater.inflate([UInt8](fixed), limit: 1_000), as: UTF8.self), "hello hello hello 4D!")

        let words = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu".split(separator: " ")
        let expected = (0..<300).map { words[($0 * 7 + $0 / 3) % words.count] }.joined(separator: " ")
        let dynamic = try XCTUnwrap(Data(base64Encoded: "7c3BDYAwCIXhVVjtNSW2ESyJeHF6pQc7gFcuhPAnfBBrIG/soA2qIIGWCrrjgln7eNfK4l+MVmLMxHZ2GQfpRevNDrOVkEwyySSTTDI/mQc="))
        let inflated = try Inflater.inflate([UInt8](dynamic), limit: 10_000)
        XCTAssertEqual(String(decoding: inflated, as: UTF8.self), expected)
        XCTAssertEqual(CRC32.checksum(inflated), 561_624_354)

        let payload = [UInt8]("stored".utf8)
        let stored: [UInt8] = [0x01, 6, 0, 0xF9, 0xFF] + payload
        XCTAssertEqual(try Inflater.inflate(stored, limit: 100), payload)
        XCTAssertThrowsError(try Inflater.inflate([UInt8](dynamic), limit: 100), "output limit is enforced")
        XCTAssertThrowsError(try Inflater.inflate([0x07], limit: 100), "reserved block type is rejected")
    }

    func testArchiveResourcesAndCorruption() throws {
        let png = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYPgPAAEDAQAIicLsAAAAAElFTkSuQmCC"))
        let page = xhtml("<p>Picture <img src=\"Doc/image1.png\" alt=\"x\"/></p>")
        let info = try analyze(try write(zip([("Doc.html", Data(page.utf8)), ("Doc/image1.png", png)])))
        XCTAssertEqual(info.htmlEntry, "Doc.html")
        XCTAssertEqual(info.archiveEntries, ["Doc.html", "Doc/image1.png"])
        let rendered = WriteProDocumentRenderer(info).render()
        XCTAssertTrue(rendered.contains("src=\"data:image/png;base64,iVBOR"))

        XCTAssertThrowsError(try AnalyzerRegistry.default.analyze(url: try write(zip([("Doc.html", Data(page.utf8))], corruptCRC: true))))
        XCTAssertThrowsError(try AnalyzerRegistry.default.analyze(url: try write(zip([("readme.txt", Data("x".utf8))]))))
        XCTAssertThrowsError(try AnalyzerRegistry.default.analyze(url: try write(zip([("Doc.html", Data(page.utf8))]).prefix(40))))
    }

    func testBareXHTMLAndEntityDeclarationsAreHandled() throws {
        let info = try analyze(try write(Data(("\u{FEFF}" + xhtml("<p>Bare&nbsp;page</p>")).utf8)))
        XCTAssertEqual(info.body.textContent, "Bare\u{00A0}page")
        XCTAssertNil(info.htmlEntry)
        let bomb = "<?xml version=\"1.0\"?><!DOCTYPE html [<!ENTITY a \"aaaaaaaa\">]><html><body><p>&a;</p></body></html>"
        XCTAssertThrowsError(try WriteProFileAnalyzer.parse(Data(bomb.utf8), fileName: "x.4wp"))
    }

    // MARK: Fixtures from 4D 21

    func testFixturesUse4DWriteProXHTML() throws {
        for name in ["text", "layout", "objects", "table", "media", "more"] {
            let info = try analyze(try fixture(name))
            XCTAssertEqual(info.version, "2.20", name)
            XCTAssertEqual(info.archiveEntries.count, 1, name)
            XCTAssertTrue(info.htmlEntry?.hasSuffix(".html") ?? false, name)
            let page = PreviewPipeline().html(for: try fixture(name))
            XCTAssertFalse(page.lowercased().contains("<script"), name)
            XCTAssertFalse(page.contains("src=\"http"), name)
            XCTAssertTrue(page.contains("class=\"wp-sheet\""), name)
            XCTAssertTrue(page.contains("Content-Security-Policy"), name)
        }
    }

    func testCharacterAndParagraphFormatting() throws {
        let r = try renderer("text")
        let html = r.render()
        XCTAssertTrue(html.contains("text-decoration-line:underline;text-decoration-style:dotted;text-decoration-color:#FF0000\"> underline"))
        XCTAssertTrue(html.contains("text-decoration-line:line-through;text-decoration-style:double;text-decoration-color:#0000FF\"> strike"))
        XCTAssertTrue(html.contains("font-variant:small-caps"))
        XCTAssertTrue(html.contains("vertical-align:super"))
        XCTAssertTrue(html.contains("text-shadow:2pt 2pt #808080"))
        XCTAssertTrue(html.contains("background-color:#EEF4FA"))
        XCTAssertTrue(html.contains("font-family:'Helvetica'"))
        XCTAssertTrue(html.contains("direction:rtl"))
        XCTAssertFalse(html.contains("bidi-override"))
        // List markers follow the item's own type and count positions within the list.
        for marker in [">●<", ">○<", ">■<", ">1.<", ">ii.<", ">C.<", ">□<", ">◆<", ">(7)<", ">(8)<"] {
            XCTAssertTrue(html.contains(marker), marker)
        }
        // Explicit tab stops: right at 5 cm with a dot leader, centered at 9 cm.
        XCTAssertTrue(html.contains("left:141.73pt;transform:translateX(-100%)\">Price"))
        XCTAssertTrue(html.contains("left:255.12pt;transform:translateX(-50%)\">Qty"))
        XCTAssertTrue(html.contains("class=\"wp-leader\" style=\"width:141.73pt\""))
        // Links are inert.
        XCTAssertTrue(html.contains("title=\"Link: https://www.4d.com\""))
        XCTAssertFalse(html.contains("href="))
        XCTAssertEqual(r.statistics.listItems, 10)
        XCTAssertEqual(r.pageCount, 1)
    }

    func testSectionsPagesColumnsHeadersAndFooters() throws {
        let r = try renderer("layout")
        let html = r.render()
        XCTAssertEqual(r.pageCount, 3)
        XCTAssertEqual(r.sectionCount, 3)
        XCTAssertEqual(r.sectionNames, [1: "Introduction", 2: "Columns", 3: "Appendix"])
        XCTAssertEqual(r.geometry.landscape, true)
        XCTAssertEqual(r.geometry.width, 842)
        XCTAssertTrue(html.contains("width:842pt;min-height:595pt;background-color:#FFFDF5"))
        XCTAssertTrue(html.contains("padding:0 42.52pt 0 42.52pt"), "1.5 cm side margins")
        XCTAssertTrue(html.contains("column-count:2;column-fill:auto;column-gap:28.35pt;column-rule-style:solid"))
        XCTAssertTrue(html.contains("break-after:column"))
        XCTAssertTrue(html.contains("Header of section 1 — <span class=\"wp-computed\""))
        XCTAssertTrue(html.contains(">Introduction</span>"))
        for page in 1...3 { XCTAssertTrue(html.contains("Page <span class=\"wp-computed\" title=\"Formula: This.pageNumber\">\(page)</span> of"), "page \(page)") }
        XCTAssertTrue(html.contains("of <span class=\"wp-computed\" title=\"Formula: This.pageCount\">3</span>"))
        // The continuous section starts on page 3, whose header still belongs to section 2.
        XCTAssertTrue(html.contains("Columns header"))
        XCTAssertFalse(html.contains("First page header of section 3"))
        XCTAssertEqual(r.formulas.first?.location, "Section 1 header")
    }

    func testLeftRightSubsectionsAndPageSize() throws {
        let r = try renderer("more")
        let html = r.render()
        XCTAssertEqual(r.pageCount, 3)
        XCTAssertEqual(r.geometry.width, 612)
        let pages: [String] = Array(html.components(separatedBy: "<figure class=\"wp-page\">").dropFirst())
        XCTAssertEqual(pages.count, 3)
        XCTAssertTrue(pages[0].contains("Left header"), "page 1 is a left page when the first page is not right")
        XCTAssertFalse(pages[0].contains("Right footer"))
        XCTAssertTrue(pages[1].contains("Right header") && pages[1].contains("Right footer"))
        XCTAssertTrue(pages[2].contains("Left header"))
        XCTAssertTrue(pages[0].contains("padding:0 28.35pt 0 85.04pt"), "3 cm left and 1 cm right margins")
        XCTAssertTrue(html.contains(">1.<") && html.contains(">b.<") && html.contains(">5.<") && html.contains(">f.<"))
        XCTAssertTrue(html.contains("rowspan=\"2\""))
        XCTAssertTrue(html.contains("&lt;tag&gt; &amp; &quot;quotes&quot;"))
        XCTAssertEqual(r.document.customAttributes, "{\"custom\":\"user value\",\"importLog\":\"none\"}")
    }

    func testFormulasAnchoredObjectsAndPictures() throws {
        let r = try renderer("objects")
        let html = r.render()
        let sources = r.formulas.map(\.source)
        XCTAssertEqual(sources, ["Current date", "String(Current time; HH MM SS)", "[Invoices]Customer", "This.data.customer.name",
                                 "Uppercase(\"total\")", "wp_value", "This.data.logo"])
        XCTAssertEqual(r.formulas[4].name, "Grand total")
        XCTAssertEqual(r.formulas.last?.location, "Body (image)")
        XCTAssertTrue(html.contains("title=\"Formula “Grand total”: Uppercase(&quot;total&quot;)\">Grand total</span>"))
        XCTAssertTrue(html.contains("class=\"wp-textbox\""))
        XCTAssertTrue(html.contains("left:300pt;top:300pt"))
        XCTAssertTrue(html.contains("left:400pt;top:100pt"))
        XCTAssertTrue(html.contains("z-index:-1"), "behind-text picture")
        XCTAssertTrue(html.contains("right:0pt;bottom:0pt"))
        XCTAssertTrue(html.contains("background-repeat:repeat"))
        XCTAssertTrue(html.contains("Picture formula: This.data.logo"))
        XCTAssertTrue(html.contains("min-height:60pt;background-image:url('data:image/png;base64,"))
        XCTAssertEqual(r.statistics.textBoxes, 1)
        XCTAssertEqual(r.statistics.anchoredImages, 3)
        XCTAssertTrue(r.notices.contains { $0.contains("wrapping") })
    }

    func testTablesAndDataSources() throws {
        let r = try renderer("table")
        let html = r.render()
        XCTAssertEqual(r.statistics.tables, 2)
        XCTAssertTrue(html.contains("margin-left:auto;margin-right:auto"))
        XCTAssertTrue(html.contains("colspan=\"2\""))
        XCTAssertTrue(html.contains("<tr class=\"wp-header-row\" style=\"border-width:1pt;background-color:#1F4E79\">"))
        XCTAssertTrue(html.contains("width:200pt;border-style:solid"))
        XCTAssertTrue(html.contains("vertical-align:middle"))
        XCTAssertTrue(html.contains("title=\"Table data source: This.data.lines\""))
        XCTAssertTrue(r.formulas.contains(WriteProFormula(source: "This.data.lines", name: nil, location: "Table data source")))
        XCTAssertTrue(r.formulas.contains(WriteProFormula(source: "This.item.name", name: nil, location: "Table")))
    }

    func testNativePicturesAndRemoteImages() throws {
        let r = try renderer("media")
        let html = r.render()
        XCTAssertFalse(html.contains("src=\"data:application"))
        XCTAssertEqual(html.components(separatedBy: "src=\"data:image/png").count - 1, 1, "4D picture container unwrapped to PNG")
        XCTAssertEqual(html.components(separatedBy: "src=\"data:image/jpeg").count - 1, 2)
        XCTAssertTrue(html.contains("title=\"Remote picture: https://example.com/logo.png\">Remote picture</span>"))
        XCTAssertTrue(html.contains("object-fit:contain;object-position:center"))
    }

    // MARK: Authored documents

    func testFormulaDetokenizerKeepsStringLiterals() {
        XCTAssertEqual(WriteProDocumentRenderer.formulaSource("String:C10([Table_1:3]Field:4; \"a:C12\")+[Invoices:1]Total:3"),
                       "String([Table_1]Field; \"a:C12\")+[Invoices]Total")
        XCTAssertEqual(WriteProDocumentRenderer.formulaSource("Is nil pointer:C315(->$p)"), "Is nil pointer(->$p)")
    }

    func testBreaksAndTrailingPageBreak() throws {
        let page = try html("""
        <p style="page-break-after:always">One</p><p style="-d4-section-break-after:continuous">Two</p>\
        <p style="-d4-section-break-after:always;page-break-after:always">Three</p><p style="page-break-after:always">Four</p>
        """, style: "div.section2 { -d4-section-name:'S2' }")
        XCTAssertEqual(page.components(separatedBy: "<figure").count - 1, 3)
        XCTAssertTrue(page.contains("<figcaption>Page 2</figcaption>"), "a page is named after the section it starts in")
        XCTAssertFalse(page.contains("Page 4"))
    }

    func testHostileMarkupAndCSSAreNeutralized() throws {
        let page = try html("""
        <script>alert(1)</script><p onclick="alert(1)" style="color:red;background-image:url(https://evil.example/x.png);font-family:'a&lt;/style&gt;&lt;script&gt;',Helvetica;\
        width:expression(alert(1));border:1px solid url(x);margin:1pt 2pt 3pt 4pt 5pt javascript:x">\
        <a href="javascript:alert(1)">link</a><img src="file:///etc/passwd" alt="local"/><img src="data:text/html;base64,PHNjcmlwdD4=" alt="html"/>\
        <iframe src="https://evil.example/"></iframe><span style="-d4-ref:'&lt;/span&gt;&lt;script&gt;'"> </span></p>
        """, style: "p.x { color:red } } <script>alert(2)</script> p { background:url(https://evil.example/y.png) }")
        let lower = page.lowercased()
        XCTAssertFalse(lower.contains("<script"))
        XCTAssertFalse(lower.contains("<iframe"))
        XCTAssertFalse(lower.contains("onclick"))
        XCTAssertFalse(lower.contains("href="))
        XCTAssertFalse(lower.contains("url(https"))
        XCTAssertFalse(lower.contains("url(x"))
        XCTAssertFalse(lower.contains("expression("))
        XCTAssertFalse(lower.contains("file:///"))
        XCTAssertFalse(lower.contains("data:text/html"))
        XCTAssertTrue(page.contains("font-family:'Helvetica'"))
        XCTAssertTrue(page.contains("color:red"))
        XCTAssertTrue(page.contains("&lt;/span&gt;&lt;script&gt;"), "formula source shown as text")
    }

    func testPresenterReport() throws {
        let model = try analyze(try fixture("objects"))
        let report = try XCTUnwrap(WriteProPresenter().report(for: model))
        XCTAssertEqual(report.title, "objects.4wp")
        XCTAssertEqual(report.stats.first?.value, "A4")
        XCTAssertTrue(report.sections.contains { $0.title == "Formulas" })
        let page = HTMLRenderer().render(report)
        XCTAssertTrue(page.contains("form-zoom-controls"))
        XCTAssertTrue(page.contains("Original XHTML"))
        XCTAssertTrue(page.contains("base64,…"), "source view elides embedded pictures")
    }
}
