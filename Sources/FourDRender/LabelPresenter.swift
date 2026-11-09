import Foundation
import FourDFileKit

public struct LabelPreview {
    public var label: LabelFileInfo
}

public struct LabelPresenter: ReportPresenter {
    public init() {}
    public var kinds: [String] { ["4d.label"] }

    public func report(for model: AnalysisModel) -> Report? {
        guard let label = model as? LabelFileInfo else { return nil }
        let l = label.layout
        var report = Report(title: label.fileName, subtitle: "4D Label")
        report.stats = [Stat("Label size", "\(n(l.width)) × \(n(l.height)) pt"),
                        Stat("Sheet", "\(l.columns) × \(l.rows)"),
                        Stat("Start", "\(l.start)"), Stat("Labels per record", "\(l.copies)")]
        report.sections = [Section("Label and sheet layout", [.labelPreview(LabelPreview(label: label))])]
        var warnings = label.warnings
        if let form = label.form {
            report.sections.append(Section("Referenced form", [
                .formPreview(FormPreview(name: form.formName, properties: form.properties, appearances: form.appearances,
                                         images: form.images, platform: form.platform))
            ]))
            warnings += form.warnings + FormPreviewRenderer.diagnostics(form)
        }
        let settings = label.root.children.filter { !["objects", "selects"].contains($0.name) }
        var values = [KeyValue("Print order", l.vertical ? "Down, then across" : "Across, then down"),
                      KeyValue("Orientation", l.landscape ? "Landscape" : "Portrait"),
                      KeyValue("Display unit", l.unit),
                      KeyValue("Margins (L / T / R / B)", [l.left, l.top, l.right, l.bottom].map(n).joined(separator: " / ") + " pt"),
                      KeyValue("Gaps (horizontal / vertical)", "\(n(l.horizontalGap)) / \(n(l.verticalGap)) pt")]
        values += settings.flatMap { node in
            node.attributes.sorted { $0.key < $1.key }.map { KeyValue("\(node.name) / \($0.key)", $0.value) }
        }
        report.sections.append(Section("Settings", [.keyValues(values),
            .note("Static design preview, not a print job. Measurements are saved points; sheet extent is inferred from labels, margins and gaps, not printer paper. Expressions and methods are never executed.", .neutral)]))
        if !warnings.isEmpty {
            report.sections.append(Section("", [.disclosure(summary: "Preview notices", detail: "\(warnings.count)",
                                                            blocks: warnings.map { .note($0, .warning) })]))
        }
        var source: [Block] = [.sourceCode(String(label.text.prefix(256 * 1024)), language: .xml)]
        if label.text.count > 256 * 1024 { source.insert(.note("Original XML display truncated to 256 Ki characters.", .warning), at: 0) }
        report.sections.append(Section("", [.disclosure(summary: "Original XML", detail: nil, blocks: source)]))
        return report
    }

    private func n(_ value: Double) -> String { String(format: "%g", locale: Locale(identifier: "en_US_POSIX"), value) }
}

enum LabelPreviewRenderer {
    static func render(_ label: LabelFileInfo, identifier: String) -> String {
        let l = label.layout
        let symbol = "\(identifier)-label"
        let clip = "\(identifier)-clip"
        let formName = label.root.children.first { $0.name == "form" }?.attributes["name"] ?? ""
        var artwork = ""
        if !formName.isEmpty {
            artwork = "<text x=\"8\" y=\"20\" font-size=\"12\" fill=\"#555\">\(esc(formName)) (referenced form)</text>"
        } else {
            artwork = label.objects.map(draw).joined()
        }
        var html = """
        <style>
        \(CanvasZoomControls.css(kind: "form"))
        .label-preview .form-scroll{overflow:auto;max-height:680px;border:1px solid var(--border);margin-bottom:16px}
        .label-preview .form-scroll>svg{display:block;max-width:none;width:calc(var(--form-width)*var(--form-scale,1));height:calc(var(--form-height)*var(--form-scale,1))}
        </style><div class="label-preview form-zoom">
        """
        html += CanvasZoomControls.render(kind: "form", identifier: identifier, viewport: ".form-zoom-content", scaleProperty: "--form-scale")
        html += "<div class=\"form-zoom-content\"><svg width=\"0\" height=\"0\" aria-hidden=\"true\" style=\"position:absolute\"><defs>"
        html += "<clipPath id=\"\(clip)\"><rect width=\"\(n(l.width))\" height=\"\(n(l.height))\"/></clipPath>"
        html += "<g id=\"\(symbol)\" clip-path=\"url(#\(clip))\"><rect width=\"\(n(l.width))\" height=\"\(n(l.height))\" fill=\"white\"/>\(artwork)</g>"
        html += "</defs></svg>"
        html += canvas(width: l.width, height: l.height, title: "Label design") + "<use href=\"#\(symbol)\"/></svg></div>"
        html += canvas(width: l.sheetWidth, height: l.sheetHeight, title: "Saved sheet layout")
        html += "<rect width=\"100%\" height=\"100%\" fill=\"white\"/>"
        for row in 0..<l.rows {
            for column in 0..<l.columns {
                let position = l.vertical ? column * l.rows + row + 1 : row * l.columns + column + 1
                let x = l.left + Double(column) * (l.width + l.horizontalGap)
                let y = l.top + Double(row) * (l.height + l.verticalGap)
                html += "<g transform=\"translate(\(n(x)) \(n(y)))\" data-position=\"\(position)\"><title>Position \(position)\(position < l.start ? " (skipped)" : "")</title>"
                if position >= l.start { html += "<use href=\"#\(symbol)\"/>" }
                html += "<rect width=\"\(n(l.width))\" height=\"\(n(l.height))\" fill=\"\(position < l.start ? "#ddd" : "none")\" stroke=\"#aaa\" stroke-width=\"0.5\" stroke-dasharray=\"3 2\"/></g>"
            }
        }
        return html + "</svg></div></div></div>"
    }

