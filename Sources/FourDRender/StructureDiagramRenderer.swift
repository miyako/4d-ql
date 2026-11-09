import Foundation

/// Script-free SVG rendering. Presentation models contain no HTML or SVG.
struct StructureDiagramRenderer {
    private let header = 28.0
    private let row = 21.0
    private let margin = 24.0
    private static let zoomLevels = [10, 25, 50, 75, 100, 150, 200]

    private struct Box {
        var node: DiagramNode
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    func render(_ diagram: StructureDiagram, identifier: String = "diagram") -> String {
        let nodes = diagram.nodes.map { node -> DiagramNode in
            var node = node
            node.omittedFields = max(0, node.omittedFields) + max(0, node.fields.count - 8)
            node.fields = Array(node.fields.prefix(8))
            return node
        }
        let boxes = layout(nodes)
        var indices: [String: Int] = [:]
        for (index, box) in boxes.enumerated() where indices[box.node.id] == nil {
            indices[box.node.id] = index
        }
        let edges = diagram.edges.filter {
            indices[$0.sourceNode] != nil && indices[$0.destinationNode] != nil
        }
        let omittedTables = max(0, diagram.omittedTables) + max(0, diagram.nodes.count - nodes.count)
        let omittedRelations = max(0, diagram.omittedRelations) + diagram.edges.count - edges.count
        var summary = "\(nodes.count) tables · \(edges.count) relations"
        var omissions: [String] = []
        if omittedTables > 0 { omissions.append("\(omittedTables) tables omitted") }
        if omittedRelations > 0 { omissions.append("\(omittedRelations) relations omitted") }
        let omittedFields = nodes.reduce(0) { $0 + $1.omittedFields }
        if omittedFields > 0 { omissions.append("\(omittedFields) fields omitted") }
        if !omissions.isEmpty { summary += " · " + omissions.joined(separator: " · ") }
        var html = "<div class=\"structure-diagram\">"
        guard !boxes.isEmpty else { return html + "<p class=\"more\" title=\"\(esc(summary))\">No tables to display.</p></div>" }

        let canvasWidth = max(200, (boxes.map { $0.x + $0.width }.max() ?? 0) + margin + 72)
        let canvasHeight = max(120, (boxes.map { $0.y + $0.height }.max() ?? 0) + margin)
        let description = "Structure diagram: \(summary). Relations connect field rows; unavailable fields connect to table headers. Underlined fields are primary keys; bold fields are indexed; italic table and field names are hidden."
        var selectors = ""
        let prefix = "diagram-zoom-\(identifier)"
        for percent in Self.zoomLevels {
            let id = "\(prefix)-\(percent)"
            html += "<input class=\"diagram-zoom-choice\" type=\"radio\" name=\"\(esc(prefix))\" id=\"\(esc(id))\" value=\"\(percent)\" aria-label=\"Diagram zoom \(percent) percent\"\(percent == 100 ? " checked" : "")>"
            selectors += "#\(id):checked ~ .diagram-viewport{--diagram-scale:\(Double(percent) / 100)}"
            selectors += "#\(id):checked ~ .diagram-zoom-controls label[for=\"\(id)\"]{background:var(--accent);border-color:var(--accent);color:white}"
            selectors += "#\(id):focus-visible ~ .diagram-zoom-controls label[for=\"\(id)\"]{outline:2px solid var(--accent);outline-offset:2px}"
        }
        html += "<div class=\"diagram-zoom-controls\" role=\"group\" aria-label=\"Diagram zoom\"><span>Zoom</span>"
        for percent in Self.zoomLevels {
            html += "<label for=\"\(esc(prefix))-\(percent)\">\(percent)%</label>"
        }
        html += "</div><style>\(selectors)</style>"
        html += "<div class=\"diagram-viewport\" tabindex=\"0\" role=\"region\" aria-label=\"Scrollable structure diagram\">"
        html += "<svg xmlns=\"http://www.w3.org/2000/svg\" class=\"diagram-svg\" role=\"img\" aria-label=\"\(esc(description))\" width=\"\(n(canvasWidth))\" height=\"\(n(canvasHeight))\" viewBox=\"0 0 \(n(canvasWidth)) \(n(canvasHeight))\" style=\"--diagram-width:\(n(canvasWidth))px;--diagram-height:\(n(canvasHeight))px\"><title>\(esc(description))</title>"
        for (index, edge) in edges.enumerated() {
            guard let source = indices[edge.sourceNode], let destination = indices[edge.destinationNode] else { continue }
            html += connector(edge, index: index, source: boxes[source], destination: boxes[destination],
                              selfRelation: source == destination)
        }
        for box in boxes { html += table(box) }
        return html + "</svg></div></div>"
    }

