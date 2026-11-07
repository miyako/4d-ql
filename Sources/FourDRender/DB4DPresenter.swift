import Foundation
import FourDFileKit

/// Presentation of .4DD data files and binary .4DB structure files.
///
/// Priorities, most prominent first:
/// 1. what the file contains: tables, records, fields (fixed-size charts, so
///    hundreds of tables fit in the same space as a handful);
/// 2. what decides whether it opens and behaves as expected: the database UUID
///    (must match the structure), sort/search language and wildcard rule
///    (affect indexes), journal file, encryption;
/// 3. a little reference information (format version, storage use, byte order).
/// Engine internals (block size, flush counters, LCIDs, …) stay in the JSON
/// output of `fourdql --json` and are not shown.
public struct DB4DPresenter: ReportPresenter {
    public init() {}
    public var kinds: [String] { ["db4d.data", "db4d.structure"] }

    /// Bars shown before the long tail folds into "Other".
    static let maxTableBars = 8
    static let maxTableRows = 8

    public func report(for model: AnalysisModel) -> Report? {
        guard let info = model as? DB4DFileInfo else { return nil }
        let h = info.header
        let isData = info.role == .data
        let enc = info.encryption

        var subtitle = isData ? "4D data file" : "4D structure file (binary)"
        if isData, let lm = info.lastModified { subtitle += " · last write \(lm.text)" }
        var r = Report(title: info.fileName, subtitle: subtitle)

        // Only states that need attention, or that change what can be read.
        if enc.isEncrypted { r.badges.append(Badge("🔒 Encrypted", .warning)) }
        r.badges.append(h.flushedCleanly ? Badge("Closed cleanly", .good)
                                         : Badge("Not closed cleanly", .danger))
        if h.needsRepair { r.badges.append(Badge("Needs repair", .danger)) }
        if h.segmentCount > 1 { r.badges.append(Badge("\(h.segmentCount) segments", .warning)) }

        let fieldCount = info.tables.reduce(0) { $0 + $1.fields.count }
        r.stats.append(Stat("Tables", Fmt.n(info.tables.count)))
        if isData { r.stats.append(Stat("Records", Fmt.n(info.totalRecords))) }
        r.stats.append(Stat("Fields", Fmt.n(fieldCount)))
        if !isData {
            r.stats.append(Stat("Relations", Fmt.n(info.relations.count)))
            if let res = info.resources { r.stats.append(Stat("Resources", Fmt.n(res.total))) }
        }
        if enc.isEncrypted { r.stats.append(Stat("Encrypted tables", "\(Fmt.n(enc.encryptedTables)) of \(Fmt.n(info.tables.count))")) }

        r.sections.append(tablesSection(info))
        if fieldCount > 0 { r.sections.append(Section("Field types", [fieldTypes(info)])) }
        if !info.relations.isEmpty { r.sections.append(relationsSection(info)) }
        if let res = info.resources, !res.types.isEmpty { r.sections.append(resourcesSection(res)) }

        r.sections.append(databaseSection(info))
        r.sections.append(storageSection(info))
        r.sections.append(sortingSection(info))
        r.sections.append(journalSection(info))
        if enc.isEncrypted || enc.encryptableTables > 0 { r.sections.append(encryptionSection(info)) }

        let other = otherProperties(info)
        if !other.isEmpty { r.sections.append(Section("Other properties", [.keyValues(other)])) }
        if !info.warnings.isEmpty {
            r.sections.append(Section("Parser notes", info.warnings.prefix(5).map { .note($0, .warning) }))
        }
        return r
    }

    // MARK: Contents

