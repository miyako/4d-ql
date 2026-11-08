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
        report.stats = [
            Stat("Table", root.attributes["table_name"].map { value($0, key: "table_name") }
                 ?? root.attributes["table_no"].map { "Table \($0)" } ?? "Not specified"),
            Stat("Fields", Fmt.n(fields.count)),
            Stat("Format", root.attributes["format"].map { value($0, key: "format") } ?? "Not specified"),
            Stat("Encoding", root.attributes["encoding"].map { value($0, key: "encoding") } ?? "Not specified"),
        ]

        let limit = 500
        let cards = fields.prefix(limit).map { field -> OrderedCard in
            var details = [
                KeyValue("Table #", field.attributes["table_no"] ?? root.attributes["table_no"] ?? "Not specified"),
                KeyValue("Field #", field.attributes["field_no"] ?? "Not specified"),
            ]
            details += settings(field.attributes.filter { !Self.fieldKeys.contains($0.key) })
            details += properties(field).map { KeyValue($0[0], $0[1]) }
            return OrderedCard(title: field.attributes["name"] ?? "Not specified",
                               subtitle: field.attributes["kind"].map { Self.types[$0] ?? $0 } ?? "Not specified",
                               details: details, icon: field.attributes["kind"].flatMap { Self.icons[$0] })
        }
        var fieldBlocks: [Block] = fields.isEmpty ? [.note("No fields are selected in this configuration.", .neutral)] :
            [.orderedCards(cards)]
        if fields.count > limit {
            fieldBlocks.append(.note("\(Fmt.plural(fields.count - limit, "more field")) not shown; JSON output includes all fields.", .neutral))
        }
        report.sections.append(Section("Fields in import/export order", fieldBlocks))

        let additionalSettings = root.attributes.filter { !["table_name", "format", "encoding"].contains($0.key) }
        if !additionalSettings.isEmpty {
            report.sections.append(Section("Settings", [.keyValues(settings(additionalSettings))], width: .half))
        }
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
            var blocks: [Block] = [.keyValues(configuration.prefix(limit).map { KeyValue($0[0], $0[1]) })]
            if configuration.count > limit {
                blocks.append(.note("\(Fmt.plural(configuration.count - limit, "more setting")) not shown; JSON output includes all settings.", .neutral))
            }
            report.sections.append(Section("Options", blocks, width: .half))
        }
        return report
    }

    private static let fieldKeys: Set<String> = ["table_no", "field_no", "name", "kind"]
    private static let icons: [String: OrderedCard.Icon] = [
        "alpha": .text, "text": .text, "int16": .integer, "int32": .integer, "int64": .integer,
        "real": .real, "boolean": .boolean, "date": .date, "time": .time,
        "picture": .picture, "blob": .blob, "object": .object, "collection": .collection,
    ]
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