    private static func canvas(width: Double, height: Double, title: String) -> String {
        "<p>\(title)</p><div class=\"form-scroll\" tabindex=\"0\" role=\"region\" aria-label=\"\(title)\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(n(width))\" height=\"\(n(height))\" viewBox=\"0 0 \(n(width)) \(n(height))\" role=\"img\" aria-label=\"\(title)\" style=\"--form-width:\(n(width))px;--form-height:\(n(height))px\">"
    }

    private static func draw(_ object: LabelObject) -> String {
        let a = object.attributes
        let w = object.width, h = object.height
        let renderer = FormPreviewRenderer(platform: .current)
        let stroke = renderer.color(a["stroke-color"], fallback: "black")
        let fill = renderer.color(a["fill-color"], fallback: "none")
        let style = " fill=\"\(fill)\" fill-opacity=\"\(n(value(a, "fill-opacity", 1)))\" stroke=\"\(stroke)\" stroke-opacity=\"\(n(value(a, "stroke-opacity", 1)))\" stroke-width=\"\(n(value(a, "stroke-width", 1)))\""
        var svg = "<g transform=\"translate(\(n(object.x)) \(n(object.y)))\"><title>\(esc(FormTextLayout.bounded(a["value"] ?? object.type)))</title>"
        switch object.type {
        case "rect", "round-rect":
            svg += "<rect width=\"\(n(w))\" height=\"\(n(h))\" rx=\"\(n(object.type == "round-rect" ? value(a, "rx", 6) : 0))\" ry=\"\(n(object.type == "round-rect" ? value(a, "ry", 6) : 0))\"\(style)/>"
        case "oval":
            svg += "<ellipse cx=\"\(n(w/2))\" cy=\"\(n(h/2))\" rx=\"\(n(w/2))\" ry=\"\(n(h/2))\"\(style)/>"
        case "line":
            let up = a["direction"] == "up"
            svg += "<line x1=\"0\" y1=\"\(up ? n(h) : "0")\" x2=\"\(n(w))\" y2=\"\(up ? "0" : n(h))\"\(style)/>"
        case "polyline":
            let components = (a["data"] ?? "").split { $0 == "," || $0.isWhitespace }
            let points = components.compactMap { Double($0) }
            if points.count == components.count, points.count >= 4, points.count <= 4_096, points.count % 2 == 0,
               points.allSatisfy({ $0.isFinite && abs($0) <= 32_768 }) {
                let pairs = stride(from: 0, to: points.count, by: 2).map { "\(n(points[$0] + w/2)),\(n(points[$0+1] + h/2))" }.joined(separator: " ")
                svg += "<polyline points=\"\(pairs)\"\(style)/>"
            }
        case "text", "variable":
            let style = a["style"] ?? ""
            let alignment = a["alignment"] ?? "left"
            var properties: FormValue = .object([])
            properties["type"] = .string("text")
            properties["fontFamily"] = .string(a["font-name"] ?? "Helvetica")
            properties["fontWeight"] = .string(style.contains("bold") ? "bold" : "normal")
            properties["fontStyle"] = .string(style.contains("italic") ? "italic" : "normal")
            properties["textDecoration"] = .string(style.contains("underline") ? "underline" : "none")
            properties["textAlign"] = .string(["end", "right"].contains(alignment) ? "right" : alignment == "center" ? "center" : "left")
            svg += renderer.text(a["value"] ?? "", p: properties, x: 0, y: 0, width: w, height: h,
                                 size: max(1, min(256, value(a, "font-size", 12))), center: false,
                                 ink: renderer.color(a["font-color"], fallback: stroke))
        case "image":
            if let image = object.image {
                svg += "<image width=\"\(n(w))\" height=\"\(n(h))\" href=\"\(image.dataURI)\" preserveAspectRatio=\"\(a["preserve-aspect-ratio"] == "false" ? "none" : "xMidYMid meet")\"/>"
            } else { svg += placeholder(width: w, height: h, text: "Image unavailable") }
        default:
            svg += placeholder(width: w, height: h, text: object.type)
        }
        return svg + "</g>"
    }

    private static func placeholder(width: Double, height: Double, text: String) -> String {
        "<svg width=\"\(n(width))\" height=\"\(n(height))\" overflow=\"hidden\"><rect width=\"100%\" height=\"100%\" fill=\"#eee\" stroke=\"#999\"/><text x=\"4\" y=\"14\" fill=\"#555\" font-size=\"11\">\(esc(text))</text></svg>"
    }
    private static func value(_ a: [String: String], _ key: String, _ fallback: Double) -> Double { a[key].flatMap(Double.init) ?? fallback }
    private static func n(_ value: Double) -> String { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value).replacingOccurrences(of: ".00", with: "") }
    private static func esc(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#39;")
    }
}
