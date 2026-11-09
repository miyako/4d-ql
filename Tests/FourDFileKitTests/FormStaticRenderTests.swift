import XCTest
@testable import FourDFileKit
@testable import FourDRender

final class FormStaticRenderTests: XCTestCase {
    private func fixture() throws -> FormFileInfo {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "form", withExtension: "4DForm",
                                                subdirectory: "Fixtures/FormStaticProject/Project/Sources/Forms/Root"))
        return try XCTUnwrap(AnalyzerRegistry.macOSReference.analyze(url: url) as? FormFileInfo)
    }

    func testResolvedSubformUsesLocalCoordinatesAndContainerClip() throws {
        let info = try fixture()
        let appearance = try XCTUnwrap(info.appearances.first { $0.theme == .classicLight })
        let objects = appearance.pages.flatMap(\.objects)
        let container = try XCTUnwrap(objects.first { $0.type == "subform" && !$0.children.isEmpty })
        let child = try XCTUnwrap(container.children.first)
        let html = FormPreviewRenderer().render(FormPreview(name: info.formName, properties: info.properties,
                                                            appearances: [appearance], images: info.images))
        let containerTitle = "<title>\(container.name) · subform"
        let tail = try XCTUnwrap(html.components(separatedBy: containerTitle).dropFirst().first)
        let clip = try XCTUnwrap(tail.range(of: "class=\"static-subform light classic\" clip-path=\"url(#form-clip-"))
        let childTitle = try XCTUnwrap(tail.range(of: "<title>\(child.name) · \(child.type)"))
        XCTAssertLessThan(clip.lowerBound, childTitle.lowerBound)
        let x = try XCTUnwrap(child.properties["left"]?.double)
        let y = try XCTUnwrap(child.properties["top"]?.double)
        let transform = String(format: "translate(%.0f %.0f)", x, y)
        XCTAssertTrue(tail[..<childTitle.lowerBound].hasSuffix("<g transform=\"\(transform)\">"))
        XCTAssertFalse(FormPreviewRenderer.diagnostics(info).contains { $0.contains("Placeholder only: subform") })
        XCTAssertTrue(html.contains("translate(72 12) scale(1 1)"))
        XCTAssertFalse(html.contains("<script"))
    }

    func testInheritedObjectsRetainOrderedPaintBehindLocalObjects() throws {
        let info = try fixture()
        let appearance = try XCTUnwrap(info.appearances.first { $0.theme == .classicLight })
        let page = try XCTUnwrap(appearance.pages.first { $0.number == 1 })
        let html = FormPreviewRenderer().render(FormPreview(name: info.formName, properties: info.properties,
                                                            appearances: [appearance], images: info.images))
        let pageHTML = try XCTUnwrap(html.components(separatedBy: "class=\"form-page\" data-page=\"1\"").dropFirst().first)
        var previous = pageHTML.startIndex
        for object in page.objects where object.properties["visibility"]?.string != "hidden" {
            let title = try XCTUnwrap(pageHTML.range(of: "<title>\(object.name) · \(object.type)", range: previous..<pageHTML.endIndex))
            XCTAssertGreaterThanOrEqual(title.lowerBound, previous)
            previous = title.upperBound
        }
    }

    func testStaticLocalizationIsReportedWithoutObsoleteUnsupportedNotice() throws {
        let info = try fixture()
        XCTAssertNotNil(info.localizationLanguage)
        let report = try XCTUnwrap(FormPresenter().report(for: info))
        let html = HTMLRenderer().render(report)
        XCTAssertTrue(html.contains("Localization"))
        XCTAssertFalse(html.contains("project translations are not loaded"))
        XCTAssertFalse(html.contains("Embedded forms, web content"))
    }

    func testSubformExplicitLightSchemeOverridesDarkParentPalette() throws {
        let source = try XCTUnwrap(Bundle.module.url(forResource: "FormStaticProject", withExtension: nil,
                                                    subdirectory: "Fixtures"))
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("FormStaticScheme-" + UUID().uuidString)
        try FileManager.default.copyItem(at: source, to: temporary)
        addTeardownBlock { try FileManager.default.removeItem(at: temporary) }
        let panelURL = temporary.appendingPathComponent("Project/Sources/Forms/Panel/form.4DForm")
        var panel = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: panelURL)) as? [String: Any])
        panel["colorScheme"] = "light"
        try JSONSerialization.data(withJSONObject: panel, options: .sortedKeys).write(to: panelURL, options: .atomic)
        let rootURL = temporary.appendingPathComponent("Project/Sources/Forms/Root/form.4DForm")
        let info = try XCTUnwrap(AnalyzerRegistry.macOSReference.analyze(url: rootURL) as? FormFileInfo)
        let appearance = try XCTUnwrap(info.appearances.first { $0.theme == .glassDark })
        let html = FormPreviewRenderer().render(FormPreview(name: info.formName, properties: info.properties,
                                                            appearances: [appearance], images: info.images))
        XCTAssertTrue(html.contains("class=\"static-subform light glass\""))
        XCTAssertTrue(html.contains(".static-subform.glass.light{--form-bg:#fff"))
        XCTAssertTrue(html.contains("class=\"form-appearance dark glass\""))
    }
}
