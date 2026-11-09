import XCTest
@testable import FourDFileKit
@testable import FourDRender

final class CatalogTests: XCTestCase {
    private func file(_ data: Data, ext: String = "4DCatalog") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func analyze(_ xml: String) throws -> CatalogInfo {
        let url = try file(Data(xml.utf8))
        let model = try AnalyzerRegistry.default.analyze(url: url)
        return try XCTUnwrap(model as? CatalogInfo)
    }

    private func fixture() throws -> CatalogInfo {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/catalog", withExtension: "4DCatalog"))
        return try XCTUnwrap(try AnalyzerRegistry.default.analyze(url: url) as? CatalogInfo)
    }

    private func catalogWithEditor(_ xml: String, editor: Data) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("catalog.4DCatalog")
        try Data(xml.utf8).write(to: url)
        try editor.write(to: folder.appendingPathComponent("catalog_editor.json"))
        return url
    }

    func testExternalEditorCoordinatesOverrideEmbeddedAndKeepUnspecifiedPositions() throws {
        let xml = """
        <base>
          <table name="A"><table_extra><editor_table_info><coordinates left="1" top="2"/></editor_table_info></table_extra></table>
          <table name="B"><table_extra><editor_table_info><coordinates left="600" top="2"/></editor_table_info></table_extra></table>
          <table name="顧客"/>
        </base>
        """
        let editor = """
        {"tables":{"A":{"coordinates":{"left":"-20.5","top":"30.25","width":"120","height":"200"}},
        "顧客":{"coordinates":{"left":20000,"top":30000}},"Removed":{"coordinates":{"left":1,"top":1}}}}
        """
        let url = try catalogWithEditor(xml, editor: Data(editor.utf8))
        let info = try XCTUnwrap(try AnalyzerRegistry.default.analyze(url: url) as? CatalogInfo)
        XCTAssertEqual(info.tables[0].position?.x, -20.5)
        XCTAssertEqual(info.tables[0].position?.y, 30.25)
        XCTAssertEqual(info.tables[1].position?.x, 600)
        XCTAssertEqual(info.tables[1].position?.y, 2)
        XCTAssertEqual(info.tables[2].position?.x, 20000)
        XCTAssertEqual(info.tables[2].position?.y, 30000)
        XCTAssertTrue(info.warnings.isEmpty)
        let html = PreviewPipeline().html(for: url)
        XCTAssertTrue(html.contains("data-node-id=\"2\" transform=\"translate(20044.5 30022.0)\""))
        XCTAssertTrue(html.contains("width=\"20284.5\" height=\"30080.0\""))
    }

    func testInvalidEditorFilesWarnAndRetainEmbeddedLayout() throws {
        let xml = """
        <base><table name="A"><table_extra><editor_table_info><coordinates left="7" top="8"/></editor_table_info></table_extra></table></base>
        """
        for editor in [
            Data("not JSON".utf8), Data(#"{"tables":[]}"#.utf8),
            Data(#"{"tables":{"A":{"coordinates":{"left":"NaN","top":1}}}}"#.utf8),
            Data(#"{"tables":{"A":{"coordinates":{"left":true,"top":1}}}}"#.utf8),
            Data(#"{"tables":{"A":{"coordinates":{"left":1}}}}"#.utf8),
            Data(#"{"tables":{"A":null}}"#.utf8),
            Data(count: 4 * 1024 * 1024 + 1),
            Data((String(repeating: "[", count: 66) + "0" + String(repeating: "]", count: 66)).utf8)
        ] {
            let url = try catalogWithEditor(xml, editor: editor)
            let info = try XCTUnwrap(try AnalyzerRegistry.default.analyze(url: url) as? CatalogInfo)
            XCTAssertEqual(info.tables[0].position?.x, 7)
            XCTAssertEqual(info.tables[0].position?.y, 8)
            XCTAssertTrue(info.warnings.contains { $0.contains("catalog_editor.json") })
            XCTAssertTrue(PreviewPipeline().html(for: url).contains("Parser notes"))
        }
    }

    func testEmptyEditorAndAmbiguousNames() throws {
        let url = try catalogWithEditor("<base><table name=\"A\"/></base>", editor: Data(#"{"tables":{}}"#.utf8))
        let info = try XCTUnwrap(try AnalyzerRegistry.default.analyze(url: url) as? CatalogInfo)
        XCTAssertNil(info.tables[0].position)
        XCTAssertTrue(info.warnings.isEmpty)
        let ambiguousURL = try catalogWithEditor("<base><table name=\"A\"/><table name=\"A\"/></base>",
            editor: Data(#"{"tables":{"A":{"coordinates":{"left":1,"top":2}}}}"#.utf8))
        let ambiguous = try XCTUnwrap(try AnalyzerRegistry.default.analyze(url: ambiguousURL) as? CatalogInfo)
        XCTAssertTrue(ambiguous.tables.allSatisfy { $0.position == nil })
        XCTAssertTrue(ambiguous.warnings.contains { $0.contains("ambiguous editor layout") })
    }

    func testEditorSymlinkCannotEscapeCatalogFolder() throws {
        let url = try catalogWithEditor("<base><table name=\"A\"/></base>", editor: Data())
        let editorURL = url.deletingLastPathComponent().appendingPathComponent("catalog_editor.json")
        let outside = try file(Data(#"{"tables":{"A":{"coordinates":{"left":9,"top":9}}}}"#.utf8), ext: "json")
        try FileManager.default.removeItem(at: editorURL)
        try FileManager.default.createSymbolicLink(at: editorURL, withDestinationURL: outside)
        let info = try XCTUnwrap(try AnalyzerRegistry.default.analyze(url: url) as? CatalogInfo)
        XCTAssertNil(info.tables[0].position)
        XCTAssertTrue(info.warnings.contains { $0.contains("escapes the catalog folder") })
    }

    func testCatalogModelAndUUIDResolution() throws {
        let info = try fixture()
        XCTAssertEqual(info.kind, "catalog.structure")
        XCTAssertEqual(info.name, "Catalog Fixture")
        XCTAssertEqual(info.schemas, ["DEFAULT_SCHEMA"])
        XCTAssertEqual(info.tables.count, 2)
        XCTAssertEqual(info.tables.map(\.number), [7, 42])
        XCTAssertEqual(info.tables[0].fields.map(\.typeName), ["Long Integer", "Alpha (40)", "Text", "Object"])
        XCTAssertTrue(info.tables[0].fields[0].primaryKey)
        XCTAssertTrue(info.tables[0].fields[0].notNull)
        XCTAssertTrue(info.tables[0].fields[0].autoSequence)
        XCTAssertEqual(info.tables[0].fields[0].indexUUIDs, ["CLIENT-INDEX"])
        XCTAssertTrue(info.tables[0].fields[3].hidden)
        XCTAssertTrue(info.tables[1].hidden)
        XCTAssertTrue(info.tables[1].encryptable)
        XCTAssertEqual(info.tables[0].position?.x, -20.5)
        XCTAssertEqual(info.tables[1].fields[2].typeName, "Type 999")
        XCTAssertEqual(info.indexCount, 1)
        let relation = try XCTUnwrap(info.relations.first)
        XCTAssertEqual(relation.source.tableIndex, 1)
        XCTAssertEqual(relation.source.fieldIndex, 1)
        XCTAssertEqual(relation.source.label, "[Invoices]Client_ID")
        XCTAssertEqual(relation.destination.label, "[Clients]ID")
        XCTAssertEqual(relation.name, "Client")
        XCTAssertEqual(relation.inverseName, "Invoices")
        XCTAssertTrue(relation.autoLoadManyToOne)
        XCTAssertFalse(relation.autoLoadOneToMany)
        XCTAssertTrue(relation.foreignKey)
        XCTAssertEqual(relation.integrity, "reject")
        XCTAssertTrue(info.warnings.isEmpty)
        let json = try JSONSerialization.jsonObject(with: info.jsonData()) as? [String: Any]
        XCTAssertEqual(json?["kind"] as? String, "catalog.structure")
        XCTAssertEqual((json?["relations"] as? [[String: Any]])?.count, 1)
    }

    func testRegistryAndUTIWithoutExtension() throws {
        XCTAssertTrue(AnalyzerRegistry.default.allContentTypes.contains("com.4d.4d.catalog"))
        let url = try file(Data("<base/>".utf8), ext: "unknown")
        XCTAssertEqual(try AnalyzerRegistry.default.analyze(url: url, contentType: "com.4d.4d.catalog").kind, "catalog.structure")
        let mixed = try file(Data("<base/>".utf8), ext: "4dCaTaLoG")
        XCTAssertEqual(try AnalyzerRegistry.default.analyze(url: mixed).kind, "catalog.structure")
    }

    func testEmptyAndUnknownElements() throws {
        let empty = try analyze("<base><unknown><table name=\"Not a table\"/></unknown></base>")
        XCTAssertTrue(empty.tables.isEmpty)
        XCTAssertTrue(empty.relations.isEmpty)
        XCTAssertTrue(empty.warnings.isEmpty)
        let report = try XCTUnwrap(CatalogPresenter().report(for: empty))
        XCTAssertTrue(report.stats.isEmpty)
        XCTAssertEqual(report.sections.first?.title, "Structure diagram")
        XCTAssertTrue(HTMLRenderer().render(report).contains("No tables."))
        XCTAssertFalse(HTMLRenderer().render(report).contains("<svg"))
    }

    func testMalformedXMLAndWrongRootReportErrors() throws {
        for xml in ["", "not XML", "<base><table></base>", "<other><table name=\"A\"/></other>"] {
            let url = try file(Data(xml.utf8))
            XCTAssertThrowsError(try AnalyzerRegistry.default.analyze(url: url))
            let html = PreviewPipeline().html(for: url)
            XCTAssertTrue(html.contains("No preview available"))
            XCTAssertTrue(html.contains("invalid 4D catalog"))
        }
    }

    func testEntitiesCannotReadFilesOrExpand() throws {
        for declaration in [
            "<!ENTITY secret SYSTEM \"file:///etc/passwd\">",
            "<!ENTITY secret \"expanded\">",
        ] {
            let url = try file(Data("<!DOCTYPE base [\(declaration)]><base name=\"&secret;\"/>".utf8))
            XCTAssertThrowsError(try AnalyzerRegistry.default.analyze(url: url))
            XCTAssertFalse(PreviewPipeline().html(for: url).contains("root:"))
        }
        let info = try analyze("<!DOCTYPE base SYSTEM \"file:///does-not-exist.dtd\"><base name=\"offline\"/>")
        XCTAssertEqual(info.name, "offline")
    }

    func testEncodedCatalogs() throws {
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-16\"?><base name=\"日本語\"><table name=\"顧客\"/></base>"
        for encoding in [String.Encoding.utf16LittleEndian, .utf16BigEndian] {
            var data = Data(encoding == .utf16LittleEndian ? [0xff, 0xfe] : [0xfe, 0xff])
            data.append(try XCTUnwrap(xml.data(using: encoding)))
            let info = try XCTUnwrap(try AnalyzerRegistry.default.analyze(url: file(data)) as? CatalogInfo)
            XCTAssertEqual(info.name, "日本語")
            XCTAssertEqual(info.tables.first?.name, "顧客")
        }
        let legacy = "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?><base name=\"Café\"/>"
        let info = try XCTUnwrap(try AnalyzerRegistry.default.analyze(url: file(XCTUnwrap(legacy.data(using: .isoLatin1)))) as? CatalogInfo)
        XCTAssertEqual(info.name, "Café")
    }

    func testDiagnosticsAndNameFallback() throws {
        let info = try analyze("""
        <base>
          <table name="A"><field name="ID" type="invalid"/><primary_key field_name="ID"/></table>
          <table/><table name="B"><field/><field name="ID" type="4"/></table>
          <relation>
            <related_field kind="source"><field_ref name="ID"><table_ref name="A"/></field_ref></related_field>
            <related_field kind="destination"><field_ref name="Missing"><table_ref name="B"/></field_ref></related_field>
          </relation>
          <relation/>
        </base>
        """)
        XCTAssertEqual(info.tables.count, 2)
        XCTAssertTrue(info.tables[0].fields[0].primaryKey)
        XCTAssertEqual(info.relations.count, 1)
        XCTAssertEqual(info.relations[0].source.tableIndex, 0)
        XCTAssertNil(info.relations[0].destination.fieldIndex)
        XCTAssertTrue(info.warnings.contains { $0.contains("Unresolved relation") })
        XCTAssertTrue(info.warnings.contains { $0.contains("Unknown field type") })
        XCTAssertTrue(info.warnings.contains { $0.contains("Skipped a table") })
        XCTAssertTrue(info.warnings.contains { $0.contains("Skipped a field") })
        XCTAssertTrue(info.warnings.contains { $0.contains("Skipped a relation") })
    }

    func testAmbiguousNamesDoNotResolveArbitrarily() throws {
        let info = try analyze("""
        <base><table name="A"><field name="ID" type="4"/><field name="ID" type="4"/><primary_key field_name="ID"/></table></base>
        """)
        XCTAssertFalse(info.tables[0].fields.contains { $0.primaryKey })
        XCTAssertTrue(info.warnings.contains { $0.contains("Unresolved primary key") })
    }

    func testDiagramLeadsAndMetadataIsCollapsed() throws {
        let info = try fixture()
        let report = try XCTUnwrap(CatalogPresenter().report(for: info))
        XCTAssertTrue(report.stats.isEmpty)
        XCTAssertEqual(report.sections.map(\.title), ["Structure diagram", "Details"])
        let firstBlock = try XCTUnwrap(report.sections.first?.blocks.first)
        guard case .structureDiagram(let diagram) = firstBlock else { return XCTFail("Diagram must be the first block") }
        XCTAssertTrue(diagram.nodes[0].fields[0].indexed)
        XCTAssertTrue(diagram.nodes[0].fields[0].primaryKey)
        XCTAssertEqual(diagram.nodes[0].fields.map(\.icon), [.integer, .text, .text, .object])
        XCTAssertEqual(diagram.nodes[1].fields.map(\.icon), [.integer, .integer, .unknown])
        XCTAssertFalse(diagram.nodes[0].fields[1].indexed)
        XCTAssertTrue(diagram.nodes[1].fields[0].primaryKey)
        XCTAssertFalse(diagram.nodes[1].fields[0].indexed)
        let lastBlock = try XCTUnwrap(report.sections.last?.blocks.first)
        guard case .disclosure(let summary, _, let metadata) = lastBlock else { return XCTFail("Metadata must be collapsed") }
        XCTAssertEqual(summary, "Catalog details")
        let properties = metadata.compactMap { block -> [KeyValue]? in
            if case .keyValues(let values) = block { return values }; return nil
        }.flatMap { $0 }
        XCTAssertEqual(properties.filter { ["Tables", "Fields", "Relations", "Indexes"].contains($0.key) }.map(\.value), ["2", "7", "1", "1"])
        XCTAssertFalse(report.badges.contains { $0.text.contains("Encrypted") })
        let html = HTMLRenderer().render(report)
        XCTAssertTrue(html.contains("<svg"))
        XCTAssertTrue(html.contains("Client_ID"))
        XCTAssertTrue(html.contains("diagram-primary-key diagram-indexed"))
        XCTAssertFalse(html.contains("<script"))
        XCTAssertFalse(html.contains("<div class=\"stats\">"))
        XCTAssertFalse(html.contains("<div class=\"bars\">"))
        XCTAssertFalse(html.contains("<table>"))
        XCTAssertFalse(html.contains("<details open"))
        let svgStart = try XCTUnwrap(html.range(of: "<svg"))
        let metadataStart = try XCTUnwrap(html.range(of: "<details>"))
        XCTAssertLessThan(svgStart.lowerBound, metadataStart.lowerBound)
        XCTAssertTrue(html.contains("does not reveal whether a data file is encrypted"))
    }

    func testLargeCatalogIncludesEveryTableAndKeepsJSONComplete() throws {
        let tableXML = (0..<300).map { table in
            "<table name=\"T\(table)\">" + (0..<20).map { "<field name=\"F\($0)\" type=\"4\"/>" }.joined() +
            "<primary_key field_name=\"F19\"/></table>"
        }.joined()
        let relation = """
        <relation><related_field kind="source"><field_ref name="F19"><table_ref name="T298"/></field_ref></related_field>
        <related_field kind="destination"><field_ref name="F19"><table_ref name="T299"/></field_ref></related_field></relation>
        """
        let info = try analyze("<base>\(tableXML)\(relation)</base>")
        let report = try XCTUnwrap(CatalogPresenter().report(for: info))
        let blocks = report.sections.flatMap(\.blocks)
        let diagram = try XCTUnwrap(blocks.compactMap { block -> StructureDiagram? in
            if case .structureDiagram(let diagram) = block { return diagram }; return nil
        }.first)
        XCTAssertEqual(diagram.nodes.count, 300)
        XCTAssertEqual(diagram.omittedTables, 0)
        XCTAssertEqual(diagram.edges.count, 1)
        XCTAssertEqual(diagram.edges[0].sourceNode, "298")
        XCTAssertEqual(diagram.edges[0].destinationNode, "299")
        XCTAssertEqual(diagram.omittedRelations, 0)
        XCTAssertTrue(diagram.nodes.allSatisfy { $0.fields.count == 8 && $0.omittedFields == 12 })
        XCTAssertTrue(diagram.nodes.allSatisfy { $0.fields.contains { $0.primaryKey && $0.name == "F19" } })
        XCTAssertEqual(info.tables.count, 300)
        XCTAssertEqual(info.tables.flatMap(\.fields).count, 6_000)
        let html = HTMLRenderer().render(report)
        XCTAssertEqual(html.components(separatedBy: "class=\"diagram-node\"").count - 1, 300)
        XCTAssertTrue(html.contains("data-node-id=\"299\""))
        XCTAssertLessThan(html.utf8.count, 5 * 1024 * 1024)
    }

    func testResourceLimitsAndInvalidCoordinates() throws {
        let deep = String(repeating: "<x>", count: 128) + String(repeating: "</x>", count: 128)
        XCTAssertThrowsError(try analyze("<base>\(deep)</base>"))
        let url = try file(Data(count: 32 * 1024 * 1024 + 1))
        XCTAssertThrowsError(try AnalyzerRegistry.default.analyze(url: url))
        let info = try analyze("""
        <base><table name="A"><table_extra><editor_table_info><coordinates left="NaN" top="infinity"/></editor_table_info></table_extra></table></base>
        """)
        XCTAssertNil(info.tables[0].position)
        XCTAssertTrue(info.warnings.contains { $0.contains("invalid editor coordinates") })
        XCTAssertThrowsError(try analyze("<base>" + String(repeating: "<x/>", count: 200_000) + "</base>"))
    }

    func testAllRelationsAndJoinedFieldPriority() throws {
        let fields = (0..<20).map { "<field name=\"F\($0)\" type=\"4\"/>" }.joined()
        let relation = """
        <relation><related_field kind="source"><field_ref name="F19"><table_ref name="A"/></field_ref></related_field>
        <related_field kind="destination"><field_ref name="ID"><table_ref name="B"/></field_ref></related_field></relation>
        """
        let info = try analyze("<base><table name=\"A\">\(fields)</table><table name=\"B\"><field name=\"ID\" type=\"4\"/></table>" +
                               String(repeating: relation, count: 70) + "</base>")
        let report = try XCTUnwrap(CatalogPresenter().report(for: info))
        let diagram = try XCTUnwrap(report.sections.flatMap(\.blocks).compactMap { block -> StructureDiagram? in
            if case .structureDiagram(let diagram) = block { return diagram }; return nil
        }.first)
        XCTAssertEqual(diagram.edges.count, 70)
        XCTAssertEqual(diagram.omittedRelations, 0)
        XCTAssertEqual(diagram.omittedTables, 0)
        XCTAssertTrue(diagram.nodes[0].fields.contains { $0.name == "F19" })
        XCTAssertEqual(diagram.edges[0].sourceField, "19")
        XCTAssertEqual(info.relations.count, 70)
    }

    func testFixtureProjectCatalogMatchesBinaryDefinitions() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/encfixture/Project/Sources/catalog.4DCatalog")
        let catalog = try XCTUnwrap(try AnalyzerRegistry.default.analyze(url: url) as? CatalogInfo)
        let binaryURL = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/plain", withExtension: "4DD"))
        let binary = try XCTUnwrap(try AnalyzerRegistry.default.analyze(url: binaryURL) as? DB4DFileInfo)
        XCTAssertEqual(catalog.tables.map(\.name), binary.tables.map(\.name))
        XCTAssertEqual(catalog.tables.flatMap(\.fields).map(\.typeCode), binary.tables.flatMap(\.fields).map(\.typeCode))
        XCTAssertEqual(catalog.tables.map(\.encryptable), binary.tables.map(\.encryptable))
        XCTAssertEqual(catalog.databaseUUID.lowercased(), binary.header.databaseUUID.replacingOccurrences(of: "-", with: "").lowercased())
    }

    func testSharedTypeLabels() {
        for code in [10, 14, 17] {
            XCTAssertEqual(FieldInfo.typeName(code: code, limitingLength: 40), "Alpha (40)")
            XCTAssertEqual(FieldInfo.typeName(code: code, limitingLength: nil), "Text")
            XCTAssertEqual(FieldInfo.typeName(code: code, limitingLength: 0), "Text")
        }
        XCTAssertEqual(FieldInfo.typeName(code: 21, limitingLength: nil), "Object")
        XCTAssertEqual(FieldInfo.typeName(code: 11, limitingLength: nil), "BLOB")
    }

    func testCatalogTypesMapToDiagramIcons() throws {
        let types: [(Int, DiagramField.Icon)] = [
            (1, .boolean), (2, .integer), (3, .integer), (4, .integer), (5, .integer),
            (6, .real), (7, .real), (8, .date), (9, .time), (10, .text),
            (11, .blob), (12, .picture), (13, .uuid), (14, .text), (17, .text),
            (18, .blob), (21, .object), (999, .unknown),
        ]
        for (code, expected) in types {
            let info = try analyze("<base><table name=\"A\"><field name=\"Field\" type=\"\(code)\"/></table></base>")
            let report = try XCTUnwrap(CatalogPresenter().report(for: info))
            let block = try XCTUnwrap(report.sections.first?.blocks.first)
            guard case .structureDiagram(let diagram) = block else { return XCTFail("Expected a diagram") }
            XCTAssertEqual(diagram.nodes[0].fields[0].icon, expected, "Type \(code)")
        }
    }
}