    private func tablesSection(_ info: DB4DFileInfo) -> Section {
        guard !info.tables.isEmpty else { return Section("Tables", [.text("No tables.")]) }
        // Data files rank by records; structure files (or empty data) by fields.
        let byRecords = info.role == .data && info.totalRecords > 0
        let metric: (TableInfo) -> Int = { byRecords ? ($0.recordCount ?? 0) : $0.fields.count }
        let ranked = info.tables.sorted { metric($0) != metric($1) ? metric($0) > metric($1) : $0.number < $1.number }

        let fold = ranked.count > Self.maxTableBars + 1
        let shown = fold ? Array(ranked.prefix(Self.maxTableBars)) : ranked
        var rows = shown.map { t -> BarRow in
            var tip = "[\(t.number)] \(t.name) — \(Fmt.plural(t.fields.count, "field"))"
            if let rc = t.recordCount { tip += ", \(Fmt.plural(rc, "record"))" }
            if let bc = t.blobCount, bc > 0 { tip += ", \(Fmt.plural(bc, "external blob"))" }
            if t.encrypted == true { tip += ", encrypted" } else if t.encryptable { tip += ", encryptable" }
            return BarRow(label: t.name, value: Double(metric(t)),
                          display: byRecords ? Fmt.n(t.recordCount ?? 0) : Fmt.n(t.fields.count),
                          extra: byRecords ? Fmt.n(t.fields.count) : "",
                          marker: t.encrypted == true ? "🔒" : nil, tooltip: tip)
        }
        if fold {
            let rest = ranked.dropFirst(Self.maxTableBars)
            let restRecords = rest.reduce(0) { $0 + ($1.recordCount ?? 0) }
            let restFields = rest.reduce(0) { $0 + $1.fields.count }
            // No bar: the folded total is not comparable with a single table.
            rows.append(BarRow(label: "\(Fmt.n(rest.count)) other tables", value: 0,
                               display: byRecords ? Fmt.n(restRecords) : Fmt.n(restFields),
                               extra: byRecords ? Fmt.n(restFields) : "", muted: true,
                               tooltip: rest.prefix(30).map(\.name).joined(separator: ", ") + (rest.count > 30 ? ", …" : "")))
        }
        return Section("Tables", [.bars(rows: rows, valueHeader: byRecords ? "Records" : "Fields",
                                        extraHeader: byRecords ? "Fields" : "")])
    }

    /// Field types grouped into eight families, each with a fixed colour slot.
    static let families: [(name: String, slot: Int, kinds: Set<FieldKind>)] = [
        ("Text", 1, [.text, .legacyText, .uuid]),
        ("Integer", 2, [.integer, .longint, .integer64]),
        ("Real", 3, [.real, .float]),
        ("Date & time", 4, [.date, .time]),
        ("Boolean", 5, [.boolean]),
        ("Picture", 6, [.picture]),
        ("BLOB", 7, [.blob]),
        ("Object", 8, [.object]),
    ]

    private func fieldTypes(_ info: DB4DFileInfo) -> Block {
        let fields = info.tables.flatMap(\.fields)
        var segments = Self.families.map { fam -> Segment in
            let n = fields.filter { $0.kind.map(fam.kinds.contains) ?? false }.count
            return Segment(label: fam.name, value: Double(n), display: Fmt.n(n), slot: fam.slot)
        }
        let unknown = fields.filter { $0.kind == nil }.count
        if unknown > 0 { segments.append(Segment(label: "Other", value: Double(unknown), display: Fmt.n(unknown), slot: nil)) }
        return .composition(segments)
    }

    private func relationsSection(_ info: DB4DFileInfo) -> Section {
        let rows = info.relations.prefix(Self.maxTableRows).map {
            [$0.sourceField, $0.destinationField, [$0.name, $0.inverseName].filter { !$0.isEmpty }.joined(separator: " / ")]
        }
        let more = info.relations.count > Self.maxTableRows ? "and \(Fmt.n(info.relations.count - Self.maxTableRows)) more" : nil
        return Section("Relations", [.table(Table(
            columns: [("Many", .leading), ("One", .leading), ("Names", .leading)], rows: Array(rows), more: more))])
    }

    /// Resource types whose meaning is reasonably certain. Others are shown by code only.
    static let resourceNames: [String: String] = [
        "FO4D": "Form", "MEN4": "Menu bar", "4PCT": "Picture library", "4pct": "Picture library",
        "#GRP": "Group", "STR#": "String list", "ST4D": "Style sheet", "UUID": "Database UUID",
    ]

