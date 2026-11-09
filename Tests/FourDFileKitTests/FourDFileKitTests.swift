import XCTest
@testable import FourDFileKit
@testable import FourDRender

final class FourDFileKitTests: XCTestCase {

    /// A minimal, empty but valid DB4D header.
    private func syntheticFile(lastOperation: Int32 = 0, dialect: Int32 = 1041) throws -> URL {
        var d = Data(count: 512)
        func put32(_ v: Int32, _ o: Int) { withUnsafeBytes(of: v.littleEndian) { d.replaceSubrange(o..<o + 4, with: $0) } }
        func put16(_ v: Int16, _ o: Int) { withUnsafeBytes(of: v.littleEndian) { d.replaceSubrange(o..<o + 2, with: $0) } }
        d.replaceSubrange(0..<4, with: [0x02, 0x44, 0x01, 0x44])
        put32(lastOperation, 0x04)
        put16(1, 0x0C)                 // one segment
        put32(2, 0x10); put32(3, 0x14) // version 3.2
        put32(512, 0x28)               // logical EOF
        put32(128, 0x40); put32(7, 0x44)
        put32(dialect, 0xF8)
        d[0xFC] = 0x01                 // ICU
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".4DD")
        try d.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testHeader() throws {
        let model = try AnalyzerRegistry.default.analyze(url: try syntheticFile())
        let info = try XCTUnwrap(model as? DB4DFileInfo)
        XCTAssertEqual(info.kind, "db4d.data")
        XCTAssertEqual(info.header.formatVersion, "3.2")
        XCTAssertEqual(info.header.blockSize, 128)
        XCTAssertTrue(info.header.flushedCleanly)
        XCTAssertTrue(info.header.collation.useICU)
        XCTAssertEqual(info.header.dialectLocaleIdentifier, "ja_JP")
        XCTAssertTrue(info.tables.isEmpty)
    }

    func testInterruptedFlushIsReported() throws {
        let report = PreviewPipeline().report(for: try syntheticFile(lastOperation: -1))
        XCTAssertTrue(report.badges.contains { $0.tone == .danger })
    }

