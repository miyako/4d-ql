import Foundation

/// Script-free presets that the owned Quick Look viewer upgrades to continuous controls.
struct CanvasZoomControls {
    private static let percentages = [10, 25, 50, 75, 100, 150, 200]

    static func render(kind: String, identifier: String, viewport: String, scaleProperty: String) -> String {
        let prefix = "\(kind)-zoom-\(HTMLRenderer.escape(identifier))"
        var html = ""
        var selectors = ""
        for percent in percentages {
            let id = "\(prefix)-\(percent)"
            html += "<input class=\"\(kind)-zoom-choice\" type=\"radio\" name=\"\(prefix)\" id=\"\(id)\" value=\"\(percent)\" aria-label=\"\(kind.capitalized) zoom \(percent) percent\"\(percent == 100 ? " checked" : "")>"
            selectors += "#\(id):checked ~ \(viewport){\(scaleProperty):\(Double(percent) / 100)}"
            selectors += "#\(id):checked ~ .\(kind)-zoom-controls label[for=\"\(id)\"]{background:var(--accent);border-color:var(--accent);color:white}"
            selectors += "#\(id):focus-visible ~ .\(kind)-zoom-controls label[for=\"\(id)\"]{outline:2px solid var(--accent);outline-offset:2px}"
        }
        html += "<div class=\"\(kind)-zoom-controls\" role=\"group\" aria-label=\"\(kind.capitalized) zoom\"><span>Zoom</span>"
        for percent in percentages {
            html += "<label for=\"\(prefix)-\(percent)\">\(percent)%</label>"
        }
        return html + "</div><style>\(selectors)</style>"
    }

    static func css(kind: String) -> String {
        """
        .\(kind)-zoom-choice{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0,0,0,0);clip-path:inset(50%);white-space:nowrap}
        .\(kind)-zoom-controls{display:flex;flex-wrap:wrap;align-items:center;gap:6px;margin-bottom:10px;font-size:12px}
        .\(kind)-zoom-controls>span{color:var(--muted);margin-right:4px}
        .\(kind)-zoom-controls label{cursor:pointer;padding:4px 8px;border:1px solid var(--line);border-radius:5px}
        .\(kind)-zoom-controls button{font:inherit;color:var(--fg);background:var(--soft);border:1px solid var(--line);border-radius:5px;padding:4px 8px;cursor:pointer}
        .\(kind)-zoom-controls input[type=range]{width:180px;max-width:40vw;vertical-align:middle;accent-color:var(--accent)}
        .\(kind)-zoom-controls output{min-width:4em;text-align:right;font-variant-numeric:tabular-nums}
        .\(kind)-zoom-controls button:focus-visible,.\(kind)-zoom-controls input:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
        """
    }
}
