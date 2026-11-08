import Foundation
import FourDFileKit

public struct QueryPresenter: ReportPresenter {
    public init() {}
    public var kinds: [String] { ["4d.query"] }

    public func report(for model: AnalysisModel) -> Report? {
        guard let info = model as? QueryFileInfo else { return nil }
        var report = Report(title: info.fileName, subtitle: "4D Saved Query")
        let source = Block.disclosure(summary: "Original JSON",
                                      detail: info.properties["version"].map { "Version \(display($0))" },
                                      blocks: [.sourceCode(info.text, language: .json)])
        guard info.properties["version"]?.integer == 3 else {
            report.sections = [Section("Query", [
                .note("This query version is not decoded. The original JSON is available below.", .warning), source,
            ])]
            return report
        }
        report.stats = [
            Stat("Main table", "Table \(display(info.properties["mainTable"]))"),
            Stat("Conditions", Fmt.n(info.lines.count)),
        ]
        let destinations = [1: "Create selection", 2: "Filter selection",
                            3: "Add to selection", 4: "Remove from selection"]
        if let destination = info.properties["queryDestination"] {
            report.badges = [Badge(destination.integer.flatMap { destinations[$0] }
                                  ?? "Query destination \(display(destination))")]
        }
        let conditions = info.lines.prefix(200).enumerated().map { index, line in
            let connector: String
            if index == 0 {
                connector = line["lineOperator"].map { "Connector \(display($0)) (first line)" } ?? "WHERE"
            } else {
                connector = line["lineOperator"]?.integer.flatMap { [1: "AND", 2: "OR", 3: "EXCEPT"][$0] }
                    ?? "Unknown connector \(display(line["lineOperator"]))"
            }
            let field = "Table \(display(line["tableNumber"])) / Field \(display(line["fieldNumber"]))"
            let operation = operation(for: line)
            let operands = line.keys.sorted().filter {
                !["lineOperator", "tableNumber", "fieldNumber", "criterion"].contains($0)
            }.map { KeyValue($0 == "oneBox" ? "Value" : $0, display(line[$0]), mono: true) }
            return QueryCondition(connector: connector, field: field, operation: operation,
                                  code: display(line["criterion"]), operands: operands)
        }
        var blocks: [Block] = []
        if conditions.isEmpty {
            blocks.append(.note("No conditions are saved in this query.", .neutral))
        } else {
            blocks.append(.queryConditions(conditions))
        }
        if info.lines.count > conditions.count {
            blocks.append(.note("Showing the first 200 conditions. All conditions remain in Original JSON.", .warning))
        }
        blocks.append(source)
        report.sections = [Section("Conditions", blocks)]
        return report
    }

    private func operation(for line: [String: QueryValue]) -> String {
        // Saved operator IDs are overloaded by field type in 4D's query.xml.
        // A standalone query has no schema, so never choose a type-dependent meaning.
        guard let code = line["criterion"]?.integer else { return "Unknown criterion" }
        switch code {
        case 0: return "is false"
        case 1: return line["oneBox"] == nil ? "is true / is equal to" : "is equal to"
        case 2: return "is not equal to"
        case 3: return "is greater than or equal to (type-dependent)"
        case 4: return "is greater than"
        case 5: return "is less than or equal to (type-dependent)"
        case 6: return "is less than"
        case 7: return "is between (inclusive)"
        case 8, -8: return "is between (exclusive)"
        case 9: return "starts with"
        case 10: return "ends with"
        case 11: return "contains / is today"
        case 12: return "does not contain / is within current period"
        case 13, -13: return "contains keywords"
        case 14, -14: return "does not contain keywords"
        case 15: return "is in list"
        case 21: return "is yesterday"
        case 22: return "is within last period"
        case 23: return "is within the last"
        case 31: return "is tomorrow"
        case 32: return "is within next period"
        case 33: return "is within the next"
        case 41: return "is empty"
        case 42: return "is not empty"
        default: return "Unknown criterion"
        }
    }

    private func display(_ value: QueryValue?) -> String {
        guard let value else { return "(not saved)" }
        switch value {
        case .string(let text): return text.isEmpty ? "\"\" (empty)" : text
        case .integerNumber(let number): return String(number)
        case .number(let number): return String(number).hasSuffix(".0") ? String(String(number).dropLast(2)) : String(number)
        case .bool(let flag): return flag ? "true" : "false"
        case .null: return "null"
        case .array, .object:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            do { return String(decoding: try encoder.encode(value), as: UTF8.self) }
            catch { return "Unable to display saved value: \(error)" }
        }
    }
}
