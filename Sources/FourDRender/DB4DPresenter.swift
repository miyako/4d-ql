import Foundation
import FourDFileKit

/// Presentation of .4DD data files and binary .4DB structure files.
public struct DB4DPresenter: ReportPresenter {
    public init() {}
    public var kinds: [String] { ["db4d.data", "db4d.structure"] }

    public func report(for model: AnalysisModel) -> Report? {
        guard let info = model as? DB4DFileInfo else { return nil }
        let h = info.header
        let isData = info.role == .data

        var r = Report(title: info.fileName,
                       subtitle: "\(isData ? "4D data file" : "4D structure file (binary)") · \(Fmt.bytes(info.fileSize))")

        // Health and configuration at a glance.
        r.badges.append(h.flushedCleanly ? Badge("Closed cleanly", .good)
                                         : Badge("Not closed cleanly (cache flush interrupted)", .danger))
        if h.needsRepair { r.badges.append(Badge("Marked as needing repair", .danger)) }
        if let lang = languageName(h) { r.badges.append(Badge("Sort/search: \(lang)")) }
        if h.collation.useICU { r.badges.append(Badge("ICU")) }
        if h.indexesInSeparateFile { r.badges.append(Badge(isData ? "Indexes in .4DIndx" : "Indexes in .4DIndy")) }
        if h.segmentCount > 1 { r.badges.append(Badge("\(h.segmentCount) segments", .warning)) }

        // Headline numbers.
        let fieldCount = info.tables.reduce(0) { $0 + $1.fields.count }
        r.stats.append(Stat("Tables", Fmt.n(info.tables.count)))
        if isData { r.stats.append(Stat("Records", Fmt.n(info.totalRecords))) }
        r.stats.append(Stat("Fields", Fmt.n(fieldCount)))
        if !info.relations.isEmpty || !isData { r.stats.append(Stat("Relations", Fmt.n(h.relationCount))) }
        r.stats.append(Stat("Indexes", Fmt.n(isData ? h.indexCount : max(h.indexCount, h.structureIndexCount))))
        if let res = info.resources { r.stats.append(Stat("Resources", Fmt.n(res.total))) }
        if let lm = info.lastModified { r.stats.append(Stat("Last write", lm.text)) }

        r.sections.append(tablesSection(info))
        if !info.relations.isEmpty { r.sections.append(relationsSection(info)) }
        if let res = info.resources { r.sections.append(resourcesSection(res)) }
        r.sections.append(fileSection(info))
        r.sections.append(collationSection(h))
        if !info.extraProperties.isEmpty {
            r.sections.append(Section("Database properties", [.keyValues(info.extraProperties.map { ($0.key, $0.value) })]))
        }
        if !info.warnings.isEmpty {
            r.sections.append(Section("Parser notes", info.warnings.prefix(20).map { .note($0, .warning) }))
        }
        return r
    }

    private func tablesSection(_ info: DB4DFileInfo) -> Section {
        guard !info.tables.isEmpty else { return Section("Tables", [.text("No tables.")]) }
        var blocks: [Block] = []
        if info.role == .data, info.totalRecords > 0 {
            let top = info.tables.sorted { ($0.recordCount ?? 0) > ($1.recordCount ?? 0) }.prefix(12)
            blocks.append(.bars(top.map { (label: $0.name, value: Double($0.recordCount ?? 0), display: Fmt.n($0.recordCount ?? 0)) }))
        }
        for t in info.tables {
            var detail = [Fmt.plural(t.fields.count, "field")]
            if let rc = t.recordCount { detail.insert(Fmt.plural(rc, "record"), at: 0) }
            if let bc = t.blobCount, bc > 0 { detail.append(Fmt.plural(bc, "external blob")) }
            var inner: [Block] = []
            if !t.fields.isEmpty {
                inner.append(.table(Table(columns: [("#", .trailing), ("Field", .leading), ("Type", .leading)],
                                          rows: t.fields.map { [String($0.number), $0.name, $0.typeName] })))
            } else {
                inner.append(.note("Field definitions are not stored for this table.", .neutral))
            }
            var meta: [(String, String)] = [("Table number", String(t.number)), ("UUID", t.uuid)]
            if let lm = t.lastModified { meta.append(("Last header write", lm.text)) }
            if t.historicalDefinitions > 0 { meta.append(("Older definitions kept", String(t.historicalDefinitions))) }
            inner.append(.keyValues(meta))
            blocks.append(.disclosure(summary: "[\(t.number)] \(t.name)", detail: detail.joined(separator: " · "), blocks: inner))
        }
        return Section("Tables", blocks)
    }

