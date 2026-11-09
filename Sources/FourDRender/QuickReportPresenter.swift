import Foundation
import FourDFileKit

public struct QuickReportPreview {
    public let report: QuickReportFileInfo
    public init(report: QuickReportFileInfo) { self.report = report }
}

public struct QuickReportPresenter: ReportPresenter {
    public init() {}
    public let kinds = ["4d.quick-report"]

    public func report(for model: AnalysisModel) -> Report? {
        guard let info = model as? QuickReportFileInfo else { return nil }
        var report = Report(title: info.fileName, subtitle: "4D Quick Report")
        report.badges = [Badge(info.crossTable ? "Cross-table" : "List report"),
                         Badge(info.littleEndian ? "Little-endian" : "Big-endian")]
        report.stats = [Stat("Columns", "\(info.columns.count)"), Stat("Sort levels", "\(info.sorts.count)")]
        report.sections = [
            Section("Report template", [
                .note("Design preview only. Record values, calculated formulas and pagination require the original database and are not executed.", .neutral),
                .quickReportPreview(QuickReportPreview(report: info)),
            ]),
        ]
        let rows = info.columns.enumerated().map { index, col -> [String] in
            [String(index + 1), col.title, QuickReportPreviewRenderer.source(col),
             col.automaticWidth ? "Automatic" : "\(col.width) px",
             col.hidden ? "Hidden" : "Visible", col.repeatedValues ? "Repeat" : "Suppress duplicates",
             col.displayFormat]
        }
        report.sections.append(Section("Column definitions", [
            .table(Table(columns: [("#", .trailing), ("Title", .leading), ("Source", .leading),
                                   ("Width", .leading), ("Visibility", .leading), ("Values", .leading),
                                   ("Format", .leading)], rows: rows)),
        ]))
        if !info.sorts.isEmpty {
            report.sections.append(Section("Sort order", [.keyValues(info.sorts.enumerated().map { index, value in
                let col = info.columns[abs(value) - 1]
                return KeyValue("\(index + 1)", "\(col.title.isEmpty ? "Column \(abs(value))" : col.title) — \(value < 0 ? "descending" : "ascending")")
            })]))
        }
        if !info.notes.isEmpty {
            report.sections.append(Section("Preview limitations", info.notes.map { .note($0, .warning) }))
        }
        return report
    }
}

enum QuickReportPreviewRenderer {
    static func source(_ column: QuickReportColumn) -> String {
        if let table = column.tableNumber, let field = column.fieldNumber {
            return "Table \(table) / Field \(field)"
        }
        return column.formulaBytes > 0 ? "Formula (tokenized)" : "Unassigned"
    }

    static func render(_ preview: QuickReportPreview) -> String {
        let report = preview.report
        let visible = report.columns.enumerated().filter { !$0.element.hidden }
        var h = "<div class=\"qr-scroll\"><div class=\"qr-page\">"
        h += band(report.header)
        if report.columns.isEmpty {
            h += "<p class=\"qr-empty\">No columns are saved.</p>"
        } else if visible.isEmpty {
            h += "<p class=\"qr-empty\">All columns are hidden.</p>"
        } else if report.crossTable {
            h += "<table class=\"qr-grid\"><tbody>"
            for row in 0..<3 {
                h += "<tr>"
                for col in 0..<3 {
                    let column = report.columns[col]
                    let cell = column.cells[row]
                    var text = cellText(cell)
                    if row == 0 && col == 1 { text = source(report.columns[0]) }
                    if row == 1 && col == 0 { text = source(report.columns[1]) }
                    if row == 1 && col == 1 {
                        text = [text, source(report.columns[2])].filter { !$0.isEmpty }.joined(separator: " · ")
                    }
                    h += td(text, style: cell.style, borders: cell.borders, column: column)
                }
                h += "</tr>"
            }
            h += "</tbody></table>"
        } else {
            h += "<table class=\"qr-grid\"><tbody>"
            if visible.contains(where: { !$0.element.titleHidden }) {
                h += "<tr>"
                for (_, column) in visible {
                    h += td(column.titleHidden ? "" : column.title, style: column.titleStyle,
                            borders: column.titleBorders, column: column)
                }
                h += "</tr>"
            }
            if visible.contains(where: { !$0.element.detailHidden }) {
                let passes = visible.contains(where: { $0.element.detailStyle.alternateBackground != nil }) ? 2 : 1
                for pass in 0..<passes {
                    h += "<tr class=\"qr-detail\">"
                    for (_, column) in visible {
                        let hidden = column.detailHidden || (pass > 0 && !column.repeatedValues)
                        h += td(hidden ? "" : source(column), style: column.detailStyle,
                                borders: column.detailBorders, column: column, alternate: pass > 0)
                    }
                    h += "</tr>"
                }
            }
            for row in 0..<report.rowCount where visible.contains(where: { !$0.element.cells[row].hidden }) {
                let label = row == report.rowCount - 1 ? "Grand total" : "Subtotal \(row + 1)"
                h += "<tr class=\"qr-row-label\"><td colspan=\"\(visible.count)\">\(esc(label))</td></tr><tr>"
                for (_, column) in visible {
                    let cell = column.cells[row]
                    h += td(cell.hidden ? "" : cellText(cell), style: cell.style,
                            borders: cell.borders, column: column)
                }
                h += "</tr>"
            }
            h += "</tbody></table>"
        }
        h += band(report.footer)
        return h + "</div></div>"
    }

