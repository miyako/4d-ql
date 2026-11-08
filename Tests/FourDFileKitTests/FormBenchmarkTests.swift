import XCTest
@testable import FourDFileKit
@testable import FourDRender

final class FormBenchmarkTests: XCTestCase {
    private let forms = ["Typography", "Controls", "ContactInvoice", "References"]

    private func fixture(_ path: String) throws -> URL {
        try XCTUnwrap(Bundle.module.resourceURL?
            .appendingPathComponent("Fixtures/FormBenchmarkProject")
            .appendingPathComponent(path))
    }

    private func analyze(_ name: String) throws -> FormFileInfo {
        let url = try fixture("Project/Sources/Forms/\(name)/form.4DForm")
        return try XCTUnwrap(AnalyzerRegistry.default.analyze(url: url) as? FormFileInfo)
    }

    private func object(_ info: FormFileInfo, _ name: String,
                        theme: FormTheme = .classicLight, page: Int = 1) throws -> FormObject {
        try XCTUnwrap(info.appearances.first { $0.theme == theme }?
            .pages.first { $0.number == page }?.objects.first { $0.name == name })
    }

    func testBenchmarkProjectIsDatalessAndLegacyCompatible() throws {
        let project = try JSONSerialization.jsonObject(
            with: Data(contentsOf: fixture("Project/FormBenchmark.4DProject"))) as? [String: Any]
        XCTAssertEqual(project?["compatibilityVersion"] as? Int, 2000)
        XCTAssertEqual(project?["tokenizedText"] as? Bool, false)
        let dependencies = try JSONSerialization.jsonObject(
            with: Data(contentsOf: fixture("Project/Sources/dependencies.json"))) as? [String: Any]
        XCTAssertEqual((dependencies?["dependencies"] as? [String: Any])?.count, 0)
        let manifest = try JSONSerialization.jsonObject(
            with: Data(contentsOf: fixture("benchmark.json"))) as? [String: Any]
        XCTAssertEqual(manifest?["forms"] as? [String], forms)
        XCTAssertEqual(manifest?["mode"] as? String, "named-static")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: try fixture("Project/Sources/Methods/benchmark_capture.4dm").path))
    }

    func testAllBenchmarkFormsHaveThreePagesFourThemesAndScriptFreeHTML() throws {
        for name in forms {
            let info = try analyze(name)
            XCTAssertEqual(info.formName, name)
            XCTAssertEqual(info.appearances.count, 4)
            XCTAssertTrue(info.warnings.isEmpty, "\(name): \(info.warnings)")
            for appearance in info.appearances {
                XCTAssertEqual(appearance.pages.map(\.number), [0, 1, 2])
                XCTAssertFalse(appearance.pages[0].objects.isEmpty)
            }
            let html = PreviewPipeline().html(for: try fixture("Project/Sources/Forms/\(name)/form.4DForm"))
            XCTAssertFalse(html.lowercased().contains("<script"))
            for theme in ["classicLight", "classicDark", "glassLight", "glassDark"] {
                XCTAssertTrue(html.contains("id=\"theme-\(theme)\""))
                for page in [0, 1, 2] {
                    XCTAssertTrue(html.contains("id=\"page-\(theme)-\(page)\""))
                }
            }
        }
    }

    func testTypographyAndControlHeightCoverageArePreserved() throws {
        let typography = try analyze("Typography")
        XCTAssertTrue(try object(typography, "japaneseWrap").properties["text"]?.string?.contains("図書館") == true)
        XCTAssertTrue(try object(typography, "arabicRTL").properties["text"]?.string?.contains("رسالة") == true)
        XCTAssertTrue(try object(typography, "accentsEmoji").properties["text"]?.string?.contains("👨‍👩‍👧‍👦") == true)
        XCTAssertEqual(try object(typography, "crlfBlankLines").properties["text"]?.string,
                       "First line\r\n\r\nThird line\r\nFourth line")
        XCTAssertEqual(try object(typography, "longSingleLine", page: 2).properties["multiline"]?.string, "no")
        let controls = try analyze("Controls")
        for kind in ["button", "dropdown", "checkbox", "radio"] {
            for height in [13, 16, 18, 20, 23, 26, 27, 32, 40] {
                XCTAssertEqual(try object(controls, "\(kind)\(height)").properties["height"]?.double,
                               Double(height))
            }
            XCTAssertNil(try object(controls, "\(kind)Default").properties["height"])
        }
    }

    func testProjectPointersStylesheetsAndStaticPicturesResolve() throws {
        let info = try analyze("References")
        XCTAssertEqual(try object(info, "pointerInput", page: 2).properties["width"]?.double, 480)
        XCTAssertEqual(try object(info, "pointerInput", page: 2).properties["height"]?.double, 23)
        XCTAssertEqual(try object(info, "pointerOverride", page: 2).properties["width"]?.double, 640)
        XCTAssertEqual(try object(info, "globalStyle").properties["fontSize"]?.double, 17)
        XCTAssertEqual(try object(info, "globalStyle", theme: .classicDark).properties["stroke"]?.string, "#86C8EF")
        XCTAssertEqual(try object(info, "macStyle", theme: .glassLight).properties["fontSize"]?.double, 18)
        XCTAssertEqual(try object(info, "explicitStyle").properties["fontSize"]?.double, 19)
        XCTAssertEqual(try object(info, "jsonOverridesCSS").properties["fontSize"]?.double, 13)
        XCTAssertEqual(try object(info, "jsonOverridesCSS").properties["stroke"]?.string, "#287C7A")
        XCTAssertFalse(info.images.isEmpty)
        for name in ["staticMark", "scaledPicture", "tiledPicture", "croppedPicture", "centeredPicture"] {
            XCTAssertNotNil(try object(info, name, page: name == "staticMark" ? 1 : 2).images["picture"])
        }
        let invoice = try analyze("ContactInvoice")
        let listbox = try object(invoice, "lineItems", page: 2)
        XCTAssertEqual(listbox.properties["rowHeight"]?.string, "28px")
        XCTAssertEqual(listbox.properties["headerHeight"]?.string, "30px")
        XCTAssertEqual(listbox.properties["footerHeight"]?.string, "28px")
        XCTAssertEqual(listbox.properties["showFooters"]?.bool, true)
    }

    func testControlGroupTitleUsesNativeAutomaticFont() throws {
        let info = try analyze("Controls")
        for theme in [FormTheme.classicLight, .classicDark, .glassLight, .glassDark] {
            let group = try object(info, "inputStyleGroup", theme: theme, page: 2)
            XCTAssertEqual(group.type, "groupBox")
            XCTAssertEqual(group.properties["text"]?.string, "Input style atlas")
            XCTAssertNil(group.properties["fontSize"])
            XCTAssertNil(group.properties["fontFamily"])
            XCTAssertEqual(group.properties["width"]?.double, 672)
            XCTAssertEqual(group.properties["height"]?.double, 452)
        }
    }
}
