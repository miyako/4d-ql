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
        r.sections = [Section("s", [.keyValues([("k", "\"v\"")])])]
        let html = HTMLRenderer().render(r)
        XCTAssertFalse(html.contains("<script>&"))
        XCTAssertTrue(html.contains("&lt;script&gt;&amp;"))
        XCTAssertTrue(html.contains("&quot;v&quot;"))
    }

    /// Runs every *.4DD / *.4DB in $FOURD_SAMPLES through the full pipeline.
    func testSampleFiles() throws {
        guard let dir = ProcessInfo.processInfo.environment["FOURD_SAMPLES"] else {
            throw XCTSkip("set FOURD_SAMPLES to a folder of sample files")
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: dir)
            .filter { ["4dd", "4db"].contains(($0 as NSString).pathExtension.lowercased()) }
        for f in files {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(f)
            _ = PreviewPipeline().html(for: url) // must not crash
        }
    }
}
