import Foundation

public struct SetRecordRange: Codable, Equatable {
    public let first: Int
    public var last: Int
}

public struct SetDistributionBin: Codable, Equatable {
    public let first: Int
    public let last: Int
    public var selected: Int
}

public struct SetFileInfo: AnalysisModel {
    public let kind = "4d.set"
    public let fileName: String
    public let fileSize: Int
    public let byteOrder: String
    public let savedCurrentRecord: Int?
    /// Address span, not the table's live record count or the set's cardinality.
    public let addressSpan: Int
    public let selectedRecords: Int
    public let firstRecord: Int?
    public let lastRecord: Int?
    public let emptyPages: Int
    public let fullPages: Int
    public let bitmapPages: Int
    public let rangeCount: Int
    /// The first 200 contiguous ranges; counts and distribution cover the whole set.
    public let ranges: [SetRecordRange]
    public let distribution: [SetDistributionBin]
}

public enum SetFileError: Error, CustomStringConvertible {
    case tooLarge, invalid(String), unsupportedByteOrder, unsupportedMarker(UInt32), unsupportedPage(UInt8)

    public var description: String {
        switch self {
        case .tooLarge: return "Saved set exceeds the 4 MiB preview limit."
        case .invalid(let reason): return "Invalid saved set: \(reason)"
        case .unsupportedByteOrder: return "Big-endian saved sets are not yet decoded; a verified historical sample is required."
        case .unsupportedMarker(let marker): return "Saved set serialization marker \(marker) is not supported."
        case .unsupportedPage(let tag): return "Saved set page encoding \(tag) is not supported."
        }
    }
}

public struct SetFileAnalyzer: FileAnalyzer {
    public init() {}
    public var identifier: String { "4st" }
    public var contentTypes: [String] { ["com.4d.4d.setFile"] }
    public var filenameExtensions: [String] { ["4st"] }

    public func analyze(_ source: ByteSource, options: AnalysisOptions) throws -> AnalysisModel {
        guard source.size <= 4 * 1024 * 1024 else { throw SetFileError.tooLarge }
        guard source.size >= 24 else { throw SetFileError.invalid("the 24-byte header is truncated.") }
        var reader = BinaryReader(try source.read(at: 0, length: Int(source.size)), littleEndian: false)
        let current = try reader.i32()
        try reader.skip(4) // Unidentified outer-header field; not a table identifier.
        let signature = try reader.bytes(4)
        if signature == Data("4D07".utf8) { throw SetFileError.unsupportedByteOrder }
        guard signature == Data("70D4".utf8) else { throw SetFileError.invalid("unrecognized payload signature.") }
        reader.littleEndian = true
        let marker = try reader.u32()
        guard marker == 1 else { throw SetFileError.unsupportedMarker(marker) }
        let span = Int(try reader.u32())
        let pageCount = Int(try reader.u32())
        guard span <= Int32.max, pageCount == (span + 32767) / 32768 else {
            throw SetFileError.invalid("address span and page count do not agree.")
        }
        guard pageCount <= reader.remaining else { throw SetFileError.invalid("the page directory is truncated.") }
        let tags = try reader.bytes(pageCount)
        var emptyPages = 0, fullPages = 0, bitmapPages = 0
        for tag in tags {
            switch tag {
            case 0: emptyPages += 1
            case 1: fullPages += 1
            case 7: bitmapPages += 1
            default: throw SetFileError.unsupportedPage(tag)
            }
        }
        guard reader.remaining == bitmapPages * 4096 else {
            throw SetFileError.invalid("bitmap payload length does not match the page directory.")
        }

        var summary = SetSummary(span: span)
        for (page, tag) in tags.enumerated() {
            let first = page * 32768
            let length = min(32768, span - first)
            switch tag {
            case 0:
                summary.previousSelected = false
            case 1:
                summary.addFull(first: first, length: length)
            default:
                // Bitmap words, like the payload header, are little-endian.
                // Padding outside the address span is not a record.
                for wordIndex in 0..<1024 {
                    let word = try reader.u32()
                    let start = first + wordIndex * 32
                    if start < span {
                        summary.addWord(word, first: start, length: min(32, span - start))
                    }
                }
            }
        }
        return SetFileInfo(fileName: source.url.lastPathComponent, fileSize: Int(source.size),
                           byteOrder: "little-endian", savedCurrentRecord: current >= 0 ? Int(current) : nil,
                           addressSpan: span, selectedRecords: summary.selected,
                           firstRecord: summary.first, lastRecord: summary.last,
                           emptyPages: emptyPages, fullPages: fullPages, bitmapPages: bitmapPages,
                           rangeCount: summary.rangeCount, ranges: summary.ranges,
                           distribution: summary.bins)
    }
}

private struct SetSummary {
    var selected = 0
    var first: Int?
    var last: Int?
    var rangeCount = 0
    var ranges: [SetRecordRange] = []
    var previousSelected = false
    var bins: [SetDistributionBin]
    let binWidth: Int

    init(span: Int) {
        let width = max(1, (span + 15) / 16)
        binWidth = width
        bins = stride(from: 0, to: span, by: width).map {
            SetDistributionBin(first: $0, last: min(span, $0 + width) - 1, selected: 0)
        }
    }

    mutating func addFull(first: Int, length: Int) {
        if !previousSelected { rangeCount += 1 }
        previousSelected = true
        selected += length
        if self.first == nil { self.first = first }
        last = first + length - 1
        recordRange(first, first + length - 1)
        var start = first
        let end = first + length
        while start < end {
            let bin = start / binWidth
            let next = min(end, bins[bin].last + 1)
            bins[bin].selected += next - start
            start = next
        }
    }

    mutating func addWord(_ raw: UInt32, first: Int, length: Int) {
        let mask = (UInt64(1) << length) - 1
        let word = UInt64(raw) & mask
        let starts = word & ~((word << 1) | (previousSelected ? 1 : 0))
        rangeCount += starts.nonzeroBitCount
        previousSelected = word & (UInt64(1) << (length - 1)) != 0
        selected += word.nonzeroBitCount
        if word == 0 { return }

        if self.first == nil { self.first = first + word.trailingZeroBitCount }
        last = first + 63 - word.leadingZeroBitCount
        var start = first
        let end = first + length
        while start < end {
            let bin = start / binWidth
            let next = min(end, bins[bin].last + 1)
            let chunk = (word >> (start - first)) & ((UInt64(1) << (next - start)) - 1)
            bins[bin].selected += chunk.nonzeroBitCount
            start = next
        }

        // Stop expanding runs once the visible prefix is complete, but finish
        // its last range if it continues into this word/page.
        if ranges.count < 200 || (ranges.last?.last == first - 1 && word & 1 != 0) {
            var remaining = word
            var offset = first
            while remaining != 0 {
                let gap = remaining.trailingZeroBitCount
                remaining >>= gap
                offset += gap
                let run = (~remaining).trailingZeroBitCount
                recordRange(offset, offset + run - 1)
                remaining >>= run
                offset += run
                if ranges.count == 200 { break }
            }
        }
    }

    private mutating func recordRange(_ first: Int, _ last: Int) {
        if let prior = ranges.last, prior.last + 1 == first {
            ranges[ranges.count - 1].last = last
        } else if ranges.count < 200 {
            ranges.append(SetRecordRange(first: first, last: last))
        }
    }
}
