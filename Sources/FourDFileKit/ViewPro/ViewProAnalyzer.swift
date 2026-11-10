import Foundation

public struct ViewProFileAnalyzer: FileAnalyzer {
    public init() {}
    public var identifier: String { "4vp" }
    public var contentTypes: [String] { ["com.4d.4d.ViewProDocument"] }
    public var filenameExtensions: [String] { ["4vp"] }

    public func analyze(_ source: ByteSource, options: AnalysisOptions) throws -> AnalysisModel {
        guard source.size <= 16 * 1024 * 1024 else { throw ViewProError.limit("JSON exceeds 16 MiB.") }
        return try Self.parse(source.read(at: 0, length: Int(source.size)), fileName: source.url.lastPathComponent)
    }

    public static func parse(_ data: Data, fileName: String) throws -> ViewProFileInfo {
        guard data.count <= 16 * 1024 * 1024 else { throw ViewProError.limit("JSON exceeds 16 MiB.") }
        let root: FormValue
        do {
            var parser = try FormJSONParser(data)
            root = try parser.parse()
        } catch FormError.invalid(let reason) {
            throw ViewProError.invalid(reason)
        } catch FormError.limit(let reason) {
            throw ViewProError.limit(reason)
        }
        guard case .object = root, root["version"]?.double == 1,
              let workbook = root["spreadJS"], case .object = workbook,
              let sheets = workbook["sheets"], case .object = sheets else {
            throw ViewProError.invalid("Expected version 1 and a spreadJS workbook with a sheets object.")
        }
        guard sheets.members.count <= 256 else { throw ViewProError.limit("More than 256 sheets.") }
        let globalStyles = try namedStyles(workbook["namedStyles"])
        var parsed: [ViewProSheet] = []
        var cellCount = 0
        var indices = Set<Int>()
        for (position, member) in sheets.members.enumerated() {
            let sheet = try parseSheet(member.value, name: member.name, position: position,
                                       globalStyles: globalStyles, cellCount: &cellCount)
            guard indices.insert(sheet.index).inserted else { throw ViewProError.invalid("Duplicate sheet index \(sheet.index).") }
            parsed.append(sheet)
        }
        let order = Dictionary(uniqueKeysWithValues: sheets.members.map { ($0.name, integer($0.value["order"]) ?? integer($0.value["index"]) ?? 0) })
        parsed.sort {
            let a = order[$0.name] ?? $0.index, b = order[$1.name] ?? $1.index
            return a == b ? $0.index < $1.index : a < b
        }
        return ViewProFileInfo(fileName: fileName, version: "1", spreadVersion: workbook["version"]?.string,
                               activeSheet: try count(workbook["activeSheetIndex"], fallback: 0, label: "activeSheetIndex"),
                               sheets: parsed, warnings: [])
    }

