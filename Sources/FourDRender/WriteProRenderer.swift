import Foundation
import FourDFileKit

/// A formula reference found in a 4D Write Pro document.
public struct WriteProFormula: Equatable {
    public var source: String
    public var name: String?
    public var location: String
}

/// Static, script-free page rendering of a 4D Write Pro document.
///
/// The document's own XHTML is never passed through: every element is rebuilt from a small
/// vocabulary, every CSS declaration is translated from the 4D dialect and validated, and
/// anything executable (links, formulas, remote images) is reduced to an inert placeholder.
public final class WriteProDocumentRenderer {
    public struct Statistics: Equatable {
        public var paragraphs = 0, listItems = 0, tables = 0, images = 0, anchoredImages = 0, textBoxes = 0, links = 0
    }

    struct Geometry {
        var width = 595.0, height = 842.0
        var margins = Edges(all: 70.87)
        var landscape = false
        var firstRight = true
    }

    struct Edges { var top, right, bottom, left: Double
        init(all: Double) { top = all; right = all; bottom = all; left = all }
        init(_ t: Double, _ r: Double, _ b: Double, _ l: Double) { top = t; right = r; bottom = b; left = l }
    }

    enum FlowItem {
        case block(WriteProNode)
        case listItem(WriteProNode, marker: String)
    }

    struct Segment { var section: Int; var items: [FlowItem] = [] }
    struct Sheet { var segments: [Segment] }

    struct PageContext {
        var number = 1, count = 1, index = 1, section = 1
        var sectionName = ""
        var geometry = Geometry()
    }

    struct Decoration: Equatable { var line: String; var style: String; var color: String? }
    struct Inherited { var underline: Decoration?; var lineThrough: Decoration?; var link: String? }

    public let document: WriteProFileInfo
    public private(set) var statistics = Statistics()
    public private(set) var formulas: [WriteProFormula] = []
    public private(set) var notices: [String] = []
    public private(set) var sectionNames: [Int: String] = [:]
    public private(set) var sectionCount = 1
    var sheets: [Sheet] = []
    var pages: [PageContext] = []
    private var headerFooters: [String: WriteProNode] = [:]
    private var anchored: [WriteProNode] = []
    private var cascadeCache: [String: [WriteProDeclaration]] = [:]
    private var noticeSet = Set<String>()
    private var budget = 0
    static let paragraphBudget = 8_000

    public var pageCount: Int { sheets.count }
    public var geometry: (width: Double, height: Double, landscape: Bool) {
        let g = pages.first?.geometry ?? Geometry()
        return (g.width, g.height, g.landscape)
    }

    public init(_ document: WriteProFileInfo) {
        self.document = document
        classify()
        collectFormulas(document.body, location: "Body")
        paginate()
        count(document.body)
    }

    // MARK: - Structure

    private static let headerFooterPattern = try! NSRegularExpression(pattern: "^section([0-9]+)(First|Left|Right)?(Header|Footer)$")

    private func classify() {
        var flow: [FlowItem] = []
        for child in document.body.children where !child.isText {
            if child.name == "div", let name = child.classes.first(where: { Self.match(Self.headerFooterPattern, $0) }) {
                headerFooters[name] = child
            } else if isAnchored(child) {
                anchored.append(child)
            } else if child.name == "ul" || child.name == "ol" {
                flow += listItems(child)
            } else {
                flow.append(.block(child))
            }
        }
        var sheets = [Sheet(segments: [Segment(section: 1)])]
        var section = 1
        for item in flow {
            let node: WriteProNode
            switch item { case .block(let n), .listItem(let n, _): node = n }
            let d = cascade(node)
            if Self.isPageBreak(value(d, "page-break-before") ?? value(d, "break-before")),
               !(sheets[sheets.count - 1].segments.allSatisfy { $0.items.isEmpty }) {
                sheets.append(Sheet(segments: [Segment(section: section)]))
            }
            sheets[sheets.count - 1].segments[sheets[sheets.count - 1].segments.count - 1].items.append(item)
            let sectionBreak = value(d, "-d4-section-break-after")?.lowercased()
            if sectionBreak == "always" || sectionBreak == "continuous" {
                section += 1
                if sectionBreak == "always" || Self.isPageBreak(value(d, "page-break-after")) {
                    sheets.append(Sheet(segments: [Segment(section: section)]))
                } else {
                    sheets[sheets.count - 1].segments.append(Segment(section: section))
                }
            } else if Self.isPageBreak(value(d, "page-break-after") ?? value(d, "break-after")) {
                sheets.append(Sheet(segments: [Segment(section: section)]))
            }
        }
        // A trailing break leaves an empty sheet that 4D does not print.
        if sheets.count > 1, sheets[sheets.count - 1].segments.allSatisfy({ $0.items.isEmpty }) { sheets.removeLast() }
        self.sheets = sheets
        sectionCount = section
        for n in 1...section {
            if let name = value(sectionDeclarations(n), "-d4-section-name") { sectionNames[n] = WriteProCSS.unquote(name) }
        }
    }

    private static func isPageBreak(_ value: String?) -> Bool {
        guard let v = value?.lowercased() else { return false }
        return ["always", "page", "left", "right", "recto", "verso"].contains(v)
    }

    private func listItems(_ list: WriteProNode) -> [FlowItem] {
        var items: [FlowItem] = []
        var counter = Int(list.attributes["start"] ?? "") ?? 1
        for child in list.children where !child.isText {
            if child.name == "li" {
                items.append(.listItem(child, marker: marker(for: child, number: counter, ordered: list.name == "ol")))
                counter += 1
            } else if child.name == "ul" || child.name == "ol" {
                items += listItems(child)
            } else {
                items.append(.block(child))
            }
        }
        return items
    }

    private func paginate() {
        let total = sheets.count
        var number = 0
        var previousLastSection = 0
        for (offset, sheet) in sheets.enumerated() {
            let section = sheet.segments.first?.section ?? 1
            let startsSection = section != previousLastSection
            if startsSection, let first = value(sectionDeclarations(section), "-d4-page-first-number").flatMap({ Int($0) }) {
                number = first
            } else {
                number += 1
            }
            pages.append(PageContext(number: number, count: total, index: offset + 1, section: section,
                                     sectionName: sectionNames[section] ?? "", geometry: geometry(section: section)))
            previousLastSection = sheet.segments.last?.section ?? section
        }
    }

    // MARK: - Cascade

    func cascade(_ node: WriteProNode) -> [WriteProDeclaration] {
        let key = node.name + "|" + (node.attributes["class"] ?? "")
        let sheet: [WriteProDeclaration]
        if let cached = cascadeCache[key] {
            sheet = cached
        } else {
            sheet = document.declarations(tag: node.name, classes: node.classes)
            cascadeCache[key] = sheet
        }
        guard let style = node.attributes["style"] else { return sheet }
        return sheet + WriteProCSS.declarations(style)
    }

