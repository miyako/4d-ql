import Foundation
import FourDFileKit

public struct ViewProPresenter: ReportPresenter {
    public init() {}
    public var kinds: [String] { ["4d.viewpro"] }

    public func report(for model: AnalysisModel) -> Report? {
        guard let document = model as? ViewProFileInfo else { return nil }
        var report = Report(title: document.fileName, subtitle: "4D View Pro spreadsheet")
        if let version = document.spreadVersion { report.badges.append(Badge("SpreadJS \(version)")) }
        let formulas = document.sheets.reduce(0) { $0 + $1.cells.filter { $0.formula != nil }.count }
        report.stats = [
            Stat("Sheets", "\(document.sheets.count)"),
            Stat("Saved cells", "\(document.sheets.reduce(0) { $0 + $1.cells.count })"),
            Stat("Formulas", "\(formulas)")
        ]
        report.sections = [Section("Workbook", [
            .viewProPreview(document),
            .note("Static preview of saved values and formatting. Formulas and 4D code are never evaluated; links are inert. Charts, pictures, conditional formatting and print layout are not reproduced.", .neutral)
        ])]
        if !document.sheets.isEmpty {
            report.sections.append(Section("", [.disclosure(summary: "Sheet details", detail: "\(document.sheets.count)", blocks: [
                .table(Table(columns: [("Sheet", .leading), ("Visibility", .leading), ("Rows", .trailing), ("Columns", .trailing)],
                             rows: document.sheets.map { [$0.name, $0.visible ? "Visible" : "Hidden", "\($0.rowCount)", "\($0.columnCount)"] }))
            ])]))
        }
        let warnings = document.warnings + document.sheets.flatMap { sheet in sheet.warnings.map { "\(sheet.name): \($0)" } }
        if !warnings.isEmpty {
            report.sections.append(Section("", [.disclosure(summary: "Preview notices", detail: "\(warnings.count)",
                                                            blocks: warnings.map { .note($0, .warning) })]))
        }
        return report
    }
}

enum ViewProPreviewRenderer {
    private static let maxRows = 200
    private static let maxColumns = 40
    private static let maxSheets = 16
    private static let escape = HTMLRenderer.escape

    static func render(_ document: ViewProFileInfo, identifier: String) -> String {
        let visible = document.sheets.filter(\.visible)
        guard !visible.isEmpty else { return "<p class=\"note\">No visible worksheets.</p>" }
        var selected = visible.first { $0.index == document.activeSheet } ?? visible[0]
        var sheets = Array(visible.prefix(maxSheets))
        if !sheets.contains(where: { $0.index == selected.index }) { sheets[sheets.count - 1] = selected }
        selected = sheets.first { $0.index == selected.index } ?? sheets[0]
        let id = "vp-\(escape(identifier))"
        var html = "<style>\(css)\(CanvasZoomControls.css(kind: "form"))"
        for sheet in sheets {
            html += "#\(id)-\(sheet.index):checked~.vp-panels>.vp-panel-\(sheet.index){display:block}"
            html += "#\(id)-\(sheet.index):checked~.vp-tabs>label[for=\"\(id)-\(sheet.index)\"]{background:var(--accent);color:white}"
            html += "#\(id)-\(sheet.index):focus-visible~.vp-tabs>label[for=\"\(id)-\(sheet.index)\"]{outline:2px solid var(--accent)}"
        }
        html += "</style><div class=\"vp-workbook\">"
        for sheet in sheets {
            html += "<input class=\"vp-choice\" type=\"radio\" name=\"\(id)\" id=\"\(id)-\(sheet.index)\" aria-label=\"\(escape(sheet.name))\"\(sheet.index == selected.index ? " checked" : "")>"
        }
        html += "<div class=\"vp-tabs\" role=\"group\" aria-label=\"Worksheets\">"
        for sheet in sheets { html += "<label for=\"\(id)-\(sheet.index)\">\(escape(sheet.name))</label>" }
        html += "</div><div class=\"vp-panels\">"
        for sheet in sheets {
            html += "<div class=\"vp-panel vp-panel-\(sheet.index)\"><div class=\"form-zoom\">"
            html += CanvasZoomControls.render(kind: "form", identifier: "\(identifier)-sheet-\(sheet.index)", viewport: ".form-zoom-content", scaleProperty: "--form-scale")
            html += "<div class=\"form-zoom-content\"><div class=\"form-scroll vp-scroll\" tabindex=\"0\" role=\"region\" aria-label=\"\(escape(sheet.name)) spreadsheet\">"
            html += renderSheet(sheet)
            html += "</div></div></div></div>"
        }
        html += "</div></div>"
        if visible.count > sheets.count {
            html += "<p class=\"note warning\">Showing \(sheets.count) of \(visible.count) visible sheets.</p>"
        }
        return html
    }

