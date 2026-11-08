import Foundation

/// Renders a Report as a self-contained HTML page (no scripts, no external
/// resources) that follows the system light/dark appearance.
///
/// Quick Look may run previews with JavaScript disabled, so hover details use
/// the `title` attribute and nothing depends on script.
public struct HTMLRenderer {
    public init() {}

    public func render(_ report: Report) -> String {
        var h = "<!doctype html><html><head><meta charset=\"utf-8\">"
        if report.sections.flatMap(\.blocks).contains(where: { if case .formPreview = $0 { return true }; return false }) {
            h += "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; img-src data: 'self'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'\">"
        }
        h += "<meta name=\"color-scheme\" content=\"light dark\">"
        h += "<title>\(esc(report.title))</title><style>\(Self.css)</style></head><body>"
        h += "<header><h1>\(esc(report.title))</h1>"
        if let s = report.subtitle { h += "<p class=\"sub\">\(esc(s))</p>" }
        if !report.badges.isEmpty {
            h += "<div class=\"badges\">" + report.badges.map { "<span class=\"badge \(tone($0.tone))\">\(esc($0.text))</span>" }.joined() + "</div>"
        }
        h += "</header>"
        if !report.stats.isEmpty {
            h += "<div class=\"stats\">" + report.stats.map {
                "<div class=\"stat\"><div class=\"v\">\(esc($0.value))</div><div class=\"l\">\(esc($0.label))</div></div>"
            }.joined() + "</div>"
        }

        // Consecutive half-width sections are laid out side by side.
        var i = 0
        let sections = report.sections
        while i < sections.count {
            if sections[i].width == .half {
                var group: [Section] = []
                while i < sections.count, sections[i].width == .half { group.append(sections[i]); i += 1 }
                h += "<div class=\"pair\">" + group.map(section).joined() + "</div>"
            } else {
                h += section(sections[i]); i += 1
            }
        }
        h += "</body></html>"
        return h
    }

    private func section(_ s: Section) -> String {
        "<section>" + (s.title.isEmpty ? "" : "<h2>\(esc(s.title))</h2>") + s.blocks.map(block).joined() + "</section>"
    }

