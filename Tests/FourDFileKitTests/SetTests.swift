import XCTest
@testable import FourDFileKit
@testable import FourDRender

final class SetTests: XCTestCase {
    private func fixture(_ path: String, ext: String = "4st") throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/Sets/\(path)", withExtension: ext))
    }

    private func file(_ data: Data, ext: String = "4st") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
        try data.write(to: url)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    private func analyze(_ url: URL) throws -> SetFileInfo {
        let model = try AnalyzerRegistry.default.analyze(url: url)
        return try XCTUnwrap(model as? SetFileInfo)
    }

    private func records(_ info: SetFileInfo) -> [Int] {
        info.ranges.flatMap { Array($0.first...$0.last) }
    }

    private func check(_ info: SetFileInfo, records expected: [Int], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(info.selectedRecords, expected.count, file: file, line: line)
        XCTAssertEqual(info.firstRecord, expected.first, file: file, line: line)
        XCTAssertEqual(info.lastRecord, expected.last, file: file, line: line)
        let starts = expected.enumerated().filter { $0.offset == 0 || expected[$0.offset - 1] + 1 != $0.element }
        XCTAssertEqual(info.rangeCount, starts.count, file: file, line: line)
        XCTAssertEqual(info.ranges.count, min(200, starts.count), file: file, line: line)
        for (index, range) in info.ranges.enumerated() {
            let begin = starts[index].offset
            let end = index + 1 < starts.count ? starts[index + 1].offset : expected.count
            XCTAssertEqual(range.first, expected[begin], file: file, line: line)
            XCTAssertEqual(range.last, expected[end - 1], file: file, line: line)
        }
        XCTAssertEqual(info.distribution.reduce(0) { $0 + $1.selected }, expected.count, file: file, line: line)
        XCTAssertLessThanOrEqual(info.distribution.count, 16, file: file, line: line)
        for bin in info.distribution {
            XCTAssertEqual(bin.selected, expected.filter { $0 >= bin.first && $0 <= bin.last }.count,
                           file: file, line: line)
        }
    }

    func testSuppliedSetsAgainstOriginalMaps() throws {
        for name in ["all", "random", "mixed"] {
            let info = try analyze(fixture("supplied/\(name)"))
            let map = try JSONDecoder().decode([Int?].self, from: Data(contentsOf: fixture("supplied/\(name)", ext: "json")))
            var expected = map.enumerated().compactMap { $0.element == 1 ? $0.offset - 1 : nil }
            if name == "mixed" {
                // The generator increments $i again after the For loop has already
                // advanced it: its tail is shifted by one, unlike the saved set.
                XCTAssertEqual(Set(records(info)).subtracting(expected), [155])
                XCTAssertEqual(Set(expected).subtracting(records(info)), [310])
                expected = expected.filter { $0 != 310 } + [155]
                expected.sort()
            }
            check(info, records: expected)
            XCTAssertEqual(info.addressSpan, name == "random" ? 301 : 310)
            XCTAssertEqual(info.selectedRecords, ["all": 310, "mixed": 242, "random": 74][name])
            XCTAssertEqual(info.fileSize, 4121)
            XCTAssertNil(info.savedCurrentRecord)
            XCTAssertEqual(info.bitmapPages, 1)
            XCTAssertEqual(info.byteOrder, "little-endian")
        }
    }

    func testTool4DGeneratedPageEncodingsAndSavedCurrentRecord() throws {
        let cases: [(String, [Int], Int?)] = [
            ("empty", [], nil),
            ("full", Array(0..<100000), 0),
            ("first", [0], 0),
            ("boundary", [32768], 32768),
            ("last", [99999], 99999),
            ("page", Array(0..<32768), 0),
            ("middle", Array(32768..<65536), 32768),
            ("two-pages", Array(0..<65536), 0),
            ("tail", Array(32768..<100000), 32768),
            ("ends", Array(0..<10) + Array(99989..<100000), 0),
        ]
        for (name, expected, current) in cases {
            let info = try analyze(fixture("generated/\(name)"))
            check(info, records: expected)
            XCTAssertEqual(info.savedCurrentRecord, current, name)
            XCTAssertEqual(info.addressSpan, name == "empty" ? 0 : 100000)
        }
        let full = try analyze(fixture("generated/full"))
        XCTAssertEqual(full.fullPages, 3)
        XCTAssertEqual(full.bitmapPages, 1)
        XCTAssertEqual(full.fileSize, 4124)
        let middle = try analyze(fixture("generated/middle"))
        XCTAssertEqual(middle.fullPages, 1)
        XCTAssertEqual(middle.emptyPages, 3)
        XCTAssertEqual(middle.bitmapPages, 0)
        XCTAssertEqual(middle.fileSize, 28)
    }

    private func set(span: Int, tags: [UInt8], payload: Data = Data(), current: Int32 = -1) -> Data {
        var data = Data()
        func append(_ value: UInt32, little: Bool = true) {
            for byte in 0..<4 {
                data.append(UInt8(truncatingIfNeeded: value >> ((little ? byte : 3 - byte) * 8)))
            }
        }
        append(UInt32(bitPattern: current), little: false)
        append(0)
        data.append(contentsOf: "70D4".utf8)
        append(1)
        append(UInt32(span))
        append(UInt32(tags.count))
        data.append(contentsOf: tags)
        data.append(payload)
        return data
    }

    func testRandomizedBitmapsRangesAndHistogramBoundaries() throws {
        var state: UInt32 = 0x12345678
        for span in [1, 7, 31, 32, 33, 155, 310, 32767, 32768, 32769, 65581] {
            var bitmap = Data(repeating: 0, count: ((span + 32767) / 32768) * 4096)
            var expected: [Int] = []
            for index in 0..<span {
                state = state &* 1664525 &+ 1013904223
                if state & 0x80000000 != 0 {
                    bitmap[index / 8] |= 1 << (index % 8)
                    expected.append(index)
                }
            }
            let data = set(span: span, tags: Array(repeating: 7, count: (span + 32767) / 32768), payload: bitmap)
            check(try analyze(file(data)), records: expected)
        }
    }

    func testRangesMergeAcrossWordsAndCompressedPageBoundaries() throws {
        var payload = Data(repeating: 0xFF, count: 8192)
        payload[0] = 0xFE
        payload[8191] = 0x7F
        let info = try analyze(file(set(span: 5 * 32768, tags: [0, 7, 1, 7, 0], payload: payload)))
        check(info, records: Array(32769..<131071))
        XCTAssertEqual(info.ranges, [SetRecordRange(first: 32769, last: 131070)])
    }

    func testPaddingBitsAreNotRecordsAndEmptySpanNeedsNoPages() throws {
        let info = try analyze(file(set(span: 35, tags: [7], payload: Data(repeating: 0xFF, count: 4096))))
        check(info, records: Array(0..<35))
        let empty = try analyze(file(set(span: 0, tags: [])))
        check(empty, records: [])
        XCTAssertTrue(empty.distribution.isEmpty)
        let addressedEmpty = try analyze(file(set(span: 35, tags: [0])))
        check(addressedEmpty, records: [])
        XCTAssertEqual(addressedEmpty.addressSpan, 35)
    }

    func testHugeCompressedSetDoesNotExpandIntoIndividualRecords() throws {
        let info = try analyze(file(set(span: Int(Int32.max), tags: Array(repeating: 1, count: 65536))))
        XCTAssertEqual(info.selectedRecords, Int(Int32.max))
        XCTAssertEqual(info.ranges, [SetRecordRange(first: 0, last: Int(Int32.max) - 1)])
        XCTAssertEqual(info.rangeCount, 1)
        XCTAssertEqual(info.distribution.count, 16)
        XCTAssertEqual(info.distribution.reduce(0) { $0 + $1.selected }, Int(Int32.max))
        XCTAssertEqual(info.fileSize, 24 + 65536)
    }

    func testRangeLimitRetainsExactTotalsAndLastRecord() throws {
        var bitmap = Data(repeating: 0x55, count: 4096)
        bitmap[60...100] = Data(repeating: 0xFF, count: 41)[...]
        let expected = (0..<32768).filter { bitmap[$0 / 8] & (1 << ($0 % 8)) != 0 }
        let url = try file(set(span: 32768, tags: [7], payload: bitmap))
        let info = try analyze(url)
        check(info, records: expected)
        XCTAssertEqual(info.ranges.count, 200)
        XCTAssertTrue(PreviewPipeline().html(for: url).contains("Showing the first 200"))
        let thorough = try XCTUnwrap(try AnalyzerRegistry.default.analyze(url: url, options: .thorough) as? SetFileInfo)
        XCTAssertEqual(thorough.ranges, info.ranges)
        XCTAssertEqual(thorough.selectedRecords, info.selectedRecords)
    }

    func testLastVisibleRangeContinuesAcrossBitmapAndFullPages() throws {
        var bitmap = Data(repeating: 0xFF, count: 4096)
        for index in 0..<49 { bitmap[index] = 0x55 }
        bitmap[49] = 0x15
        var tail = Data(repeating: 0, count: 4096)
        for index in 0..<16 { tail[index] = 0xFF }
        tail[(90000 - 65536) / 8] |= 1 << (90000 % 8)
        let expected = Array(stride(from: 0, through: 396, by: 2)) + Array(400..<65664) + [90000]
        let info = try analyze(file(set(span: 98304, tags: [7, 1, 7], payload: bitmap + tail)))
        check(info, records: expected)
        XCTAssertEqual(info.rangeCount, 201)
        XCTAssertEqual(info.ranges.last, SetRecordRange(first: 400, last: 65663))
        XCTAssertEqual(info.lastRecord, 90000)
    }

    func testRoutingJSONAndPreview() throws {
        let url = try file(Data(contentsOf: fixture("generated/ends")), ext: "4ST")
        let info = try analyze(url)
        XCTAssertEqual(info.kind, "4d.set")
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: info.jsonData()) as? [String: Any])
        XCTAssertEqual(json["selectedRecords"] as? Int, 21)
        XCTAssertEqual((json["ranges"] as? [[String: Int]])?.count, 2)
        let untagged = try file(Data(contentsOf: url), ext: "bin")
        XCTAssertTrue(try AnalyzerRegistry.default.analyze(url: untagged, contentType: "com.4d.4d.setFile") is SetFileInfo)
        XCTAssertTrue(AnalyzerRegistry.default.allContentTypes.contains("com.4d.4d.setFile"))
        let html = PreviewPipeline().html(for: url)
        for text in ["4D Saved Set", "Records in set", "Address span", "Record ranges", "zero-based",
                     "not the table", "Saved current record", "Bitmap pages", "99,989", "99,999"] {
            XCTAssertTrue(html.contains(text), text)
        }
        XCTAssertFalse(html.contains("No preview available"))
        let emptyHTML = PreviewPipeline().html(for: try fixture("generated/empty"))
        XCTAssertTrue(emptyHTML.contains("This set is empty"))
        XCTAssertFalse(emptyHTML.contains("nan"))
    }

    func testUnsupportedEncodingsAndMalformedFilesAreExplicit() throws {
        let valid = set(span: 1, tags: [7], payload: Data(repeating: 0, count: 4096))
        var bad: [Data] = (0..<24).map { Data(valid.prefix($0)) }
        bad += [set(span: 32769, tags: [0]), set(span: 0, tags: [0]),
                set(span: 1, tags: [0], payload: Data([0])),
                set(span: 1, tags: [7]), set(span: 1, tags: [2]),
                Data(valid.dropLast()), valid + Data([0])]
        bad.append(set(span: Int(Int32.max) + 1, tags: [0]))
        for offset in [8, 12, 20] {
            var data = valid
            data[offset] = 0xFE
            bad.append(data)
        }
        var big = valid
        big.replaceSubrange(8..<12, with: Data("4D07".utf8))
        bad.append(big)
        for data in bad {
            let url = try file(data)
            XCTAssertThrowsError(try analyze(url))
            XCTAssertTrue(PreviewPipeline().html(for: url).contains("No preview available"))
        }
        XCTAssertTrue(PreviewPipeline().html(for: try file(big)).contains("Big-endian saved sets are not yet decoded"))
        let unknownPage = try file(set(span: 1, tags: [3]))
        XCTAssertTrue(PreviewPipeline().html(for: unknownPage).contains("page encoding 3 is not supported"))
        let large = try file(Data(repeating: 0, count: 4 * 1024 * 1024 + 1))
        XCTAssertThrowsError(try analyze(large)) {
            XCTAssertEqual(String(describing: $0), SetFileError.tooLarge.description)
        }
    }
}
