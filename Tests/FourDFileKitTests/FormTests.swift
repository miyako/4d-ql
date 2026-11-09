import XCTest
@testable import FourDFileKit
@testable import FourDRender

final class FormTests: XCTestCase {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FormTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    @discardableResult
    private func write(_ text: String, _ name: String, in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func form(_ objects: String, extra: String = "", common: String = "{}") -> String {
        #"{"pages":[{"objects":\#(common)},{"objects":\#(objects)}]\#(extra)}"#
    }

    private func analyze(_ url: URL) throws -> FormFileInfo {
        let result = try AnalyzerRegistry.macOSReference.analyze(url: url)
        return try XCTUnwrap(result as? FormFileInfo)
    }

    private func object(_ info: FormFileInfo, theme: FormTheme = .classicLight, page: Int = 1, name: String) throws -> FormObject {
        try XCTUnwrap(info.appearances.first { $0.theme == theme }?.pages.first { $0.number == page }?.objects.first { $0.name == name })
    }

    func testProjectFixtureRoutingPointersAndFourAppearances() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "form", withExtension: "4DForm", subdirectory: "Fixtures/FormProject/Project/Sources/Forms/Controls"))
        let info = try analyze(url)
        XCTAssertEqual(info.formName, "Controls")
        XCTAssertEqual(info.appearances.count, 4)
        XCTAssertEqual(info.warnings, [])
        XCTAssertEqual(try object(info, name: "name").properties["width"]?.double, 430)
        XCTAssertEqual(try object(info, page: 0, name: "save").properties["height"]?.double, 23)
        XCTAssertEqual(try object(info, theme: .glassDark, page: 0, name: "save").properties["height"]?.double, 27)
        XCTAssertEqual(try object(info, theme: .classicDark, name: "name").properties["fill"]?.string, "#20242A")
        XCTAssertEqual(try object(info, theme: .glassDark, name: "emails").properties["alternateFill"]?.string, "#30343B")
        XCTAssertEqual(info.images.count, 1)
        XCTAssertEqual(info.dependencies.count, 5)
        XCTAssertTrue(AnalyzerRegistry.default.allContentTypes.contains("com.4d.4d.form"))
        let html = PreviewPipeline(analyzers: .macOSReference).html(for: url)
        for expected in ["Liquid Glass light", "Liquid Glass dark", "Classic light", "Classic dark",
                         "Page 0", "Page 1", "Page 2", "Form.contact.name", "Email address",
                         "data:image/svg+xml;base64,", "Original JSON", "Form details"] {
            XCTAssertTrue(html.contains(expected), expected)
        }
        XCTAssertFalse(html.contains("No preview available"))
        XCTAssertFalse(html.contains("<script"))
        XCTAssertFalse(html.contains(":has("))
        XCTAssertEqual(html.components(separatedBy: "data:image/svg+xml;base64,").count - 1, 1)
    }

    func testUnavailableResourcesAreVisibleBeforeTheCanvas() throws {
        let folder = try folder()
        let url = try write(form(#"{"label":{"type":"text","left":0,"top":0,"width":100,"height":20,"text":"Contact"}}"#,
                                 extra: #","css":"missing.css""#), "form.4DForm", in: folder)
        let info = try analyze(url)
        XCTAssertFalse(info.warnings.isEmpty)
        let html = PreviewPipeline(analyzers: .macOSReference).html(for: url)
        let notice = try XCTUnwrap(html.range(of: "Some resources or form features could not be reproduced."))
        let canvas = try XCTUnwrap(html.range(of: "class=\"form-preview\""))
        XCTAssertLessThan(notice.lowerBound, canvas.lowerBound)
        XCTAssertTrue(html.contains("Preview notices"))
        XCTAssertTrue(html.contains("missing.css"))
    }

    func testLiquidGlassTabsUseCenteredEditorTemplateSegments() throws {
        let folder = try folder()
        let url = try write(form(#"{"tabs":{"type":"tab","left":0,"top":0,"width":200,"height":30,"labels":["A","B"]},"bound":{"type":"tab","left":0,"top":40,"width":200,"height":30,"dataSource":"Form.tabs"}}"#),
                             "form.4DForm", in: folder)
        let info = try analyze(url)
        let glass = try XCTUnwrap(info.appearances.first { $0.theme == .glassLight })
        let html = FormPreviewRenderer().render(FormPreview(name: "Tabs", properties: info.properties,
                                                            appearances: [glass], images: []))
        XCTAssertTrue(html.contains("x=\"72\" y=\"1\" width=\"56\" height=\"24\" rx=\"5\""))
        XCTAssertTrue(html.contains("x=\"72\" y=\"1\" width=\"28\" height=\"24\" rx=\"4\" fill=\"var(--form-accent)\""))
        let bound = try XCTUnwrap(html.components(separatedBy: "<title>bound · tab").dropFirst().first)
        XCTAssertTrue(bound.components(separatedBy: "</svg></div>").first?.contains("fill=\"var(--form-accent)\"") ?? false)
        XCTAssertTrue(bound.contains(">Form.tabs</tspan>"))
    }

    func testClassicTabsUseCenteredSelectedSegments() throws {
        let folder = try folder()
        let url = try write(form(#"{"tabs":{"type":"tab","left":0,"top":0,"width":200,"height":30,"labels":["A","B"]}}"#),
                             "form.4DForm", in: folder)
        let info = try analyze(url)
        let classic = try XCTUnwrap(info.appearances.first { $0.theme == .classicLight })
        let html = FormPreviewRenderer().render(FormPreview(name: "Tabs", properties: info.properties,
                                                            appearances: [classic], images: []))
        XCTAssertTrue(html.contains("x=\"72\" y=\"2.50\" width=\"56\" height=\"21\" rx=\"5\""))
        XCTAssertTrue(html.contains("x=\"72\" y=\"2.50\" width=\"28\" height=\"21\" rx=\"4\" fill=\"var(--form-tab-selected)\""))
    }

    func testBlankLinesUseAbsoluteSVGPositions() throws {
        try requireMacOSFontMetrics()
        let folder = try folder()
        let url = try write(form(#"{"label":{"type":"text","left":0,"top":0,"width":200,"height":100,"fontSize":13,"text":"First\r\n\r\nLast"}}"#),
                             "form.4DForm", in: folder)
        let html = PreviewPipeline(analyzers: .macOSReference).html(for: url)
        XCTAssertTrue(html.contains("<tspan x=\"0\" y=\"29\"></tspan>"))
        XCTAssertTrue(html.contains("<tspan x=\"0\" y=\"45\">Last</tspan>"))
        XCTAssertFalse(html.contains(" dy=\""))
    }

    func testListboxColumnsReserveTheVerticalScrollbarArea() throws {
        let folder = try folder()
        for (scrollbar, width) in [("visible", "184"), ("hidden", "200")] {
            let url = try write(form(#"{"grid":{"type":"listbox","left":0,"top":0,"width":200,"height":100,"scrollbarVertical":"\#(scrollbar)","headerHeight":30,"columns":[{"name":"total","width":100,"header":{"text":"Total"}}]}}"#),
                                 scrollbar+".4DForm", in: folder)
            let html = PreviewPipeline(analyzers: .macOSReference).html(for: url)
            XCTAssertTrue(html.contains("<rect x=\"0\" width=\"\(width)\" height=\"30\""))
        }
    }

    func testListboxFootersClipToOneLineUnlessWrappingIsRequested() throws {
        let folder = try folder()
        for wrapping in ["", #","multiline":"yes""#] {
            let url = try write(form(#"{"grid":{"type":"listbox","left":0,"top":0,"width":118,"height":100,"scrollbarVertical":"hidden","showFooters":true,"footerHeight":28,"columns":[{"name":"price","width":118,"footer":{"dataSource":"Form.invoice.currency"\#(wrapping)}}]}}"#),
                                 UUID().uuidString+".4DForm", in: folder)
            XCTAssertEqual(PreviewPipeline(analyzers: .macOSReference).html(for: url).contains(">Form.invoice.currency</tspan>"), wrapping.isEmpty)
        }
    }

    func testGroupFramesReserveTitleHeightAndUntitledGroupsStayBare() throws {
        let folder = try folder()
        let url = try write(form(#"{"titled":{"type":"groupBox","left":0,"top":0,"width":200,"height":100,"text":"Group","fontSize":10},"bare":{"type":"groupBox","left":0,"top":120,"width":200,"height":100,"fontSize":10}}"#),
                             "groups.4DForm", in: folder)
        let html = PreviewPipeline(analyzers: .macOSReference).html(for: url)
        XCTAssertTrue(html.contains("<rect y=\"12\" width=\"200\" height=\"88\""))
        let bare = try XCTUnwrap(html.components(separatedBy: "<title>bare · groupBox</title>").dropFirst().first)
            .components(separatedBy: "</g>").first ?? ""
        XCTAssertTrue(bare.contains("<rect y=\"0\" width=\"200\" height=\"100\""))
        XCTAssertFalse(bare.contains("<tspan"))
    }

    func testGroupTitlesAlignWithinTheWholeFrame() throws {
        let folder = try folder()
        let pattern = #"<svg x="([\d.]+)" y="0" width="([\d.]+)" height="12" overflow="hidden"><text x="([\d.]+)""#
        let regex = try NSRegularExpression(pattern: pattern)
        for (alignment, anchor) in [("center", 100.0), ("right", 188.0)] {
            let url = try write(form(#"{"group":{"type":"groupBox","left":0,"top":0,"width":200,"height":100,"text":"Group","fontSize":10,"textAlign":"\#(alignment)"}}"#),
                                 alignment+".4DForm", in: folder)
            let html = PreviewPipeline(analyzers: .macOSReference).html(for: url)
            let source = html as NSString
            let match = try XCTUnwrap(regex.firstMatch(in: html, range: NSRange(location: 0, length: source.length)))
            let x = try XCTUnwrap(Double(source.substring(with: match.range(at: 1))))
            let origin = try XCTUnwrap(Double(source.substring(with: match.range(at: 3))))
            XCTAssertEqual(x+origin, anchor, accuracy: 0.02)
        }
    }

    func testTextAndInputPaddingDefineTheInnerTextViewport() throws {
        let folder = try folder()
        let url = try write(form(#"{"label":{"type":"text","left":0,"top":0,"width":100,"height":80,"text":"Hello","fontSize":13,"paddingLeft":8,"paddingRight":12,"paddingTop":10,"paddingBottom":14},"field":{"type":"input","left":0,"top":100,"width":100,"height":80,"dataSource":"Form.name","fontSize":13,"paddingLeft":8,"paddingRight":12,"paddingTop":10,"paddingBottom":14,"verticalAlign":"top"}}"#),
                             "padding.4DForm", in: folder)
        let html = PreviewPipeline(analyzers: .macOSReference).html(for: url)
        XCTAssertEqual(html.components(separatedBy: "<svg x=\"8\" y=\"10\" width=\"80\" height=\"56\"").count-1, 8)
    }

    func testRoundedTextAndTallSingleLineInputUseNativePaintExtents() throws {
        let folder = try folder()
        let url = try write(form(#"{"label":{"type":"text","left":0,"top":0,"width":134,"height":29,"text":"Label","fill":"white","borderStyle":"solid","borderRadius":5},"field":{"type":"input","left":0,"top":100,"width":332,"height":34,"dataSource":"Form.name","borderStyle":"solid","borderRadius":20,"multiline":"no"}}"#),
                             "rounded.4DForm", in: folder)
        let html = PreviewPipeline(analyzers: .macOSReference).html(for: url)
        XCTAssertTrue(html.contains("<rect x=\"-6\" y=\"-1\" width=\"146\" height=\"31\""))
        XCTAssertTrue(html.contains("<rect x=\"-18\" y=\"-1\" width=\"368\" height=\"36\""))
    }

    func testIconCaptionsUseSavedPlacementAndNativeDefaultStacking() throws {
        try requireMacOSFontMetrics()
        let folder = try folder()
        try write(#"<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><rect width="24" height="24" fill="black"/></svg>"#,
                  "icon.svg", in: folder)
        let url = try write(form(#"{"button":{"type":"button","left":0,"top":0,"width":160,"height":60,"text":"Button","icon":"icon.svg"},"check":{"type":"checkbox","left":0,"top":80,"width":160,"height":60,"text":"Check","style":"roundedBevel","icon":"icon.svg","textPlacement":"top"}}"#),
                             "icons.4DForm", in: folder)
        let html = PreviewPipeline(analyzers: .macOSReference).html(for: url)
        XCTAssertTrue(html.contains("<svg x=\"68\" y=\"6\" width=\"24\" height=\"24\""))
        XCTAssertTrue(html.contains("<svg x=\"68\" y=\"30\" width=\"24\" height=\"24\""))
    }

    func testJustifiedTextExpandsWordSpacesButNotTheParagraphEnd() throws {
        let folder = try folder()
        let url = try write(form(#"{"label":{"type":"text","left":0,"top":0,"width":120,"height":100,"fontFamily":"Arial","fontSize":13,"textAlign":"justify","text":"One two three four five six seven eight nine ten."}}"#),
                             "justify.4DForm", in: folder)
        let html = PreviewPipeline(analyzers: .macOSReference).html(for: url)
        XCTAssertTrue(html.contains(" word-spacing=\""))
        let finalLine = try XCTUnwrap(html.components(separatedBy: "<tspan").last?.components(separatedBy: "</tspan>").first)
        XCTAssertFalse(finalLine.contains("word-spacing"))
    }

    func testInvalidPaddingProducesAVisibleNoticeWithoutNonfiniteSVG() throws {
        let folder = try folder()
        let url = try write(form(#"{"label":{"type":"text","left":0,"top":0,"width":100,"height":80,"text":"Hello","paddingLeft":"NaNpx","paddingTop":-1,"paddingBottom":9000}}"#),
                             "padding.4DForm", in: folder)
        let html = PreviewPipeline(analyzers: .macOSReference).html(for: url)
        XCTAssertTrue(html.contains("Invalid text padding is ignored"))
        XCTAssertTrue(html.contains("Some resources or form features could not be reproduced"))
        XCTAssertFalse(html.contains("x=\"nan\""))
    }

    func testOrderedObjectKeysAndUnicodeBOM() throws {
        let folder = try folder()
        let objects = #"{"z":{"type":"rectangle","left":0,"top":0,"width":100,"height":100},"あ":{"type":"text","left":0,"top":0,"width":100,"height":20,"text":"日本語"},"a":{"type":"button","left":20,"top":30,"text":"Last"}}"#
        let url = try write("\u{FEFF}" + form(objects, extra: #","entryOrder":["a","z"]"#), "stack.4DFORM", in: folder)
        let info = try analyze(url)
        XCTAssertEqual(info.appearances[0].pages[1].objects.map(\.name), ["z", "あ", "a"])
        let html = PreviewPipeline(analyzers: .macOSReference).html(for: url)
        let z = try XCTUnwrap(html.range(of: "<title>z · rectangle</title>"))
        let a = try XCTUnwrap(html.range(of: "<title>a · button</title>"))
        XCTAssertLessThan(z.lowerBound, a.lowerBound)
        XCTAssertTrue(html.contains("日本語"))
        XCTAssertTrue(try AnalyzerRegistry.macOSReference.analyze(url: url, contentType: "com.4d.4d.form") is FormFileInfo)
    }

    func testCSSCascadeSpecificityImportantMediaAndAttributes() throws {
        let folder = try folder()
        let css = """
        * { fontSize: 10; stroke: black; }
        button { fontSize: 11; }
        .primary { fontSize: 12; }
        button.primary { fontSize: 13; }
        #save { fontSize: 14; text: "CSS"; }
        [text="Save"] { fill: red; }
        button[class~="primary"] { text-decoration: underline; }
        [dataSource|="Form"] { font-style: italic; }
        #save { text: "Override;:}" !important; stroke: rgb(10, 20, 30) !important; }
        @media (form-theme: liquid-glass) {
          #save { height: 27px; }
          @media (prefers-color-scheme: dark) { #save { fill: #123456; } }
        }
        @media (form-theme: mac-classic) and (prefers-color-scheme: dark) { #save { fill: #abcdef; } }
        @media (form-theme: win-classic) { #save { fill: green !important; } }
        """
        try write(css, "first.css", in: folder)
        try write("#save { fontSize: 16; }", "last.css", in: folder)
        let url = try write(form(#"{"save":{"type":"button","class":"primary other","left":0,"top":0,"text":"Save","dataSource":"Form.value","stroke":"blue"}}"#, extra: #","css":["first.css","last.css"]"#), "form.4DForm", in: folder)
        let info = try analyze(url)
        let light = try object(info, name: "save").properties
        XCTAssertEqual(light["fontSize"]?.double, 16)
        XCTAssertEqual(light["text"]?.string, "Override;:}")
        XCTAssertEqual(light["stroke"]?.string, "rgb(10, 20, 30)")
        XCTAssertEqual(light["fill"]?.string, "red")
        XCTAssertEqual(light["textDecoration"]?.string, "underline")
        XCTAssertEqual(light["fontStyle"]?.string, "italic")
        XCTAssertEqual(try object(info, theme: .glassDark, name: "save").properties["fill"]?.string, "#123456")
        XCTAssertEqual(try object(info, theme: .glassLight, name: "save").properties["height"]?.double, 27)
        XCTAssertEqual(try object(info, theme: .classicDark, name: "save").properties["fill"]?.string, "#abcdef")
        XCTAssertTrue(info.warnings.isEmpty, info.warnings.joined(separator: "\n"))
    }

    func testJSONWinsAndFixedColorSchemeCannotBeOverridden() throws {
        let folder = try folder()
        try write("""
        button { height: 27px; text: CSS; colorScheme: light !important; }
        @media (prefers-color-scheme: dark) { button { stroke: white; } }
        """, "style.css", in: folder)
        let url = try write(form(#"{"a":{"type":"button","left":0,"top":0,"height":23,"text":"JSON"}}"#, extra: #","colorScheme":"dark","css":"style.css""#), "form.4DForm", in: folder)
        let info = try analyze(url)
        for theme in FormPlatform.macOS.themes {
            let p = try object(info, theme: theme, name: "a").properties
            XCTAssertEqual(p["height"]?.double, 23)
            XCTAssertEqual(p["text"]?.string, "JSON")
            XCTAssertEqual(p["stroke"]?.string, "white")
        }
        XCTAssertTrue(info.warnings.contains("CSS cannot set colorScheme."))
        let html = PreviewPipeline(analyzers: .macOSReference).html(for: url)
        XCTAssertTrue(html.contains("Form forces dark"))
        XCTAssertFalse(html.contains("id=\"theme-classicLight\""))
        XCTAssertFalse(html.contains("id=\"theme-glassLight\""))
    }

    func testRecursiveExternalPointersEscapesAndLocalOverrides() throws {
        let folder = try folder()
        try write(#"{"base":{"type":"input","left":1,"top":2,"width":90,"height":22,"icon":"icon.svg"}}"#, "nested/base.json", in: folder)
        try write(#"{"part":{"$ref":"base.json#/base","width":140}}"#, "nested/template.json", in: folder)
        try write(#"<svg xmlns="http://www.w3.org/2000/svg" width="5" height="5"><rect width="5" height="5"/></svg>"#, "nested/icon.svg", in: folder)
        let url = try write(form(##"{"field":{"$ref":"nested/template.json#/part","left":20},"same":{"$ref":"#/defaults/a~1b~0c"}}"##, extra: #","defaults":{"a/b~c":{"type":"text","left":4,"top":5,"text":"Escaped"}} "#), "form.4DForm", in: folder)
        let info = try analyze(url)
        let field = try object(info, name: "field")
        XCTAssertEqual(field.properties["left"]?.double, 20)
        XCTAssertEqual(field.properties["width"]?.double, 140)
        XCTAssertEqual(field.properties["icon"]?.string, "nested/icon.svg")
        XCTAssertNotNil(field.images["icon"])
        XCTAssertEqual(try object(info, name: "same").properties["text"]?.string, "Escaped")
        XCTAssertTrue(info.warnings.isEmpty, info.warnings.joined(separator: "\n"))
    }

    func testPointerErrorsAndUnavailableDependenciesAreExplicit() throws {
        let folder = try folder()
        let objects = ##"{"missing":{"$ref":"absent.json#/x","type":"text","left":0,"top":0},"cycle":{"$ref":"#/loop","type":"text","left":0,"top":20},"network":{"$ref":"https://example.com/x","type":"text","left":0,"top":40},"escape":{"$ref":"../other.json","type":"text","left":0,"top":60}}"##
        let url = try write(form(objects, extra: ##","loop":{"$ref":"#/loop"},"css":"missing.css""##), "form.4DForm", in: folder)
        let info = try analyze(url)
        XCTAssertGreaterThanOrEqual(info.warnings.count, 5)
        for expected in ["absent.json", "Cyclic JSON pointer", "https://example.com", "escapes", "missing.css"] {
            XCTAssertTrue(info.warnings.joined().contains(expected), expected)
        }
        XCTAssertEqual(try object(info,name:"missing").properties["$ref"]?.string, "absent.json#/x")
        let html = PreviewPipeline(analyzers: .macOSReference).html(for: url)
        XCTAssertTrue(html.contains("Preview notices"))
        XCTAssertFalse(html.contains("href=\"https://"))
    }

    func testSymlinkEscapeIsRejected() throws {
        let folder = try folder()
        let outside = try self.folder()
        let secret = try write(#"{"value":42}"#, "outside.json", in: outside)
        try createSymbolicLink(at: folder.appendingPathComponent("link.json"), to: secret)
        let url = try write(form(#"{"a":{"$ref":"link.json","type":"text","left":0,"top":0}}"#), "form.4DForm", in: folder)
        XCTAssertTrue(try analyze(url).warnings.joined().contains("escapes"))
    }

    func testExternalReferenceLocalPictureAndStylesheetOverridesKeepBase() throws {
        let folder = try folder()
        try write(#"{"base":{"type":"picture","left":0,"top":0,"width":20,"height":20}}"#, "nested/base.json", in: folder)
        try write(#"{"part":{"$ref":"base.json#/base","picture":"logo.svg","css":"local.css"}}"#, "nested/template.json", in: folder)
        try write(#"<svg xmlns="http://www.w3.org/2000/svg" width="5" height="5"><rect width="5" height="5"/></svg>"#, "nested/logo.svg", in: folder)
        let url = try write(form(#"{"picture":{"$ref":"nested/template.json#/part"}}"#), "form.4DForm", in: folder)
        let info = try analyze(url)
        let picture = try object(info, name: "picture")
        XCTAssertEqual(picture.properties["picture"]?.string, "nested/logo.svg")
        XCTAssertEqual(picture.properties["css"]?.string, "nested/local.css")
        XCTAssertNotNil(picture.images["picture"])
        XCTAssertTrue(info.warnings.isEmpty)
    }

    func testQuotedSelectorCommasAndTinyFontSizes() throws {
        let folder = try folder()
        try write(#"button[text="Hello, world"], .other { fill: red; }"#, "style.css", in: folder)
        let url = try write(form(#"{"a":{"type":"button","left":0,"top":0,"width":200,"height":20,"text":"Hello, world","fontSize":1e-20}}"#, extra: #","css":"style.css""#), "form.4DForm", in: folder)
        let info = try analyze(url)
        XCTAssertEqual(try object(info,name:"a").properties["fill"]?.string, "red")
        XCTAssertTrue(info.warnings.isEmpty)
        XCTAssertFalse(PreviewPipeline(analyzers: .macOSReference).html(for:url).contains("No preview available"))
    }

    func testJSONCornerCoordinatesBeatCSSDimensions() throws {
        let folder = try folder()
        try write("button { height: 27px; width: 200px; }", "style.css", in: folder)
        let url = try write(form(#"{"a":{"type":"button","left":10,"top":20,"right":110,"bottom":40}}"#, extra: #","css":"style.css""#), "form.4DForm", in: folder)
        let p = try object(analyze(url),name:"a").properties
        XCTAssertNil(p["height"])
        XCTAssertNil(p["width"])
        XCTAssertTrue(PreviewPipeline(analyzers: .macOSReference).html(for:url).contains("width=\"100\" height=\"20\""))
    }

    func testCSSPicturePathsUseStylesheetDirectory() throws {
        let folder = try folder()
        try write("picture { picture: url('logo.svg'); }", "styles/local.css", in: folder)
        try write(#"<svg xmlns="http://www.w3.org/2000/svg" width="5" height="5"><rect width="5" height="5"/></svg>"#, "styles/logo.svg", in: folder)
        let url = try write(form(#"{"a":{"type":"picture","left":0,"top":0,"width":50,"height":50}}"#, extra: #","css":"styles/local.css""#), "form.4DForm", in: folder)
        let info = try analyze(url)
        XCTAssertEqual(try object(info,name:"a").properties["picture"]?.string, "styles/logo.svg")
        XCTAssertNotNil(try object(info,name:"a").images["picture"])
        XCTAssertTrue(info.warnings.isEmpty)
    }

    func testDefaultCSSSymlinkCannotEscapeProject() throws {
        let folder = try folder()
        let outside = try self.folder()
        let css = try write("text { text: Wrong !important; }", "outside.css", in: outside)
        let url = try write(form(#"{"a":{"type":"text","left":0,"top":0,"text":"Right"}}"#), "Project/Sources/Forms/Example/form.4DForm", in: folder)
        let link = folder.appendingPathComponent("Project/Sources/styleSheets.css")
        try createSymbolicLink(at: link, to: css)
        let info = try analyze(url)
        XCTAssertEqual(try object(info,name:"a").properties["text"]?.string,"Right")
        XCTAssertTrue(info.warnings.joined().contains("escapes"))
    }

    func testUnsupportedCSSIsVisibleAndNonVisualObjectsRetained() throws {
        let folder = try folder()
        try write("@import 'https://example.com/x.css'; button:hover { text: Hover; } button { method: Run; }", "style.css", in: folder)
        let url = try write(form(#"{"a":{"type":"button","left":0,"top":0,"text":"Right"},"b":{"type":"text","left":0,"top":20,"width":"wrong","text":"Invalid coordinates"}}"#, extra: #","css":"style.css""#), "form.4DForm", in: folder)
        let info = try analyze(url)
        XCTAssertTrue(info.warnings.joined().contains("Unsupported"))
        XCTAssertTrue(info.warnings.contains("CSS cannot set method."))
        XCTAssertEqual(info.appearances[0].pages[1].objects.count,2)
        let html = PreviewPipeline(analyzers: .macOSReference).html(for:url)
        XCTAssertTrue(html.contains("invalid or out-of-range coordinates"))
        XCTAssertFalse(html.contains("<title>b · text</title>"))
    }

    func testPictureSpritesCropFirstFrame() throws {
        let folder = try folder()
        try write(#"<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20"><rect width="20" height="20" fill="red"/><rect x="20" width="20" height="20" fill="blue"/></svg>"#, "sprite.svg", in: folder)
        let url = try write(form(#"{"a":{"type":"pictureButton","left":0,"top":0,"width":50,"height":50,"picture":"sprite.svg","columnCount":2,"rowCount":1}}"#), "form.4DForm", in: folder)
        let html = PreviewPipeline(analyzers: .macOSReference).html(for:url)
        XCTAssertTrue(html.contains("scale(2.50 2.50)"))
        XCTAssertTrue(html.contains("<svg width=\"20\" height=\"20\" overflow=\"hidden\"><use href=\"#form-image-0\""))
    }

    func testInvalidFormsAndHardLimits() throws {
        let folder = try folder()
        for text in ["", "[]", "{}", #"{"pages":[]}"#, #"{"pages":[null,{}]}"#,
                     #"{"pages":[null,{"objects":{"x":null}}]}"#,
                     #"{"pages":[null,{"objects":{}}],"pages":[]}"#] {
            let url = try write(text, UUID().uuidString+".4DForm", in: folder)
            XCTAssertThrowsError(try analyze(url), text)
        }
        let url = try write(String(repeating: "[", count: 66) + "0" + String(repeating: "]", count:66), "deep.4DForm", in: folder)
        XCTAssertThrowsError(try analyze(url))
        try Data(repeating: 32, count: 4*1024*1024+1).write(to:url)
        XCTAssertThrowsError(try analyze(url))
        try Data([0xff]).write(to:url)
        XCTAssertThrowsError(try analyze(url))
    }

    func testStaticPlaceholdersNoExecutionAndEscaping() throws {
        let folder = try folder()
        let url = try write(form(#"{"bound":{"type":"input","left":10,"top":10,"width":300,"height":22,"dataSource":"Form.value","defaultValue":"Do not execute"},"unsafe":{"type":"text","left":10,"top":40,"width":300,"height":22,"text":"<script>alert(1)</script>","fontFamily":"\" onload=\"bad"},"web":{"type":"webArea","left":10,"top":80,"width":300,"height":100,"urlSource":"https://example.com"}}"#), "form.4DForm", in: folder)
        let html = PreviewPipeline(analyzers: .macOSReference).html(for:url)
        XCTAssertTrue(html.contains(">Form.value</tspan>"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertFalse(html.contains(" onload=\"bad"))
        XCTAssertTrue(html.contains("Placeholder only: webArea"))
        XCTAssertFalse(html.contains("<iframe"))
    }

    func testGlassTwentySevenPointThreshold() throws {
        let folder = try folder()
        let url = try write(form(#"{"short":{"type":"button","left":0,"top":0,"width":100,"height":26},"large":{"type":"button","left":0,"top":40,"width":100,"height":27}}"#), "form.4DForm", in: folder)
        let info = try analyze(url)
        let glass = try XCTUnwrap(info.appearances.first { $0.theme == .glassLight })
        let preview = FormPreview(name: "Threshold", properties: info.properties, appearances:[glass], images: [])
        let html = FormPreviewRenderer().render(preview)
        XCTAssertTrue(html.contains("height=\"24\" rx=\"2\""))
        XCTAssertTrue(html.contains("height=\"28\" rx=\"14\""))
    }

    func testMeasuredNativeHeightAndFontVariants() throws {
        let folder = try folder()
        for (declared, painted, fontSize) in [(13,16,9),(16,16,9),(18,20,11),(20,20,11),
                                             (23,24,13),(26,24,13),(27,28,13),(32,28,13),(40,40,13)] {
            let url = try write(form(#"{"a":{"type":"button","left":0,"top":0,"width":100,"height":\#(declared),"text":"HEIGHT"}}"#), "form.4DForm", in: folder)
            let info = try analyze(url)
            let glass = try XCTUnwrap(info.appearances.first { $0.theme == .glassLight })
            let html = FormPreviewRenderer().render(FormPreview(name:"Native",properties:info.properties,appearances:[glass],images:[]))
            XCTAssertTrue(html.contains("width=\"100\" height=\"\(painted)\" rx="), "\(declared)")
            XCTAssertTrue(html.contains("font-size=\"\(fontSize)\""), "\(declared)")
        }
    }

    func testMeasuredSingleLineRadiusExpandsHorizontally() throws {
        let folder = try folder()
        let url = try write(form(#"{"a":{"type":"input","left":490,"top":64,"width":220,"height":24,"borderStyle":"solid","borderRadius":8,"dataSource":"Form.radius"}}"#), "form.4DForm", in:folder)
        XCTAssertTrue(PreviewPipeline(analyzers: .macOSReference).html(for:url).contains("x=\"-9\" y=\"-1\" width=\"238\" height=\"26\" rx=\"8\""))
    }

    func testNativeOmittedHeightDefaultsAndTallDropdownException() throws {
        let folder = try folder()
        let url = try write(form(#"{"a":{"type":"button","left":0,"top":0,"width":100,"text":"Default"},"b":{"type":"checkbox","left":0,"top":40,"width":100,"text":"Default"},"c":{"type":"dropdown","left":0,"top":80,"width":100,"height":40,"dataSource":"Form.value"}}"#), "form.4DForm", in:folder)
        let info = try analyze(url)
        let glass = try XCTUnwrap(info.appearances.first { $0.theme == .glassLight })
        let html = FormPreviewRenderer().render(FormPreview(name:"Native",properties:info.properties,appearances:[glass],images:[]))
        XCTAssertTrue(html.contains("width=\"100\" height=\"20\" rx=\"2\""))
        XCTAssertTrue(html.contains("font-size=\"11\""))
        XCTAssertTrue(html.contains("width=\"16\" height=\"16\" rx=\"3\""))
        XCTAssertTrue(html.contains("width=\"100\" height=\"40\" rx=\"2\""))
    }

    func testClassicAndGlassHaveDistinctAutomaticFontAndToggleDefaults() throws {
        let folder = try folder()
        let url = try write(form(#"{"button":{"type":"button","left":0,"top":0,"width":100,"height":20,"text":"HEIGHT"},"check":{"type":"checkbox","left":0,"top":40,"width":100,"text":"HEIGHT"},"menu":{"type":"dropdown","left":0,"top":80,"width":100,"height":23,"dataSource":"Form.value"}}"#), "form.4DForm", in:folder)
        let info = try analyze(url)
        func render(_ theme: FormTheme) throws -> String {
            let appearance = try XCTUnwrap(info.appearances.first { $0.theme == theme })
            return FormPreviewRenderer().render(FormPreview(name:"Native",properties:info.properties,appearances:[appearance],images:[]))
        }
        let classic = try render(.classicDark)
        let glass = try render(.glassDark)
        func fragment(_ html: String, _ name: String) throws -> String {
            let tail = try XCTUnwrap(html.components(separatedBy:"<title>\(name) · ").dropFirst().first)
            return try XCTUnwrap(tail.components(separatedBy:"<g transform=").first)
        }
        let classicCheck = try fragment(classic,"check")
        let glassCheck = try fragment(glass,"check")
        XCTAssertTrue(classicCheck.contains("height=\"20\""))
        XCTAssertTrue(classicCheck.contains("width=\"14\" height=\"14\" rx=\"3\""))
        XCTAssertTrue(glassCheck.contains("height=\"16\""))
        XCTAssertTrue(glassCheck.contains("width=\"16\" height=\"16\" rx=\"3\""))
        XCTAssertTrue(try fragment(classic,"button").contains("font-size=\"13\""))
        XCTAssertTrue(try fragment(glass,"button").contains("font-size=\"11\""))
        XCTAssertTrue(try fragment(classic,"menu").contains("fill=\"var(--form-accent)\""))
        XCTAssertFalse(try fragment(glass,"menu").contains("fill=\"var(--form-accent)\""))
        XCTAssertTrue(classic.contains("--form-bg:#323232"))
        XCTAssertTrue(classic.contains("--form-control:#656565"))
        XCTAssertTrue(glass.contains("--form-bg:#fff;--form-control:#e1e1e1;--form-group:#f3f3f3"))
        XCTAssertTrue(glass.contains("--form-bg:#1e1e1e;--form-control:#383838"))
    }

    func testDarkPictureSubstitutionAndActiveSVGRejected() throws {
        let folder = try folder()
        try write(#"<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8"><rect width="8" height="8" fill="blue"/></svg>"#, "logo.svg", in: folder)
        try write(#"<svg xmlns="http://www.w3.org/2000/svg" width="9" height="9"><rect width="9" height="9" fill="white"/></svg>"#, "logo_dark.svg", in: folder)
        try write(#"<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>"#, "active.svg", in: folder)
        let url = try write(form(#"{"logo":{"type":"picture","left":0,"top":0,"picture":"logo.svg"},"bad":{"type":"picture","left":20,"top":0,"picture":"active.svg"}}"#), "form.4DForm", in: folder)
        let info = try analyze(url)
        XCTAssertEqual(info.images.count, 2)
        XCTAssertNotEqual(try object(info,theme:.classicLight,name:"logo").images["picture"],
                          try object(info,theme:.classicDark,name:"logo").images["picture"])
        XCTAssertNil(try object(info,name:"bad").images["picture"])
        XCTAssertTrue(info.warnings.joined().contains("SVG has unsupported"))
    }
}
