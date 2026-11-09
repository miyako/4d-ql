import XCTest
@testable import FourDFileKit
@testable import FourDRender

final class LabelTests: XCTestCase {
    private func file(_ xml: String, extension ext: String = "4lbp") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
        try Data(xml.utf8).write(to: url)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    private func analyze(_ xml: String) throws -> LabelFileInfo {
        let model = try AnalyzerRegistry.default.analyze(url: file(xml))
        return try XCTUnwrap(model as? LabelFileInfo)
    }

    private func label(_ objects: String = "", extra: String = "", attributes: String = "") -> String {
        """
        <label version="2" columns="2" rows="3" start="2" labels-per-record="2" \(attributes)>
        <size id="size" width="200" height="100" unit="mm"/>
        <setting id="setting" vertical="true" landscape="true" auto-width="false"/>
        <margin id="margin" left="10" top="20" right="30" bottom="40"/>
        <gap id="gap" horizontal="5" vertical="7"/>
        <objects id="objects">\(objects)</objects>\(extra)</label>
        """
    }

    private let text = """
    <object id="caption" type="text" left="321" top="110.5" right="481" bottom="140.5"
      value="Hello &amp; &lt;script&gt;" font-name="Helvetica" font-size="14" font-color="#123456"
      style="bold italic underline" alignment="center"/>
    """

    func testNativeMatrixGeometryAndPointUnits() throws {
        let info = try analyze(label(text))
        XCTAssertEqual(info.layout.width, 200)
        XCTAssertEqual(info.layout.height, 100)
        XCTAssertEqual(info.layout.unit, "mm")
        XCTAssertEqual(info.layout.sheetWidth, 445)
        XCTAssertEqual(info.layout.sheetHeight, 374)
        XCTAssertEqual(info.layout.copies, 2)
        XCTAssertTrue(info.layout.vertical)
        XCTAssertTrue(info.layout.landscape)
        let object = try XCTUnwrap(info.objects.first)
        XCTAssertEqual(object.x, 10)
        XCTAssertEqual(object.y, 10)
        XCTAssertEqual(object.width, 160)
        XCTAssertEqual(object.height, 30)
        XCTAssertEqual(object.attributes["value"], "Hello & <script>")
    }

