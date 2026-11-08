import Foundation

/// Builds a `DB4DFileInfo` from a container. Shared by the .4DD and .4DB analyzers,
/// which differ only in role and in which optional passes they run.
enum DB4DAnalysis {
    static func run(_ source: ByteSource, role: DB4DFileInfo.Role, options: AnalysisOptions) throws -> DB4DFileInfo {
        let raw = try RawHeader(source: source)
        let c = DB4DContainer(source: source, littleEndian: raw.header.littleEndian)
        var warnings: [String] = []

        func attempt<T>(_ what: String, _ fallback: T, _ body: () throws -> T) -> T {
            do { return try body() } catch { warnings.append("\(what): \(error)"); return fallback }
        }

        // Table definitions. A data file keeps every version of a table's
        // definition it has seen; the last one written is the current one.
        let defs = attempt("table definitions", []) { try c.tableDefinitions(at: raw.tableDefinitionsAddress) }
        var latest: [String: TableDefinition] = [:]
        var versions: [String: Int] = [:]
        for d in defs {
            latest[d.uuid] = d
            versions[d.uuid, default: 0] += 1
        }

        let storage = attempt("data tables", []) { try c.dataTables(at: raw.dataTablesAddress) }

        var tables: [TableInfo] = []
        var resourceTable: DataTable?
        switch role {
        case .data:
            for t in storage.sorted(by: { $0.number < $1.number }) {
                let def = latest[t.uuid]
                let encrypted: Bool? = t.firstRecordTag.map { $0 == DataBlockTag.encryptedRecord }
                tables.append(TableInfo(
                    number: t.number, name: def?.name ?? "Table \(t.number)", uuid: t.uuid,
                    fields: def?.fields ?? [], recordCount: t.recordCount, blobCount: t.blobCount,
                    lastModified: t.timestamp.isValid ? t.timestamp : nil,
                    historicalDefinitions: max(0, (versions[t.uuid] ?? 1) - 1),
                    encryptable: def?.encryptable ?? false, encrypted: encrypted))
            }
        case .structure:
            // User tables are defined here but stored in the data file. The
            // container's own storage holds 4D's system tables (resources, schema),
            // whose UUID fields are ASCII names such as "Res_DB4D_000000".
            var seen = Set<String>()
            for d in defs.reversed() where seen.insert(d.uuid).inserted {
                tables.append(TableInfo(number: d.index + 1, name: d.name, uuid: d.uuid, fields: d.fields,
                                        recordCount: nil, blobCount: nil, lastModified: nil,
                                        historicalDefinitions: max(0, (versions[d.uuid] ?? 1) - 1),
                                        encryptable: d.encryptable, encrypted: nil))
            }
            tables.sort { $0.number < $1.number }
            resourceTable = storage.first { $0.uuid.hasPrefix("5265735F") } // "Res_"
        }

        var fieldNames: [String: String] = [:]
        for t in latest.values { for f in t.fields { fieldNames[f.uuid] = "[\(t.name)]\(f.name)" } }
        let relations = attempt("relations", []) { try c.relations(at: raw.relationsAddress, fieldNames: fieldNames) }

        let extras: [ExtraProperty] = attempt("extra properties", []) {
            guard c.isValidAddress(raw.extraAddress), raw.extraLength > 0, raw.extraLength < 1 << 24 else { return [] }
            let d = try source.readAvailable(at: raw.extraAddress + Int64(BlockHeader.size), length: raw.extraLength)
            return ValueBag.decode(d, littleEndian: c.littleEndian)
        }

        let resources: ResourceSummary? = attempt("resources", nil) {
            guard options.scanResources, let t = resourceTable else { return nil }
            return try c.resourceSummary(of: t, options: options)
        }

        let lastModified = storage.map(\.timestamp).filter(\.isValid).max()

        let encryption = EncryptionInfo(
            keyCheckValue: extras.first { $0.key == "encryptedProofB64" }?.value,
            encryptedTables: tables.filter { $0.encrypted == true }.count,
            encryptableTables: tables.filter(\.encryptable).count)

        return DB4DFileInfo(
            role: role, fileName: source.url.lastPathComponent, fileSize: source.size,
            header: raw.header, tables: tables, relations: relations, extraProperties: extras,
            resources: resources, encryption: encryption, journal: journal(from: extras),
            lastModified: lastModified, warnings: c.warnings + warnings)
    }

    /// Journal settings live in the extra properties under "journal_file.".
    /// Seen so far: "journal_file_enabled" (bool) and "next_filepath" (the
    /// journal that starts after the next backup). Any other key ending in
    /// "path" is taken as the journal currently in use.
    static func journal(from extras: [ExtraProperty]) -> JournalInfo? {
        let props = extras.filter { $0.key.hasPrefix("journal_file.") }
        guard !props.isEmpty else { return nil }
        var info = JournalInfo(enabled: nil, path: nil, pending: false)
        for p in props {
            let key = String(p.key.dropFirst("journal_file.".count)).lowercased()
            if key.hasSuffix("enabled") {
                info.enabled = p.value == "true"
            } else if key.hasPrefix("next"), key.hasSuffix("path"), info.path == nil {
                info.path = posixPath(fromHFS: p.value)
                info.pending = true
            } else if key.hasSuffix("path") {
                info.path = posixPath(fromHFS: p.value)
                info.pending = false
            }
        }
        // Other keys (e.g. "sequence_number") say nothing about the journal itself.
        return (info.enabled == nil && info.path == nil) ? nil : info
    }

    /// "Macintosh HD:Users:me:x.journal" -> "/Users/me/x.journal". Paths on other
    /// volumes map to /Volumes/<name>/…; anything else (Windows paths) is kept.
    static func posixPath(fromHFS hfs: String) -> String {
        guard hfs.contains(":"), !hfs.hasPrefix("/"), !hfs.contains("\\"),
              let colon = hfs.firstIndex(of: ":"), colon != hfs.startIndex else { return hfs }
        let volume = String(hfs[..<colon])
        let rest = hfs[hfs.index(after: colon)...].split(separator: ":", omittingEmptySubsequences: false)
            .map { $0.replacingOccurrences(of: "/", with: ":") }.joined(separator: "/")
        let bootVolume = (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]))?.volumeName
        return (volume == bootVolume ? "/" : "/Volumes/\(volume)/") + rest
    }
}

/// .4DD / .data — 4D data file.
public struct DataFileAnalyzer: FileAnalyzer {
    public init() {}
    public var identifier: String { "4dd" }
    public var contentTypes: [String] { ["com.4d.4d.data-file"] }
    public var filenameExtensions: [String] { ["4dd", "data"] }
    public func canAnalyze(_ source: ByteSource) -> Bool { DB4DSignature.byteOrder(of: source) != nil || DB4DSignature.isLegacy(source) }
    public func analyze(_ source: ByteSource, options: AnalysisOptions) throws -> AnalysisModel {
        try DB4DAnalysis.run(source, role: .data, options: options)
    }
}

/// .4DB — binary (interpreted) structure file, used before project mode.
public struct StructureFileAnalyzer: FileAnalyzer {
    public init() {}
    public var identifier: String { "4db" }
    public var contentTypes: [String] { ["com.4d.4d.interpreted-structure-file"] }
    public var filenameExtensions: [String] { ["4db"] }
    public func canAnalyze(_ source: ByteSource) -> Bool { DB4DSignature.byteOrder(of: source) != nil || DB4DSignature.isLegacy(source) }
    public func analyze(_ source: ByteSource, options: AnalysisOptions) throws -> AnalysisModel {
        try DB4DAnalysis.run(source, role: .structure, options: options)
    }
}
