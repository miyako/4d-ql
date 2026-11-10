import Foundation
import FourDFileKit

public struct WriteProPreview {
    public var document: WriteProFileInfo
    /// Rendered page sheets (HTML fragment).
    public var pages: String
    public var pageCount: Int
}

public struct WriteProPresenter: ReportPresenter {
    public init() {}
    public var kinds: [String] { ["4d.writepro"] }

    public func report(for model: AnalysisModel) -> Report? {
        guard let doc = model as? WriteProFileInfo else { return nil }
        let renderer = WriteProDocumentRenderer(doc)
        let pages = renderer.render()
        let stats = renderer.statistics
        let size = renderer.geometry
        var report = Report(title: doc.fileName, subtitle: doc.title.isEmpty ? "4D Write Pro document" : "4D Write Pro document · \(doc.title)")
        if let version = doc.version { report.badges.append(Badge("Format \(version)")) }
        if !renderer.formulas.isEmpty { report.badges.append(Badge("\(renderer.formulas.count)\(renderer.formulas.count >= 2_000 ? "+" : "") formula\(renderer.formulas.count == 1 ? "" : "s")")) }
        if doc.body.textContent.isEmpty && renderer.formulas.isEmpty { report.badges.append(Badge("Empty", .warning)) }
        report.stats = [
            Stat("Page size", "\(paper(size.width, size.height))\(size.landscape ? " landscape" : "")"),
            Stat("Pages", "\(renderer.pageCount)"),
            Stat("Sections", "\(renderer.sectionCount)"),
            Stat("Paragraphs", "\(stats.paragraphs + stats.listItems)"),
            Stat("Tables", "\(stats.tables)"),
            Stat("Pictures", "\(stats.images + stats.anchoredImages)")
        ]
        if stats.textBoxes > 0 { report.stats.append(Stat("Text boxes", "\(stats.textBoxes)")) }
        report.sections = [Section("Document", [
            .writeProPreview(WriteProPreview(document: doc, pages: pages, pageCount: renderer.pageCount)),
            .note("Static preview: pages split at hard page and section breaks only, so long passages are not flowed onto further pages. Formulas are never evaluated; page numbers, page count and section names are computed.", .neutral)
        ])]

        if !renderer.formulas.isEmpty {
            let rows = renderer.formulas.prefix(500).map { [$0.name ?? "", $0.source, $0.location] }
            report.sections.append(Section("Formulas", [.table(Table(columns: [("Name", .leading), ("Formula", .leading), ("Location", .leading)],
                                                                     rows: Array(rows),
                                                                     more: renderer.formulas.count > 500 ? "and \(renderer.formulas.count - 500) more" : nil))]))
        }

        var styles: [KeyValue] = []
        var seen = Set<String>()
        for rule in doc.rules {
            for selector in rule.selectors {
                guard let className = selector.className, !className.hasPrefix("_"), !className.hasPrefix("section"),
                      seen.insert((selector.tag == "span" ? "c:" : "p:") + className).inserted else { continue }
                styles.append(KeyValue("\(className.replacingOccurrences(of: "_", with: " ")) (\(selector.tag == "span" ? "character" : "paragraph"))",
                                       rule.declarations.filter { !$0.name.hasPrefix("-d4-font") && $0.name != "white-space" }
                                           .map { "\($0.name): \($0.value)" }.joined(separator: "; "), mono: true))
            }
        }

        var properties: [KeyValue] = []
        if !doc.title.isEmpty { properties.append(KeyValue("Title", doc.title)) }
        for meta in doc.metadata where meta.name != "bookmarks" { properties.append(KeyValue(meta.name.capitalized, meta.value)) }
        if let entry = doc.htmlEntry { properties.append(KeyValue("Archive entry", entry, mono: true)) }
        if doc.archiveEntries.count > 1 { properties.append(KeyValue("Archive entries", "\(doc.archiveEntries.count)")) }
        if let custom = doc.customAttributes { properties.append(KeyValue("Custom attributes", custom, mono: true)) }
        for (name, range) in doc.bookmarks.sorted(by: { $0.key < $1.key }).prefix(200) {
            properties.append(KeyValue("Bookmark “\(name)”", range.count == 2 ? "characters \(range[0])–\(range[1])" : "\(range)"))
        }
        if stats.links > 0 { properties.append(KeyValue("Links", "\(stats.links) (not followed in the preview)")) }
        var details: [Block] = []
        if !properties.isEmpty { details.append(.keyValues(properties)) }
        if !styles.isEmpty { details.append(.disclosure(summary: "Style sheets", detail: "\(styles.count)", blocks: [.keyValues(styles)])) }
        if !details.isEmpty { report.sections.append(Section("Properties", details)) }

        let warnings = doc.warnings + renderer.notices
        if !warnings.isEmpty {
            report.sections.append(Section("", [.disclosure(summary: "Preview notices", detail: "\(warnings.count)",
                                                            blocks: warnings.map { .note($0, .warning) })]))
        }
        var source = doc.html.replacingOccurrences(of: #"base64,[A-Za-z0-9+/=]{64,}"#, with: "base64,…", options: .regularExpression)
        var blocks: [Block] = []
        if source.count > 256 * 1024 {
            source = String(source.prefix(256 * 1024))
            blocks.append(.note("Original XHTML display truncated to 256 Ki characters.", .warning))
        }
        blocks.append(.sourceCode(source, language: .xml))
        report.sections.append(Section("", [.disclosure(summary: "Original XHTML", detail: "embedded pictures elided", blocks: blocks)]))
        return report
    }

    private func paper(_ width: Double, _ height: Double) -> String {
        let named: [(String, Double, Double)] = [("A4", 595, 842), ("US Letter", 612, 792), ("US Legal", 612, 1008), ("A3", 842, 1191),
                                                 ("A5", 420, 595), ("B5", 499, 709)]
        let short = min(width, height), long = max(width, height)
        if let match = named.first(where: { abs($0.1 - short) < 2 && abs($0.2 - long) < 2 }) { return match.0 }
        let f = { (v: Double) in String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), v / 72 * 2.54) }
        return "\(f(width)) × \(f(height)) cm"
    }
}

enum WriteProPreviewRenderer {
    static func render(_ preview: WriteProPreview, identifier: String) -> String {
        var html = "<style>\(CanvasZoomControls.css(kind: "form"))\(WriteProDocumentRenderer.css)</style>"
        html += "<div class=\"wp-preview form-zoom\">"
        html += CanvasZoomControls.render(kind: "form", identifier: identifier, viewport: ".form-zoom-content", scaleProperty: "--form-scale")
        html += "<div class=\"form-zoom-content\"><div class=\"form-scroll\" tabindex=\"0\" role=\"region\" aria-label=\"Document pages\">"
        html += "<div class=\"wp-pages\">\(preview.pages)</div></div></div></div>"
        return html
    }
}