    static func cellText(_ cell: QuickReportCell) -> String {
        if !cell.text.isEmpty { return cell.text }
        let operators: [(UInt16, String)] = [(1, "Sum"), (2, "Average"), (4, "Minimum"),
                                             (8, "Maximum"), (16, "Count"), (32, "Standard deviation")]
        var labels = operators.filter { cell.operators & $0.0 != 0 }.map(\.1)
        if cell.operators & ~UInt16(63) != 0 { labels.append("Unknown operators \(cell.operators)") }
        return labels.joined(separator: " · ")
    }

    private static func band(_ band: QuickReportPageBand) -> String {
        guard !band.left.isEmpty || !band.center.isEmpty || !band.right.isEmpty || band.hasPicture else { return "" }
        let height = min(300, max(0, band.height))
        return "<div class=\"qr-band\" style=\"min-height:\(height)px;\(style(band.style))\">" +
            [band.left, band.center, band.right].map { "<span>\(esc($0))</span>" }.joined() + "</div>"
    }

    private static func td(_ text: String, style textStyle: QuickReportTextStyle,
                           borders: [QuickReportBorder], column: QuickReportColumn, alternate: Bool = false) -> String {
        var css = style(textStyle)
        if alternate, let background = textStyle.alternateBackground { css += "background:\(background);" }
        if !column.automaticWidth { css += "width:\(min(2000, max(16, column.width)))px;" }
        let sides = [(0, "left"), (3, "top"), (2, "right"), (5, "bottom")]
        let widths = ["0", "0.25", "0.5", "1", "2"]
        for (index, side) in sides where index < borders.count {
            let border = borders[index]
            if Int(border.thickness) < widths.count {
                css += "border-\(side):\(widths[Int(border.thickness)])pt solid \(border.color);"
            }
        }
        return "<td style=\"\(css)\">\(esc(text))</td>"
    }

    private static func style(_ style: QuickReportTextStyle) -> String {
        // Quoted font-family values need CSS escaping as well as HTML escaping.
        let font = style.fontName.unicodeScalars.map { scalar -> String in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == " " || scalar == "-" { return String(scalar) }
            return "\\" + String(scalar.value, radix: 16) + " "
        }.joined()
        var css = "font-family:'\(esc(font))',sans-serif;font-size:\(min(255, max(9, style.fontSize)))px;"
        css += "color:\(style.foreground);background:\(style.background ?? "#FFFFFF");"
        if style.face & 1 != 0 { css += "font-weight:bold;" }
        if style.face & 2 != 0 { css += "font-style:italic;" }
        if style.face & 4 != 0 { css += "text-decoration:underline;" }
        switch style.justification {
        case 9: css += "text-align:right;"
        case 11: css += "text-align:center;"
        default: css += "text-align:left;"
        }
        return css
    }

    private static func esc(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    static let css = """
    .qr-scroll{overflow:auto;max-height:720px;border:1px solid var(--border);border-radius:8px}
    .qr-page{background:#fff;color:#000;padding:28px;min-width:480px;width:max-content;max-width:100%}
    .qr-grid{border-collapse:collapse;table-layout:fixed;margin:12px 0;width:auto}
    .qr-grid td{padding:5px 8px;min-width:64px;max-width:2000px;white-space:pre-wrap;overflow-wrap:anywhere;box-sizing:border-box}
    .qr-band{display:grid;grid-template-columns:1fr 1fr 1fr;gap:12px;white-space:pre-wrap}
    .qr-band span:nth-child(2){text-align:center}.qr-band span:nth-child(3){text-align:right}
    .qr-detail td{opacity:.72}.qr-row-label td{font:10px sans-serif;color:#666;padding-top:12px}
    .qr-empty{font:13px sans-serif;color:#666}
    """
}