    func testRegistryUTIUppercaseBOMAndJSONOutput() throws {
        let url = try file("\u{FEFF}" + label(text), extension: "4LBP")
        let model = try AnalyzerRegistry.default.analyze(url: url)
        XCTAssertTrue(model is LabelFileInfo)
        XCTAssertTrue(try AnalyzerRegistry.default.analyze(url: file(label(), extension: "tmp"),
                                                         contentType: "com.4d.4d.labelFile") is LabelFileInfo)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: model.jsonData()) as? [String: Any])
        XCTAssertEqual(json["kind"] as? String, "4d.label")
        XCTAssertEqual((json["objects"] as? [[String: Any]])?.first?["x"] as? Double, 10)
        XCTAssertTrue(AnalyzerRegistry.default.allContentTypes.contains("com.4d.4d.labelFile"))
    }

    func testHTMLArtSheetOrderSkippingAndEscaping() throws {
        let url = try file(label(text))
        let html = PreviewPipeline().html(for: url)
        XCTAssertTrue(html.contains("4D Label"))
        XCTAssertTrue(html.contains("Hello &amp; &lt;script&gt;"))
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("translate(10 10)"))
        XCTAssertTrue(html.contains("font-weight=\"bold\""))
        XCTAssertTrue(html.contains("font-style=\"italic\""))
        XCTAssertTrue(html.contains("text-decoration=\"underline\""))
        XCTAssertTrue(html.contains("text-anchor=\"middle\""))
        XCTAssertTrue(html.contains("Position 1 (skipped)"))
        let positions = try NSRegularExpression(pattern: "data-position=\"([0-9]+)\"").matches(in: html, range: NSRange(html.startIndex..., in: html))
        XCTAssertEqual(positions.compactMap { Range($0.range(at: 1), in: html).map { String(html[$0]) } }, ["1", "4", "2", "5", "3", "6"])
        XCTAssertTrue(html.contains("default-src 'none'"))
        XCTAssertTrue(html.contains("Original XML"))
        XCTAssertTrue(html.contains("form-zoom"))
    }

    func testShapesPolylineAndVersionOneRounding() throws {
        let objects = ["rect", "round-rect", "oval", "line", "polyline"].map {
            "<object type=\"\($0)\" left=\"311\" top=\"100.5\" right=\"351\" bottom=\"120.5\" stroke-color=\"#112233\" stroke-width=\"2\" stroke-opacity=\"0.5\" fill-color=\"#ff0000\" fill-opacity=\"0.2\" direction=\"up\" data=\"-20,-10 0,10 20,-10\"/>"
        }.joined()
        let info = try analyze(label(objects).replacingOccurrences(of: "version=\"2\"", with: "version=\"1\""))
        XCTAssertEqual(info.objects.map(\.type), ["rect", "round-rect", "oval", "line", "polyline"])
        XCTAssertEqual(info.objects[1].attributes["rx"], "6")
        let html = HTMLRenderer().render(try XCTUnwrap(LabelPresenter().report(for: info)))
        XCTAssertTrue(html.contains("<ellipse"))
        XCTAssertTrue(html.contains("<line x1=\"0\" y1=\"20\" x2=\"40\" y2=\"0\""))
        XCTAssertTrue(html.contains("points=\"0,0 20,20 40,0\""))
        XCTAssertTrue(html.contains("stroke-opacity=\"0.50\""))
        XCTAssertTrue(html.contains("fill-opacity=\"0.20\""))
    }

    func testPassiveRasterImageAndBadImageNotices() throws {
        let png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII="
        let info = try analyze(label("""
        <object type="image" left="311" top="100.5" right="321" bottom="110.5" image-codec=".png" image-data="\(png)" preserve-aspect-ratio="false"/>
        <object type="image" image-data="not base64!"/>
        """))
        XCTAssertTrue(try XCTUnwrap(info.objects.first?.image).dataURI.hasPrefix("data:image/png;base64,"))
        XCTAssertTrue(info.warnings.contains { $0.contains("invalid base64") })
        let html = HTMLRenderer().render(try XCTUnwrap(LabelPresenter().report(for: info)))
        XCTAssertTrue(html.contains("preserveAspectRatio=\"none\""))
        XCTAssertTrue(html.contains("Image unavailable"))
    }

    func testFormulasMethodsAndUnsupportedObjectsAreExplicit() throws {
        let info = try analyze(label("""
        <object type="variable" value="[People]Name + RunMe" field-type="2"/>
        <object type="future-widget"/>
        """, extra: "<form name=\"Missing\" number=\"1\"/><method name=\"DoNotRun\" evaluate-per-label=\"true\"/>"))
        XCTAssertTrue(info.warnings.contains { $0.contains("not evaluated") })
        XCTAssertTrue(info.warnings.contains { $0.contains("DoNotRun") && $0.contains("not executed") })
        XCTAssertTrue(info.warnings.contains { $0.contains("future-widget") })
        XCTAssertTrue(info.warnings.contains { $0.contains("Referenced form Missing could not be loaded") })
        XCTAssertNil(info.form)
    }

    func testInvalidAndHostileXMLIsRejected() throws {
        for xml in ["{}", "<other/>", "<label>", "<label/><label/>",
                    "<!DOCTYPE label [<!ENTITY x \"expanded\">]><label>&x;</label>",
                    "<!DOCTYPE label [<!ENTITY x SYSTEM \"file:///etc/passwd\">]><label>&x;</label>",
                    "<label>" + String(repeating: "<x>", count: 40) + String(repeating: "</x>", count: 40) + "</label>",
                    "<label>" + String(repeating: "<x/>", count: 20_001) + "</label>"] {
            XCTAssertThrowsError(try analyze(xml), xml.prefix(100).description)
        }
    }

    func testInvalidNumbersAndPreviewBudgetsAreRejected() throws {
        for change in [
            ("columns=\"2\"", "columns=\"0\""), ("rows=\"3\"", "rows=\"3.5\""),
            ("columns=\"2\"", "columns=\"400\""), ("width=\"200\"", "width=\"NaN\""),
            ("width=\"200\"", "width=\"8192\""), ("horizontal=\"5\"", "horizontal=\"-1\""),
            ("vertical=\"true\"", "vertical=\"yes\""), ("version=\"2\"", "version=\"3\"")
        ] {
            XCTAssertThrowsError(try analyze(label().replacingOccurrences(of: change.0, with: change.1)))
        }
        XCTAssertThrowsError(try analyze(label("<object left=\"1\" right=\"-1\"/>")))
        XCTAssertThrowsError(try analyze(label("<object stroke-opacity=\"2\"/>")))
        XCTAssertThrowsError(try analyze(label(String(repeating: "<object/>", count: 1_001))))
        XCTAssertThrowsError(try analyze("<label>" + String(repeating: " ", count: 4 * 1024 * 1024) + "</label>"))
        XCTAssertThrowsError(try analyze("<label><size/><size/></label>"))
    }

    func testReferencedTableFormUsesSharedRendererAndRejectsAmbiguity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let resources = root.appendingPathComponent("Resources")
        let table = root.appendingPathComponent("Project/Sources/TableForms/1/Address")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: table, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let form = """
        {"width":200,"height":100,"pages":[{"objects":{}},{"objects":{"Caption":{"type":"text","left":10,"top":10,"width":100,"height":20,"text":"Form caption"}}}]}
        """
        try Data(form.utf8).write(to: table.appendingPathComponent("form.4DForm"))
        let url = resources.appendingPathComponent("address.4lbp")
        try Data(label(text, extra: "<form name=\"Address\" number=\"1\"/>").utf8).write(to: url)
        let info = try XCTUnwrap(try AnalyzerRegistry.default.analyze(url: url) as? LabelFileInfo)
        XCTAssertEqual(info.form?.formName, "Address")
        XCTAssertEqual(info.form?.appearances.first?.pages.last?.objects.first?.properties["text"]?.string, "Form caption")
        XCTAssertTrue(PreviewPipeline().html(for: url).contains("Form caption"))
        let second = root.appendingPathComponent("Project/Sources/TableForms/2/Address")
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try Data(form.utf8).write(to: second.appendingPathComponent("form.4DForm"))
        let ambiguous = try XCTUnwrap(try AnalyzerRegistry.default.analyze(url: url) as? LabelFileInfo)
        XCTAssertNil(ambiguous.form)
        XCTAssertTrue(ambiguous.warnings.contains { $0.contains("ambiguous") })
    }

    func testFormNameTraversalIsRejected() throws {
        let info = try analyze(label(extra: "<form name=\"../../outside\"/>"))
        XCTAssertNil(info.form)
        XCTAssertTrue(info.warnings.contains { $0.contains("Invalid saved form name") })
    }

    func testUTF16AndEntityRejectionBeforeParsing() throws {
        let url = try file("")
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-16\"?>" + label(text)
        try XCTUnwrap(xml.data(using: .utf16)).write(to: url)
        let model = try AnalyzerRegistry.default.analyze(url: url)
        let info = try XCTUnwrap(model as? LabelFileInfo)
        XCTAssertTrue(info.text.contains("Hello &amp;"))
        let hostile = "<?xml version=\"1.0\" encoding=\"UTF-16\"?><!DOCTYPE label [<!ENTITY x \"expanded\">]><label>&x;</label>"
        try XCTUnwrap(hostile.data(using: .utf16)).write(to: url)
        XCTAssertThrowsError(try AnalyzerRegistry.default.analyze(url: url))
    }

    func testUnsupportedStylingAndTextLimitsHaveNotices() throws {
        let info = try analyze(label("""
        <object type="text" value="\(String(repeating: "a", count: 4_100))" font-size="999" font-color="url(https://example.invalid/x)"/>
        """))
        XCTAssertTrue(info.warnings.contains { $0.contains("unsupported font-color") })
        XCTAssertTrue(info.warnings.contains { $0.contains("4,096 UTF-16") })
        XCTAssertTrue(info.warnings.contains { $0.contains("256 points") })
        XCTAssertThrowsError(try analyze(label("<object type=\"polyline\" data=\"1,2 invalid\"/>")))
    }

    func testExactSheetBudgetsAndUnknownSettings() throws {
        let fourHundred = try analyze("""
        <label version="2" columns="20" rows="20" custom="retained">
          <size width="10" height="10"/><future option="preserved"/>
        </label>
        """)
        XCTAssertEqual(fourHundred.layout.columns * fourHundred.layout.rows, 400)
        XCTAssertEqual(fourHundred.root.attributes["custom"], "retained")
        XCTAssertEqual(fourHundred.root.children.last?.attributes["option"], "preserved")
        XCTAssertTrue(fourHundred.warnings.contains { $0.contains("Additional saved settings") })
        let limit = """
        <label columns="1" rows="1"><size width="8192" height="1"/>
          <margin left="0" right="0" top="0" bottom="0"/></label>
        """
        XCTAssertEqual(try analyze(limit).layout.sheetWidth, 8_192)
        XCTAssertThrowsError(try analyze(limit.replacingOccurrences(of: "8192", with: "8193")))
        let outsideStart = try analyze("<label columns=\"1\" rows=\"1\" start=\"2\"/>")
        XCTAssertTrue(outsideStart.warnings.contains { $0.contains("outside this sheet") })
    }

    func testNative4DExportsPreserveArtworkAndUnits() throws {
        func fixture(_ path: String) throws -> LabelFileInfo {
            let url = try XCTUnwrap(Bundle.module.url(forResource: path, withExtension: "4lbp",
                                                     subdirectory: "Fixtures/LabelProject"))
            let model = try AnalyzerRegistry.default.analyze(url: url)
            return try XCTUnwrap(model as? LabelFileInfo)
        }
        let authored = try fixture("Resources/Labels/representative")
        XCTAssertEqual(authored.objects.count, 10)
        XCTAssertEqual(authored.objects.first?.x, 4)
        XCTAssertEqual(authored.objects.first?.y, 4)
        XCTAssertEqual(authored.objects.first?.width, 244)
        XCTAssertEqual(authored.objects.first?.height, 172)
        XCTAssertEqual(authored.objects[2].attributes["value"], "Parcel & Co.")
        XCTAssertEqual(authored.objects[5].attributes["value"], "Café — 東京")
        XCTAssertEqual(authored.objects[6].attributes["value"], "[Parcels]Recipient")
        XCTAssertEqual(authored.objects[7].attributes["value"], "\"Code: \"+String(7)")
        XCTAssertEqual(authored.objects[8].image?.width, 24)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let objects = try encoder.encode(authored.objects)
        for engine in ["21-2", "21-r5"] {
            let native = try fixture("References/\(engine)/representative-roundtrip")
            XCTAssertEqual(try encoder.encode(native.objects), objects)
            let millimeters = try fixture("References/\(engine)/display-unit-mm")
            XCTAssertEqual(millimeters.layout.unit, "mm")
            XCTAssertEqual(millimeters.layout.width, 252)
            XCTAssertEqual(millimeters.layout.height, 179)
            XCTAssertEqual(try encoder.encode(millimeters.objects), objects)
        }
        let savedForm = try fixture("Resources/Labels/saved-form-reference")
        XCTAssertEqual(savedForm.root.children.first { $0.name == "form" }?.attributes["number"], "999")
        XCTAssertEqual(savedForm.form?.formName, "ShippingLabel")
        XCTAssertTrue(savedForm.form?.appearances.first?.pages.flatMap(\.objects).contains {
            $0.properties["text"]?.string == "HOST FORM REFERENCE"
        } == true)
        XCTAssertFalse(savedForm.warnings.contains { $0.contains("could not be loaded") })
    }
}