    func value(_ declarations: [WriteProDeclaration], _ name: String) -> String? {
        declarations.last { $0.name == name }?.value
    }

    private func sectionDeclarations(_ n: Int) -> [WriteProDeclaration] {
        document.rule(tag: "div", className: "section0") + document.rule(tag: "div", className: "section\(n)")
    }

    private func geometry(section: Int) -> Geometry {
        let d = sectionDeclarations(section)
        var g = Geometry()
        if let w = value(d, "-d4-page-width").flatMap({ Self.points($0) }), w > 36, w < 14_400 { g.width = w }
        if let h = value(d, "-d4-page-height").flatMap({ Self.points($0) }), h > 36, h < 14_400 { g.height = h }
        if value(d, "-d4-page-orientation")?.lowercased() == "landscape" {
            g.landscape = true
            if g.width < g.height { swap(&g.width, &g.height) }
        }
        g.margins = edges(d, shorthand: "-d4-page-margin", prefix: "-d4-page-margin-", fallback: Edges(all: 70.87))
        g.firstRight = value(d, "-d4-page-first-right")?.lowercased() != "false"
        return g
    }

    private func edges(_ d: [WriteProDeclaration], shorthand: String, prefix: String, fallback: Edges) -> Edges {
        var e = fallback
        for decl in d {
            if decl.name == shorthand {
                let v = WriteProCSS.components(decl.value).compactMap { Self.points($0) }
                switch v.count {
                case 1: e = Edges(all: v[0])
                case 2: e = Edges(v[0], v[1], v[0], v[1])
                case 3: e = Edges(v[0], v[1], v[2], v[1])
                case 4...: e = Edges(v[0], v[1], v[2], v[3])
                default: break
                }
            } else if decl.name.hasPrefix(prefix), let p = Self.points(decl.value) {
                switch decl.name.dropFirst(prefix.count) {
                case "top": e.top = p
                case "right": e.right = p
                case "bottom": e.bottom = p
                case "left": e.left = p
                default: break
                }
            }
        }
        e.top = Self.clamp(e.top, 0, 2_000); e.right = Self.clamp(e.right, 0, 2_000)
        e.bottom = Self.clamp(e.bottom, 0, 2_000); e.left = Self.clamp(e.left, 0, 2_000)
        return e
    }

    private func isAnchored(_ node: WriteProNode) -> Bool {
        guard node.name == "img" || node.name == "div" else { return false }
        let d = cascade(node)
        return value(d, "position")?.lowercased() == "absolute" || d.contains { $0.name.hasPrefix("-d4-anchor-") }
            || (node.name == "div" && (node.attributes["id"] ?? "").hasPrefix("textBox"))
    }

    private func count(_ node: WriteProNode) {
        switch node.name {
        case "p": statistics.paragraphs += 1
        case "li": statistics.listItems += 1
        case "table": statistics.tables += 1
        case "a": statistics.links += 1
        case "img": if isAnchored(node) { statistics.anchoredImages += 1 } else { statistics.images += 1 }
        case "div": if isAnchored(node) { statistics.textBoxes += 1 }
        default: break
        }
        for child in node.children where !child.isText { count(child) }
    }

    // MARK: - Formulas

    private func collectFormulas(_ node: WriteProNode, location: String) {
        guard !node.isText, formulas.count < 2_000 else { return }
        var location = location
        if node.name == "div", let name = node.classes.first(where: { Self.match(Self.headerFooterPattern, $0) }) {
            location = Self.describeHeaderFooter(name)
        } else if node.name == "div", isAnchored(node) {
            location = "Text box"
        } else if node.name == "table" {
            location = "Table"
        }
        let d = cascade(node)
        if let ref = value(d, "-d4-ref") {
            let what = node.name == "img" ? "\(location) (image)" : node.name == "table" ? "Table data source" : location
            formulas.append(WriteProFormula(source: Self.formulaSource(WriteProCSS.unquote(ref)),
                                            name: value(d, "-d4-ref-name").map(WriteProCSS.unquote), location: what))
        } else if let url = value(d, "-d4-ref-url") {
            formulas.append(WriteProFormula(source: "(compiled formula \(WriteProCSS.unquote(url)))",
                                            name: value(d, "-d4-ref-name").map(WriteProCSS.unquote), location: location))
        }
        for child in node.children { collectFormulas(child, location: location) }
    }

    static func describeHeaderFooter(_ className: String) -> String {
        guard let m = headerFooterPattern.firstMatch(in: className, range: NSRange(className.startIndex..., in: className)),
              let n = Range(m.range(at: 1), in: className), let kind = Range(m.range(at: 3), in: className) else { return className }
        var text = "Section \(className[n]) \(className[kind].lowercased())"
        if let v = Range(m.range(at: 2), in: className) { text += " (\(className[v].lowercased()) page)" }
        return text
    }

