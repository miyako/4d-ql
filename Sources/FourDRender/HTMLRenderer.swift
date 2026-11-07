import Foundation

/// Renders a Report as a self-contained HTML page (no scripts, no external
/// resources) that follows the system light/dark appearance.
public struct HTMLRenderer {
    public init() {}

    public func render(_ report: Report) -> String {
        var h = "<!doctype html><html><head><meta charset=\"utf-8\">"
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
        for s in report.sections {
            h += "<section><h2>\(esc(s.title))</h2>" + s.blocks.map(block).joined() + "</section>"
        }
        h += "</body></html>"
        return h
    }

    private func block(_ b: Block) -> String {
        switch b {
        case .keyValues(let kv):
            return "<dl>" + kv.map { "<dt>\(esc($0.0))</dt><dd>\(esc($0.1))</dd>" }.joined() + "</dl>"
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
            return h + "</tbody></table>"
        case .bars(let bars):
            let maxV = bars.map(\.value).max() ?? 0
            return "<div class=\"bars\">" + bars.map { b in
                let pct = maxV > 0 ? max(0.5, b.value / maxV * 100) : 0
                return "<div class=\"bar\"><span class=\"bl\">\(esc(b.label))</span><span class=\"track\"><span class=\"fill\" style=\"width:\(String(format: "%.1f", pct))%\"></span></span><span class=\"bv\">\(esc(b.display))</span></div>"
            }.joined() + "</div>"
        case .disclosure(let summary, let detail, let blocks):
            var h = "<details><summary><span class=\"st\">\(esc(summary))</span>"
            if let d = detail { h += "<span class=\"sd\">\(esc(d))</span>" }
            return h + "</summary>" + blocks.map(block).joined() + "</details>"
        case .note(let text, let t):
            return "<p class=\"note \(tone(t))\">\(esc(text))</p>"
        case .text(let text):
            return "<p>\(esc(text))</p>"
        }
    }

    private func tone(_ t: Badge.Tone) -> String {
        switch t { case .neutral: "neutral"; case .good: "good"; case .warning: "warning"; case .danger: "danger" }
    }

    private func align(_ a: Table.Align) -> String { a == .trailing ? "num" : "" }

    private func esc(_ s: String) -> String {
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

    static let css = """
    :root{--bg:#fff;--fg:#1d1d1f;--muted:#6e6e73;--line:#e5e5ea;--soft:#f5f5f7;--accent:#0a66d8;--good:#1e8e3e;--warn:#b26a00;--bad:#c5221f}
    @media (prefers-color-scheme:dark){:root{--bg:#1e1e1e;--fg:#f2f2f7;--muted:#a1a1a6;--line:#3a3a3c;--soft:#2a2a2c;--accent:#4c9bff;--good:#4cc76b;--warn:#f0a83a;--bad:#ff6b63}}
    *{box-sizing:border-box}
    body{margin:0;padding:20px 24px 32px;background:var(--bg);color:var(--fg);font:13px/1.45 -apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif}
    h1{font-size:20px;margin:0;font-weight:600;word-break:break-all}
    h2{font-size:12px;text-transform:uppercase;letter-spacing:.06em;color:var(--muted);margin:22px 0 8px;font-weight:600}
    .sub{margin:2px 0 0;color:var(--muted)}
    .badges{margin-top:10px;display:flex;flex-wrap:wrap;gap:6px}
    .badge{font-size:11px;padding:2px 8px;border-radius:10px;border:1px solid var(--line);color:var(--muted)}
    .badge.good{color:var(--good);border-color:currentColor}.badge.warning{color:var(--warn);border-color:currentColor}.badge.danger{color:var(--bad);border-color:currentColor}
    .stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(110px,1fr));gap:8px;margin-top:16px}
    .stat{background:var(--soft);border-radius:8px;padding:10px 12px}
    .stat .v{font-size:18px;font-weight:600;font-variant-numeric:tabular-nums}
    .stat .l{color:var(--muted);font-size:11px}
    dl{display:grid;grid-template-columns:max-content 1fr;gap:4px 16px;margin:0}
    dt{color:var(--muted)}dd{margin:0;word-break:break-word;font-variant-numeric:tabular-nums}
    table{border-collapse:collapse;width:100%}
    th{text-align:left;font-weight:500;color:var(--muted);border-bottom:1px solid var(--line);padding:4px 8px}
    td{border-bottom:1px solid var(--line);padding:4px 8px;vertical-align:top;word-break:break-word}
    .num{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
    details{border-bottom:1px solid var(--line)}
    summary{cursor:default;padding:6px 2px;display:flex;gap:12px;align-items:baseline;list-style:none}
    summary::-webkit-details-marker{display:none}
    summary::before{content:"▸";color:var(--muted);font-size:10px;width:10px}
    details[open]>summary::before{content:"▾"}
    .st{font-weight:500}.sd{color:var(--muted);margin-left:auto;font-variant-numeric:tabular-nums;white-space:nowrap}
    details table{margin:0 0 10px 22px;width:calc(100% - 22px)}
    .bars{display:grid;gap:4px}
    .bar{display:grid;grid-template-columns:minmax(80px,30%) 1fr max-content;gap:10px;align-items:center}
    .bl{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
    .track{height:8px;background:var(--soft);border-radius:4px;overflow:hidden}
    .fill{display:block;height:100%;background:var(--accent);border-radius:4px}
    .bv{color:var(--muted);font-variant-numeric:tabular-nums;min-width:60px;text-align:right}
    .note{padding:8px 10px;border-radius:6px;background:var(--soft);margin:6px 0}
    .note.warning{color:var(--warn)}.note.danger{color:var(--bad)}.note.good{color:var(--good)}
    """
}