    func testGarbageIsRejectedNotCrashing() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".4DD")
        var bytes: [UInt8] = [0x02, 0x44, 0x01, 0x44]
        bytes += (0..<400).map { _ in UInt8.random(in: 0...255) }
        try Data(bytes).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let html = PreviewPipeline().html(for: url)
        XCTAssertTrue(html.contains("No preview available"))
    }

    func testHTMLEscaping() {
        var r = Report(title: "<script>&")
        r.sections = [Section("s", [.keyValues([KeyValue("k", "\"v\"")])])]
        let html = HTMLRenderer().render(r)
        XCTAssertFalse(html.contains("<script>&"))
        XCTAssertTrue(html.contains("&lt;script&gt;&amp;"))
        XCTAssertTrue(html.contains("&quot;v&quot;"))
    }

    /// Runs every supported file in $FOURD_SAMPLES through the full pipeline.
    func testSampleFiles() throws {
        guard let dir = ProcessInfo.processInfo.environment["FOURD_SAMPLES"] else {
            throw XCTSkip("set FOURD_SAMPLES to a folder of sample files")
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: dir)
            .filter { ["4dd", "4db", "4dcatalog"].contains(($0 as NSString).pathExtension.lowercased()) }
        for f in files {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(f)
            _ = PreviewPipeline().html(for: url) // must not crash
        }
    }

    // MARK: Encryption (fixtures from scripts/make-fixtures.sh)

    private func fixture(_ name: String) throws -> DB4DFileInfo {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "4DD"))
        return try XCTUnwrap(try AnalyzerRegistry.default.analyze(url: url) as? DB4DFileInfo)
    }

    private func table(_ info: DB4DFileInfo, _ name: String) throws -> TableInfo {
        try XCTUnwrap(info.tables.first { $0.name == name })
    }

    func testEncryptedDataFile() throws {
        let info = try fixture("encrypted")
        XCTAssertTrue(info.encryption.isEncrypted)
        XCTAssertNotNil(info.encryption.keyCheckValue)
        XCTAssertEqual(info.encryption.encryptedTables, 1)
        XCTAssertEqual(info.encryption.encryptableTables, 2)

        // Catalog and counts stay readable in an encrypted file.
        let secret = try table(info, "Secret")
        XCTAssertEqual(secret.encrypted, true)
        XCTAssertTrue(secret.encryptable)
        XCTAssertEqual(secret.recordCount, 5)
        XCTAssertEqual(secret.fields.map(\.name), ["ID", "name", "note", "payload"])

        let plain = try table(info, "Plain")
        XCTAssertEqual(plain.encrypted, false)
        XCTAssertFalse(plain.encryptable)

        let empty = try table(info, "EmptySecret")
        XCTAssertTrue(empty.encryptable)
        XCTAssertNil(empty.encrypted, "no records: encryption state cannot be read")

        let report = DB4DPresenter().report(for: info)!
        XCTAssertTrue(report.badges.contains { $0.text.contains("Encrypted") })
        XCTAssertTrue(report.sections.contains { $0.title == "Encryption" })
        XCTAssertFalse(keyValues(report).contains { $0.key.contains("encryptedProof") || $0.key.contains("Encrypted proof") },
                       "internal key check value is not shown")
    }

    // MARK: Presentation rules

    private func keyValues(_ r: Report) -> [KeyValue] {
        r.sections.flatMap(\.blocks).flatMap { b -> [KeyValue] in
            if case .keyValues(let kv) = b { return kv }
            return []
        }
    }

    private func barRows(_ r: Report, section: String) -> [BarRow] {
        r.sections.first { $0.title == section }?.blocks.compactMap { b -> [BarRow]? in
            if case .bars(let rows, _, _) = b { return rows }
            return nil
        }.first ?? []
    }

    func testJournalPath() throws {
        let info = try fixture("journaled")
        let j = try XCTUnwrap(info.journal)
        XCTAssertTrue(j.pending)
        XCTAssertTrue(j.path?.hasSuffix("/fixture.journal") ?? false)
        XCTAssertTrue(j.path?.hasPrefix("/") ?? false, "converted from 4D's colon path")
        let kv = keyValues(DB4DPresenter().report(for: info)!)
        XCTAssertTrue(kv.contains { $0.key == "Next journal" && $0.mono })
        XCTAssertNil(try fixture("plain").journal)
    }

    func testPosixPathFromHFS() {
        #if os(macOS)
        let boot = (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? "Macintosh HD"
        XCTAssertEqual(DB4DAnalysis.posixPath(fromHFS: "\(boot):Users:me:a.journal"), "/Users/me/a.journal")
        #endif
        XCTAssertEqual(DB4DAnalysis.posixPath(fromHFS: "Backup:j:a.journal"), "/Volumes/Backup/j/a.journal")
        XCTAssertEqual(DB4DAnalysis.posixPath(fromHFS: "C:\\data\\a.journal"), "C:\\data\\a.journal")
    }

    func testEngineNames() {
        XCTAssertEqual(DB4DPresenter.engineName("icu:77.1.0"), "ICU 77.1.0")
        XCTAssertEqual(DB4DPresenter.engineName("icu:68.1.0, alternate=search"), "ICU 68.1.0 (alternate=search)")
        XCTAssertEqual(DB4DPresenter.engineName("mecab:0.996;sys.dic:102;"), "MeCab 0.996 · sys.dic 102")
        XCTAssertEqual(DB4DPresenter.engineName("AlphaNum"), "AlphaNum")
        XCTAssertEqual(DB4DPresenter.humanize("data_file_path"), "Data file path")
    }

    func testManyTablesFoldIntoOther() throws {
        var info = try fixture("plain")
        let template = info.tables[0]
        info.tables = (1...300).map { n in
            var t = template
            t.number = n; t.name = "T\(n)"; t.recordCount = n
            return t
        }
        let rows = barRows(DB4DPresenter().report(for: info)!, section: "Tables")
        XCTAssertEqual(rows.count, DB4DPresenter.maxTableBars + 1)
        XCTAssertEqual(rows.first?.label, "T300", "largest table first")
        XCTAssertTrue(rows.last?.muted ?? false)
        XCTAssertEqual(rows.last?.label, "292 other tables")
    }

    func testJapaneseOptionsOnlyWithoutICU() throws {
        var info = try fixture("plain")
        func hasJapaneseOptions(_ locale: String, collation: UInt8) -> Bool {
            info.header.dialectLocaleIdentifier = locale
            info.header.collation = CollationOptions(collation)
            return keyValues(DB4DPresenter().report(for: info)!).contains { $0.key == "Hiragana first" }
        }
        XCTAssertTrue(hasJapaneseOptions("ja_JP", collation: 0x00))
        XCTAssertFalse(hasJapaneseOptions("ja_JP", collation: 0x01), "ICU on")
        XCTAssertFalse(hasJapaneseOptions("fr_FR", collation: 0x00), "not Japanese")
        XCTAssertFalse(keyValues(DB4DPresenter().report(for: info)!).contains { $0.key.contains("LCID") || $0.value.contains("LCID") })
    }

    func testEncryptableButNotEncrypted() throws {
        let info = try fixture("plain")
        XCTAssertFalse(info.encryption.isEncrypted)
        XCTAssertEqual(info.encryption.encryptableTables, 2)
        XCTAssertEqual(try table(info, "Secret").encrypted, false)
        let report = DB4DPresenter().report(for: info)!
        XCTAssertFalse(report.badges.contains { $0.text.contains("Encrypted") })
        XCTAssertTrue(report.sections.contains { $0.title == "Encryption" })
    }

    func testFieldTypeIconsPreserveFamiliesAndCounts() throws {
        let expected: [(FieldKind, FieldTypeIcon)] = [
            (.boolean, .boolean), (.byte, .integer), (.integer, .integer),
            (.longint, .integer), (.integer64, .integer), (.real, .real), (.float, .real),
            (.date, .date), (.time, .time), (.text, .text), (.legacyBlob, .blob),
            (.picture, .picture), (.uuid, .uuid), (.legacyText, .text),
            (.unlimitedText, .text), (.blob, .blob), (.object, .object),
        ]
        for (kind, icon) in expected {
            XCTAssertEqual(DB4DPresenter.icon(for: kind), icon, "\(kind)")
        }
        let block = DB4DPresenter.fieldTypes(expected.map { Optional($0.0) } + [nil])
        guard case .composition(let segments) = block else { return XCTFail("Expected composition") }
        XCTAssertEqual(segments.map(\.label),
                       ["Text", "Integer", "Real", "Date & time", "Boolean", "Picture", "BLOB", "Object", "Other"])
        XCTAssertEqual(segments.map(\.value), [4, 4, 2, 2, 1, 1, 2, 1, 1])
        XCTAssertEqual(segments.map(\.display), ["4", "4", "2", "2", "1", "1", "2", "1", "1"])
        XCTAssertEqual(segments.map(\.slot), [1, 2, 3, 4, 5, 6, 7, 8, nil])
        XCTAssertEqual(segments.map(\.icons),
                       [[.text, .uuid], [.integer], [.real], [.date], [.boolean],
                        [.picture], [.blob], [.object], [.unknown]])
    }

    func testGroupedIconsOnlyShowTypesPresent() {
        for (kind, icon) in [(FieldKind.uuid, FieldTypeIcon.uuid), (.text, .text), (.date, .date), (.time, .date)] {
            guard case .composition(let segments) = DB4DPresenter.fieldTypes([kind, kind]) else {
                return XCTFail("Expected composition")
            }
            XCTAssertEqual(segments.filter { $0.value > 0 }.map(\.icons), [[icon]])
            XCTAssertEqual(segments.reduce(0) { $0 + $1.value }, 2)
        }
        var report = Report(title: "Empty")
        report.sections = [Section("Field types", [DB4DPresenter.fieldTypes([])])]
        XCTAssertFalse(HTMLRenderer().render(report).contains("<div class=\"comp\">"))
    }

    func testDataAndStructureChartsUseCatalogIconsAndColors() throws {
        var info = try fixture("plain")
        var template = try XCTUnwrap(info.tables.first)
        let field = try XCTUnwrap(template.fields.first)
        template.fields = ((1...21).compactMap(FieldKind.init(rawValue:)).map(\.rawValue) + [999]).map { code in
            var field = field
            field.typeCode = code
            return field
        }
        info.tables = [template]
        for role in [DB4DFileInfo.Role.data, .structure] {
            info.role = role
            let report = try XCTUnwrap(DB4DPresenter().report(for: info))
            XCTAssertEqual(report.sections.first?.title, "Tables")
            XCTAssertEqual(barRows(report, section: "Tables").count, 1)
            let html = HTMLRenderer().render(report)
            for icon in FieldTypeIcon.allCases where icon != .time {
                XCTAssertTrue(html.contains(FieldTypeIconRenderer.render(icon)), "\(role): \(icon)")
            }
            XCTAssertFalse(html.contains(FieldTypeIconRenderer.render(.time)))
            XCTAssertTrue(html.contains("Date &amp; time"))
            XCTAssertTrue(html.contains(".type-icon-text,.type-icon-uuid{color:var(--s1)}"))
            XCTAssertTrue(html.contains(".type-icon-integer{color:var(--s2)}"))
            XCTAssertTrue(html.contains(".type-icon-real{color:var(--s3)}"))
            XCTAssertTrue(html.contains(".type-icon-date,.type-icon-time{color:var(--s4)}"))
            XCTAssertTrue(html.contains(".type-icon-boolean{color:var(--s5)}"))
            XCTAssertTrue(html.contains(".type-icon-picture{color:var(--s6)}"))
            XCTAssertTrue(html.contains(".type-icon-blob{color:var(--s7)}"))
            XCTAssertTrue(html.contains(".type-icon-object{color:var(--s8)}"))
            XCTAssertTrue(html.contains(".type-icon-unknown{color:var(--muted)}"))
            XCTAssertTrue(html.contains("prefers-color-scheme:dark"))
            XCTAssertFalse(html.contains("<script"))
        }
    }

    func testCompositionWithoutIconsKeepsSwatchesAndEscapesLabels() {
        var report = Report(title: "Chart")
        report.sections = [Section("Field types", [.composition([
            Segment(label: "<Text>&", value: 1, display: "\"1\"", slot: 1),
            Segment(label: "<Other>", value: 1, display: "1", slot: nil, icons: [.unknown]),
        ])])]
        let html = HTMLRenderer().render(report)
        XCTAssertTrue(html.contains("<span class=\"sw s1\"></span>&lt;Text&gt;&amp;"))
        XCTAssertTrue(html.contains("&quot;1&quot;"))
        XCTAssertTrue(html.contains("aria-hidden=\"true\" focusable=\"false\""))
        XCTAssertTrue(html.contains("</svg>&lt;Other&gt;"))
        XCTAssertFalse(html.contains("<Other>"))
    }
}