    private func resourcesSection(_ res: ResourceSummary) -> Section {
        let label: (ResourceTypeCount) -> String = { t in Self.resourceNames[t.type].map { "\(t.type) · \($0)" } ?? t.type }
        var rows = res.types.prefix(Self.maxTableBars).map {
            BarRow(label: label($0), value: Double($0.count), display: Fmt.n($0.count))
        }
        if res.types.count > Self.maxTableBars {
            let rest = res.types.dropFirst(Self.maxTableBars)
            rows.append(BarRow(label: "\(rest.count) other types", value: 0,
                               display: Fmt.n(rest.reduce(0) { $0 + $1.count }), muted: true,
                               tooltip: rest.map(\.type).joined(separator: ", ")))
        }
        var blocks: [Block] = [.bars(rows: rows, valueHeader: "Count", extraHeader: "")]
        if !res.complete {
            blocks.append(.note("Counted \(Fmt.n(res.scanned)) of \(Fmt.n(res.total)) resources.", .neutral))
        }
        return Section("Resources", blocks)
    }

    // MARK: Opening and behaviour

    private func databaseSection(_ info: DB4DFileInfo) -> Section {
        let caption = info.role == .data
            ? "Opens only with the structure or project that has this UUID."
            : "Data files created for this structure carry the same UUID."
        return Section("Database", [
            .identity(label: "Database UUID", value: info.header.databaseUUID, caption: caption),
            .keyValues([KeyValue("Format version", info.header.formatVersion),
                        KeyValue("Byte order", info.header.littleEndian ? "Little endian" : "Big endian")]),
        ], width: .half)
    }

    private func storageSection(_ info: DB4DFileInfo) -> Section {
        let size = info.fileSize, used = min(info.header.logicalEOF, size)
        let fraction = size > 0 ? Double(used) / Double(size) : 0
        let free = size - used
        return Section("Storage", [
            .meter(fraction: fraction, label: "\(Fmt.bytes(used)) used of \(Fmt.bytes(size))",
                   caption: free > 0 ? "\(Fmt.bytes(free)) allocated but unused (\(Fmt.percent(1 - fraction)))" : "No unused space"),
        ], width: .half)
    }

    private func sortingSection(_ info: DB4DFileInfo) -> Section {
        let h = info.header, c = h.collation
        var kv = [KeyValue("Language", languageName(h) ?? "Unknown")]
        // 4D setting: "Consider @ as a wildcard only at the beginning or end of text patterns".
        kv.append(KeyValue("@ in the middle", c.ignoreWildcardInMiddle ? "Literal character" : "Wildcard"))

        // These options only matter for Japanese without ICU (the MeCab-based engine).
        let japanese = h.dialectLocaleIdentifier?.hasPrefix("ja") ?? false
        if japanese && !c.useICU {
            kv += [
                KeyValue("ICU", "No"),
                KeyValue("Secondary strength (matching)", yesNo(c.secondaryStrengthForMatching)),
                KeyValue("Quaternary strength (sorting)", yesNo(c.quaternaryStrengthForSorting)),
                KeyValue("Hiragana first", yesNo(c.hiraganaFirstOnQuaternaryLevel)),
                KeyValue("Language-neutral deadchars", yesNo(c.languageNeutralDeadchar)),
                KeyValue("Traditional sorting", yesNo(c.traditionalStyleSorting)),
            ]
        }

        // Engine markers: 4D reindexes when they differ from the running engine.
        if let v = property(info, "__stringCompHash") { kv.append(KeyValue("Comparison engine", Self.engineName(v))) }
        if let v = property(info, "__keywordBuildingHash") { kv.append(KeyValue("Keyword engine", Self.engineName(v))) }
        return Section("Sorting and searching", [.keyValues(kv)], width: .half)
    }

