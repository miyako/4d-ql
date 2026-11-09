import XCTest
import FourDFileKit
import FourDRender

final class FormWindowsRendererTests: XCTestCase {
    private let windowsThemes: [FormTheme] = [.windowsClassic, .fluentLight, .fluentDark]

    private func fixture(_ project: String, _ form: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: "form", withExtension: "4DForm",
            subdirectory: "Fixtures/\(project)/Project/Sources/Forms/\(form)"))
    }

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FormWindows-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    @discardableResult
    private func write(_ text: String, _ path: String, in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func project(form: String) throws -> URL {
        let root = try folder()
        try write("text { stroke: #111111; }", "Project/Sources/styleSheets.css", in: root)
        try write("text { stroke: #222222; }", "Project/Sources/styleSheets_mac.css", in: root)
        try write("text { stroke: #333333; }", "Project/Sources/styleSheets_windows.css", in: root)
        return try write(form, "Project/Sources/Forms/Example/form.4DForm", in: root)
    }

    private func checkedThemes(_ html: String) -> [String] {
        windowsThemes.map(\.rawValue).filter { html.contains("id=\"theme-\($0)\" checked>") }
    }

    func testThemesBelongToExactlyOnePlatform() {
        XCTAssertEqual(FormPlatform.windows.themes, windowsThemes)
        XCTAssertEqual(FormPlatform.macOS.themes, [.classicLight, .classicDark, .glassLight, .glassDark])
        XCTAssertEqual(Set(FormTheme.allCases), Set(FormPlatform.macOS.themes + FormPlatform.windows.themes))
        XCTAssertTrue(windowsThemes.allSatisfy { $0.platform == .windows })
        XCTAssertTrue(FormPlatform.macOS.themes.allSatisfy { $0.platform == .macOS })
        XCTAssertEqual(windowsThemes.map(\.rawValue), ["windowsClassic", "fluentLight", "fluentDark"])
        XCTAssertEqual(windowsThemes.map(\.dark), [false, false, true])
        #if os(Windows)
        XCTAssertEqual(FormPlatform.current, .windows)
        #elseif os(macOS)
        XCTAssertEqual(FormPlatform.current, .macOS)
        #endif
    }

    func testWindowsDocumentUsesWindowsThemesAndSchemaVersionTwo() throws {
        let result = try FormRenderer().render(url: fixture("FormProject", "Controls"), preferredLanguages: ["en"], platform: .windows)
        XCTAssertEqual(result.document.form.platform, .windows)
        XCTAssertEqual(result.document.form.appearances.map(\.theme), windowsThemes)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: result.document.jsonData()) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 2)
        XCTAssertEqual(json["referencePlatform"] as? String, "Windows")
        let images = try XCTUnwrap((json["form"] as? [String: Any])?["images"] as? [[String: Any]])
        XCTAssertFalse(images.isEmpty)
        XCTAssertTrue(images.allSatisfy { ($0["dataURI"] as? String)?.hasPrefix("data:image/") == true })
    }

    func testWindowsHTMLKeepsRasterizerStructureWithoutScriptOrMediaQuery() throws {
        let html = try FormRenderer().render(url: fixture("FormProject", "Controls"), platform: .windows).html
        XCTAssertFalse(html.contains("<script"))
        // The shared report chrome may follow the system scheme; the form
        // renderer's own CSS and markup must not.
        let preview = try XCTUnwrap(html.range(of: "<div class=\"form-preview\">"))
        let formStyle = try XCTUnwrap(html.range(of: "<style>", options: .backwards, range: html.startIndex..<preview.lowerBound))
        XCTAssertFalse(html[formStyle.lowerBound...].contains("prefers-color-scheme"))
        XCTAssertTrue(html.contains("Content-Security-Policy"))
        XCTAssertEqual(checkedThemes(html), ["windowsClassic"])
        for theme in windowsThemes {
            XCTAssertTrue(html.contains("<label for=\"theme-\(theme.rawValue)\">\(theme.label)</label>"))
            XCTAssertTrue(html.contains("data-theme=\"\(theme.rawValue)\"><input class=\"page-choice\""))
            XCTAssertTrue(html.contains("#theme-\(theme.rawValue):checked ~ .form-appearance[data-theme=\"\(theme.rawValue)\"]{display:block}"))
        }
        for theme in FormPlatform.macOS.themes { XCTAssertFalse(html.contains("theme-\(theme.rawValue)")) }
        XCTAssertTrue(html.contains("class=\"form-appearance light win-classic\""))
        XCTAssertTrue(html.contains("class=\"form-appearance light fluent\""))
        XCTAssertTrue(html.contains("class=\"form-appearance dark fluent\""))
        XCTAssertTrue(html.contains("<div class=\"form-preview\">"))
        XCTAssertTrue(html.contains("<div class=\"form-page\" data-page=\"1\"><div class=\"form-scroll\" tabindex=\"0\" role=\"region\" aria-label=\"Scrollable form canvas\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\""))
        XCTAssertTrue(html.contains("class=\"form-themes\""))
        XCTAssertTrue(html.contains("class=\"form-caption\""))
        XCTAssertTrue(html.contains("href=\"data:image/"))
    }

    func testFluentFormsAndExplicitThemesSelectTheInitialRadio() throws {
        let fluent = try project(form: #"{"fluentUI":true,"pages":[{"objects":{}},{"objects":{"a":{"type":"text","left":0,"top":0,"width":80,"height":20,"text":"A"}}}]}"#)
        XCTAssertEqual(checkedThemes(try FormRenderer().render(url: fluent, platform: .windows).html), ["fluentLight"])
        let explicit = try FormRenderer().render(url: fixture("FormProject", "Controls"), platform: .windows,
            options: FormRenderOptions(initialTheme: .fluentDark))
        XCTAssertEqual(checkedThemes(explicit.html), ["fluentDark"])
        XCTAssertEqual(explicit.document.initialTheme, .fluentDark)
        XCTAssertThrowsError(try FormRenderer().render(url: fixture("FormProject", "Controls"), platform: .windows,
            options: FormRenderOptions(initialTheme: .classicLight))) {
            guard case FormRenderError.unavailableTheme(.classicLight) = $0 else { return XCTFail("\($0)") }
        }
    }

    func testForcedColorSchemeLimitsWindowsThemes() throws {
        let objects = #""pages":[{"objects":{}},{"objects":{"a":{"type":"text","left":0,"top":0,"width":80,"height":20,"text":"A"}}}]"#
        let dark = try FormRenderer().render(url: project(form: "{\"colorScheme\":\"dark\",\(objects)}"), platform: .windows)
        XCTAssertEqual(checkedThemes(dark.html), ["fluentDark"])
        XCTAssertFalse(dark.html.contains("theme-windowsClassic"))
        XCTAssertFalse(dark.html.contains("theme-fluentLight"))
        XCTAssertThrowsError(try FormRenderer().render(url: project(form: "{\"colorScheme\":\"dark\",\(objects)}"), platform: .windows,
            options: FormRenderOptions(initialTheme: .windowsClassic)))

        let light = try FormRenderer().render(url: project(form: "{\"colorScheme\":\"light\",\(objects)}"), platform: .windows)
        XCTAssertEqual(checkedThemes(light.html), ["windowsClassic"])
        XCTAssertTrue(light.html.contains("id=\"theme-fluentLight\""))
        XCTAssertFalse(light.html.contains("theme-fluentDark"))
    }

    func testWindowsAnalysisUsesWindowsProjectStylesheet() throws {
        let url = try project(form: #"{"pages":[{"objects":{}},{"objects":{"a":{"type":"text","left":0,"top":0,"width":80,"height":20,"text":"A"}}}]}"#)
        func stroke(_ platform: FormPlatform) throws -> String? {
            let form = try FormRenderer().analyze(url: url, preferredLanguages: ["en"], platform: platform)
            return form.appearances.first?.pages.first { $0.number == 1 }?.objects.first { $0.name == "a" }?.properties["stroke"]?.string
        }
        XCTAssertEqual(try stroke(.windows), "#333333")
        XCTAssertEqual(try stroke(.macOS), "#222222")
        let windows = try FormRenderer().analyze(url: url, preferredLanguages: ["en"], platform: .windows)
        XCTAssertTrue(windows.dependencies.contains { $0.hasSuffix("styleSheets_windows.css") })
        XCTAssertFalse(windows.dependencies.contains { $0.hasSuffix("styleSheets_mac.css") })
    }

    func testMacOSOutputIsIndependentOfTheWindowsPlatform() throws {
        let url = try fixture("FormProject", "Controls")
        let mac = try FormRenderer().render(url: url, platform: .macOS)
        XCTAssertEqual(mac.document.schemaVersion, 1)
        XCTAssertEqual(mac.document.referencePlatform, "macOS")
        XCTAssertEqual(Set(mac.document.form.appearances.map(\.theme)), Set(FormPlatform.macOS.themes))
        XCTAssertFalse(mac.html.contains("win-classic"))
        XCTAssertFalse(mac.html.contains("fluent"))
    }
}