final class StructurePreviewTests: XCTestCase {
    /// A .4DB preview leads with tables and fields; relations appear only as a
    /// count, resources not at all, and the preview skips the resource scan.
    func testStructureFocusesOnTablesAndFields() throws {
        guard let dir = ProcessInfo.processInfo.environment["FOURD_SAMPLES"] else {
            throw XCTSkip("set FOURD_SAMPLES to a folder of sample files")
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.lowercased().hasSuffix(".4db") }
        guard !files.isEmpty else { throw XCTSkip("no .4DB in FOURD_SAMPLES") }
        for f in files {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(f)
            // The sample folder may hold deliberately corrupt files; skip them.
            guard let info = (try? AnalyzerRegistry.default.analyze(url: url)) as? DB4DFileInfo else { continue }
            XCTAssertNil(info.resources, "preview skips the resource scan")
            let report = DB4DPresenter().report(for: info)!
            let titles = report.sections.map(\.title)
            XCTAssertEqual(titles.first, "Tables")
            XCTAssertFalse(titles.contains("Relations"))
            XCTAssertFalse(titles.contains("Resources"))
            XCTAssertFalse(report.stats.contains { $0.label == "Resources" })
            XCTAssertTrue(report.stats.contains { $0.label == "Relations" })

            let thorough = try XCTUnwrap(try AnalyzerRegistry.default.analyze(url: url, options: .thorough) as? DB4DFileInfo)
            XCTAssertNotNil(thorough.resources, "still available for --json --thorough")
        }
    }
}
