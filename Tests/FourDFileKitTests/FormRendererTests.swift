import XCTest
import FourDFileKit
import FourDRender

final class FormRendererTests: XCTestCase {
    private func fixture(_ project: String, _ form: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: "form", withExtension: "4DForm",
            subdirectory: "Fixtures/\(project)/Project/Sources/Forms/\(form)"))
    }

    func testDefaultStandaloneHTMLIsIdenticalToSharedPreview() throws {
        for (project, form) in [("FormProject", "Controls"), ("FormStaticProject", "Root"),
                                ("FormBenchmarkProject", "References")] {
            let url = try fixture(project, form)
            let result = try FormRenderer().render(url: url, platform: .macOS)
            XCTAssertEqual(result.html, PreviewPipeline(analyzers: .macOSReference).html(for: url))
            XCTAssertFalse(result.html.contains("<script"))
            XCTAssertTrue(result.html.contains("Content-Security-Policy"))
        }
    }

    func testVersionedDocumentContainsResolvedProjectResources() throws {
        let result = try FormRenderer().render(url: fixture("FormProject", "Controls"), preferredLanguages: ["en"], platform: .macOS)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: result.document.jsonData()) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        XCTAssertEqual(json["referencePlatform"] as? String, "macOS")
        let form = try XCTUnwrap(json["form"] as? [String: Any])
        XCTAssertEqual(form["kind"] as? String, "4d.form")
        XCTAssertEqual((form["dependencies"] as? [String])?.count, 5)
        let images = try XCTUnwrap(form["images"] as? [[String: Any]])
        XCTAssertEqual(images.count, 1)
        XCTAssertTrue((images[0]["dataURI"] as? String)?.hasPrefix("data:image/svg+xml;base64,") == true)
        XCTAssertTrue(result.document.notices.isEmpty)
        let appearance = try XCTUnwrap(result.document.form.appearances.first)
        let name = try XCTUnwrap(appearance.pages.first { $0.number == 1 }?.objects.first { $0.name == "name" })
        XCTAssertEqual(name.properties["width"]?.double, 430)
        XCTAssertEqual(name.properties["stroke"]?.string, "#286092")
    }

    func testExplicitThemeAndPageAreInitiallySelected() throws {
        let result = try FormRenderer().render(url: fixture("FormProject", "Controls"), platform: .macOS,
            options: FormRenderOptions(initialTheme: .classicDark, initialPage: 2))
        XCTAssertTrue(result.html.contains("id=\"theme-classicDark\" checked>"))
        for theme in FormPlatform.macOS.themes {
            XCTAssertTrue(result.html.contains("id=\"page-\(theme.rawValue)-2\" checked>"))
            XCTAssertFalse(result.html.contains("id=\"page-\(theme.rawValue)-1\" checked>"))
        }
        XCTAssertEqual(result.document.initialTheme, .classicDark)
        XCTAssertEqual(result.document.initialPage, 2)
    }

    func testForcedColorSchemeCannotBeOverridden() throws {
        let url = try fixture("FormStaticProject", "Base")
        XCTAssertThrowsError(try FormRenderer().render(url: url, platform: .macOS, options: FormRenderOptions(initialTheme: .classicLight))) {
            guard case FormRenderError.unavailableTheme(.classicLight) = $0 else { return XCTFail("\($0)") }
        }
        XCTAssertNoThrow(try FormRenderer().render(url: url, platform: .macOS, options: FormRenderOptions(initialTheme: .classicDark)))
    }

    func testUnavailablePageReportsAnError() throws {
        XCTAssertThrowsError(try FormRenderer().render(url: fixture("FormProject", "Controls"), platform: .macOS,
            options: FormRenderOptions(initialPage: 99))) {
            guard case FormRenderError.unavailablePage(99) = $0 else { return XCTFail("\($0)") }
        }
    }

    func testEmptyTypedModelsReportAnError() throws {
        let renderer = FormRenderer()
        var form = try renderer.analyze(url: fixture("FormProject", "Controls"), platform: .macOS)
        for index in form.appearances.indices { form.appearances[index].pages = [] }
        XCTAssertThrowsError(try renderer.render(form: form)) {
            guard case FormRenderError.noAppearance = $0 else { return XCTFail("\($0)") }
        }
        form.appearances = []
        XCTAssertThrowsError(try renderer.render(form: form)) {
            guard case FormRenderError.noAppearance = $0 else { return XCTFail("\($0)") }
        }
    }

    func testLanguageAndStaticCompositionUseTheSameAnalyzedModel() throws {
        let renderer = FormRenderer()
        let form = try renderer.analyze(url: fixture("FormStaticProject", "Root"), preferredLanguages: ["fr"], platform: .macOS)
        let result = try renderer.render(form: form)
        XCTAssertEqual(form.localizationLanguage, "fr")
        XCTAssertTrue(result.html.contains("Enregistrer"))
        XCTAssertTrue(result.html.contains("Traduction par nom d&#39;objet"))
        let page = try XCTUnwrap(form.appearances.first?.pages.first { $0.number == 0 })
        XCTAssertEqual(page.objects.map(\.name), ["grandBackground", "grandMain", "shared", "basePageOne", "shared"])
        let panel = try XCTUnwrap(form.appearances.first?.pages.first { $0.number == 1 }?.objects.first { $0.name == "panel" })
        XCTAssertEqual(panel.children.map(\.name), ["panelBackground", "picture", "nested"])
        XCTAssertTrue(result.document.notices.contains { $0.contains("noncanonical") || $0.contains("schema") })
    }

    func testMalformedFormThrowsRatherThanReturningErrorHTML() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FormRenderer-" + UUID().uuidString + ".4DForm")
        try Data("{invalid".utf8).write(to: url)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try FormRenderer().render(url: url, platform: .macOS))
    }

    func testPageZeroOnlyFormsHaveAVisibleDefaultPage() throws {
        var form = try FormRenderer().analyze(url: fixture("FormProject", "Controls"), platform: .macOS)
        for index in form.appearances.indices {
            form.appearances[index].pages = form.appearances[index].pages.filter { $0.number == 0 }
        }
        let result = try FormRenderer().render(form: form)
        for theme in FormPlatform.macOS.themes {
            XCTAssertTrue(result.html.contains("id=\"page-\(theme.rawValue)-0\" checked>"))
        }
        XCTAssertTrue(result.html.contains("Contact"))
    }
}
