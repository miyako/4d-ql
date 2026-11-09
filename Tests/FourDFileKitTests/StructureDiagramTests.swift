import XCTest
@testable import FourDRender

final class StructureDiagramTests: XCTestCase {
    private func node(_ id: String, position: DiagramPosition? = nil) -> DiagramNode {
        DiagramNode(id: id, title: "Table \(id)", fields: [
            DiagramField(id: "id", name: "ID", type: "Integer", primaryKey: true),
            DiagramField(id: "parent", name: "Parent", type: "Integer", hidden: true)
        ], position: position)
    }

    private func render(_ diagram: StructureDiagram) -> String {
        var report = Report(title: "Structure")
        report.sections = [Section("Diagram", [.structureDiagram(diagram)])]
        return HTMLRenderer().render(report)
    }

    func testDeterministicScriptFreeAccessibleOutput() {
        let diagram = StructureDiagram(nodes: [node("A"), node("B")], edges: [
            DiagramEdge(sourceNode: "A", sourceField: "parent", destinationNode: "B",
                        destinationField: "id", label: "Parent relation")
        ])
        let html = render(diagram)
        XCTAssertEqual(html, render(diagram))
        XCTAssertTrue(html.contains("<svg xmlns="))
        XCTAssertTrue(html.contains("role=\"img\""))
        XCTAssertTrue(html.contains("<title>Structure diagram: 2 tables · 1 relations"))
        XCTAssertTrue(html.contains("tabindex=\"0\" role=\"region\""))
        XCTAssertTrue(html.contains("max-height:max(320px,calc(100vh - 180px));overflow:auto"))
        XCTAssertFalse(html.contains("<p class=\"diagram-summary\">"))
        XCTAssertFalse(html.contains("<p class=\"diagram-key\">"))
        XCTAssertFalse(html.contains("Scroll to explore; hover for details"))
        XCTAssertTrue(html.contains("prefers-color-scheme:dark"))
        XCTAssertFalse(html.contains("<script"))
        XCTAssertFalse(html.contains("<link"))
    }

    func testHostileTextEscapedInEveryContextAndFullTooltipsPreserved() {
        let hostile = "\"><script>alert('x')</script>&\u{0001}"
        let longName = hostile + String(repeating: "Untruncated", count: 10)
        let diagram = StructureDiagram(nodes: [
            DiagramNode(id: hostile, title: longName, fields: [
                DiagramField(id: hostile, name: longName, type: hostile, primaryKey: true, hidden: true)
            ])
        ], edges: [
            DiagramEdge(sourceNode: hostile, sourceField: hostile, destinationNode: hostile,
                        destinationField: hostile, label: longName)
        ])
        let html = render(diagram)
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertFalse(html.contains("\u{0001}"))
        XCTAssertTrue(html.contains("data-node-id=\"&quot;&gt;&lt;script&gt;"))
        XCTAssertTrue(html.contains("data-source-field=\"&quot;&gt;&lt;script&gt;"))
        XCTAssertTrue(html.contains("&lt;/script&gt;&amp;"))
        XCTAssertTrue(html.contains("<title>\(HTMLRenderer.escape(longName))</title>"))
        XCTAssertTrue(html.contains("\(HTMLRenderer.escape(longName)): \(HTMLRenderer.escape(hostile)) (primary key) (hidden)"))
        XCTAssertTrue(html.contains("diagram-field diagram-hidden"))
        XCTAssertTrue(html.contains("font-style:italic"))
        XCTAssertTrue(html.contains("diagram-field-name diagram-primary-key"))
        XCTAssertFalse(html.contains(">PK "))
        XCTAssertTrue(html.contains("…"))
    }

    func testSavedPositionsNormalizedAndPartialCoverageReused() {
        let diagram = StructureDiagram(nodes: [
            node("A", position: DiagramPosition(x: -100, y: -50)),
            node("B", position: DiagramPosition(x: 500, y: -50)),
            node("C", position: DiagramPosition(x: -100, y: 250)),
            node("D")
        ], edges: [])
        let html = render(diagram)
        XCTAssertTrue(html.contains("data-node-id=\"A\" transform=\"translate(24.0 24.0)\""))
        XCTAssertTrue(html.contains("data-node-id=\"B\" transform=\"translate(624.0 24.0)\""))
        XCTAssertTrue(html.contains("data-node-id=\"C\" transform=\"translate(24.0 324.0)\""))
        XCTAssertTrue(html.contains("data-node-id=\"D\" transform=\"translate(24.0 448.0)\""))
    }