    private func journalSection(_ info: DB4DFileInfo) -> Section {
        guard let j = info.journal else {
            return Section("Journal", [.text("No journal file recorded.")], width: .half)
        }
        var kv: [KeyValue] = []
        if let on = j.enabled { kv.append(KeyValue("Journaling", on ? "On" : "Off")) }
        if let p = j.path { kv.append(KeyValue(j.pending ? "Next journal" : "Journal file", p, mono: true)) }
        var blocks: [Block] = [.keyValues(kv)]
        if j.pending { blocks.append(.note("4D starts writing this journal after the next backup.", .neutral)) }
        return Section("Journal", blocks, width: .half)
    }

    private func encryptionSection(_ info: DB4DFileInfo) -> Section {
        let enc = info.encryption
        let names: ([TableInfo]) -> String = { ts in
            ts.isEmpty ? "None" : ts.prefix(10).map(\.name).joined(separator: ", ") + (ts.count > 10 ? " and \(ts.count - 10) more" : "")
        }
        var kv: [KeyValue] = []
        if info.role == .data {
            kv.append(KeyValue("Encrypted tables", names(info.tables.filter { $0.encrypted == true })))
            let pending = info.tables.filter { $0.encryptable && $0.encrypted == false }
            if !pending.isEmpty { kv.append(KeyValue("Encryptable, not encrypted", names(pending))) }
            let unknown = info.tables.filter { $0.encryptable && $0.encrypted == nil }
            if !unknown.isEmpty { kv.append(KeyValue("Encryptable, no records", names(unknown))) }
        } else {
            kv.append(KeyValue("Encryptable tables", names(info.tables.filter(\.encryptable))))
        }
        var blocks: [Block] = [.keyValues(kv)]
        if enc.isEncrypted {
            blocks.append(.note("Records of encrypted tables need the data key; definitions and counts are stored in clear.", .neutral))
        } else if info.role == .data {
            blocks.append(.note("The structure allows encryption, but this data file is not encrypted.", .neutral))
        }
        return Section("Encryption", blocks)
    }

    /// Extra properties not already shown elsewhere, with readable keys.
    private func otherProperties(_ info: DB4DFileInfo) -> [KeyValue] {
        let shown: Set<String> = ["__stringCompHash", "__keywordBuildingHash", "encryptedProofB64"]
        return info.extraProperties
            // "*_stamp" values are internal change counters.
            .filter { !shown.contains($0.key) && !$0.key.hasPrefix("journal_file.") && !$0.key.hasSuffix("_stamp") }
            .prefix(8)
            .map { KeyValue(Self.humanize($0.key), $0.value) }
    }

    // MARK: Helpers

    private func property(_ info: DB4DFileInfo, _ key: String) -> String? {
        info.extraProperties.first { $0.key == key }?.value
    }

    private func yesNo(_ b: Bool) -> String { b ? "Yes" : "No" }

    private func languageName(_ h: DB4DHeader) -> String? {
        if h.dialectCode == -4444 { return "System" }
        guard let id = h.dialectLocaleIdentifier else { return nil }
        return Locale.current.localizedString(forIdentifier: id) ?? id
    }

    /// "icu:68.1.0, alternate=search" -> "ICU 68.1.0 (alternate=search)";
    /// "mecab:0.996;sys.dic:102;" -> "MeCab 0.996 · sys.dic 102".
    static func engineName(_ raw: String) -> String {
        let names = ["icu": "ICU", "mecab": "MeCab"]
        var parts: [String] = [], options: [String] = []
        for piece in raw.split(whereSeparator: { $0 == ";" || $0 == "," }) {
            let p = piece.trimmingCharacters(in: .whitespaces)
            guard !p.isEmpty else { continue }
            if let colon = p.firstIndex(of: ":") {
                let k = String(p[..<colon]), v = String(p[p.index(after: colon)...])
                parts.append("\(names[k.lowercased()] ?? k) \(v)")
            } else {
                options.append(p)
            }
        }
        guard !parts.isEmpty else { return raw }
        return parts.joined(separator: " · ") + (options.isEmpty ? "" : " (\(options.joined(separator: ", ")))")
    }

    /// "data_file_path" -> "Data file path"; "__x" -> "X".
    static func humanize(_ key: String) -> String {
        let words = key.split(separator: "_").joined(separator: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