    private static func renderSheet(_ sheet: ViewProSheet) -> String {
        let relevant = sheet.cells.filter {
            sheet.rows[$0.row]?.visible != false && sheet.columns[$0.column]?.visible != false
        }
        let minRow = relevant.map(\.row).min() ?? 0
        let minColumn = relevant.map(\.column).min() ?? 0
        let startRow = minRow >= maxRows ? minRow : 0
        let startColumn = minColumn >= maxColumns ? minColumn : 0
        let endRow = min(sheet.rowCount, max((relevant.map(\.row).max() ?? 9) + 1,
                                            sheet.spans.map { $0.row + $0.rowCount }.max() ?? 0))
        let endColumn = min(sheet.columnCount, max((relevant.map(\.column).max() ?? 7) + 1,
                                                  sheet.spans.map { $0.column + $0.columnCount }.max() ?? 0))
        let rows = axisIndices(start: startRow, end: endRow, limit: maxRows, axes: sheet.rows)
        let columns = axisIndices(start: startColumn, end: endColumn, limit: maxColumns, axes: sheet.columns)
        let rowSet = Set(rows), columnSet = Set(columns)
        let cells = Dictionary(uniqueKeysWithValues: sheet.cells.filter { rowSet.contains($0.row) && columnSet.contains($0.column) }
            .map { ("\($0.row):\($0.column)", $0) })
        var covered = Set<String>()
        var spans: [String: (Int, Int)] = [:]
        for span in sheet.spans {
            let rs = rows.filter { $0 >= span.row && $0 < span.row + span.rowCount }
            let cs = columns.filter { $0 >= span.column && $0 < span.column + span.columnCount }
            guard rs.first == span.row, cs.first == span.column else { continue }
            spans["\(span.row):\(span.column)"] = (rs.count, cs.count)
            for row in rs {
                for column in cs where row != span.row || column != span.column { covered.insert("\(row):\(column)") }
            }
        }
        let width = 48 + columns.reduce(0.0) { $0 + boundedDimension(sheet.columns[$1]?.size ?? sheet.defaultColumnWidth, fallback: 64) }
        let grid = (sheet.showGridLines && sheet.showHorizontalGridLines ? "" : " vp-no-horizontal") +
            (sheet.showGridLines && sheet.showVerticalGridLines ? "" : " vp-no-vertical")
        var html = "<table class=\"vp-grid\(grid)\" style=\"width:\(dimension(width, fallback: 48, maximum: 100_000))px\"><colgroup><col style=\"width:48px\">"
        for column in columns {
            html += "<col style=\"width:\(dimension(sheet.columns[column]?.size ?? sheet.defaultColumnWidth, fallback: 64))px\">"
        }
        html += "</colgroup><thead><tr><th></th>"
        for column in columns { html += "<th scope=\"col\">\(columnName(column))</th>" }
        html += "</tr></thead><tbody>"
        var missingValues = 0
        var unformatted = 0
        var unresolvedColors = false
        func validatedStyle(_ style: ViewProStyle, numeric: Bool) -> String {
            let colors = [style.foreground, style.background].compactMap { $0 } + style.borders.values.compactMap(\.color)
            if colors.contains(where: { color($0) == nil }) { unresolvedColors = true }
            return cellCSS(style, numeric: numeric)
        }
        for (rowIndex, row) in rows.enumerated() {
            html += "<tr style=\"height:\(dimension(sheet.rows[row]?.size ?? sheet.defaultRowHeight, fallback: 20))px\"><th scope=\"row\">\(row + 1)</th>"
            for column in columns {
                let key = "\(row):\(column)"
                guard !covered.contains(key) else { continue }
                let cell = cells[key]
                let style = sheet.defaultStyle.merging(sheet.columns[column]?.style ?? ViewProStyle())
                    .merging(sheet.rows[row]?.style ?? ViewProStyle()).merging(cell?.style ?? ViewProStyle())
                var text = cell?.formattedText ?? cell?.value?.text ?? ""
                if cell?.formattedText == nil {
                    switch cell?.value {
                    case .number(let number):
                        if let formatted = SpreadsheetNumberFormat.text(number, format: style.formatter) { text = formatted }
                        else { unformatted += 1 }
                    case .dateSerial(let number):
                        if let formatted = SpreadsheetNumberFormat.text(number, format: style.formatter, oaDate: true) { text = formatted }
                        else { unformatted += 1 }
                    default: break
                    }
                }
                if cell?.value == nil, let formula = cell?.formula, cell?.formattedText == nil {
                    text = formula.hasPrefix("=") ? formula : "=" + formula
                    missingValues += 1
                }
                var title = "\(columnName(column))\(row + 1)"
                if let formula = cell?.formula { title += " | Formula: \(formula)" }
                if let link = cell?.link { title += " | Link (not followed): \(link)" }
                let span = spans[key].map { " rowspan=\"\($0.0)\" colspan=\"\($0.1)\"" } ?? ""
                let numeric: Bool
                switch cell?.value { case .number, .dateSerial, .boolean: numeric = true; default: numeric = false }
                let content: String
                if let runs = cell?.runs, !runs.isEmpty {
                    content = runs.map { "<span style=\"\(escape(validatedStyle($0.style, numeric: false)))\">\(escape($0.text))</span>" }.joined()
                } else { content = escape(text) }
                let mergedRows = spans[key]?.0 ?? 1
                let height = rows[rowIndex..<min(rows.count, rowIndex + mergedRows)].reduce(0.0) {
                    $0 + boundedDimension(sheet.rows[$1]?.size ?? sheet.defaultRowHeight, fallback: 20)
                }
                html += "<td\(span) title=\"\(escape(title))\" style=\"\(escape(validatedStyle(style, numeric: numeric)))\"><div style=\"max-height:\(dimension(max(1, height - 1), fallback: 19))px\">\(content)</div></td>"
            }
            html += "</tr>"
        }
        html += "</tbody></table>"
        let omitted = relevant.filter { !rowSet.contains($0.row) || !columnSet.contains($0.column) }.count
        if omitted > 0 || startRow > 0 || startColumn > 0 || endRow > (rows.last ?? -1) + 1 || endColumn > (columns.last ?? -1) + 1 {
            html += "<p class=\"note warning\">Bounded preview: up to \(maxRows) visible rows and \(maxColumns) visible columns; \(omitted) saved cells outside the displayed range.</p>"
        }
        if missingValues > 0 {
            html += "<p class=\"note warning\">\(missingValues) formula cells have no saved result; their formulas are shown instead.</p>"
        }
        if unformatted > 0 {
            html += "<p class=\"note warning\">\(unformatted) cells use unsupported number formats; their raw saved values are shown.</p>"
        }
        if unresolvedColors {
            html += "<p class=\"note warning\">Theme or unsupported color references could not be resolved; default preview colors are used.</p>"
        }
        return html
    }