    func testHiddenTablesHaveItalicHeadingsWithoutHidingVisibleFields() {
        let title = "Hidden <table> " + String(repeating: "long title ", count: 8)
        let hidden = DiagramNode(id: "hidden", title: title,
                                 fields: [DiagramField(id: "id", name: "ID", type: "Integer")],
                                 hidden: true)
        XCTAssertFalse(node("visible").hidden)
        let html = render(StructureDiagram(nodes: [hidden, node("visible")], edges: []))
        XCTAssertTrue(html.contains("<title>\(HTMLRenderer.escape(title)) (hidden table)</title>"))
        XCTAssertTrue(html.contains("<text class=\"diagram-heading diagram-hidden\""))
        XCTAssertTrue(html.contains("<text class=\"diagram-heading\""))
        XCTAssertTrue(html.contains("<g class=\"diagram-field\" data-field-id=\"id\">"))
        XCTAssertTrue(html.contains("italic table and field names are hidden"))
    }

    func testOverlapAndSparseSavedCoordinatesUseGrid() {
        let grid = render(StructureDiagram(nodes: [node("A"), node("B")], edges: []))
        let overlap = render(StructureDiagram(nodes: [
            node("A", position: DiagramPosition(x: 10, y: 10)),
            node("B", position: DiagramPosition(x: 20, y: 20))
        ], edges: []))
        let sparse = render(StructureDiagram(nodes: [
            node("A", position: DiagramPosition(x: 900, y: 900)), node("B")
        ], edges: []))
        XCTAssertEqual(grid, overlap)
        XCTAssertEqual(grid, sparse)
        XCTAssertTrue(grid.contains("data-node-id=\"B\" transform=\"translate(232.0 24.0)\""))
    }

    func testInvalidAndExtremeCoordinatesNeverReachSVG() {
        let grid = render(StructureDiagram(nodes: [node("A"), node("B")], edges: []))
        for position in [
            DiagramPosition(x: .nan, y: 0), DiagramPosition(x: 0, y: .infinity),
            DiagramPosition(x: -.infinity, y: 0),
            DiagramPosition(x: Double.greatestFiniteMagnitude, y: 0)
        ] {
            let html = render(StructureDiagram(nodes: [node("A", position: position), node("B")], edges: []))
            XCTAssertEqual(html, grid)
            XCTAssertFalse(html.contains("NaN"))
            XCTAssertFalse(html.contains("Infinity"))
        }
        let wideLayout = render(StructureDiagram(nodes: [
            node("A", position: DiagramPosition(x: -10_000, y: 0)),
            node("B", position: DiagramPosition(x: 10_000, y: 0))
        ], edges: []))
        XCTAssertTrue(wideLayout.contains("width=\"20264.0\" height=\"124.0\" viewBox=\"0 0 20264.0 124.0\""))
        XCTAssertTrue(wideLayout.contains("data-node-id=\"B\" transform=\"translate(20024.0 24.0)\""))
    }

    func testFieldOmissionsWithoutTableOrRelationCaps() {
        let fields = (0..<10).map { DiagramField(id: "\($0)", name: "Field \($0)", type: "Text") }
        let nodes = (0..<25).map { DiagramNode(id: "\($0)", title: "Table \($0)", fields: fields, omittedFields: 3) }
        let edges = (0..<65).map {
            DiagramEdge(sourceNode: "0", sourceField: "0", destinationNode: "1",
                        destinationField: "1", label: "Relation \($0)")
        }
        let html = render(StructureDiagram(nodes: nodes, edges: edges, omittedTables: 7, omittedRelations: 9))
        XCTAssertTrue(html.contains("25 tables · 65 relations · 7 tables omitted · 9 relations omitted · 125 fields omitted"))
        XCTAssertFalse(html.contains("<p class=\"diagram-summary\">"))
        XCTAssertFalse(html.contains("<p class=\"diagram-key\">"))
        XCTAssertTrue(html.contains(">5 fields omitted</text>"))
        XCTAssertFalse(html.contains("data-field-id=\"8\""))
        XCTAssertTrue(html.contains("data-node-id=\"24\""))
        let dangling = render(StructureDiagram(nodes: [node("A")], edges: [
            DiagramEdge(sourceNode: "A", sourceField: "id", destinationNode: "missing",
                        destinationField: "id", label: "Missing")
        ]))
        XCTAssertTrue(dangling.contains("1 relations omitted"))
        XCTAssertTrue(render(StructureDiagram(nodes: [], edges: [], omittedTables: 4)).contains("4 tables omitted"))
    }