    private static func parseSheet(_ source: FormValue, name: String, position: Int,
                                   globalStyles: [String: FormValue], cellCount: inout Int) throws -> ViewProSheet {
        guard case .object = source else { throw ViewProError.invalid("Sheet \(name) is not an object.") }
        let rowCount = try count(source["rowCount"], fallback: 200, label: "rowCount")
        let columnCount = try count(source["columnCount"], fallback: 20, label: "columnCount")
        let index = try count(source["index"], fallback: position, label: "sheet index")
        _ = try count(source["order"], fallback: index, label: "sheet order")
        let visibility = try count(source["visible"], fallback: 1, label: "sheet visibility")
        guard (0...2).contains(visibility) else { throw ViewProError.invalid("Unknown sheet visibility \(visibility).") }
        let styles = globalStyles.merging(try namedStyles(source["namedStyles"])) { _, local in local }
        var warnings: [String] = []
        let data = source["data"]
        if let data, case .object = data {} else if data != nil { throw ViewProError.invalid("Sheet data must be an object.") }
        let defaultStyle = try style(data?["defaultDataNode"]?["style"], named: styles)
        var rows = try axes(source["rows"], count: rowCount)
        var columns = try axes(source["columns"], count: columnCount)
        // SpreadJS can retain row/column styles without saving size metadata.
        try addAxisStyles(data?["rowDataArray"], to: &rows, count: rowCount, named: styles)
        try addAxisStyles(data?["columnDataArray"], to: &columns, count: columnCount, named: styles)
        var cells: [ViewProCell] = []
        if let table = data?["dataTable"] {
            guard case .object = table else { throw ViewProError.invalid("dataTable must be an object.") }
            var rowIndices = Set<Int>()
            for row in table.members {
                let r = try coordinate(row.name, count: rowCount)
                guard rowIndices.insert(r).inserted, case .object = row.value else { throw ViewProError.invalid("Invalid or duplicate dataTable row.") }
                var columnIndices = Set<Int>()
                for column in row.value.members {
                    let c = try coordinate(column.name, count: columnCount)
                    guard columnIndices.insert(c).inserted, case .object = column.value else { throw ViewProError.invalid("Invalid or duplicate dataTable cell.") }
                    cellCount += 1
                    guard cellCount <= 20_000 else { throw ViewProError.limit("More than 20,000 saved cells.") }
                    let node = column.value
                    var runs: [ViewProTextRun] = []
                    let value = try cellValue(node["value"], runs: &runs, named: styles, warnings: &warnings)
                    if let formula = node["formula"], formula.string == nil { throw ViewProError.invalid("Cell formula must be text.") }
                    var cell = ViewProCell(row: r, column: c, value: value, formula: node["formula"]?.string,
                                           formattedText: node["style"]?["formatInfo"]?["text"]?.string,
                                           style: try style(node["style"], named: styles),
                                           link: node["hyperlink"]?["url"]?.string)
                    cell.runs = runs
                    cells.append(cell)
                }
            }
        }
        cells.sort { $0.row == $1.row ? $0.column < $1.column : $0.row < $1.row }
        var spans: [ViewProSpan] = []
        if let values = source["spans"] {
            guard case .array = values, values.values.count <= 2000 else { throw ViewProError.limit("Invalid spans or more than 2,000 merged ranges.") }
            for span in values.values {
                guard let row = integer(span["row"]), let column = integer(span["col"]),
                      let height = integer(span["rowCount"]), let width = integer(span["colCount"]),
                      row >= 0, column >= 0, height > 0, width > 0,
                      row < rowCount, column < columnCount, height <= rowCount - row, width <= columnCount - column else {
                    throw ViewProError.invalid("Merged range lies outside its sheet.")
                }
                let current = ViewProSpan(row: row, column: column, rowCount: height, columnCount: width)
                guard !spans.contains(where: {
                    row < $0.row + $0.rowCount && row + height > $0.row &&
                    column < $0.column + $0.columnCount && column + width > $0.column
                }) else { throw ViewProError.invalid("Overlapping merged ranges.") }
                spans.append(current)
            }
        }
        for (key, label) in [("charts", "Charts"), ("pictures", "Pictures"), ("shapes", "Shapes"),
                             ("conditionalFormats", "Conditional formatting"), ("tables", "Table styling")] {
            if let value = source[key], !value.values.isEmpty || !value.members.isEmpty {
                warnings.append("\(label) are not reproduced.")
            }
        }
        let defaults = source["defaults"]
        var sheet = ViewProSheet(name: name, index: index, visible: visibility == 1, rowCount: rowCount, columnCount: columnCount,
                            cells: cells, rows: rows, columns: columns,
                            defaultRowHeight: try size(defaults?["rowHeight"], fallback: 20),
                            defaultColumnWidth: try size(defaults?["colWidth"], fallback: 64),
                            defaultStyle: defaultStyle, spans: spans,
                            showGridLines: source["gridline"]?["showHorizontalGridline"]?.bool != false ||
                                source["gridline"]?["showVerticalGridline"]?.bool != false,
                            warnings: Array(Set(warnings)).sorted())
        sheet.showHorizontalGridLines = source["gridline"]?["showHorizontalGridline"]?.bool != false
        sheet.showVerticalGridLines = source["gridline"]?["showVerticalGridline"]?.bool != false
        return sheet
    }

    private static func cellValue(_ value: FormValue?, runs: inout [ViewProTextRun], named: [String: FormValue],
                                  warnings: inout [String]) throws -> ViewProValue? {
        guard let value else { return nil }
        switch value {
        case .null: return nil
        case .bool(let value): return .boolean(value)
        case .integer(let value): return .number(Double(value))
        case .number(let value): return .number(value)
        case .string(let value):
            if value.hasPrefix("/OADate("), value.hasSuffix(")/"),
               let serial = Double(value.dropFirst(8).dropLast(2)), serial.isFinite {
                return .dateSerial(serial)
            }
            return .text(value)
        case .object:
            if let error = value["_calcError"]?.string { return .error(error) }
            if let rich = value["richText"], case .array = rich {
                for run in rich.values {
                    guard let text = run["text"]?.string else { throw ViewProError.invalid("Rich-text run has no text.") }
                    runs.append(ViewProTextRun(text: text, style: try style(run["style"], named: named)))
                }
                return .text(runs.map(\.text).joined())
            }
            warnings.append("Unsupported object cell values are shown as [Object].")
            return .text("[Object]")
        case .array:
            warnings.append("Unsupported array cell values are shown as [Array].")
            return .text("[Array]")
        }
    }

