import XCTest
@testable import FourDFileKit

final class QuickReportConversionTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "4qr",
                                                 subdirectory: "Fixtures/QuickReport"))
        return try Data(contentsOf: url)
    }

    private func rootChunks(_ definition: QuickReportDefinition) throws -> [QuickReportDefinitionChunk] {
        guard case .form(type: "REPT", chunks: let chunks) = definition.root.payload else {
            throw QuickReportError.invalid("expected FORM REPT")
        }
        return chunks
    }

    func testEveryFixtureRoundTripsByteForByteThroughJSON() throws {
        let directory = try XCTUnwrap(Bundle.module.url(forResource: "QuickReport", withExtension: nil,
                                                        subdirectory: "Fixtures"))
        let fixtures = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "4qr" }
        XCTAssertGreaterThanOrEqual(fixtures.count, 43)
        for url in fixtures {
            let original = try Data(contentsOf: url)
            let json = try QuickReportConverter.json(from: original)
            XCTAssertEqual(try QuickReportConverter.binary(from: json), original, url.lastPathComponent)
        }
    }

    func testOpaqueDataTrailingBytesFlagsAndPaddingAreLossless() throws {
        var definition = try QuickReportConverter.decode(fixture("sales"))
        var chunks = try rootChunks(definition)
        let version = try XCTUnwrap(chunks.firstIndex { $0.tag == "Vers" })
        chunks[version].trailingBytes = Data([0xDE, 0xAD, 0xBE])
        chunks[version].padding = 0x7F
        for tag in ["Frml", "PICT", "PRPS", "PRPF", "PRNT", "NEW!"] {
            chunks.append(QuickReportDefinitionChunk(tag: tag, payload: .opaque(bytes: Data([0, 0xFF, 1])),
                                                      padding: 0xA5))
        }
        chunks.append(QuickReportDefinitionChunk(tag: "FORM", payload: .form(type: "ZERO", chunks: [])))
        chunks.append(QuickReportDefinitionChunk(tag: "FORM", payload: .form(type: "TEST", chunks: [
            QuickReportDefinitionChunk(tag: "Info", payload: .opaque(bytes: Data([0xFE])), padding: 0x77)
        ])))
        definition.root.payload = .form(type: "REPT", chunks: chunks)
        let binary = try QuickReportConverter.encode(definition)
        let json = try QuickReportConverter.json(from: binary)
        XCTAssertEqual(try QuickReportConverter.binary(from: json), binary)
        let restored = try QuickReportConverter.decode(binary)
        let restoredChunks = try rootChunks(restored)
        XCTAssertEqual(restoredChunks[version].trailingBytes, Data([0xDE, 0xAD, 0xBE]))
        XCTAssertEqual(restoredChunks[version].padding, 0x7F)
        XCTAssertEqual(restoredChunks.suffix(3).first?.padding, 0xA5)
    }

    func testEditsAreWrittenAndLengthsAreRecomputed() throws {
        for name in ["sales", "sales-be", "sales-stream25", "crosstab"] {
            var definition = try QuickReportConverter.decode(fixture(name))
            var chunks = try rootChunks(definition)
            let headerIndex = try XCTUnwrap(chunks.firstIndex {
                if case .form(type: "Head", chunks: _) = $0.payload { return true }
                return false
            })
            guard case .form(let type, var headerChunks) = chunks[headerIndex].payload else { return XCTFail() }
            let stringsIndex = try XCTUnwrap(headerChunks.firstIndex { $0.tag == "Strs" })
            headerChunks[stringsIndex].payload = .bandStrings(left: "Modified 日本語 😀", center: "", right: "page #")
            chunks[headerIndex].payload = .form(type: type, chunks: headerChunks)
            definition.root.payload = .form(type: "REPT", chunks: chunks)
            let binary = try QuickReportConverter.encode(definition)
            let report = try QuickReportDecoder(data: binary).decode(fileName: "")
            XCTAssertEqual(report.header.left, "Modified 日本語 😀", name)
            XCTAssertEqual(report.header.center, "", name)
            XCTAssertEqual(report.header.right, "page #", name)
            XCTAssertEqual(report.littleEndian, definition.littleEndian, name)
            XCTAssertEqual(try QuickReportConverter.binary(from: QuickReportConverter.json(from: binary)), binary)
        }
    }

    func testInvalidDefinitionsFailExplicitly() throws {
        let original = try QuickReportConverter.decode(fixture("sales"))
        var definition = original
        definition.schemaVersion = 2
        XCTAssertThrowsError(try QuickReportConverter.encode(definition))
        definition = original
        definition.root.tag = "NOPE"
        XCTAssertThrowsError(try QuickReportConverter.encode(definition))

        for invalid in [
            QuickReportDefinitionChunk(tag: "Vers", payload: .opaque(bytes: Data())),
            QuickReportDefinitionChunk(tag: "Sort", payload: .sorts(columns: [0])),
            QuickReportDefinitionChunk(tag: "Sort", payload: .sorts(columns: [99])),
            QuickReportDefinitionChunk(tag: "Vers", payload: .version(value: 99)),
            QuickReportDefinitionChunk(tag: "StVr", payload: .version(value: 29)),
            QuickReportDefinitionChunk(tag: "Info", payload: .reportInfo(kind: 0, tableNumber: 1, rowCount: 0, flag: 1)),
            QuickReportDefinitionChunk(tag: "NEW", payload: .opaque(bytes: Data())),
            QuickReportDefinitionChunk(tag: "NEW!", payload: .opaque(bytes: Data()), trailingBytes: Data([1]))
        ] {
            definition = original
            var chunks = try rootChunks(definition)
            chunks.removeAll { $0.tag == invalid.tag }
            chunks.append(invalid)
            definition.root.payload = .form(type: "REPT", chunks: chunks)
            XCTAssertThrowsError(try QuickReportConverter.encode(definition), invalid.tag)
        }

        definition = original
        definition.root.payload = .form(type: "REPT", chunks: [])
        XCTAssertThrowsError(try QuickReportConverter.encode(definition))
        XCTAssertThrowsError(try QuickReportConverter.binary(from: Data("{}".utf8)))
        XCTAssertThrowsError(try QuickReportConverter.decode(Data([1, 2, 3])))
    }

    func testDepthAndChunkCountLimits() throws {
        var definition = try QuickReportConverter.decode(fixture("empty"))
        let original = try rootChunks(definition)
        var node = QuickReportDefinitionChunk(tag: "FORM", payload: .form(type: "TEST", chunks: []))
        for _ in 0..<9 {
            node = QuickReportDefinitionChunk(tag: "FORM", payload: .form(type: "TEST", chunks: [node]))
        }
        definition.root.payload = .form(type: "REPT", chunks: original + [node])
        XCTAssertThrowsError(try QuickReportConverter.encode(definition))
        let leaf = QuickReportDefinitionChunk(tag: "NEW!", payload: .opaque(bytes: Data()))
        definition.root.payload = .form(type: "REPT", chunks: original + Array(repeating: leaf, count: 20_000))
        XCTAssertThrowsError(try QuickReportConverter.encode(definition))
    }

    func testStringLimitCountsUTF16Bytes() throws {
        var definition = try QuickReportConverter.decode(fixture("empty"))
        var chunks = try rootChunks(definition)
        let headerIndex = try XCTUnwrap(chunks.firstIndex {
            if case .form(type: "Head", chunks: _) = $0.payload { return true }
            return false
        })
        guard case .form(let type, var headerChunks) = chunks[headerIndex].payload else { return XCTFail() }
        let stringsIndex = try XCTUnwrap(headerChunks.firstIndex { $0.tag == "Strs" })
        for count in [32_768, 32_769] {
            let text = String(repeating: "😀", count: count)
            headerChunks[stringsIndex].payload = .bandStrings(left: text, center: "", right: "")
            chunks[headerIndex].payload = .form(type: type, chunks: headerChunks)
            definition.root.payload = .form(type: "REPT", chunks: chunks)
            if count == 32_768 {
                let bytes = try QuickReportConverter.encode(definition)
                XCTAssertEqual(try QuickReportDecoder(data: bytes).decode(fileName: "").header.left, text)
            } else {
                XCTAssertThrowsError(try QuickReportConverter.encode(definition))
            }
        }
    }

    func testUnknownJSONPropertiesAreRejected() throws {
        let json = try QuickReportConverter.json(from: fixture("sales"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        object["typo"] = true
        XCTAssertThrowsError(try QuickReportConverter.binary(from: JSONSerialization.data(withJSONObject: object))) {
            XCTAssertTrue(String(describing: $0).contains("$.typo"))
        }
    }
}