    func testHundredsOfTablesAndRelationsFitInsideExpandedCanvas() {
        let nodes = (0..<400).map { node("\($0)") }
        let edges = (0..<399).map {
            DiagramEdge(sourceNode: "\($0)", sourceField: "parent", destinationNode: "\($0 + 1)",
                        destinationField: "id", label: "Join")
        }
        let html = render(StructureDiagram(nodes: nodes, edges: edges))
        XCTAssertEqual(html.components(separatedBy: "class=\"diagram-node\"").count - 1, 400)
        XCTAssertEqual(html.components(separatedBy: "class=\"diagram-edge\"").count - 1, 399)
        XCTAssertTrue(html.contains("400 tables · 399 relations."))
        XCTAssertTrue(html.contains("width=\"4216.0\" height=\"2480.0\" viewBox=\"0 0 4216.0 2480.0\""))
        XCTAssertTrue(html.contains("data-node-id=\"399\" transform=\"translate(3976.0 2380.0)\""))
        XCTAssertFalse(html.contains("tables omitted"))
        XCTAssertFalse(html.contains("relations omitted"))
    }

    func testHundredsOfSavedPositionsBeyondFormerCanvasLimitArePreserved() {
        let nodes = (0..<300).map { node("\($0)", position: DiagramPosition(x: Double($0) * 500, y: Double($0) * 100)) }
        let html = render(StructureDiagram(nodes: nodes, edges: []))
        XCTAssertTrue(html.contains("data-node-id=\"299\" transform=\"translate(149524.0 29924.0)\""))
        XCTAssertTrue(html.contains("width=\"149764.0\" height=\"30024.0\" viewBox=\"0 0 149764.0 30024.0\""))
    }

    func testConnectorsAnchorToActualFieldRowsAndMissingFieldHeader() {
        let html = render(StructureDiagram(nodes: [node("A"), node("B")], edges: [
            DiagramEdge(sourceNode: "A", sourceField: "parent", destinationNode: "B",
                        destinationField: "id", label: "Field relation"),
            DiagramEdge(sourceNode: "A", sourceField: "omitted", destinationNode: "B",
                        destinationField: "omitted", label: "Header relation")
        ]))
        XCTAssertTrue(html.contains("M 168.0 83.5 C 200.0 83.5, 200.0 62.5, 232.0 62.5"))
        XCTAssertTrue(html.contains("M 168.0 38.0 C 200.0 38.0, 200.0 38.0, 232.0 38.0"))
        XCTAssertTrue(html.contains("<title>Field relation: Table A.Parent → Table B.ID</title>"))
    }

    func testRelationNamesAreTooltipOnlyAndTableHeadingsAreCentered() throws {
        let html = render(StructureDiagram(nodes: [node("A"), node("B")], edges: [
            DiagramEdge(sourceNode: "A", sourceField: "parent", destinationNode: "B",
                        destinationField: "id", label: "Parent relation")
        ]))
        let start = try XCTUnwrap(html.range(of: "<g class=\"diagram-edge\""))
        let end = try XCTUnwrap(html.range(of: "</g>", range: start.upperBound..<html.endIndex))
        let connector = html[start.lowerBound..<end.upperBound]
        XCTAssertTrue(connector.contains("<title>Parent relation: Table A.Parent → Table B.ID</title>"))
        XCTAssertFalse(connector.contains("<text"))
        XCTAssertTrue(html.contains("<text class=\"diagram-heading\" x=\"72.0\" y=\"18\" text-anchor=\"middle\">Table A</text>"))
        XCTAssertTrue(html.contains("<text class=\"diagram-field-name diagram-primary-key\" x=\"30\" y=\"42.0\">ID</text>"))
    }

    func testPrimaryKeysAreUnderlinedAndIndexedFieldNamesAreBold() {
        let html = render(StructureDiagram(nodes: [
            DiagramNode(id: "A", title: "A", fields: [
                DiagramField(id: "pk", name: "Primary", type: "Integer", primaryKey: true),
                DiagramField(id: "idx", name: "Indexed", type: "Text", indexed: true),
                DiagramField(id: "both", name: "Both", type: "Integer", primaryKey: true, hidden: true, indexed: true),
                DiagramField(id: "plain", name: "Plain", type: "Text")
            ])
        ], edges: []))
        XCTAssertTrue(html.contains("<text class=\"diagram-field-name diagram-primary-key\" x=\"30\" y=\"42.0\">Primary</text>"))
        XCTAssertTrue(html.contains("<text class=\"diagram-field-name diagram-indexed\" x=\"30\" y=\"63.0\">Indexed</text>"))
        XCTAssertTrue(html.contains("<text class=\"diagram-field-name diagram-primary-key diagram-indexed\" x=\"30\" y=\"84.0\">Both</text>"))
        XCTAssertTrue(html.contains("<text class=\"diagram-field-name\" x=\"30\" y=\"105.0\">Plain</text>"))
        XCTAssertTrue(html.contains("<title>Both: Integer (primary key) (indexed) (hidden)</title>"))
        XCTAssertTrue(html.contains("diagram-primary-key{text-decoration:underline}"))
        XCTAssertTrue(html.contains("diagram-indexed{font-weight:700}"))
        XCTAssertFalse(html.contains(">PK "))
    }