    private func block(_ b: Block) -> String {
        switch b {
        case .keyValues(let kv):
            return "<dl>" + kv.map {
                "<dt>\(esc($0.key))</dt><dd\($0.mono ? " class=\"mono\"" : "")>\(esc($0.value))</dd>"
            }.joined() + "</dl>"

        case .identity(let label, let value, let caption):
            var h = "<div class=\"identity\"><div class=\"il\">\(esc(label))</div><div class=\"iv mono\">\(esc(value))</div>"
            if let c = caption { h += "<div class=\"ic\">\(esc(c))</div>" }
            return h + "</div>"

        case .meter(let fraction, let label, let caption):
            let pct = max(0, min(1, fraction)) * 100
            var h = "<div class=\"meter\" title=\"\(esc(label))\"><div class=\"ml\">\(esc(label))</div>"
            h += "<div class=\"track\"><span class=\"fill\" style=\"width:\(String(format: "%.1f", pct))%\"></span></div>"
            if let c = caption { h += "<div class=\"mc\">\(esc(c))</div>" }
            return h + "</div>"

        case .bars(let rows, let valueHeader, let extraHeader):
            let maxV = rows.filter { !$0.muted }.map(\.value).max() ?? rows.map(\.value).max() ?? 0
            var h = "<div class=\"bars\"><div class=\"bh\"><span></span><span></span><span class=\"num\">\(esc(valueHeader))</span><span class=\"num\">\(esc(extraHeader))</span></div>"
            for r in rows {
                // Tiny non-zero values stay visible; zero stays empty. "Other" may exceed the scale: cap it.
                let pct = (maxV > 0 && r.value > 0) ? min(100, max(0.5, r.value / maxV * 100)) : 0
                let tip = r.tooltip.map { " title=\"\(esc($0))\"" } ?? ""
                h += "<div class=\"bar\(r.muted ? " muted" : "")\"\(tip)>"
                h += "<span class=\"bl\">\(esc(r.label))\(r.marker.map { " <span class=\"mk\">\(esc($0))</span>" } ?? "")</span>"
                h += "<span class=\"track\"><span class=\"fill\" style=\"width:\(String(format: "%.1f", pct))%\"></span></span>"
                h += "<span class=\"bv num\">\(esc(r.display))</span><span class=\"bx num\">\(esc(r.extra))</span></div>"
            }
            return h + "</div>"

        case .composition(let segments):
            let total = segments.reduce(0) { $0 + $1.value }
            guard total > 0 else { return "" }
            func cls(_ s: Segment) -> String { s.slot.map { "s\(min(max($0, 1), 8))" } ?? "so" }
            var h = "<div class=\"comp\"><div class=\"strip\">"
            for s in segments where s.value > 0 {
                h += "<span class=\"seg \(cls(s))\" style=\"flex-grow:\(s.value)\" title=\"\(esc(s.label)): \(esc(s.display))\"></span>"
            }
            h += "</div><ul class=\"legend\">"
            for s in segments where s.value > 0 {
                let marker = s.icons.isEmpty ? "<span class=\"sw \(cls(s))\"></span>" :
                    s.icons.map { FieldTypeIconRenderer.render($0) }.joined()
                h += "<li>\(marker)\(esc(s.label)) <span class=\"lc\">\(esc(s.display))</span></li>"
            }
            return h + "</ul></div>"

        case .table(let t):
            var h = "<table><thead><tr>"
            h += t.columns.map { "<th class=\"\(align($0.1))\">\(esc($0.0))</th>" }.joined()
            h += "</tr></thead><tbody>"
            for row in t.rows {
                h += "<tr>" + row.enumerated().map { i, cell in
                    let a = i < t.columns.count ? align(t.columns[i].1) : ""
                    return "<td class=\"\(a)\">\(esc(cell))</td>"
                }.joined() + "</tr>"
            }
            h += "</tbody></table>"
            if let more = t.more { h += "<p class=\"more\">\(esc(more))</p>" }
            return h

        case .orderedCards(let cards):
            return "<ol class=\"ordered-cards\">" + cards.map { card in
                let type = card.icon.map {
                    "<span class=\"field-type-icon\" role=\"img\" aria-label=\"\(esc(card.subtitle))\" title=\"\(esc(card.subtitle))\">\(esc($0.rawValue))</span>"
                } ?? "<span class=\"field-type-label\">\(esc(card.subtitle))</span>"
                return "<li><div class=\"field-card-heading\"><span class=\"field-card-name\">\(esc(card.title))</span>\(type)</div>"
                    + "<dl>" + card.details.map {
                        "<div><dt>\(esc($0.key))</dt><dd>\(esc($0.value))</dd></div>"
                    }.joined() + "</dl></li>"
            }.joined() + "</ol>"

        case .queryConditions(let conditions):
            return "<ol class=\"query-conditions\">" + conditions.map { condition in
                "<li><span class=\"query-connector\">\(esc(condition.connector))</span>"
                    + "<div class=\"query-card\"><div class=\"query-field\">\(esc(condition.field))</div>"
                    + "<div class=\"query-operation\">\(esc(condition.operation))"
                    + " <span class=\"query-code\">criterion \(esc(condition.code))</span></div>"
                    + block(.keyValues(condition.operands)) + "</div></li>"
            }.joined() + "</ol>"

        case .structureDiagram(let diagram):
            return StructureDiagramRenderer().render(diagram)

        case .formPreview(let preview):
            return FormPreviewRenderer().render(preview)

        case .disclosure(let summary, let detail, let blocks):
            var h = "<details><summary><span class=\"st\">\(esc(summary))</span>"
            if let d = detail { h += "<span class=\"sd\">\(esc(d))</span>" }
            return h + "</summary>" + blocks.map(block).joined() + "</details>"

        case .note(let text, let t):
            return "<p class=\"note \(tone(t))\">\(esc(text))</p>"

        case .text(let text):
            return "<p>\(esc(text))</p>"
        case .sourceCode(let text, let language):
            let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            let highlighted = SourceHighlighter.html(normalized, language: language, escape: esc)
            return "<pre class=\"source-text mono\"><code>\(highlighted)</code></pre>"

        case .code(let spans):
            var lines = [""]
            for span in spans {
                let parts = span.text.components(separatedBy: "\n")
                for (index, part) in parts.enumerated() {
                    if index > 0 { lines.append("") }
                    if !part.isEmpty {
                        let text = esc(part)
                        lines[lines.count - 1] += span.style == .plain ? text :
                            "<span class=\"syntax-\(span.style.rawValue)\">\(text)</span>"
                    }
                }
            }
            if lines.last == "" && lines.count > 1 { lines.removeLast() }
            return "<pre class=\"source\"><code>" + lines.enumerated().map {
                "<span class=\"source-line\"><span class=\"line-number\" aria-hidden=\"true\">\($0.offset + 1)</span><span class=\"line-code\">\($0.element)</span></span>"
            }.joined(separator: "\n") + "</code></pre>"
        }
    }

    private func tone(_ t: Badge.Tone) -> String {
        switch t { case .neutral: "neutral"; case .good: "good"; case .warning: "warning"; case .danger: "danger" }
    }

    private func align(_ a: Table.Align) -> String { a == .trailing ? "num" : "" }

    private func esc(_ s: String) -> String {
        Self.escape(s)
    }

    static func escape(_ s: String) -> String {
        var o = ""
        o.reserveCapacity(s.count)
        for ch in s.unicodeScalars {
            switch ch {
            case "&": o += "&amp;"
            case "<": o += "&lt;"
            case ">": o += "&gt;"
            case "\"": o += "&quot;"
            default:
                // Drop control characters that sometimes survive in 4D name buffers.
                if ch.value < 0x20 && ch != "\n" && ch != "\t" { continue }
                o.unicodeScalars.append(ch)
            }
        }
        return o
    }

    // Categorical slots s1–s8 are the validated reference palette (dataviz skill),
    // light and dark steps; adjacent pairs pass the CVD and normal-vision checks.
    static let css = """
    :root{--bg:#fcfcfb;--fg:#0b0b0b;--muted:#52514e;--faint:#8a8984;--line:#e6e5e1;--soft:#f2f1ee;--track:#ebeae6;
    --accent:#2a78d6;--other:#a3a29c;--good:#1e8e3e;--warn:#b26a00;--bad:#c5221f;
    --s1:#2a78d6;--s2:#eb6834;--s3:#1baf7a;--s4:#eda100;--s5:#e87ba4;--s6:#008300;--s7:#6250d6;--s8:#e34948}
    @media (prefers-color-scheme:dark){:root{--bg:#1a1a19;--fg:#f0efec;--muted:#c3c2b7;--faint:#8f8e86;--line:#353533;--soft:#252524;--track:#2e2e2c;
    --accent:#3987e5;--other:#6d6c66;--good:#4cc76b;--warn:#f0a83a;--bad:#ff6b63;
    --s1:#3987e5;--s2:#d95926;--s3:#199e70;--s4:#c98500;--s5:#d55181;--s6:#008300;--s7:#9085e9;--s8:#e66767}}
    *{box-sizing:border-box}
    body{margin:0;padding:20px 24px 28px;background:var(--bg);color:var(--fg);font:13px/1.45 -apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif}
    h1{font-size:20px;margin:0;font-weight:600;word-break:break-all}
    h2{font-size:11px;text-transform:uppercase;letter-spacing:.06em;color:var(--muted);margin:20px 0 8px;font-weight:600}
    .sub{margin:2px 0 0;color:var(--muted)}
    .mono{font-family:ui-monospace,"SF Mono",Menlo,monospace;font-size:12px}
    .query-conditions{list-style:none;padding:0;margin:0;max-height:640px;overflow:auto}
    .query-conditions li{display:grid;grid-template-columns:80px minmax(0,1fr);gap:12px;align-items:start;margin-bottom:10px}
    .query-connector{color:var(--accent);font-size:11px;font-weight:700;padding-top:12px;overflow-wrap:anywhere}
    .query-card{padding:12px 14px;background:var(--soft);border:1px solid var(--line);border-radius:8px}
    .query-field{font-weight:600;font-size:14px;overflow-wrap:anywhere}
    .query-operation{margin:4px 0 8px;overflow-wrap:anywhere}
    .query-code{font-size:10px;color:var(--muted)}
    .query-card dd{white-space:pre-wrap;overflow-wrap:anywhere}
    @media(max-width:400px){.query-conditions li{grid-template-columns:1fr;gap:4px}.query-card dl{grid-template-columns:1fr}}
    .ordered-cards{list-style:none;padding:0;margin:0;display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,260px),1fr));gap:6px;max-height:640px;overflow:auto}
    .ordered-cards li{min-width:0;padding:7px 10px;background:var(--soft);border:1px solid var(--line);border-radius:8px}
    .field-card-heading{display:flex;align-items:center;gap:8px;justify-content:space-between}
    .field-card-name{font-weight:600;overflow-wrap:anywhere;min-width:0}
    .field-type-icon{flex:none;color:var(--accent);font:600 11px/1.5 ui-monospace,"SF Mono",Menlo,monospace;min-width:26px;text-align:center}
    .field-type-label{font-size:11px;color:var(--muted);overflow-wrap:anywhere}
    .ordered-cards dl{display:flex;flex-wrap:wrap;gap:2px 12px;margin:3px 0 0;font-size:11px}
    .ordered-cards dl>div{display:flex;gap:4px;min-width:0;max-width:100%}
    .ordered-cards dt{flex:none}.ordered-cards dd{white-space:pre-wrap;overflow-wrap:anywhere;min-width:0}
    .source-text{white-space:pre;overflow:auto;padding:12px;background:var(--soft);border-radius:8px;tab-size:4}
    .source-text code{font:inherit}
    .source-text .syntax-key,.source-text .syntax-tag{color:#175aa8}
    .source-text .syntax-string,.source-text .syntax-entity{color:#226b35}
    .source-text .syntax-number,.source-text .syntax-attribute{color:#8c3e97}
    .source-text .syntax-literal{color:#9c4b10}
    .source-text .syntax-comment{color:var(--muted);font-style:normal}
    @media (prefers-color-scheme:dark){
    .source-text .syntax-key,.source-text .syntax-tag{color:#80b8ff}
    .source-text .syntax-string,.source-text .syntax-entity{color:#93d49d}
    .source-text .syntax-number,.source-text .syntax-attribute{color:#d3a0ec}
    .source-text .syntax-literal{color:#f2b37b}}
    .num{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
    .badges{margin-top:10px;display:flex;flex-wrap:wrap;gap:6px}
    .badge{font-size:11px;padding:2px 8px;border-radius:10px;border:1px solid var(--line);color:var(--muted)}
    .badge.good{color:var(--good);border-color:currentColor}.badge.warning{color:var(--warn);border-color:currentColor}.badge.danger{color:var(--bad);border-color:currentColor}
    .stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(100px,1fr));gap:8px;margin-top:14px}
    .stat{background:var(--soft);border-radius:8px;padding:10px 12px}
    .stat .v{font-size:20px;font-weight:600;font-variant-numeric:tabular-nums}
    .stat .l{color:var(--muted);font-size:11px}
    .pair{display:grid;grid-template-columns:1fr 1fr;gap:0 28px}
    @media (max-width:560px){.pair{grid-template-columns:1fr}}
    dl{display:grid;grid-template-columns:max-content 1fr;gap:4px 14px;margin:0}
    dt{color:var(--muted)}dd{margin:0;word-break:break-word;font-variant-numeric:tabular-nums}
    .identity{background:var(--soft);border-radius:8px;padding:10px 12px;margin-bottom:10px}
    .il{color:var(--muted);font-size:11px}.iv{font-size:14px;margin:2px 0;word-break:break-all;user-select:all}.ic{color:var(--faint);font-size:11px}
    .meter{margin:4px 0 10px}.ml{margin-bottom:4px}.mc{color:var(--muted);font-size:11px;margin-top:4px}
    .track{display:block;height:8px;background:var(--track);border-radius:4px;overflow:hidden}
    .fill{display:block;height:100%;background:var(--accent);border-radius:4px}
    .bars{display:grid;gap:5px}
    .bh,.bar{display:grid;grid-template-columns:minmax(90px,32%) 1fr 64px 52px;gap:10px;align-items:center}
    .bh{color:var(--faint);font-size:11px}
    .bl{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.mk{color:var(--muted);font-size:11px}
    .bv{color:var(--fg)}.bx{color:var(--muted)}
    .bar.muted .bl{color:var(--muted)}.bar.muted .fill{background:var(--other)}
    .comp .strip{display:flex;gap:2px;height:12px}
    .seg{display:block;height:100%;min-width:3px}.seg:first-child{border-radius:4px 0 0 4px}.seg:last-child{border-radius:0 4px 4px 0}.seg:only-child{border-radius:4px}
    .legend{list-style:none;margin:8px 0 0;padding:0;display:flex;flex-wrap:wrap;gap:4px 14px;font-size:12px}
    .legend li{display:flex;align-items:center;gap:5px}.lc{color:var(--muted);font-variant-numeric:tabular-nums}
    .sw{width:10px;height:10px;border-radius:3px;display:inline-block}
    .s1{background:var(--s1)}.s2{background:var(--s2)}.s3{background:var(--s3)}.s4{background:var(--s4)}
    .s5{background:var(--s5)}.s6{background:var(--s6)}.s7{background:var(--s7)}.s8{background:var(--s8)}.so{background:var(--other)}
    table{border-collapse:collapse;width:100%}
    th{text-align:left;font-weight:500;color:var(--muted);border-bottom:1px solid var(--line);padding:4px 8px}
    td{border-bottom:1px solid var(--line);padding:4px 8px;vertical-align:top;word-break:break-word}
    .more{color:var(--muted);font-size:11px;margin:6px 0 0}
    details{border-bottom:1px solid var(--line)}
    summary{cursor:default;padding:6px 2px;display:flex;gap:12px;align-items:baseline;list-style:none}
    summary::-webkit-details-marker{display:none}
    summary::before{content:"▸";color:var(--muted);font-size:10px;width:10px}
    details[open]>summary::before{content:"▾"}
    .st{font-weight:500}.sd{color:var(--muted);margin-left:auto;font-variant-numeric:tabular-nums;white-space:nowrap}
    .note{padding:8px 10px;border-radius:6px;background:var(--soft);margin:8px 0 0;font-size:12px;color:var(--muted)}
    .note.warning{color:var(--warn)}.note.danger{color:var(--bad)}.note.good{color:var(--good)}
    \(StructureDiagramRenderer.css)
    \(FieldTypeIconRenderer.css)
    .source{margin:0;padding:12px 0;background:var(--soft);border:1px solid var(--line);border-radius:8px;overflow:auto;max-height:760px;font:12px/1.6 ui-monospace,"SF Mono",Menlo,monospace;tab-size:4}
    .source-line{display:inline-flex;min-width:100%}
    .line-number{display:inline-block;flex-shrink:0;width:5em;padding:0 1em;color:var(--faint);text-align:right;user-select:none}
    .line-code{padding-right:16px}
    .syntax-comment{color:var(--muted);font-style:italic}
    .syntax-processing,.syntax-keyword{color:#7a3e9d}
    .syntax-string{color:#a13425}
    .syntax-number,.syntax-constant{color:#875a0a}
    .syntax-variable{color:#176b8a}
    .syntax-command{color:#2459a6}
    .syntax-type{color:#20704a}
    .syntax-property{color:#795321}
    .syntax-operator{color:var(--fg)}
    @media (prefers-color-scheme:dark){
    .syntax-processing,.syntax-keyword{color:#cf9aeb}.syntax-string{color:#f1a395}
    .syntax-number,.syntax-constant{color:#e3be76}.syntax-variable{color:#7dc9e6}
    .syntax-command{color:#8db9f3}.syntax-type{color:#82cba4}.syntax-property{color:#dbbb8c}}
    """
}
