import XCTest
@testable import FourDFileKit

final class FormStaticTests: XCTestCase {
    private func analyze(_ url: URL, languages: [String] = ["en"]) throws -> FormFileInfo {
        try XCTUnwrap(FormFileAnalyzer(preferredLanguages: languages).analyze(ByteSource(url: url), options: AnalysisOptions()) as? FormFileInfo)
    }

    private func fixture() throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: "form", withExtension: "4DForm",
                                       subdirectory: "Fixtures/FormStaticProject/Project/Sources/Forms/Root"))
    }

    private func folder() throws -> URL {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/FormStaticTests-" + UUID().uuidString)
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

    private func form(_ objects: String = "{}", extra: String = "") -> String {
        #"{"pages":[{"objects":{}},{"objects":\#(objects)}]\#(extra)}"#
    }

    private func objects(_ info: FormFileInfo, page: Int = 1, theme: FormTheme = .classicLight) throws -> [FormObject] {
        try XCTUnwrap(info.appearances.first { $0.theme == theme }?.pages.first { $0.number == page }?.objects)
    }

    func testInheritedPagesLayeringDuplicateNamesAndProperties() throws {
        let info = try analyze(fixture())
        let background = try objects(info, page: 0)
        XCTAssertEqual(background.map(\.name), ["grandBackground", "grandMain", "shared", "basePageOne", "shared"])
        XCTAssertEqual(background[2].properties["text"]?.string, "Inherited base")
        XCTAssertEqual(background.last?.properties["text"]?.string, "Local")
        XCTAssertEqual(background[2].properties["textColor"]?.string, "#112233")
        XCTAssertNil(background[2].properties["fill"])
        XCTAssertEqual(background.last?.properties["textColor"]?.string, "#112233")
        XCTAssertEqual(info.properties["width"]?.double, 640)
        XCTAssertEqual(info.properties["windowTitle"]?.string, "Static forms")
        XCTAssertTrue(info.text.contains(":xliff:window"))
        XCTAssertEqual(background[2].source?.formName, "Base")
        XCTAssertEqual(background[3].source?.page, 1)
        XCTAssertEqual(try objects(info, page: 2).map(\.name), ["second"])
        XCTAssertFalse(info.appearances.flatMap(\.pages).flatMap(\.objects).contains { $0.name == "omitted" })
    }

    func testSubformsKeepLocalGeometryClipContractOrderImagesAndSource() throws {
        let info = try analyze(fixture())
        let panel = try XCTUnwrap(objects(info).first { $0.name == "panel" })
        XCTAssertEqual(panel.children.map(\.name), ["panelBackground", "picture", "nested"])
        XCTAssertEqual(panel.properties["left"]?.double, 100)
        XCTAssertEqual(panel.properties["width"]?.double, 120)
        XCTAssertEqual(panel.children[1].properties["left"]?.double, -5)
        XCTAssertEqual(panel.children[1].properties["width"]?.double, 160)
        XCTAssertEqual(panel.children[0].properties["textColor"]?.string, "#445566")
        XCTAssertEqual(panel.children[1].source?.document, "Project/Sources/Forms/Panel/form.4DForm")
        XCTAssertEqual(panel.children[2].children.first?.properties["text"]?.string, "Save")
        XCTAssertEqual(panel.children[2].children.first?.properties["left"]?.double, 2)
        XCTAssertFalse(panel.children[2].children.first?.source?.document.contains(FileManager.default.currentDirectoryPath) ?? true)
        XCTAssertNotNil(panel.embeddedProperties)
        XCTAssertEqual(info.images.count, 1)
        XCTAssertEqual(panel.children[1].images["picture"], info.images.first?.id)
        XCTAssertEqual(info.dependencies.filter { $0.hasSuffix("Panel/form.4DForm") }.count, 1)
        XCTAssertEqual(info.dependencies.filter { $0.hasSuffix("tile.svg") }.count, 1)
        XCTAssertTrue(info.warnings.allSatisfy {
            $0.contains("showing initial page") || $0.contains("inline detailForm object is noncanonical")
        }, "\(info.warnings)")
        XCTAssertTrue(info.warnings.contains {
            $0.contains("Subform nested:") && $0.contains("static approximation") &&
            $0.contains("native editor may show a placeholder") && $0.contains("No OBJECT SET SUBFORM command is executed")
        })
        XCTAssertEqual(panel.children[2].children.first?.source?.inline, true)
    }

    func testXLIFFExplicitNumericAutomaticAndRegionalFallback() throws {
        let info = try analyze(fixture(), languages: ["fr-CA"])
        XCTAssertEqual(info.localizationLanguage, "fr")
        XCTAssertEqual(info.properties["windowTitle"]?.string, "Formulaires statiques")
        let items = try objects(info)
        XCTAssertEqual(items.first { $0.name == "explicit" }?.properties["text"]?.string, "Enregistrer")
        XCTAssertEqual(items.first { $0.name == "explicit" }?.properties["tooltip"]?.string, "Enregistrer les modifications")
        XCTAssertEqual(items.first { $0.name == "automatic" }?.properties["text"]?.string, "Traduction par nom d'objet")
        XCTAssertEqual(items.first?.children.last?.children.first?.properties["text"]?.string, "Enregistrer")
        XCTAssertEqual(info.dependencies.filter { $0.contains(".lproj") }.count, 1)
        XCTAssertTrue(info.dependencies.contains { $0.hasSuffix(".xliff") })
    }

    func testEnglishFallbackAndUnsupportedLocaleNotice() throws {
        let info = try analyze(fixture(), languages: ["xx-invalid", "ja"])
        XCTAssertEqual(info.localizationLanguage, "en")
        XCTAssertTrue(info.warnings.contains { $0.contains("Unsupported preview locale") })
    }

    func testStaticPathFormAndPointerOverrideUseDependencyBase() throws {
        let folder = try folder()
        try write(form(#"{"title":{"$ref":"parts.json#/label","width":99}}"#), "deps/detail.json", in: folder)
        try write(#"{"label":{"type":"text","text":"Template","width":50,"picture":"pic.svg"}}"#, "deps/parts.json", in: folder)
        try write(#"<svg width="8" height="8"><rect width="8" height="8"/></svg>"#, "deps/pic.svg", in: folder)
        let root = try write(form(#"{"panel":{"type":"subform","detailForm":"deps/detail.json","left":1,"top":2,"width":100,"height":50}}"#), "form.4DForm", in: folder)
        let info = try analyze(root)
        let child = try XCTUnwrap(objects(info).first?.children.first)
        XCTAssertEqual(child.properties["width"]?.double, 99)
        XCTAssertEqual(child.properties["picture"]?.string, "deps/pic.svg")
        XCTAssertEqual(info.images.count, 1)
        XCTAssertEqual(info.warnings, [])
    }

    func testFormReferenceInsideExternalPointerIsRebased() throws {
        let folder = try folder()
        try write(form(#"{"text":{"type":"text","text":"External"}}"#), "deps/child.json", in: folder)
        try write(#"{"panel":{"type":"subform","detailForm":"child.json","left":0,"top":0,"width":100,"height":50}}"#, "deps/template.json", in: folder)
        let url = try write(form(#"{"panel":{"$ref":"deps/template.json#/panel"}}"#), "form.4DForm", in: folder)
        let info = try analyze(url)
        XCTAssertEqual(try objects(info).first?.children.first?.properties["text"]?.string, "External")
        XCTAssertEqual(info.warnings, [])
    }

    func testSubformCycleKeepsContainersAndLocalContent() throws {
        let folder = try folder()
        let a = try write(form(#"{"label":{"type":"text","text":"A"},"panel":{"type":"subform","detailForm":"b.json"}}"#), "a.4DForm", in: folder)
        try write(form(#"{"label":{"type":"text","text":"B"},"panel":{"type":"subform","detailForm":"a.4DForm"}}"#), "b.json", in: folder)
        let info = try analyze(a)
        let children = try XCTUnwrap(objects(info).last?.children)
        XCTAssertEqual(children.first?.properties["text"]?.string, "B")
        XCTAssertEqual(children.last?.type, "subform")
        XCTAssertEqual(children.last?.children.count, 0)
        XCTAssertTrue(info.warnings.contains { $0.contains("cycle or depth 64") && $0.contains("placeholder") })
    }

    func testInheritedCycleKeepsAllNoncyclicObjects() throws {
        let folder = try folder()
        let a = try write(form(#"{"a":{"type":"text","text":"A"}}"#, extra: #","inheritedForm":"b.json""#), "a.4DForm", in: folder)
        try write(form(#"{"b":{"type":"text","text":"B"}}"#, extra: #","inheritedForm":"a.4DForm""#), "b.json", in: folder)
        let info = try analyze(a)
        XCTAssertEqual(try objects(info, page: 0).map(\.name), ["b"])
        XCTAssertEqual(try objects(info).map(\.name), ["a"])
        XCTAssertTrue(info.warnings.contains { $0.contains("Inherited form:") && $0.contains("cycle") })
    }

    func testDynamicListMissingAndComponentSubformsArePlaceholders() throws {
        let folder = try folder()
        let url = try write(form(#"{"dynamic":{"type":"subform","detailForm":{"expression":"Form.name"}},"list":{"type":"subform","listForm":"Rows","detailForm":"Detail","table":1},"component":{"type":"subform","detailForm":"Widget:Clock"},"missing":{"type":"subform","detailForm":"missing.json"}}"#), "form.4DForm", in: folder)
        let info = try analyze(url)
        XCTAssertEqual(try objects(info).count, 4)
        XCTAssertTrue(try objects(info).allSatisfy { $0.children.isEmpty })
        XCTAssertEqual(info.warnings.count, 4)
        XCTAssertEqual(info.dependencies, [])
    }

    func testConfinementAfterSymlinksAndTraversal() throws {
        let folder = try folder()
        let outside = try write(form(#"{"private":{"type":"text","text":"DO NOT READ"}}"#), "outside/child.json", in: folder)
        let rootFolder = folder.appendingPathComponent("standalone")
        try FileManager.default.createDirectory(at: rootFolder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: rootFolder.appendingPathComponent("link.json"), withDestinationURL: outside)
        let url = try write(form(#"{"symlink":{"type":"subform","detailForm":"link.json"},"escape":{"type":"subform","detailForm":"../outside/child.json"}}"#), "form.4DForm", in: rootFolder)
        let info = try analyze(url)
        XCTAssertTrue(try objects(info).allSatisfy { $0.children.isEmpty })
        XCTAssertTrue(info.warnings.contains { $0.contains("escapes") })
        XCTAssertEqual(info.dependencies, [])
    }

    func testStaticNamedAndNumberedTableInheritanceAndObjectLocalization() throws {
        let folder = try folder()
        try write(#"<base><table name="Customers" id="7"/></base>"#, "Project/Sources/catalog.4DCatalog", in: folder)
        try write(form(#"{"button":{"type":"button","text":"Save"}}"#), "Project/Sources/TableForms/7/Input/Detail/form.4DForm", in: folder)
        try write(xliff(#"<group resname="[Customers]"><group resname="Detail"><trans-unit resname="button"><source>Save</source><target>Customer save</target></trans-unit></group></group>"#), "Resources/en.lproj/strings.xlf", in: folder)
        for table in [#""[Customers]""#, "7"] {
            let url = try write(form(extra: #","inheritedForm":"Detail","inheritedFormTable":\#(table)"#), "Project/Sources/Forms/Root/form.4DForm", in: folder)
            let info = try analyze(url)
            XCTAssertEqual(try objects(info, page: 0).first?.properties["text"]?.string, "Customer save")
            XCTAssertEqual(try objects(info, page: 0).first?.source?.tableName, "Customers")
            XCTAssertEqual(info.warnings, [])
        }
    }

    func testAmbiguousTableFormIsNotGuessed() throws {
        let folder = try folder()
        for direction in ["Input", "Output"] {
            try write(form(), "Project/Sources/TableForms/1/\(direction)/Detail/form.4DForm", in: folder)
        }
        let url = try write(form(extra: #","inheritedForm":"Detail","inheritedFormTable":1"#), "Project/Sources/Forms/Root/form.4DForm", in: folder)
        let info = try analyze(url)
        XCTAssertTrue(info.warnings.contains { $0.contains("ambiguous inherited table form") })
    }

    private func xliff(_ units: String, language: String = "en", version: String = "1.2") -> String {
        #"<xliff version="\#(version)"><file source-language="en" target-language="\#(language)"><body>\#(units)</body></file></xliff>"#
    }

    private func localized(_ files: [(String, String)], languages: [String] = ["en"], text: String = ":xliff:key") throws -> FormFileInfo {
        let folder = try folder()
        for (path, data) in files { try write(data, "Resources/" + path, in: folder) }
        let url = try write(form(#"{"label":{"type":"text","text":"\#(text)"}}"#), "Project/Sources/Forms/Root/form.4DForm", in: folder)
        return try analyze(url, languages: languages)
    }

    func testXMLPredefinedEntitiesUnicodeAndCDATA() throws {
        let info = try localized([("en.lproj/a.xlf", xliff(#"<trans-unit resname="key"><source>Source</source><target>日本 &amp; &lt;![CDATA[ literal ]]&gt;</target></trans-unit>"#))])
        XCTAssertEqual(try objects(info).first?.properties["text"]?.string, "日本 & <![CDATA[ literal ]]>")
        let cdata = try localized([("en.lproj/a.xlf", xliff(#"<trans-unit resname="key"><target><![CDATA[<safe> & text]]></target></trans-unit>"#))])
        XCTAssertEqual(try objects(cdata).first?.properties["text"]?.string, "<safe> & text")
    }

    func testDTDEntitiesInlineContentAndXLIFF2AreRejectedVisibly() throws {
        let bad = [
            #"<!DOCTYPE xliff [<!ENTITY secret SYSTEM "file:///etc/passwd">]>"# + xliff(#"<trans-unit resname="key"><target>&secret;</target></trans-unit>"#),
            xliff(#"<trans-unit resname="key"><target>before<g>inline</g>after</target></trans-unit>"#),
            xliff(#"<trans-unit resname="key"><target>Wrong</target></trans-unit>"#, version: "2.0"),
            #"<xliff version="1.2"><file><body>"#
        ]
        for xml in bad {
            let info = try localized([("en.lproj/a.xlf", xml)])
            XCTAssertEqual(try objects(info).first?.properties["text"]?.string, ":xliff:key")
            XCTAssertTrue(info.warnings.contains { $0.contains("XLIFF a.xlf") })
        }
    }

    func testPureInternalDTDEntityIsRejectedWithOriginalTextAndNotice() throws {
        let xml = #"<!DOCTYPE xliff [<!ENTITY replacement "INTERNAL ENTITY MUST NOT EXPAND">]>"# +
            xliff(#"<trans-unit resname="key"><target>&replacement;</target></trans-unit>"#)
        let info = try localized([("en.lproj/a.xlf", xml)])
        for theme in FormTheme.allCases {
            XCTAssertEqual(try objects(info, theme: theme).first?.properties["text"]?.string, ":xliff:key")
        }
        XCTAssertTrue(info.text.contains(":xliff:key"))
        XCTAssertTrue(info.warnings.contains {
            $0.contains("XLIFF a.xlf") && $0.contains("without DTD/entities") && $0.contains("original text retained")
        })
        XCTAssertEqual(info.dependencies, ["Resources/en.lproj/a.xlf"])
    }

    func testForeignXLIFFNamespaceIsRejectedWithOriginalTextAndNotice() throws {
        let documents = [
            #"<xliff xmlns="urn:test:foreign" version="1.2"><file source-language="en" target-language="en"><body><trans-unit resname="key"><target>FOREIGN NAMESPACE MUST NOT TRANSLATE</target></trans-unit></body></file></xliff>"#,
            #"<xliff xmlns="urn:oasis:names:tc:xliff:document:1.2" version="1.2"><file source-language="en" target-language="en"><body><trans-unit resname="key"><target xmlns="urn:test:foreign">FOREIGN NAMESPACE MUST NOT TRANSLATE</target></trans-unit></body></file></xliff>"#
        ]
        for xml in documents {
            let info = try localized([("en.lproj/a.xlf", xml)])
            for theme in FormTheme.allCases {
                XCTAssertEqual(try objects(info, theme: theme).first?.properties["text"]?.string, ":xliff:key")
            }
            XCTAssertTrue(info.text.contains(":xliff:key"))
            XCTAssertTrue(info.warnings.contains {
                $0.contains("XLIFF a.xlf") && $0.contains("Invalid/unsupported XLIFF") && $0.contains("original text retained")
            })
            XCTAssertEqual(info.dependencies, ["Resources/en.lproj/a.xlf"])
        }
    }

    func testDuplicateTranslationsAreNotGuessedAndISOFoldersPrecedeLegacy() throws {
        let first = xliff(#"<trans-unit resname="key"><target>First</target></trans-unit>"#)
        let second = xliff(#"<trans-unit resname="key"><target>Second</target></trans-unit>"#)
        let duplicates = try localized([("en.lproj/a.xlf", first), ("en.lproj/b.xlf", second)])
        XCTAssertEqual(try objects(duplicates).first?.properties["text"]?.string, ":xliff:key")
        XCTAssertTrue(duplicates.warnings.contains { $0.contains("Ambiguous XLIFF translation") })
        let folders = try localized([("en.lproj/a.xlf", first), ("english.lproj/b.xlf", second)])
        XCTAssertEqual(folders.localizationLanguage, "en")
        XCTAssertEqual(try objects(folders).first?.properties["text"]?.string, "First")
        XCTAssertEqual(folders.warnings, [])
    }

    func testMissingTargetMismatchedLanguageAndCaseSensitivityRetainReferences() throws {
        for xml in [
            xliff(#"<trans-unit resname="key"><source>Do not invent translation</source></trans-unit>"#),
            xliff(#"<trans-unit resname="key"><target>Bonjour</target></trans-unit>"#, language: "fr"),
            xliff(#"<trans-unit resname="Key"><target>Case sensitive</target></trans-unit>"#)
        ] {
            let info = try localized([("en.lproj/a.xlf", xml)])
            XCTAssertEqual(try objects(info).first?.properties["text"]?.string, ":xliff:key")
            XCTAssertFalse(info.warnings.isEmpty)
        }
    }

    func testAmbiguousLastLocaleFallbackDoesNotPickAnArbitraryLanguage() throws {
        let info = try localized([
            ("fr.lproj/a.xlf", xliff(#"<trans-unit resname="key"><target>French</target></trans-unit>"#, language: "fr")),
            ("de.lproj/a.xlf", xliff(#"<trans-unit resname="key"><target>German</target></trans-unit>"#, language: "de"))
        ], languages: ["ja"])
        XCTAssertNil(info.localizationLanguage)
        XCTAssertTrue(info.warnings.contains { $0.contains("Ambiguous XLIFF fallback locale") })
    }

    func testXLIFFResourceSymlinkCannotEscapeProject() throws {
        let folder = try folder()
        let outside = folder.appendingPathComponent("outside")
        try write(xliff(#"<trans-unit resname="key"><target>DO NOT READ</target></trans-unit>"#), "en.lproj/a.xlf", in: outside)
        let project = folder.appendingPathComponent("package")
        let url = try write(form(#"{"label":{"type":"text","text":":xliff:key"}}"#), "Project/Sources/Forms/Root/form.4DForm", in: project)
        try FileManager.default.createSymbolicLink(at: project.appendingPathComponent("Resources"), withDestinationURL: outside)
        let info = try analyze(url)
        XCTAssertEqual(try objects(info).first?.properties["text"]?.string, ":xliff:key")
        XCTAssertEqual(info.dependencies, [])
        XCTAssertTrue(info.warnings.contains { $0.contains("escapes") })
    }

    func testObjectAndDependencyLimitsKeepMeaningfulContainers() throws {
        let folder = try folder()
        let members = (0..<1_100).map { #""label\#($0)":{"type":"text","text":"\#($0)"}"# }.joined(separator: ",")
        try write(form("{\(members)}"), "child.json", in: folder)
        let url = try write(form(#"{"panel":{"type":"subform","detailForm":"child.json","width":100,"height":50}}"#), "form.4DForm", in: folder)
        let info = try analyze(url)
        XCTAssertEqual(try objects(info).first?.children.count, 999)
        XCTAssertTrue(info.warnings.contains { $0.contains("1,000 static form objects") })
        try write(String(repeating: " ", count: 4 * 1024 * 1024 + 1), "child.json", in: folder)
        let oversized = try analyze(url)
        XCTAssertEqual(try objects(oversized).first?.children.count, 0)
        XCTAssertTrue(oversized.warnings.contains { $0.contains("4 MiB") && $0.contains("placeholder") })
    }

    func testStaticDepthAndReadCountLimitsAreVisible() throws {
        let folder = try folder()
        for index in 0..<70 {
            try write(form(#"{"label":{"type":"text","text":"\#(index)"},"panel":{"type":"subform","detailForm":"f\#(index + 1).json"}}"#), "f\(index).json", in: folder)
        }
        let info = try analyze(folder.appendingPathComponent("f0.json"))
        XCTAssertTrue(info.warnings.contains { $0.contains("64") && $0.contains("placeholder") })
        XCTAssertLessThanOrEqual(info.dependencies.count, 64)
        var child = try XCTUnwrap(objects(info).last)
        var depth = 0
        while let next = child.children.last { depth += 1; child = next }
        XCTAssertLessThanOrEqual(depth, 64)
        XCTAssertEqual(child.type, "subform")
    }

    func testXMLDepthLimitAndReferenceLocationsDoNotEvaluateExpressions() throws {
        let nested = String(repeating: "<group>", count: 70) +
            #"<trans-unit resname="key"><target>Too deep</target></trans-unit>"# + String(repeating: "</group>", count: 70)
        let info = try localized([("en.lproj/a.xlf", xliff(nested))])
        XCTAssertTrue(info.warnings.contains { $0.contains("depth 64") })
        let folder = try folder()
        try write(xliff(#"<trans-unit resname="key"><target>Translated</target></trans-unit>"#), "Resources/en.lproj/a.xlf", in: folder)
        let url = try write(form(#"{"input":{"type":"input","dataSource":":xliff:key","method":":xliff:key","text":"prefix :xliff:key"},"tabs":{"type":"tab","labels":[":xliff:key","Plain"]}}"#),
                            "Project/Sources/Forms/Root/form.4DForm", in: folder)
        let result = try analyze(url)
        XCTAssertEqual(try objects(result).first?.properties["dataSource"]?.string, ":xliff:key")
        XCTAssertEqual(try objects(result).first?.properties["method"]?.string, ":xliff:key")
        XCTAssertEqual(try objects(result).first?.properties["text"]?.string, "prefix :xliff:key")
        XCTAssertEqual(try objects(result).last?.properties["labels"]?.values.first?.string, "Translated")
    }

    func testInlineInheritanceAndZeroTableRespectLocalProperties() throws {
        let folder = try folder()
        let inherited = form(#"{"same":{"type":"text","text":"Inherited","left":8}}"#)
        let url = try write(form(#"{"same":{"type":"text","text":"Local","left":9}}"#,
                                 extra: #","width":100,"inheritedForm":\#(inherited),"inheritedFormTable":0"#),
                            "form.4DForm", in: folder)
        let info = try analyze(url)
        XCTAssertEqual(try objects(info, page: 0).first?.properties["left"]?.double, 8)
        XCTAssertEqual(try objects(info).first?.properties["left"]?.double, 9)
        XCTAssertEqual(info.properties["width"]?.double, 100)
        XCTAssertEqual(info.warnings.count, 1)
        XCTAssertTrue(info.warnings.contains {
            $0.contains("inline inheritedForm object is noncanonical") && $0.contains("not native editor equivalence")
        })
    }

    func testInlineSubformIsVisiblyNoncanonicalDynamicInputApproximation() throws {
        let folder = try folder()
        let inline = form(#"{"label":{"type":"text","text":"Literal dynamic-form description","left":2,"top":3}}"#)
        let url = try write(form(#"{"panel":{"type":"subform","detailForm":\#(inline),"left":10,"top":20,"width":50,"height":30}}"#),
                            "form.4DForm", in: folder)
        let info = try analyze(url)
        let panel = try XCTUnwrap(objects(info).first)
        XCTAssertEqual(panel.children.first?.properties["text"]?.string, "Literal dynamic-form description")
        XCTAssertEqual(panel.children.first?.source?.inline, true)
        XCTAssertNotNil(panel.embeddedProperties)
        XCTAssertEqual(info.dependencies, [])
        XCTAssertEqual(info.warnings.count, 1)
        XCTAssertTrue(info.warnings.contains {
            $0.contains("inline detailForm object is noncanonical .4DForm schema") &&
            $0.contains("static approximation") && $0.contains("native editor may show a placeholder") &&
            $0.contains("No OBJECT SET SUBFORM command is executed")
        })
    }

    func testLanguageSpecificityWithinFilesAndObjectNameReferences() throws {
        let folder = try folder()
        try write(xliff(#"<trans-unit resname="key"><target>Generic French</target></trans-unit>"#, language: "fr"),
                  "Resources/fr-ca.lproj/a.xlf", in: folder)
        try write(xliff(#"<trans-unit resname="key"><target>Canadian French</target></trans-unit>"#, language: "fr-CA"),
                  "Resources/fr-ca.lproj/b.xlf", in: folder)
        let url = try write(form(#"{":xliff:key":{"type":"button","text":"Original"},"explicit":{"type":"button","text":":xliff:key"}}"#),
                            "Project/Sources/Forms/Root/form.4DForm", in: folder)
        let info = try analyze(url, languages: ["fr-CA"])
        XCTAssertTrue(try objects(info).allSatisfy { $0.properties["text"]?.string == "Canadian French" })
        XCTAssertEqual(info.warnings, [])
    }

    func testUnsupportedXLIFFUnitDoesNotDiscardOtherStaticTranslations() throws {
        let units = #"<trans-unit resname="unsupported"><target><g>Inline</g></target></trans-unit><trans-unit resname="key"><target>Supported</target></trans-unit>"#
        let info = try localized([("en.lproj/a.xlf", xliff(units))])
        XCTAssertEqual(try objects(info).first?.properties["text"]?.string, "Supported")
        XCTAssertTrue(info.warnings.contains { $0.contains("Unsupported inline content") })
    }

    func testFileCountAndTotalByteBudgetLeaveFailedSubformsAsPlaceholders() throws {
        let folder = try folder()
        var members: [String] = []
        for index in 0..<70 {
            try write(form(#"{"label":{"type":"text","text":"Small"}}"#), "f\(index).json", in: folder)
            members.append(#""panel\#(index)":{"type":"subform","detailForm":"f\#(index).json"}"#)
        }
        let url = try write(form("{\(members.joined(separator: ","))}"), "form.4DForm", in: folder)
        let info = try analyze(url)
        XCTAssertEqual(info.dependencies.count, 64)
        XCTAssertEqual(try objects(info).count, 70)
        XCTAssertEqual(try objects(info).last?.children.count, 0)
        XCTAssertTrue(info.warnings.contains { $0.contains("64 dependency files") })

        let bigFolder = try self.folder()
        let large = form(#"{"label":{"type":"text","text":"\#(String(repeating: "x", count: 3_500_000))"}}"#)
        members = []
        for index in 0..<5 {
            try write(large, "f\(index).json", in: bigFolder)
            members.append(#""panel\#(index)":{"type":"subform","detailForm":"f\#(index).json"}"#)
        }
        let bigURL = try write(form("{\(members.joined(separator: ","))}"), "form.4DForm", in: bigFolder)
        let largeInfo = try analyze(bigURL)
        XCTAssertEqual(largeInfo.dependencies.count, 4)
        XCTAssertEqual(try objects(largeInfo).last?.children.count, 0)
        XCTAssertTrue(largeInfo.warnings.contains { $0.contains("16 MiB") && $0.contains("placeholder") })
    }

    func testAggregateExpansionAndXMLTextBudgetsAreVisible() throws {
        let folder = try folder()
        let metadata = String(repeating: "null,", count: 29_999) + "null"
        try write(form(#"{"label":{"type":"text","text":"Child"}}"#, extra: #","metadata":[\#(metadata)]"#), "child.json", in: folder)
        let members = (0..<5).map { #""panel\#($0)":{"type":"subform","detailForm":"child.json"}"# }.joined(separator: ",")
        let url = try write(form("{\(members)}"), "form.4DForm", in: folder)
        let info = try analyze(url)
        XCTAssertTrue(info.warnings.contains { $0.contains("100,000") && $0.contains("placeholder") })
        XCTAssertEqual(try objects(info).last?.children.count, 0)
        XCTAssertEqual(info.dependencies, ["child.json"])

        let unit = #"<trans-unit resname="key"><target>\#(String(repeating: "x", count: 1_048_577))</target></trans-unit>"#
        let xmlInfo = try localized([("en.lproj/a.xlf", xliff(unit))])
        XCTAssertEqual(try objects(xmlInfo).first?.properties["text"]?.string, ":xliff:key")
        XCTAssertTrue(xmlInfo.warnings.contains { $0.contains("1 MiB text") })
    }

    func testEmptyFormStillReportsMissingStylesheetAndNumberedPageLimit() throws {
        let folder = try folder()
        let url = try write(form(extra: #","css":"missing.css""#), "form.4DForm", in: folder)
        XCTAssertTrue(try analyze(url).warnings.contains { $0.contains("missing.css") })
        let pages = (0..<20).map { _ in #"{"objects":{}}"# }.joined(separator: ",")
        try write(#"{"pages":[\#(pages)]}"#, "form.4DForm", in: folder)
        let info = try analyze(url)
        XCTAssertEqual(info.appearances.first?.pages.count, 17)
        XCTAssertTrue(info.warnings.contains { $0.contains("first 16 numbered pages") })
    }
}