    private func relationsSection(_ info: DB4DFileInfo) -> Section {
        Section("Relations", [.table(Table(
            columns: [("Many (source)", .leading), ("One (destination)", .leading), ("Names", .leading)],
            rows: info.relations.map { [$0.sourceField, $0.destinationField, [$0.name, $0.inverseName].filter { !$0.isEmpty }.joined(separator: " / ")] }))])
    }

    /// Resource types whose meaning is reasonably certain. Others are shown by code only.
    static let resourceNames: [String: String] = [
        "FO4D": "Form", "MEN4": "Menu bar", "4PCT": "Picture library", "4pct": "Picture library",
        "#GRP": "Group", "STR#": "String list", "ST4D": "Style sheet", "UUID": "Database UUID",
    ]

    private func resourcesSection(_ res: ResourceSummary) -> Section {
        var blocks: [Block] = [.table(Table(
            columns: [("Type", .leading), ("Meaning", .leading), ("Count", .trailing)],
            rows: res.types.map { [$0.type, Self.resourceNames[$0.type] ?? "", Fmt.n($0.count)] }))]
        if !res.complete {
            blocks.append(.note("Counted \(Fmt.n(res.scanned)) of \(Fmt.n(res.total)) resources to keep the preview fast.", .neutral))
        }
        return Section("Resources", blocks)
    }

    private func fileSection(_ info: DB4DFileInfo) -> Section {
        let h = info.header
        var kv: [(String, String)] = [
            ("Format version", h.formatVersion),
            ("Database UUID", h.databaseUUID),
            ("Size on disk", Fmt.bytes(info.fileSize)),
            ("Used (logical EOF)", Fmt.bytes(h.logicalEOF)),
            ("Block size", "\(h.blockSize) bytes"),
            ("Byte order", h.littleEndian ? "Little endian" : "Big endian"),
            ("Segments", String(h.segmentCount)),
            ("Sequence numbers", Fmt.n(h.sequenceCount)),
            ("Indexes", Fmt.n(h.indexCount)),
        ]
        if h.structureIndexCount > 0 { kv.append(("Structure indexes", Fmt.n(h.structureIndexCount))) }
        kv += [
            ("Cache flushes", Fmt.n(h.flushCount)),
            ("Header modifications", Fmt.n(h.headerModificationCount)),
        ]
        if h.lastJournalAction > 0 || h.journalFileCount > 0 {
            kv.append(("Journal files", Fmt.n(h.journalFileCount)))
            kv.append(("Last journal operation", Fmt.n(h.lastJournalAction)))
        }
        return Section("File", [.keyValues(kv)])
    }

    private func collationSection(_ h: DB4DHeader) -> Section {
        let c = h.collation
        var kv: [(String, String)] = [("Language", languageName(h).map { "\($0) (LCID \(h.dialectCode))" } ?? "LCID \(h.dialectCode)")]
        let flags: [(String, Bool)] = [
            ("ICU collation", c.useICU),
            ("Ignore wildcard in the middle", c.ignoreWildcardInMiddle),
            ("Secondary strength for matching", c.secondaryStrengthForMatching),
            ("Quaternary strength for sorting", c.quaternaryStrengthForSorting),
            ("Hiragana first (quaternary)", c.hiraganaFirstOnQuaternaryLevel),
            ("Language-neutral deadchar algorithm", c.languageNeutralDeadchar),
            ("Traditional-style sorting", c.traditionalStyleSorting),
        ]
        kv += flags.map { ($0.0, $0.1 ? "Yes" : "No") }
        return Section("Sorting and searching", [.keyValues(kv)])
    }

    private func languageName(_ h: DB4DHeader) -> String? {
        if h.dialectCode == -4444 { return "System" }
        guard let id = h.dialectLocaleIdentifier else { return nil }
        return Locale.current.localizedString(forIdentifier: id) ?? id
    }
}