    func testSelfRelationsIncludeVisibleLoopEvenOnSameField() {
        let html = render(StructureDiagram(nodes: [node("A")], edges: [
            DiagramEdge(sourceNode: "A", sourceField: "parent", destinationNode: "A",
                        destinationField: "id", label: "Self"),
            DiagramEdge(sourceNode: "A", sourceField: "id", destinationNode: "A",
                        destinationField: "id", label: "Same field")
        ]))
        XCTAssertTrue(html.contains("M 168.0 83.5 C 204.0 83.5, 204.0 73.0, 204.0 73.0 C 204.0 62.5, 204.0 62.5, 168.0 62.5"))
        XCTAssertTrue(html.contains("M 168.0 62.5 C 212.0 62.5, 212.0 40.5, 212.0 40.5 C 212.0 62.5, 212.0 62.5, 168.0 62.5"))
    }

    func testCardsAreCompactWithoutClipping31CharacterNames() {
        let renderer = StructureDiagramRenderer()
        XCTAssertEqual(renderer.cardWidth(node("A")), 144)
        XCTAssertTrue(render(StructureDiagram(nodes: [node("A")], edges: [])).contains("width=\"144.0\" height=\"76.0\""))
        for name in [
            String(repeating: "W", count: 31),
            String(repeating: "顧", count: 31),
            "A_31_Character_Field_Name_12345",
        ] {
            XCTAssertLessThanOrEqual(name.count, 31)
            let table = DiagramNode(id: "A", title: name, fields: [
                DiagramField(id: "id", name: name, type: "Text", hidden: true, indexed: true, icon: .text)
            ])
            let width = renderer.cardWidth(table)
            XCTAssertGreaterThanOrEqual(width - 40, DiagramTypography.width(name, bold: true, italic: true))
            XCTAssertGreaterThanOrEqual(width - 20, DiagramTypography.width(name, bold: true))
            let html = render(StructureDiagram(nodes: [table], edges: []))
            XCTAssertTrue(html.contains("text-anchor=\"middle\">\(name)</text>"))
            XCTAssertTrue(html.contains("y=\"42.0\">\(name)</text>"))
            XCTAssertFalse(html.contains("…"))
            XCTAssertTrue(html.contains("diagram-icon-text"))
        }
    }

    func testEveryTypeIconIsInlineAccessibleAndKeepsFullTypeInTooltip() {
        for icon in DiagramField.Icon.allCases {
            let label = "Full <type> & \"details\""
            let html = render(StructureDiagram(nodes: [
                DiagramNode(id: "A", title: "A", fields: [DiagramField(id: "id", name: "Field", type: label, icon: icon)])
            ], edges: []))
            XCTAssertTrue(html.contains("class=\"diagram-icon diagram-icon-\(icon.rawValue)\""))
            XCTAssertTrue(html.contains("role=\"img\" aria-label=\"\(HTMLRenderer.escape(label))\""))
            XCTAssertTrue(html.contains("<title>\(HTMLRenderer.escape(label))</title>"))
            XCTAssertFalse(html.contains("<image"))
            XCTAssertFalse(html.contains("diagram-type\""))
            XCTAssertFalse(html.contains("<type>"))
        }
    }

    func testVariableWidthCardsHaveCorrectPortsAndNonoverlappingColumns() {
        let renderer = StructureDiagramRenderer()
        let wide = DiagramNode(id: "A", title: "A", fields: [
            DiagramField(id: "id", name: String(repeating: "W", count: 31), type: "Text")
        ])
        let width = renderer.cardWidth(wide)
        let html = render(StructureDiagram(nodes: [wide, node("B")], edges: [
            DiagramEdge(sourceNode: "A", sourceField: "id", destinationNode: "B", destinationField: "id", label: "Join")
        ]))
        func n(_ value: Double) -> String { String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value) }
        XCTAssertGreaterThan(width, 300)
        XCTAssertTrue(html.contains("data-node-id=\"B\" transform=\"translate(\(n(24 + width + 64)) 24.0)\""))
        XCTAssertTrue(html.contains("M \(n(24 + width)) 62.5 C \(n(24 + width + 32)) 62.5, \(n(24 + width + 32)) 62.5, \(n(24 + width + 64)) 62.5"))
    }
}