    private static func namedStyles(_ value: FormValue?) throws -> [String: FormValue] {
        guard let value else { return [:] }
        guard case .array = value else { throw ViewProError.invalid("namedStyles must be an array.") }
        var result: [String: FormValue] = [:]
        for item in value.values {
            guard let name = item["name"]?.string, result[name] == nil else { throw ViewProError.invalid("Missing or duplicate named style.") }
            result[name] = item
        }
        return result
    }

    private static func style(_ source: FormValue?, named: [String: FormValue], path: Set<String> = []) throws -> ViewProStyle {
        guard let source else { return ViewProStyle() }
        if case .null = source { return ViewProStyle() }
        if case .string(let name) = source {
            guard path.count < 16, !path.contains(name), let definition = named[name] else {
                throw ViewProError.invalid("Unresolved or cyclic named style: \(name)")
            }
            return try style(definition, named: named, path: path.union([name]))
        }
        guard case .object = source else { throw ViewProError.invalid("Style must be an object.") }
        var result = ViewProStyle()
        if let parent = source["parentName"]?.string, !parent.isEmpty {
            guard path.count < 16, !path.contains(parent), let definition = named[parent] else {
                throw ViewProError.invalid("Unresolved or cyclic named style: \(parent)")
            }
            result = try style(definition, named: named, path: path.union([parent]))
        }
        var direct = ViewProStyle()
        direct.font = source["font"]?.string
        direct.foreground = source["foreColor"]?.string
        direct.background = source["backColor"]?.string
        direct.horizontalAlignment = integer(source["hAlign"])
        direct.verticalAlignment = integer(source["vAlign"])
        direct.wordWrap = source["wordWrap"]?.bool
        direct.textDecoration = integer(source["textDecoration"])
        direct.formatter = source["formatter"]?.string
        direct.textIndent = source["textIndent"]?.double
        for (property, side) in [("borderTop", "top"), ("borderRight", "right"), ("borderBottom", "bottom"), ("borderLeft", "left")] {
            if let border = source[property], let line = integer(border["style"]) {
                direct.borders[side] = ViewProBorder(color: border["color"]?.string, style: line)
            }
        }
        return result.merging(direct)
    }

    private static func axes(_ value: FormValue?, count: Int) throws -> [Int: ViewProAxis] {
        guard let value else { return [:] }
        guard case .array = value else { throw ViewProError.invalid("Axis metadata must be an array.") }
        guard value.values.count <= count else { throw ViewProError.invalid("Axis metadata exceeds sheet dimensions.") }
        var result: [Int: ViewProAxis] = [:]
        for (index, item) in value.values.enumerated() {
            if case .null = item { continue }
            guard case .object = item else { throw ViewProError.invalid("Axis entry must be an object or null.") }
            let dimension = item["size"]?.double
            if item["size"] != nil, dimension == nil { throw ViewProError.invalid("Axis size must be numeric.") }
            if item["visible"] != nil, item["visible"]?.bool == nil { throw ViewProError.invalid("Axis visibility must be boolean.") }
            if let dimension, !dimension.isFinite || dimension < 0 { throw ViewProError.invalid("Invalid axis size.") }
            result[index] = ViewProAxis(size: dimension, visible: item["visible"]?.bool != false && dimension != 0,
                                        style: ViewProStyle())
        }
        return result
    }

    private static func addAxisStyles(_ value: FormValue?, to axes: inout [Int: ViewProAxis], count: Int, named: [String: FormValue]) throws {
        guard let value else { return }
        guard case .array = value, value.values.count <= count else { throw ViewProError.invalid("Invalid axis style array.") }
        for (index, item) in value.values.enumerated() {
            if case .null = item { continue }
            guard case .object = item else { throw ViewProError.invalid("Axis style entry must be an object or null.") }
            var axis = axes[index] ?? ViewProAxis(visible: true, style: ViewProStyle())
            axis.style = try style(item["style"], named: named)
            axes[index] = axis
        }
    }

    private static func integer(_ value: FormValue?) -> Int? {
        value?.double.flatMap(Int.init(exactly:))
    }

    private static func count(_ value: FormValue?, fallback: Int, label: String) throws -> Int {
        guard let value else { return fallback }
        guard let count = integer(value), (0...10_000_000).contains(count) else { throw ViewProError.invalid("Invalid \(label).") }
        return count
    }

    private static func coordinate(_ text: String, count: Int) throws -> Int {
        guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }),
              let index = Int(text), index >= 0, index < count else { throw ViewProError.invalid("Cell index \(text) lies outside its sheet.") }
        return index
    }

    private static func size(_ value: FormValue?, fallback: Double) throws -> Double {
        guard let value else { return fallback }
        guard let size = value.double, size.isFinite, size > 0 else { throw ViewProError.invalid("Default axis size must be positive.") }
        return size
    }
}