    private func layout(_ nodes: [DiagramNode]) -> [Box] {
        var boxes = nodes.map {
            Box(node: $0, x: 0, y: 0, width: cardWidth($0),
                height: header + row * Double($0.fields.count + ($0.omittedFields > 0 ? 1 : 0)) + 6)
        }
        let valid = nodes.map { node -> DiagramPosition? in
            guard let p = node.position, p.x.isFinite, p.y.isFinite,
                  abs(p.x) <= 1_000_000_000, abs(p.y) <= 1_000_000_000 else { return nil }
            return p
        }
        // Preserve a mostly complete saved layout only if the cards do not collide.
        let enoughCoverage = !nodes.isEmpty && valid.compactMap { $0 }.count * 4 >= nodes.count * 3
        if enoughCoverage {
            let minX = valid.compactMap { $0?.x }.min() ?? 0
            let minY = valid.compactMap { $0?.y }.min() ?? 0
            for i in boxes.indices {
                if let p = valid[i] { boxes[i].x = p.x - minX + margin; boxes[i].y = p.y - minY + margin }
            }
            let saved = boxes.indices.filter { valid[$0] != nil }
            var overlapping = false
            for (offset, i) in saved.enumerated() {
                for j in saved.dropFirst(offset + 1) {
                    if boxes[i].x < boxes[j].x + boxes[j].width + 24 && boxes[j].x < boxes[i].x + boxes[i].width + 24
                        && boxes[i].y < boxes[j].y + boxes[j].height + 24
                        && boxes[j].y < boxes[i].y + boxes[i].height + 24 { overlapping = true }
                }
            }
            let extentX = saved.map { boxes[$0].x + boxes[$0].width }.max() ?? 0
            let extentY = saved.map { boxes[$0].y + boxes[$0].height }.max() ?? 0
            if !overlapping {
                var bottom = extentY + 48
                for i in boxes.indices where valid[i] == nil {
                    boxes[i].x = margin
                    boxes[i].y = bottom
                    bottom += boxes[i].height + 48
                }
                return boxes
            }
        }
        let columns = min(boxes.count, max(3, Int(ceil(sqrt(Double(boxes.count))))))
        guard columns > 0 else { return boxes }
        let columnWidths = (0..<columns).map { column in
            boxes.indices.filter { $0 % columns == column }.map { boxes[$0].width }.max() ?? 0
        }
        var top = margin
        for start in stride(from: 0, to: boxes.count, by: columns) {
            let end = min(start + columns, boxes.count)
            var left = margin
            for i in start..<end {
                boxes[i].x = left
                boxes[i].y = top
                left += columnWidths[i % columns] + 64
            }
            top += (boxes[start..<end].map(\.height).max() ?? 0) + 48
        }
        return boxes
    }

    func cardWidth(_ node: DiagramNode) -> Double {
        let heading = DiagramTypography.width(short(node.title, limit: 31), bold: true, italic: node.hidden) + 20
        let fields = node.fields.map {
            DiagramTypography.width(short($0.name, limit: 31), bold: $0.indexed, italic: $0.hidden) + 40
        }.max() ?? 0
        let footer = node.omittedFields > 0 ? DiagramTypography.width("\(node.omittedFields) fields omitted") + 20 : 0
        // Measure actual glyphs rather than assuming 31 Latin and CJK characters occupy the same space.
        return ceil(max(144, heading, fields, footer))
    }

    private func anchor(_ field: String, in box: Box) -> Double {
        guard let index = box.node.fields.firstIndex(where: { $0.id == field }) else { return box.y + header / 2 }
        return box.y + header + row * (Double(index) + 0.5)
    }

    private func connector(_ edge: DiagramEdge, index: Int, source: Box, destination: Box,
                           selfRelation: Bool) -> String {
        let sy = anchor(edge.sourceField, in: source)
        let dy = anchor(edge.destinationField, in: destination)
        let rightward = destination.x > source.x
        let sameColumn = destination.x == source.x
        let sx = source.x + (rightward || sameColumn ? source.width : 0)
        let dx = destination.x + (rightward && !selfRelation ? 0 : destination.width)
        let lane = 36.0 + Double(index % 5) * 8
        let path: String
        if selfRelation {
            let outside = sx + lane
            let middleY = sy == dy ? sy - 22 : (sy + dy) / 2
            path = "M \(n(sx)) \(n(sy)) C \(n(outside)) \(n(sy)), \(n(outside)) \(n(middleY)), \(n(outside)) \(n(middleY)) C \(n(outside)) \(n(dy)), \(n(outside)) \(n(dy)), \(n(dx)) \(n(dy))"
        } else {
            let bend = sameColumn ? sx + lane : (sx + dx) / 2
            path = "M \(n(sx)) \(n(sy)) C \(n(bend)) \(n(sy)), \(n(bend)) \(n(dy)), \(n(dx)) \(n(dy))"
        }
        let sourceName = source.node.fields.first(where: { $0.id == edge.sourceField })?.name ?? edge.sourceField
        let destinationName = destination.node.fields.first(where: { $0.id == edge.destinationField })?.name ?? edge.destinationField
        let tip = "\(edge.label): \(source.node.title).\(sourceName) → \(destination.node.title).\(destinationName)"
        let arrowX = dx + (rightward && !selfRelation ? -7 : 7)
        let arrow = "M \(n(arrowX)) \(n(dy - 4)) L \(n(dx)) \(n(dy)) L \(n(arrowX)) \(n(dy + 4))"
        return "<g class=\"diagram-edge\" data-source-node=\"\(esc(edge.sourceNode))\" data-source-field=\"\(esc(edge.sourceField))\" data-destination-node=\"\(esc(edge.destinationNode))\" data-destination-field=\"\(esc(edge.destinationField))\"><title>\(esc(tip))</title><path d=\"\(path)\"/><path d=\"\(arrow)\"/><circle cx=\"\(n(sx))\" cy=\"\(n(sy))\" r=\"3\"/><circle cx=\"\(n(dx))\" cy=\"\(n(dy))\" r=\"3\"/></g>"
    }