    private static func axisIndices(start: Int, end: Int, limit: Int, axes: [Int: ViewProAxis]) -> [Int] {
        guard start < end else { return [] }
        var result: [Int] = []
        var index = start
        // Hidden axes are sparse; never walk millions of rows to produce a preview.
        let scanEnd = min(end, start + limit + axes.count)
        while index < scanEnd && result.count < limit {
            if axes[index]?.visible != false { result.append(index) }
            index += 1
        }
        return result
    }

    static func columnName(_ index: Int) -> String {
        var number = index + 1
        var result = ""
        while number > 0 {
            number -= 1
            result = String(UnicodeScalar(65 + number % 26)!) + result
            number /= 26
        }
        return result
    }

    private static func boundedDimension(_ value: Double, fallback: Double, maximum: Double = 2000) -> Double {
        value.isFinite && value > 0 ? min(value, maximum) : fallback
    }

    private static func dimension(_ value: Double, fallback: Double, maximum: Double = 2000) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), boundedDimension(value, fallback: fallback, maximum: maximum))
    }

    private static func cellCSS(_ style: ViewProStyle, numeric: Bool) -> String {
        var css = ["text-align:\(style.horizontalAlignment == 0 ? "left" : style.horizontalAlignment == 1 ? "center" : style.horizontalAlignment == 2 ? "right" : numeric ? "right" : "left")",
                   "vertical-align:\(style.verticalAlignment == 0 ? "top" : style.verticalAlignment == 1 ? "middle" : "bottom")"]
        if let font = style.font, font.count < 200,
           font.range(of: #"^(?:(?:normal|italic|bold|[1-9]00) +)*([0-9]+(?:\.[0-9]+)?)(?:px|pt) +[\p{L}\p{N}_ ,'\"-]+$"#, options: .regularExpression) != nil,
           let sizeRange = font.range(of: #"[0-9]+(?:\.[0-9]+)?(?:px|pt)"#, options: .regularExpression),
           let size = Double(font[sizeRange].dropLast(2)), size > 0, size <= 200 {
            css.append("font:\(font)")
        }
        if let foreground = color(style.foreground) { css.append("color:\(foreground)") }
        if let background = color(style.background) { css.append("background-color:\(background)") }
        if style.wordWrap == true { css.append("white-space:pre-wrap;overflow-wrap:anywhere") }
        if let decoration = style.textDecoration {
            let values = [(1, "underline"), (2, "line-through"), (4, "overline")].compactMap { decoration & $0.0 != 0 ? $0.1 : nil }
            if !values.isEmpty { css.append("text-decoration:\(values.joined(separator: " "))") }
        }
        if let indent = style.textIndent, indent.isFinite, indent > 0 { css.append("text-indent:\(min(indent, 100) * 8)px") }
        for side in ["top", "right", "bottom", "left"] {
            guard let border = style.borders[side], (0...13).contains(border.style) else { continue }
            let line = border.style == 0 ? "none" : border.style == 6 ? "double" : [3, 8, 9, 10, 11, 12, 13].contains(border.style) ? "dashed" : border.style == 4 ? "dotted" : "solid"
            let width = [5, 6].contains(border.style) ? 3 : [2, 8, 10, 12, 13].contains(border.style) ? 2 : 1
            css.append("border-\(side):\(width)px \(line) \(color(border.color) ?? "#333333")")
        }
        return css.joined(separator: ";")
    }

    private static func color(_ value: String?) -> String? {
        guard let value, value.count <= 64,
              value.range(of: #"^(?:#[0-9A-Fa-f]{3,8}|[a-zA-Z]+|rgba?\([0-9.,% ]+\))$"#, options: .regularExpression) != nil else { return nil }
        return value
    }

    private static let css = """
    .vp-choice{position:absolute;width:1px;height:1px;clip-path:inset(50%);overflow:hidden}
    .vp-tabs{display:flex;flex-wrap:wrap;gap:4px;margin-bottom:12px}
    .vp-tabs label{padding:6px 12px;border:1px solid var(--line);border-radius:5px;cursor:pointer}
    .vp-panel{display:none}.vp-scroll{overflow:auto;max-height:70vh;background:#f4f4f4}
    .vp-grid{border-collapse:collapse;table-layout:fixed;width:max-content;background:white;color:#222;font:11pt Calibri,Arial,sans-serif;transform:scale(var(--form-scale,1));transform-origin:top left;margin:0}
    .vp-grid th,.vp-grid td{box-sizing:border-box;border:1px solid #d9d9d9;padding:2px 4px;min-width:0}
    .vp-grid th{font:12px -apple-system,system-ui,sans-serif;text-align:center;background:#f0f0f0;color:#555}
    .vp-grid td{white-space:pre;overflow:hidden;font-weight:normal;padding:0 3px}
    .vp-grid td>div{overflow:hidden;max-height:2000px}
    .vp-no-horizontal td{border-top-color:transparent;border-bottom-color:transparent}
    .vp-no-vertical td{border-left-color:transparent;border-right-color:transparent}
    .vp-grid thead th{position:sticky;top:0;z-index:2}.vp-grid tbody th{position:sticky;left:0;z-index:1}
    """
}
