import XCTest
@testable import FourDFileKit
@testable import FourDRender

/// Previews that show the macOS and Windows appearances side by side, as the
/// Quick Look extension does on macOS.
final class FormPlatformPreviewTests: XCTestCase {
    private func fixture(_ project: String, _ form: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: "form", withExtension: "4DForm",
            subdirectory: "Fixtures/\(project)/Project/Sources/Forms/\(form)"))
    }

    private func project(form: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FormPlatforms-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let files = [
            "Project/Sources/styleSheets.css": "text { stroke: #111111; }",
            "Project/Sources/styleSheets_mac.css": "text { stroke: #222222; }",
            "Project/Sources/styleSheets_windows.css": "text { stroke: #333333; }",
            "Project/Sources/Forms/Example/form.4DForm": form,
        ]
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        return root.appendingPathComponent("Project/Sources/Forms/Example/form.4DForm")
    }

    private func analyze(_ url: URL, _ platforms: [FormPlatform]) throws -> FormFileInfo {
        try FormFileAnalyzer(preferredLanguages: ["en"], platforms: platforms).analyzeForm(ByteSource(url: url))
    }

    private func html(_ form: FormFileInfo, initialTheme: FormTheme? = nil) -> String {
        HTMLRenderer().render(FormPresenter().formReport(form, initialTheme: initialTheme))
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    func testPreviewPlatformsIncludeWindowsOnMacOS() {
        #if os(macOS)
        XCTAssertEqual(FormPlatform.previewPlatforms, [.macOS, .windows])
        #else
        XCTAssertEqual(FormPlatform.previewPlatforms, [.current])
        #endif
        let analyzer = AnalyzerRegistry.default.analyzers.compactMap { $0 as? FormFileAnalyzer }.first
        XCTAssertEqual(analyzer?.platforms, FormPlatform.previewPlatforms)
    }

    func testAnalyzerInitializersKeepOneOrderedPlatformList() {
        XCTAssertEqual(FormFileAnalyzer().platforms, [.current])
        XCTAssertEqual(FormFileAnalyzer(platform: .windows).platforms, [.windows])
        XCTAssertEqual(FormFileAnalyzer(platforms: []).platforms, [.current])
        XCTAssertEqual(FormFileAnalyzer(platforms: [.windows, .macOS, .windows]).platforms, [.windows, .macOS])
        var analyzer = FormFileAnalyzer(platforms: [.macOS, .windows])
        XCTAssertEqual(analyzer.platform, .macOS)
        analyzer.platform = .windows
        XCTAssertEqual(analyzer.platforms, [.windows])
    }

    func testMultiPlatformAnalysisAppliesEachPlatformStylesheet() throws {
        let url = try project(form: #"{"pages":[{"objects":{}},{"objects":{"a":{"type":"text","left":0,"top":0,"width":80,"height":20,"text":"A"}}}]}"#)
        let form = try analyze(url, [.macOS, .windows])
        XCTAssertEqual(form.platform, .macOS)
        XCTAssertEqual(form.platforms, [.macOS, .windows])
        XCTAssertEqual(form.appearances.map(\.theme), FormPlatform.macOS.themes + FormPlatform.windows.themes)
        func stroke(_ theme: FormTheme) -> String? {
            form.appearances.first { $0.theme == theme }?.pages.first { $0.number == 1 }?
                .objects.first { $0.name == "a" }?.properties["stroke"]?.string
        }
        XCTAssertEqual(stroke(.classicLight), "#222222")
        XCTAssertEqual(stroke(.fluentLight), "#333333")
        XCTAssertTrue(form.dependencies.contains { $0.hasSuffix("styleSheets_mac.css") })
        XCTAssertTrue(form.dependencies.contains { $0.hasSuffix("styleSheets_windows.css") })
    }

    func testCombinedHTMLHasACSSOnlyPlatformSwitch() throws {
        let form = try analyze(fixture("FormProject", "Controls"), [.macOS, .windows])
        let page = html(form)
        XCTAssertFalse(page.contains("<script"))
        XCTAssertEqual(count("<div class=\"form-platforms\">", in: page), 1)
        XCTAssertTrue(page.contains("id=\"platform-macOS\" checked>"))
        XCTAssertFalse(page.contains("id=\"platform-windows\" checked>"))
        XCTAssertEqual(count("<div class=\"form-platform\" data-platform=", in: page), 2)
        XCTAssertEqual(count("<div class=\"form-preview\">", in: page), 2)
        XCTAssertTrue(page.contains("<label for=\"platform-windows\">Windows</label>"))
        XCTAssertTrue(page.contains("#platform-windows:checked ~ .form-platform[data-platform=\"windows\"]{display:block}"))
        for theme in FormPlatform.macOS.themes {
            XCTAssertTrue(page.contains("name=\"form-theme-macOS\" id=\"theme-\(theme.rawValue)\""))
        }
        for theme in FormPlatform.windows.themes {
            XCTAssertTrue(page.contains("name=\"form-theme-windows\" id=\"theme-\(theme.rawValue)\""))
        }
        XCTAssertFalse(page.contains("name=\"form-theme\" "))
        // Windows selection is explicit; macOS keeps its scheme-driven defaults.
        XCTAssertTrue(page.contains("id=\"theme-windowsClassic\" checked>"))
        XCTAssertFalse(form.images.isEmpty)
        for image in form.images {
            XCTAssertEqual(count("<image id=\"\(image.id)\"", in: page), 1)
        }
    }

    func testInitialWindowsThemeSelectsTheWindowsPlatform() throws {
        let form = try analyze(fixture("FormProject", "Controls"), [.macOS, .windows])
        let page = html(form, initialTheme: .fluentDark)
        XCTAssertTrue(page.contains("id=\"platform-windows\" checked>"))
        XCTAssertTrue(page.contains("id=\"theme-fluentDark\" checked>"))
        XCTAssertFalse(page.contains("id=\"theme-windowsClassic\" checked>"))
    }

    func testSinglePlatformHTMLIsUnchanged() throws {
        let url = try fixture("FormProject", "Controls")
        let single = try analyze(url, [.windows])
        XCTAssertEqual(single.platforms, [.windows])
        let page = html(single)
        XCTAssertFalse(page.contains("form-platforms"))
        XCTAssertTrue(page.contains("name=\"form-theme\" id=\"theme-windowsClassic\" checked>"))
        // Notices embed error descriptions whose field order varies; compare the preview itself.
        func preview(_ html: String) -> Substring { html[..<(html.range(of: "<details>")?.lowerBound ?? html.endIndex)] }
        let rendered = try FormRenderer().render(url: url, preferredLanguages: ["en"], platform: .windows).html
        XCTAssertEqual(preview(page), preview(rendered))
    }

    func testEmbeddedSelawikFontsAreUnmodifiedFontFiles() throws {
        func bytes(_ base64: String) throws -> [UInt8] { [UInt8](try XCTUnwrap(Data(base64Encoded: base64))) }
        for font in [FormSubstituteFont.regularTrueType, FormSubstituteFont.boldTrueType] {
            XCTAssertEqual(Array(try bytes(font).prefix(4)), [0, 1, 0, 0])
        }
        for font in [FormSubstituteFont.regularWOFF2, FormSubstituteFont.boldWOFF2] {
            XCTAssertEqual(Array(try bytes(font).prefix(4)), Array("wOF2".utf8))
        }
        XCTAssertEqual(count("@font-face{font-family:Selawik", in: FormSubstituteFont.css), 2)
    }

    func testSubstituteFontIsEmbeddedOnlyWhenSegoeUIIsMissing() throws {
        let form = try analyze(fixture("FormProject", "Controls"), [.macOS, .windows])
        let page = html(form)
        XCTAssertEqual(page.contains("font-src data:"), FormSubstituteFont.isNeeded)
        XCTAssertEqual(page.contains("@font-face{font-family:Selawik"), FormSubstituteFont.isNeeded)
        let mac = html(try analyze(fixture("FormProject", "Controls"), [.macOS]))
        XCTAssertFalse(mac.contains("font-src data:"))
        XCTAssertFalse(mac.contains("Selawik"))
        #if os(Windows)
        XCTAssertFalse(FormSubstituteFont.isNeeded)
        #endif
    }

    /// Windows text widths match on every host: DirectWrite with Segoe UI on
    /// Windows, CoreText with the Selawik substitute on macOS. The expected
    /// values were measured with DirectWrite on Windows 11 (Segoe UI 5.x).
    func testWindowsTextWidthsMatchSegoeUIOnEveryHost() throws {
        #if !os(macOS) && !os(Windows)
        throw XCTSkip("no platform font service")
        #endif
        let bold = FormValue.object([FormMember(name: "fontWeight", value: .string("bold"))])
        let cases: [(Double, FormValue, String, Double)] = [
            (12, .object([]), "Customer invoice", 91.682),
            (12, .object([]), "Quantity: 1,234.56", 95.484),
            (12, .object([]), "The quick brown fox jumps over the lazy dog", 237.885),
            (9, .object([]), "The quick brown fox jumps over the lazy dog", 178.414),
            (13, .object([]), "Customer invoice", 99.322),
            (12, bold, "Customer invoice", 97.611),
            (12, bold, "Quantity: 1,234.56", 103.764),
        ]
        for (size, properties, text, expected) in cases {
            let face = FormTextLayout.font(size: size, properties: properties, platform: .windows)
            XCTAssertEqual(face.width(text), expected, accuracy: 0.5, "\(size) \(text)")
        }
        let face = FormTextLayout.font(size: 12, properties: .object([]), platform: .windows)
        XCTAssertEqual(face.lineHeight, 16)
        XCTAssertEqual(face.baselineOffset, 13)
    }
}