    private func table(_ box: Box) -> String {
        let node = box.node
        var svg = "<g class=\"diagram-node\" data-node-id=\"\(esc(node.id))\" transform=\"translate(\(n(box.x)) \(n(box.y)))\"><title>\(esc(node.title))\(node.hidden ? " (hidden table)" : "")</title>"
        svg += "<rect class=\"diagram-card\" width=\"\(n(box.width))\" height=\"\(n(box.height))\" rx=\"5\"/>"
        svg += "<path class=\"diagram-header-line\" d=\"M 0 \(n(header)) H \(n(box.width))\"/>"
        svg += "<text class=\"diagram-heading\(node.hidden ? " diagram-hidden" : "")\" x=\"\(n(box.width / 2))\" y=\"18\" text-anchor=\"middle\">\(esc(short(node.title, limit: 31)))</text>"
        for (index, field) in node.fields.enumerated() {
            let y = header + row * Double(index)
            let full = "\(field.name): \(field.type)\(field.primaryKey ? " (primary key)" : "")\(field.indexed ? " (indexed)" : "")\(field.hidden ? " (hidden)" : "")"
            svg += "<g class=\"diagram-field\(field.hidden ? " diagram-hidden" : "")\" data-field-id=\"\(esc(field.id))\"><title>\(esc(full))</title>"
            let nameClass = "diagram-field-name" + (field.primaryKey ? " diagram-primary-key" : "") + (field.indexed ? " diagram-indexed" : "")
            svg += DiagramTypeIcon.render(field.icon, label: field.type, y: y + 3.5)
            svg += "<text class=\"\(nameClass)\" x=\"30\" y=\"\(n(y + 14))\">\(esc(short(field.name, limit: 31)))</text></g>"
        }
        if node.omittedFields > 0 {
            svg += "<text class=\"diagram-omitted\" x=\"10\" y=\"\(n(header + row * Double(node.fields.count) + 14))\">\(node.omittedFields) fields omitted</text>"
        }
        return svg + "</g>"
    }

    private func short(_ text: String, limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
    }

    private func esc(_ text: String) -> String { HTMLRenderer.escape(text) }
    private func n(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    static let css = """
    .structure-diagram{position:relative}
    .diagram-zoom-choice{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0,0,0,0);clip-path:inset(50%);white-space:nowrap}
    .diagram-zoom-controls{display:flex;flex-wrap:wrap;align-items:center;gap:6px;margin-bottom:10px;font-size:12px}
    .diagram-zoom-controls>span{color:var(--muted);margin-right:4px}
    .diagram-zoom-controls label{cursor:pointer;padding:4px 8px;border:1px solid var(--line);border-radius:5px}
    .diagram-viewport{max-width:100%;max-height:max(320px,calc(100vh - 180px));overflow:auto;border:1px solid var(--line);border-radius:8px;background:var(--bg)}
    .diagram-viewport:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
    .diagram-svg{display:block;max-width:none;width:calc(var(--diagram-width) * var(--diagram-scale,1));height:calc(var(--diagram-height) * var(--diagram-scale,1));font:12px "Helvetica Neue",Helvetica,sans-serif}
    .diagram-card{fill:var(--soft);stroke:var(--faint);stroke-width:1}
    .diagram-header-line{stroke:var(--line)}
    .diagram-node text{fill:var(--fg)}.diagram-heading{font-weight:700;font-size:12px}
    .diagram-node .diagram-omitted{fill:var(--muted);font-size:11px}
    .diagram-hidden{font-style:italic}
    .diagram-primary-key{text-decoration:underline}
    .diagram-indexed{font-weight:700}
    .diagram-edge path{fill:none;stroke:var(--accent);stroke-width:1.5}
    .diagram-edge circle{fill:var(--accent)}
    \(DiagramTypeIcon.css)
    """
}
