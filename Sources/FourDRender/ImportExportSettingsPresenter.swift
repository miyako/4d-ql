import Foundation
import FourDFileKit

public struct ImportExportSettingsPresenter: ReportPresenter {
    public init() {}
    public var kinds: [String] { ["4d.import-export-settings"] }

    public func report(for model: AnalysisModel) -> Report? {
        guard let info = model as? ImportExportSettingsInfo else { return nil }
        let root = info.root
        let fields = root.children.filter { $0.name == "field" }
        var report = Report(title: info.fileName, subtitle: "4D Import/Export Settings")
        report.sections.append(Section("Settings", [.keyValues(settings(root.attributes))]))

        let limit = 500
        let hasOptions = fields.contains { !$0.children.isEmpty || !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !$0.attributes.keys.filter { !Self.fieldKeys.contains($0) }.isEmpty }
        var columns: [(String, Table.Align)] = [
            ("Order", .trailing), ("Table #", .trailing), ("Field #", .trailing),
            ("Field", .leading), ("Type", .leading),
        ]
        if hasOptions { columns.append(("Options", .leading)) }
        let rows = fields.prefix(limit).enumerated().map { index, field -> [String] in
            var row = [
                "\(index + 1)", field.attributes["table_no"] ?? root.attributes["table_no"] ?? "Not specified",
                field.attributes["field_no"] ?? "Not specified", field.attributes["name"] ?? "Not specified",
                field.attributes["kind"].map { Self.types[$0] ?? $0 } ?? "Not specified",
            ]
            if hasOptions {
                let attributes = field.attributes.filter { !Self.fieldKeys.contains($0.key) }
                var options = settings(attributes).map { "\($0.key): \($0.value)" }
                options += properties(field).map { "\($0[0]): \($0[1])" }
                row.append(options.joined(separator: "; "))
            }
            return row
        }
        let fieldBlocks: [Block] = fields.isEmpty ? [.note("No fields are selected in this configuration.", .neutral)] :
            [.table(Table(columns: columns, rows: rows,
                          more: fields.count > limit ? "\(Fmt.plural(fields.count - limit, "more field")) not shown; JSON output includes all fields." : nil))]
        report.sections.append(Section("Fields in import/export order", fieldBlocks))

        var configuration: [[String]] = []
        let text = root.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { configuration.append(["Text", text]) }
        let options = root.children.filter { $0.name != "field" }
        let counts = Dictionary(grouping: options, by: \.name).mapValues(\.count)
        for (index, node) in options.enumerated() {
            let path = label(node.name) + (counts[node.name] == 1 ? "" : " [\(index + 1)]")
            configuration += properties(node, path: path, includeAttributes: true)
        }
        if !configuration.isEmpty {
            report.sections.append(Section("Options", [.table(Table(
                columns: [("Setting", .leading), ("Value", .leading)],
                rows: Array(configuration.prefix(limit)),
                more: configuration.count > limit ? "\(Fmt.plural(configuration.count - limit, "more setting")) not shown; JSON output includes all settings." : nil))]))
        }
        return report
    }

    private static let fieldKeys: Set<String> = ["table_no", "field_no", "name", "kind"]
    private static let types = [
        "alpha": "Alpha", "text": "Text", "int16": "Integer (16-bit)", "int32": "Long integer (32-bit)",
        "int64": "Integer (64-bit)", "real": "Real", "boolean": "Boolean", "date": "Date",
        "time": "Time", "picture": "Picture", "blob": "BLOB", "object": "Object", "collection": "Collection",
    ]
    private static let labels = [
        "table_name": "Table", "table_no": "Table #", "format": "Format", "encoding": "Encoding",
        "char_display_format": "Character display format", "platform": "Platform",
        "text_settings": "Text settings", "with_column_title": "Include column titles",
    ]

    private func label(_ key: String) -> String {
        Self.labels[key] ?? key.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").capitalized
    }

    private func value(_ raw: String, key: String) -> String {
        if ["table_name", "format", "encoding"].contains(key) { return raw.isEmpty ? "(empty)" : raw }
        switch raw {
        case "true": return "Yes"
        case "false": return "No"
        case "automatic": return "Automatic"
        case "decimal": return "Decimal"
        case "": return "(empty)"
        default: return raw
        }
    }

    private func settings(_ attributes: [String: String]) -> [KeyValue] {
        let preferred = ["table_name", "table_no", "format", "encoding", "platform", "char_display_format"]
        let keys = preferred.filter { attributes[$0] != nil } + attributes.keys.filter { !preferred.contains($0) }.sorted()
        return keys.map { KeyValue(label($0), value(attributes[$0] ?? "", key: $0)) }
    }

    private func properties(_ node: ImportExportSettingsNode, path: String = "", includeAttributes: Bool = false) -> [[String]] {
        var rows = includeAttributes ? settings(node.attributes).map { [path + " / " + $0.key, $0.value] } : []
        let text = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { rows.append([path.isEmpty ? "Text" : path, text]) }
        if includeAttributes && node.attributes.isEmpty && node.children.isEmpty && text.isEmpty {
            rows.append([path, "(empty)"])
        }
        for (index, child) in node.children.enumerated() {
            let childPath = (path.isEmpty ? "" : path + " / ") + "\(label(child.name)) [\(index + 1)]"
            rows += properties(child, path: childPath, includeAttributes: true)
        }
        return rows
    }
}