    /// Turns 4D's tokenized formula text (`Current date:C33`, `[Table:1]Field:2`, `K7:1`) into readable source.
    public static func formulaSource(_ tokenized: String) -> String {
        var output = ""
        var chunk = ""
        var inString = false
        func flush() {
            var c = chunk
            c = c.replacingOccurrences(of: #":C[0-9]+"#, with: "", options: .regularExpression)
            c = c.replacingOccurrences(of: #":K[0-9]+:[0-9]+"#, with: "", options: .regularExpression)
            c = c.replacingOccurrences(of: #"\[([^\[\]:]+):[0-9]+\]"#, with: "[$1]", options: .regularExpression)
            c = c.replacingOccurrences(of: #"\]([^\[\]:;()]+?):[0-9]+"#, with: "]$1", options: .regularExpression)
            output += c
            chunk = ""
        }
        for ch in tokenized {
            if inString {
                output.append(ch)
                if ch == "\"" { inString = false }
            } else if ch == "\"" {
                flush()
                output.append(ch)
                inString = true
            } else {
                chunk.append(ch)
            }
        }
        flush()
        return output
    }

    private func formulaValue(_ source: String, page: PageContext) -> String? {
        switch source.replacingOccurrences(of: " ", with: "") {
        case "This.pageNumber": return String(page.number)
        case "This.pageIndex": return String(page.index)
        case "This.pageCount": return String(page.count)
        case "This.sectionName": return page.sectionName
        case "This.sectionIndex": return String(page.section)
        default: return nil
        }
    }

    // MARK: - Rendering

    /// The page sheets as an HTML fragment; style rules are in `css`.
    public func render() -> String {
        var html = ""
        budget = Self.paragraphBudget
        for (offset, sheet) in sheets.enumerated() {
            guard budget > 0 else {
                notice("The preview shows the first \(offset) of \(sheets.count) pages; the rest of this large document is not rendered.")
                break
            }
            html += render(sheet: sheet, page: pages[offset])
        }
        return html.replacingOccurrences(of: " style=\"\"", with: "")
    }

    private func render(sheet: Sheet, page: PageContext) -> String {
        let g = page.geometry
        let bodyDecl = cascade(document.body)
        var sheetStyle = "width:\(Self.pt(g.width));min-height:\(Self.pt(g.height))"
        if let bg = value(bodyDecl, "background-color").flatMap(Self.color) { sheetStyle += ";background-color:\(bg)" }
        if let image = value(bodyDecl, "background-image").flatMap({ backgroundImage($0) }) {
            sheetStyle += ";background-image:\(image)"
            for name in ["background-repeat", "background-position", "background-size"] {
                if let v = value(bodyDecl, name), Self.safe(v) { sheetStyle += ";\(name):\(v)" }
            }
        }
        var html = "<figure class=\"wp-page\"><div class=\"wp-sheet\" style=\"\(esc(sheetStyle))\">"
        let variant = self.variant(section: page.section, page: page)
        html += area(kind: "Header", variant: variant, page: page)
        html += "<div class=\"wp-body\" style=\"padding:0 \(Self.pt(g.margins.right)) 0 \(Self.pt(g.margins.left))\">"
        for segment in sheet.segments where !segment.items.isEmpty {
            html += "<div class=\"wp-segment\" style=\"\(esc(columns(section: segment.section)))\">"
            var pageForSegment = page
            pageForSegment.section = segment.section
            pageForSegment.sectionName = sectionNames[segment.section] ?? ""
            for item in segment.items {
                guard budget > 0 else { break }
                html += render(item, page: pageForSegment)
            }
            html += "</div>"
        }
        html += "</div>"
        html += area(kind: "Footer", variant: variant, page: page)
        for node in anchored where appears(node, on: page) {
            html += anchoredObject(node, page: page)
        }
        html += "</div><figcaption>Page \(page.number)"
        if !page.sectionName.isEmpty { html += " · \(esc(page.sectionName))" }
        return html + "</figcaption></figure>"
    }

    private func variant(section: Int, page: PageContext) -> String {
        let prefix = "section\(section)"
        func exists(_ v: String) -> Bool {
            document.hasClass(prefix + v) || headerFooters.keys.contains { $0.hasPrefix(prefix + v) }
        }
        let firstSheetOfSection = pages.isEmpty ? true : pages.firstIndex { $0.section == section }.map { $0 + 1 == page.index } ?? true
        if firstSheetOfSection, exists("First") { return "First" }
        if exists("Left") || exists("Right") {
            let right = ((page.index - 1) % 2 == 0) == page.geometry.firstRight
            return right ? "Right" : "Left"
        }
        return ""
    }

    private func area(kind: String, variant: String, page: PageContext) -> String {
        let g = page.geometry
        let className = "section\(page.section)\(variant)\(kind)"
        let isHeader = kind == "Header"
        let pageMargin = isHeader ? g.margins.top : g.margins.bottom
        guard let node = headerFooters[className] else {
            return "<div class=\"wp-\(kind.lowercased())\" style=\"min-height:\(Self.pt(pageMargin))\"></div>"
        }
        let gap = 0.5 / 2.54 * 72
        let fallback = isHeader ? Edges(pageMargin / 2, g.margins.right, gap, g.margins.left)
                                : Edges(gap, g.margins.right, pageMargin / 2, g.margins.left)
        let m = edges(document.rule(tag: "div", className: className), shorthand: "margin", prefix: "margin-", fallback: fallback)
        var style = "min-height:\(Self.pt(pageMargin));padding:\(Self.pt(m.top)) \(Self.pt(m.right)) \(Self.pt(m.bottom)) \(Self.pt(m.left))"
        style += translate(document.rule(tag: "div", className: className).filter { !$0.name.hasPrefix("margin") }, role: .box)
        var html = "<div class=\"wp-\(kind.lowercased()) wp-has-content\" style=\"\(esc(style))\" title=\"\(esc(Self.describeHeaderFooter(className)))\"><div>"
        for child in node.children where !child.isText {
            if child.name == "ul" || child.name == "ol" {
                for item in listItems(child) { html += render(item, page: page) }
            } else if isAnchored(child) {
                html += anchoredObject(child, page: page)
            } else {
                html += render(.block(child), page: page)
            }
        }
        return html + "</div></div>"
    }

    private func columns(section: Int) -> String {
        let d = sectionDeclarations(section)
        guard let count = value(d, "column-count").flatMap({ Int($0) }), count > 1 else { return "" }
        var style = "column-count:\(min(count, 20));column-fill:auto"
        if let gap = value(d, "column-gap").flatMap({ Self.points($0) }) { style += ";column-gap:\(Self.pt(gap))" }
        if let s = value(d, "column-rule-style"), Self.keyword(s) { style += ";column-rule-style:\(s)" }
        if let w = value(d, "column-rule-width").flatMap({ Self.points($0) }) { style += ";column-rule-width:\(Self.pt(w))" }
        if let c = value(d, "column-rule-color").flatMap(Self.color) { style += ";column-rule-color:\(c)" }
        return style
    }

    private func render(_ item: FlowItem, page: PageContext) -> String {
        switch item {
        case .listItem(let node, let marker):
            return paragraph(node, page: page, marker: marker)
        case .block(let node):
            switch node.name {
            case "p", "li", "h1", "h2", "h3", "h4", "h5", "h6", "pre", "blockquote": return paragraph(node, page: page, marker: nil)
            case "table": return table(node, page: page)
            case "ul", "ol": return listItems(node).map { render($0, page: page) }.joined()
            case "img", "span", "a", "br": return "<div class=\"wp-p\">" + inline(node, page: page, inherited: Inherited(), tabs: nil) + "</div>"
            case "div", "section", "article":
                if isAnchored(node) { return anchoredObject(node, page: page) }
                return node.children.filter { !$0.isText }.map { render(.block($0), page: page) }.joined()
            default:
                notice("Unsupported element <\(node.name)> is shown as plain text.")
                return "<div class=\"wp-p\">\(esc(String(node.textContent.prefix(10_000))))</div>"
            }
        }
    }

    // MARK: Paragraphs

    struct TabStop { var offset: Double; var type: String; var leader: String }

    private func paragraph(_ node: WriteProNode, page: PageContext, marker: String?) -> String {
        let d = cascade(node)
        var style = translate(d, role: .block)
        var inherited = Inherited()
        applyDecorations(d, to: &inherited)
        let stops = tabStops(d)
        if let def = stops.last, def.offset > 0 { style += ";tab-size:\(Self.pt(def.offset))" }
        if let bg = value(d, "background-color").flatMap(Self.color) { style += ";--wp-ground:\(bg)" }
        let rtl = value(d, "direction")?.lowercased() == "rtl"
        let explicitStops = Array(stops.dropLast())
        let useStops = !explicitStops.isEmpty && !rtl && node.textContent.contains("\t") && !Self.containsLineBreak(node)
        var content = useStops ? tabbed(node, stops: explicitStops, defaultStop: stops.last?.offset ?? 35.43, page: page, inherited: inherited)
                               : node.children.map { inline($0, page: page, inherited: inherited, tabs: nil) }.joined()
        if node.textContent.isEmpty && !node.children.contains(where: { $0.name == "img" || $0.name == "span" }) {
            content += "\u{200B}"
        }
        var html = "<div class=\"wp-p\(marker == nil ? "" : " wp-li")\(useStops ? " wp-tabbed" : "")\" style=\"\(esc(style))\">"
        if let marker, !marker.isEmpty {
            var markerStyle = ""
            if let font = value(d, "-d4-list-font").flatMap(Self.fontFamily) { markerStyle = "font-family:\(font)" }
            html += "<span class=\"wp-marker\(rtl ? " wp-marker-rtl" : "")\" style=\"\(esc(markerStyle))\" aria-hidden=\"true\">\(esc(marker))</span>"
        }
        budget -= 1 + node.textContent.count / 400
        return html + content + "</div>"
    }

    private static func containsLineBreak(_ node: WriteProNode) -> Bool {
        if node.name == "br" { return true }
        if node.isText { return node.text.contains("\n") || node.text.contains("\u{2028}") }
        return node.children.contains(where: containsLineBreak)
    }

    private func tabStops(_ d: [WriteProDeclaration]) -> [TabStop] {
        guard let offsets = value(d, "-d4-tab-stop-offset") else { return [TabStop(offset: 1.25 / 2.54 * 72, type: "left", leader: "")] }
        let values = WriteProCSS.components(offsets).compactMap { Self.points($0) }.map { Self.clamp($0, 0, 5_000) }
        let types = WriteProCSS.components(value(d, "-d4-tab-stop-type") ?? "")
        let leaders = WriteProCSS.components(value(d, "-d4-tab-stop-leading") ?? "").map(WriteProCSS.unquote)
        return values.prefix(64).enumerated().map { i, offset in
            TabStop(offset: offset, type: i < types.count ? types[i].lowercased() : "left",
                    leader: i < leaders.count ? String(leaders[i].prefix(1)) : "")
        }
    }

    /// Lays out tab-separated segments at absolute stops on a single line.
    private func tabbed(_ node: WriteProNode, stops: [TabStop], defaultStop: Double, page: PageContext, inherited: Inherited) -> String {
        var segments: [String] = [""]
        func walk(_ n: WriteProNode, wrap: [(String, String)], inherited: Inherited) {
            if n.isText {
                let parts = n.text.components(separatedBy: "\t")
                for (i, part) in parts.enumerated() {
                    if i > 0 { segments.append("") }
                    let text = textRun(part, inherited: inherited)
                    segments[segments.count - 1] += wrap.map(\.0).joined() + text + wrap.reversed().map(\.1).joined()
                }
                return
            }
            if n.name == "span" || n.name == "a" {
                let d = cascade(n)
                if value(d, "-d4-ref") != nil || n.name == "a" {
                    segments[segments.count - 1] += wrap.map(\.0).joined() + inline(n, page: page, inherited: inherited, tabs: nil) + wrap.reversed().map(\.1).joined()
                    return
                }
                var next = inherited
                applyDecorations(d, to: &next)
                let open = "<span style=\"\(esc(translate(d, role: .inline)))\">"
                for child in n.children { walk(child, wrap: wrap + [(open, "</span>")], inherited: next) }
                return
            }
            segments[segments.count - 1] += wrap.map(\.0).joined() + inline(n, page: page, inherited: inherited, tabs: nil) + wrap.reversed().map(\.1).joined()
        }
        for child in node.children { walk(child, wrap: [], inherited: inherited) }
        var html = "<span class=\"wp-tab-text\">\(segments[0].isEmpty ? "\u{200B}" : segments[0])</span>"
        var last = 0.0
        for (i, segment) in segments.dropFirst().enumerated() {
            let stop: TabStop
            if i < stops.count {
                stop = stops[i]
            } else {
                let base = max(last, stops.last?.offset ?? 0)
                stop = TabStop(offset: (floor(base / defaultStop) + 1) * defaultStop, type: "left", leader: "")
            }
            last = stop.offset
            let x = Self.pt(stop.offset)
            if !stop.leader.isEmpty {
                let fill = String(repeating: stop.leader, count: 400)
                html += "<span class=\"wp-leader\" style=\"width:\(x)\" aria-hidden=\"true\">\(esc(fill))</span>"
            }
            let shift: String
            switch stop.type {
            case "right", "decimal": shift = ";transform:translateX(-100%)"
            case "center": shift = ";transform:translateX(-50%)"
            default: shift = ""
            }
            html += "<span class=\"wp-tab-text wp-tab-stop\" style=\"left:\(x)\(shift)\">\(segment)</span>"
        }
        return html
    }

    // MARK: Inline content

    private func applyDecorations(_ d: [WriteProDeclaration], to inherited: inout Inherited) {
        if let decoration = value(d, "text-decoration")?.lowercased() {
            let lines = decoration.split(separator: " ").map(String.init)
            inherited.underline = lines.contains("underline") ? Decoration(line: "underline", style: "solid", color: nil) : nil
            inherited.lineThrough = lines.contains("line-through") ? Decoration(line: "line-through", style: "solid", color: nil) : nil
        }
        for (kind, prefix) in [("underline", "-d4-text-underline-"), ("line-through", "-d4-text-line-through-")] {
            var current = kind == "underline" ? inherited.underline : inherited.lineThrough
            if let style = value(d, prefix + "style")?.lowercased() {
                if style == "none" { current = nil } else if current == nil, d.contains(where: { $0.name == "text-decoration" }) == false {
                    current = Decoration(line: kind, style: "solid", color: nil)
                }
                current?.style = style
            }
            if let color = value(d, prefix + "color").flatMap(Self.color) { current?.color = color }
            if kind == "underline" { inherited.underline = current } else { inherited.lineThrough = current }
        }
    }

    private func decorationStyle(_ inherited: Inherited) -> String? {
        guard let primary = inherited.underline ?? inherited.lineThrough else { return nil }
        var lines = [String]()
        if inherited.underline != nil { lines.append("underline") }
        if inherited.lineThrough != nil { lines.append("line-through") }
        let style: String
        switch primary.style {
        case "dotted", "dashed", "double", "wavy": style = primary.style
        default: style = "solid"
        }
        var css = "text-decoration-line:\(lines.joined(separator: " "));text-decoration-style:\(style)"
        if var color = primary.color {
            if primary.style == "semi-transparent", color.hasPrefix("#"), color.count == 7 { color += "80" }
            css += ";text-decoration-color:\(color)"
        } else if primary.style == "semi-transparent" {
            css += ";text-decoration-color:rgba(0,0,0,0.5)"
        }
        if primary.style == "word" { css += ";text-decoration-skip-ink:none" }
        return css
    }

    private func textRun(_ text: String, inherited: Inherited) -> String {
        guard !text.isEmpty else { return "" }
        let body = esc(text)
        guard let decoration = decorationStyle(inherited) else { return body }
        if inherited.underline?.style == "word" {
            // Underline words only: leave whitespace undecorated.
            var html = ""
            var word = ""
            for ch in text {
                if ch.isWhitespace {
                    if !word.isEmpty { html += "<span style=\"\(decoration)\">\(esc(word))</span>"; word = "" }
                    html += esc(String(ch))
                } else { word.append(ch) }
            }
            if !word.isEmpty { html += "<span style=\"\(decoration)\">\(esc(word))</span>" }
            return html
        }
        return "<span style=\"\(decoration)\">\(body)</span>"
    }

    private func inline(_ node: WriteProNode, page: PageContext, inherited: Inherited, tabs: [TabStop]?) -> String {
        if node.isText { return textRun(node.text, inherited: inherited) }
        let d = cascade(node)
        switch node.name {
        case "br":
            return "<br>"
        case "img":
            if isAnchored(node) { return anchoredObject(node, page: page) }
            return image(node, declarations: d, page: page)
        case "span", "a", "b", "strong", "i", "em", "u", "s", "strike", "sup", "sub", "font", "small", "big", "code":
            if let ref = value(d, "-d4-ref") ?? value(d, "-d4-ref-url") {
                return formula(ref: ref, declarations: d, page: page, isURL: value(d, "-d4-ref") == nil)
            }
            var extra = ""
            switch node.name {
            case "b", "strong": extra = "font-weight:bold"
            case "i", "em": extra = "font-style:italic"
            case "sup": extra = "vertical-align:super;font-size:60%"
            case "sub": extra = "vertical-align:sub;font-size:60%"
            case "code": extra = "font-family:monospace"
            default: break
            }
            var next = inherited
            if node.name == "a", !d.contains(where: { $0.name == "text-decoration" || $0.name.hasPrefix("-d4-text-underline") }) {
                next.underline = Decoration(line: "underline", style: "solid", color: nil)
            }
            if node.name == "u" { next.underline = Decoration(line: "underline", style: "solid", color: nil) }
            if node.name == "s" || node.name == "strike" { next.lineThrough = Decoration(line: "line-through", style: "solid", color: nil) }
            applyDecorations(d, to: &next)
            var style = translate(d, role: .inline)
            if !extra.isEmpty { style = extra + style }
            var attributes = ""
            var className = ""
            if node.name == "a" {
                let href = node.attributes["href"] ?? ""
                attributes = " title=\"\(esc("Link: " + String(href.prefix(2_000))))\""
                className = " class=\"wp-link\""
            }
            let content = node.children.map { inline($0, page: page, inherited: next, tabs: tabs) }.joined()
            if style.isEmpty && attributes.isEmpty { return content }
            return "<span\(className) style=\"\(esc(style))\"\(attributes)>\(content)</span>"
        default:
            if ["p", "div", "table", "ul", "ol", "li"].contains(node.name) {
                return "<span class=\"wp-inline-block\">\(render(.block(node), page: page))</span>"
            }
            return node.children.map { inline($0, page: page, inherited: inherited, tabs: tabs) }.joined()
        }
    }

    private func formula(ref: String, declarations d: [WriteProDeclaration], page: PageContext, isURL: Bool) -> String {
        let source = isURL ? "compiled formula \(WriteProCSS.unquote(ref))" : Self.formulaSource(WriteProCSS.unquote(ref))
        let name = value(d, "-d4-ref-name").map(WriteProCSS.unquote)
        let style = translate(d, role: .inline)
        if let computed = formulaValue(source, page: page) {
            return "<span class=\"wp-computed\" style=\"\(esc(style))\" title=\"\(esc("Formula: " + source))\">\(esc(computed))</span>"
        }
        let label = String((name ?? source).prefix(200))
        let title = name.map { "Formula “\($0)”: \(source)" } ?? "Formula: \(source)"
        return "<span class=\"wp-formula\" style=\"\(esc(style))\" title=\"\(esc(title))\">\(esc(label))</span>"
    }

    private func image(_ node: WriteProNode, declarations d: [WriteProDeclaration], page: PageContext) -> String {
        var style = translate(d, role: .image)
        let width = value(d, "width").flatMap { Self.points($0) } ?? Double(node.attributes["width"] ?? "")
        let height = value(d, "height").flatMap { Self.points($0) } ?? Double(node.attributes["height"] ?? "")
        if value(d, "width") == nil, let width { style += ";width:\(Self.pt(Self.clamp(width, 0, 14_400)))" }
        if value(d, "height") == nil, let height { style += ";height:\(Self.pt(Self.clamp(height, 0, 14_400)))" }
        let alt = String((node.attributes["alt"] ?? "").prefix(500))
        if let ref = value(d, "-d4-ref") {
            let source = Self.formulaSource(WriteProCSS.unquote(ref))
            return "<span class=\"wp-image-placeholder\" style=\"\(esc(style))\" title=\"\(esc("Picture formula: " + source))\">\(esc(source))</span>"
        }
        let mode = value(d, "-d4-img-display-mode")?.lowercased() ?? "scaledtofit"
        switch document.imageSource(node.attributes["src"] ?? "") {
        case .data(let uri):
            if mode.hasPrefix("replicated") {
                return "<span class=\"wp-image\" role=\"img\" aria-label=\"\(esc(alt))\" style=\"\(esc(style + ";background-image:url('\(uri)');background-repeat:repeat\(mode == "replicatedcentered" ? ";background-position:center" : "")"))\"></span>"
            }
            let fit: String
            switch mode {
            case "proportional": fit = "object-fit:contain;object-position:left top"
            case "proportionalcentered": fit = "object-fit:contain;object-position:center"
            case "truncated": fit = "object-fit:none;object-position:left top"
            case "truncatedcentered": fit = "object-fit:none;object-position:center"
            default: fit = "object-fit:fill"
            }
            return "<img class=\"wp-image\" src=\"\(esc(uri))\" alt=\"\(esc(alt))\" style=\"\(esc(fit + ";" + style))\">"
        case .remote(let url):
            notice("Remote pictures are not downloaded; they are shown as placeholders.")
            return "<span class=\"wp-image-placeholder\" style=\"\(esc(style))\" title=\"\(esc("Remote picture: " + String(url.prefix(2_000))))\">Remote picture</span>"
        case .unavailable(let reason):
            notice("Some pictures cannot be displayed (\(reason)).")
            return "<span class=\"wp-image-placeholder\" style=\"\(esc(style))\" title=\"\(esc(alt))\">Picture</span>"
        }
    }

    // MARK: Anchored objects

    private func appears(_ node: WriteProNode, on page: PageContext) -> Bool {
        let d = cascade(node)
        if let p = value(d, "-d4-anchor-page")?.lowercased() {
            if let n = Int(p) { return n == page.index }
            if p == "first" { return pages.firstIndex { $0.section == page.section }.map { $0 + 1 == page.index } ?? false }
            if p == "left" || p == "right" {
                let right = ((page.index - 1) % 2 == 0) == page.geometry.firstRight
                return right == (p == "right")
            }
        }
        if let s = value(d, "-d4-anchor-section")?.lowercased(), let n = Int(s) {
            return sheets[page.index - 1].segments.contains { $0.section == n }
        }
        return true
    }

    private func anchoredObject(_ node: WriteProNode, page: PageContext) -> String {
        let d = cascade(node)
        let g = page.geometry
        let layout = value(d, "-d4-anchor-layout")?.lowercased() ?? "front"
        if layout.hasPrefix("wrap") {
            notice("Text wrapping around anchored pictures and text boxes is not simulated; they are drawn over the text.")
        }
        var origin: (top: Double, left: Double, right: Double, bottom: Double)
        switch value(d, "-d4-anchor-origin")?.lowercased() {
        case "content-box", "body-box": origin = (g.margins.top, g.margins.left, g.margins.right, g.margins.bottom)
        case "header-box": origin = (0, g.margins.left, g.margins.right, g.height - g.margins.top)
        case "footer-box": origin = (g.height - g.margins.bottom, g.margins.left, g.margins.right, 0)
        default: origin = (0, 0, 0, 0)
        }
        let h = value(d, "-d4-anchor-h-offset").flatMap { Self.points($0) } ?? 0
        let v = value(d, "-d4-anchor-v-offset").flatMap { Self.points($0) } ?? 0
        var position = "top:\(Self.pt(origin.top));left:\(Self.pt(origin.left));right:\(Self.pt(origin.right));bottom:\(Self.pt(origin.bottom))"
        position += ";z-index:\(layout == "behind" ? -1 : 1)"
        var placement: [String] = []
        switch value(d, "-d4-anchor-h-align")?.lowercased() {
        case "right": placement.append("right:\(Self.pt(-h))")
        case "center": placement.append("left:calc(50% + \(Self.pt(h)))"); placement.append("translate:-50% 0")
        default: placement.append("left:\(Self.pt(h))")
        }
        switch value(d, "-d4-anchor-v-align")?.lowercased() {
        case "bottom": placement.append("bottom:\(Self.pt(-v))")
        case "center": placement.append("top:calc(50% + \(Self.pt(v)))"); placement.append(placement.last == "translate:-50% 0" ? "translate:-50% -50%" : "translate:0 -50%")
        default: placement.append("top:\(Self.pt(v))")
        }
        if placement.filter({ $0.hasPrefix("translate:") }).count > 1 { placement.removeAll { $0 == "translate:-50% 0" } }
        let content: String
        if node.name == "div" {
            var style = translate(d, role: .box)
            style += ";position:absolute;" + placement.joined(separator: ";")
            var inner = ""
            for child in node.children where !child.isText {
                inner += render(.block(child), page: page)
            }
            content = "<div class=\"wp-textbox\" style=\"\(esc(style))\" title=\"Text box\">\(inner)</div>"
        } else {
            let img = image(node, declarations: d.filter { !["position", "display", "z-index"].contains($0.name) }, page: page)
            content = "<span class=\"wp-anchored\" style=\"\(esc(placement.joined(separator: ";")))\">\(img)</span>"
        }
        return "<div class=\"wp-anchor-origin\" style=\"\(esc(position))\">\(content)</div>"
    }

    // MARK: Tables

    private func table(_ node: WriteProNode, page: PageContext) -> String {
        let d = cascade(node)
        var style = translate(d, role: .table)
        switch value(d, "-d4-table-align")?.lowercased() {
        case "center": style += ";margin-left:auto;margin-right:auto"
        case "right": style += ";margin-left:auto;margin-right:0"
        default: break
        }
        var html = ""
        let datasource = value(d, "-d4-ref").map { Self.formulaSource(WriteProCSS.unquote($0)) }
        if let datasource {
            style += ";outline:1px dashed #6b8ec9;outline-offset:2px"
            html += "<div class=\"wp-datasource\" title=\"\(esc("Table data source: " + datasource))\"><span class=\"wp-datasource-label\">\(esc(datasource))</span>"
        }
        html += "<table class=\"wp-table\" style=\"\(esc(style))\"><tbody>"
        var rows: [WriteProNode] = []
        for child in node.children where !child.isText {
            if child.name == "tr" { rows.append(child) }
            else if ["thead", "tbody", "tfoot"].contains(child.name) { rows += child.children.filter { $0.name == "tr" } }
        }
        for row in rows.prefix(5_000) {
            let rd = cascade(row)
            let header = value(rd, "-d4-header")?.lowercased() == "true"
            html += "<tr\(header ? " class=\"wp-header-row\"" : "") style=\"\(esc(translate(rd, role: .row)))\">"
            for cell in row.children where cell.name == "td" || cell.name == "th" {
                var attributes = ""
                for span in ["colspan", "rowspan"] {
                    if let n = Int(cell.attributes[span] ?? ""), n > 1 { attributes += " \(span)=\"\(min(n, 1_000))\"" }
                }
                let cd = cascade(cell)
                html += "<td\(attributes) style=\"\(esc(translate(cd, role: .cell)))\">"
                for child in cell.children where !child.isText { html += render(.block(child), page: page) }
                html += "</td>"
            }
            html += "</tr>"
        }
        html += "</tbody></table>"
        if datasource != nil { html += "</div>" }
        return html
    }

    // MARK: - CSS translation

    enum Role { case block, inline, table, row, cell, image, box }

    private static let lengthProperties: Set<String> = [
        "margin", "margin-top", "margin-right", "margin-bottom", "margin-left",
        "padding", "padding-top", "padding-right", "padding-bottom", "padding-left",
        "border-width", "border-top-width", "border-right-width", "border-bottom-width", "border-left-width",
        "border-radius", "border-top-left-radius", "border-top-right-radius", "border-bottom-left-radius", "border-bottom-right-radius",
        "width", "height", "min-height", "min-width", "max-width", "max-height", "text-indent", "letter-spacing", "word-spacing", "border-spacing"
    ]
    private static let keywordProperties: Set<String> = [
        "font-weight", "font-style", "text-align", "direction", "text-transform", "border-style", "border-top-style", "border-right-style",
        "border-bottom-style", "border-left-style", "border-collapse", "vertical-align", "background-repeat", "background-origin", "background-clip",
        "font-variant"
    ]
    private static let colorProperties: Set<String> = [
        "color", "background-color", "border-color", "border-top-color", "border-right-color", "border-bottom-color", "border-left-color"
    ]

    func translate(_ declarations: [WriteProDeclaration], role: Role) -> String {
        var out: [String] = []
        for decl in declarations {
            let name = decl.name
            var v = decl.value.replacingOccurrences(of: "!important", with: "").trimmingCharacters(in: .whitespaces)
            switch name {
            case "font-family":
                if let f = Self.fontFamily(v) { out.append("font-family:\(f)") }
            case "font-size":
                if Self.length(v) || Self.keyword(v) { out.append("font-size:\(v)") }
            case "line-height":
                if Self.length(v) || v == "normal" || Double(v) != nil { out.append("line-height:\(v)") }
            case "-d4-text-background-color":
                if role == .inline, let c = Self.color(v) { out.append("background-color:\(c)") }
            case "-d4-text-transform":
                switch v.lowercased() {
                case "small-uppercase", "small-caps": out.append("font-variant:small-caps")
                case "uppercase", "lowercase", "capitalize", "none": out.append("text-transform:\(v.lowercased())")
                default: break
                }
            case "text-shadow":
                if Self.safe(v) { out.append("text-shadow:\(v)") }
            case "vertical-align":
                if role == .inline || role == .cell || role == .image, Self.keyword(v) || Self.length(v) { out.append("vertical-align:\(v)") }
            case "background-image":
                if let image = backgroundImage(v) { out.append("background-image:\(image)") }
            case "background-position", "background-size":
                if Self.safe(v) { out.append("\(name):\(v)") }
            case "border", "border-top", "border-right", "border-bottom", "border-left":
                if Self.safe(v) { out.append("\(name):\(v)") }
            case "break-after":
                if v.lowercased() == "column" { out.append("break-after:column;-webkit-column-break-after:always") }
            case "opacity":
                if let o = Double(v), o >= 0, o <= 1 { out.append("opacity:\(o)") }
            case "text-decoration", "-d4-text-underline-style", "-d4-text-underline-color", "-d4-text-line-through-style", "-d4-text-line-through-color":
                break
            default:
                if Self.lengthProperties.contains(name) {
                    if role == .inline, name.hasPrefix("width") || name.hasPrefix("height") { break }
                    if name == "margin" || name == "padding" || name == "border-width" || name == "border-radius" {
                        v = WriteProCSS.components(v).filter { Self.length($0) || $0 == "auto" }.prefix(4).joined(separator: " ")
                        if !v.isEmpty { out.append("\(name):\(v)") }
                    } else if Self.length(v) || v == "auto" {
                        out.append("\(name):\(v)")
                    }
                } else if Self.colorProperties.contains(name) {
                    let colors = WriteProCSS.components(v).compactMap(Self.color)
                    if !colors.isEmpty, colors.count <= 4 { out.append("\(name):\(colors.joined(separator: " "))") }
                } else if Self.keywordProperties.contains(name) {
                    let words = WriteProCSS.components(v)
                    if !words.isEmpty, words.count <= 4, words.allSatisfy(Self.keyword) { out.append("\(name):\(words.joined(separator: " "))") }
                }
            }
        }
        return out.isEmpty ? "" : out.joined(separator: ";")
    }

    private func backgroundImage(_ value: String) -> String? {
        let v = value.trimmingCharacters(in: .whitespaces)
        guard v.lowercased().hasPrefix("url("), v.hasSuffix(")") else { return nil }
        let inner = WriteProCSS.unquote(String(v.dropFirst(4).dropLast()))
        guard case .data(let uri) = document.imageSource(inner) else {
            notice("Some background pictures cannot be displayed.")
            return nil
        }
        return "url('\(uri)')"
    }

    private func marker(for item: WriteProNode, number: Int, ordered: Bool) -> String {
        let d = cascade(item)
        let type = (value(d, "-d4-list-style-type") ?? value(d, "list-style-type") ?? (ordered ? "decimal" : "disc")).lowercased()
        let label: String
        switch type {
        case "none": return ""
        case "disc": return "●"
        case "circle": return "○"
        case "square": return "■"
        case "hollow-square": return "□"
        case "diamond": return "◆"
        case "club": return "♣"
        case "check", "checkmark": return "✓"
        case "custom":
            let format = value(d, "-d4-list-string-format-ltr").map(WriteProCSS.unquote) ?? "•"
            return String(format.replacingOccurrences(of: "#", with: String(number)).prefix(40))
        case "decimal": label = String(number)
        case "decimal-leading-zero": label = number < 10 && number >= 0 ? "0\(number)" : String(number)
        case "lower-roman": label = Self.roman(number).lowercased()
        case "upper-roman": label = Self.roman(number)
        case "lower-latin", "lower-alpha": label = Self.alphabetic(number, Array("abcdefghijklmnopqrstuvwxyz"))
        case "upper-latin", "upper-alpha": label = Self.alphabetic(number, Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ"))
        case "lower-greek", "decimal-greek": label = Self.alphabetic(number, Array("αβγδεζηθικλμνξοπρστυφχψω"))
        case "upper-greek": label = Self.alphabetic(number, Array("ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩ"))
        case "hiragana": label = Self.alphabetic(number, Array("あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをん"))
        case "katakana": label = Self.alphabetic(number, Array("アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン"))
        case "hiragana-iroha": label = Self.alphabetic(number, Array("いろはにほへとちりぬるをわかよたれそつねならむうゐのおくやまけふこえてあさきゆめみしゑひもせす"))
        case "katakana-iroha": label = Self.alphabetic(number, Array("イロハニホヘトチリヌルヲワカヨタレソツネナラムウヰノオクヤマケフコエテアサキユメミシヱヒモセス"))
        case "cjk-ideographic", "cjk-decimal", "japanese-informal": label = Self.cjk(number)
        default: label = String(number)
        }
        let format = value(d, "-d4-list-string-format-ltr").map(WriteProCSS.unquote) ?? "#."
        return String((format.contains("#") ? format.replacingOccurrences(of: "#", with: label) : label + format).prefix(40))
    }

    // MARK: - Value helpers

    static func roman(_ n: Int) -> String {
        guard n > 0, n < 4_000 else { return String(n) }
        let table: [(Int, String)] = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
                                      (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var n = n, s = ""
        for (value, symbol) in table { while n >= value { s += symbol; n -= value } }
        return s
    }

    static func alphabetic(_ n: Int, _ alphabet: [Character]) -> String {
        guard n > 0, n < 1_000_000 else { return String(n) }
        var n = n, s = ""
        while n > 0 { n -= 1; s = String(alphabet[n % alphabet.count]) + s; n /= alphabet.count }
        return s
    }

    static func cjk(_ n: Int) -> String {
        let digits = Array("〇一二三四五六七八九")
        guard n >= 0, n < 1_000_000 else { return String(n) }
        return String(String(n).compactMap { $0.wholeNumberValue.map { digits[$0] } })
    }

    /// Converts a CSS length to points; nil for relative or invalid values.
    static func points(_ value: String) -> Double? {
        let v = value.trimmingCharacters(in: .whitespaces).lowercased()
        let units: [(String, Double)] = [("pt", 1), ("px", 0.75), ("cm", 72 / 2.54), ("mm", 72 / 25.4), ("in", 72), ("pc", 12)]
        for (unit, factor) in units where v.hasSuffix(unit) {
            guard let n = Double(v.dropLast(unit.count)), n.isFinite else { return nil }
            return n * factor
        }
        if let n = Double(v), n == 0 { return 0 }
        return nil
    }

    static func length(_ value: String) -> Bool {
        let v = value.trimmingCharacters(in: .whitespaces).lowercased()
        guard !v.isEmpty, v.count < 32 else { return false }
        if points(v) != nil { return abs(points(v)!) < 100_000 }
        for unit in ["em", "%", "ex", "rem"] where v.hasSuffix(unit) {
            if let n = Double(v.dropLast(unit.count)), n.isFinite, abs(n) < 100_000 { return true }
        }
        return false
    }

    static func keyword(_ value: String) -> Bool {
        let v = value.trimmingCharacters(in: .whitespaces)
        return !v.isEmpty && v.count < 40 && v.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
            && !v.lowercased().contains("expression")
    }

    static func color(_ value: String) -> String? {
        let v = value.trimmingCharacters(in: .whitespaces)
        if v.hasPrefix("#"), [4, 5, 7, 9].contains(v.count), v.dropFirst().allSatisfy(\.isHexDigit) { return v }
        let lower = v.lowercased()
        for function in ["rgb(", "rgba(", "hsl(", "hsla("] where lower.hasPrefix(function) && lower.hasSuffix(")") {
            let inner = lower.dropFirst(function.count).dropLast()
            if inner.count < 64, inner.allSatisfy({ $0.isNumber || " .,%/".contains($0) }) { return lower }
        }
        if keyword(v), v.allSatisfy(\.isLetter) { return lower }
        return nil
    }

    /// Generic validation for composite values (shadows, positions, border shorthands).
    static func safe(_ value: String) -> Bool {
        let lower = value.lowercased()
        guard value.count < 200, !lower.contains("url"), !lower.contains("expression"), !lower.contains("var(") else { return false }
        var rest = lower
        for function in ["rgba(", "rgb(", "hsla(", "hsl("] { rest = rest.replacingOccurrences(of: function, with: "") }
        let openParens = rest.filter { $0 == "(" }.count
        return openParens == 0 && rest.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || " #%.,-+)/".contains($0)) }
    }

    static func fontFamily(_ value: String) -> String? {
        let names = value.split(separator: ",").map { WriteProCSS.unquote(String($0)).trimmingCharacters(in: .whitespaces) }
        let valid = names.filter { name in
            !name.isEmpty && name.count < 100 && !name.contains { "\\<>{};\"'()@:&".contains($0) || $0.isNewline }
        }
        guard !valid.isEmpty else { return nil }
        let generic: Set<String> = ["serif", "sans-serif", "monospace", "cursive", "fantasy", "system-ui"]
        return valid.prefix(8).map { generic.contains($0.lowercased()) ? $0.lowercased() : "'\($0)'" }.joined(separator: ",")
    }

    static func pt(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return (rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)) + "pt"
    }

    static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }

    static func match(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private func notice(_ text: String) {
        if noticeSet.insert(text).inserted { notices.append(text) }
    }

    private func esc(_ s: String) -> String { HTMLRenderer.escape(s) }

    // MARK: - Style sheet

    public static let css = """
    .wp-preview .form-scroll{overflow:auto;max-height:85vh;border:1px solid var(--line);border-radius:6px;background:#8e8d89}
    .wp-pages{zoom:var(--form-scale,1);display:flex;flex-direction:column;align-items:center;gap:18px;padding:18px;width:max-content;min-width:100%;box-sizing:border-box}
    .wp-page{margin:0;display:flex;flex-direction:column;align-items:center;gap:6px}
    .wp-page figcaption{font:11px -apple-system,BlinkMacSystemFont,sans-serif;color:#f4f4f2}
    .wp-sheet{position:relative;isolation:isolate;display:flex;flex-direction:column;box-sizing:border-box;background:#fff;color:#000;color-scheme:light;
      box-shadow:0 1px 4px rgba(0,0,0,.35);font:12pt/normal 'Times New Roman',serif;text-align:start;overflow:hidden;--wp-ground:#fff;overflow-wrap:break-word}
    .wp-header,.wp-footer{box-sizing:border-box;flex:none;display:flex;flex-direction:column}
    .wp-footer{justify-content:flex-end}
    .wp-has-content{outline:1px dashed rgba(0,0,0,.08);outline-offset:-1px}
    .wp-body{flex:1 0 auto;box-sizing:border-box}
    .wp-segment{min-height:0}
    .wp-p{white-space:pre-wrap;margin:0;padding:0;position:relative;border:0 none #000}
    .wp-marker{position:absolute;right:100%;top:0;padding-right:.35em;white-space:pre;text-indent:0;font-style:normal;font-weight:normal;text-decoration:none}
    .wp-marker-rtl{right:auto;left:100%;padding-right:0;padding-left:.35em}
    .wp-tabbed{white-space:pre}
    .wp-tab-text{position:relative;z-index:1;background:var(--wp-ground)}
    .wp-tab-stop{position:absolute;top:0;white-space:pre}
    .wp-leader{position:absolute;left:0;top:0;overflow:hidden;white-space:pre;z-index:0;text-decoration:none}
    .wp-sheet table.wp-table{border-collapse:collapse;border-spacing:0;width:auto;margin:0;table-layout:auto}
    .wp-sheet .wp-table td{border:0 none #000;padding:0;vertical-align:top;word-break:normal;overflow-wrap:break-word}
    .wp-sheet .wp-table tr{border:0 none #000}
    .wp-datasource{position:relative}
    .wp-datasource-label{position:absolute;left:0;bottom:100%;margin-bottom:3px;font:9px ui-monospace,Menlo,monospace;color:#3f63a3;white-space:nowrap}
    .wp-formula{background:#e6ebf3;border-radius:2px;box-shadow:inset 0 0 0 .5pt #a9b7cf;padding:0 2px;white-space:pre-wrap}
    .wp-computed{background:rgba(120,140,180,.12);border-radius:2px}
    .wp-link{cursor:default;color:#00e}
    .wp-image{display:inline-block;box-sizing:content-box;vertical-align:baseline;border:0 none #000}
    .wp-image-placeholder{display:inline-flex;align-items:center;justify-content:center;box-sizing:border-box;min-width:24pt;min-height:16pt;
      background:repeating-linear-gradient(45deg,#f2f2f2 0 6px,#e4e4e4 6px 12px);border:1px dashed #999;color:#555;font:9px -apple-system,sans-serif;overflow:hidden;
      vertical-align:baseline;text-align:center;white-space:normal}
    .wp-anchor-origin{position:absolute;pointer-events:none}
    .wp-anchored{position:absolute;line-height:0}
    .wp-textbox{box-sizing:content-box;overflow:hidden;border:0 none #000}
    .wp-inline-block{display:inline-block;vertical-align:top}
    """
}
