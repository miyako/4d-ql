import Foundation

public struct QuickReportTextStyle: Codable, Equatable {
    public let fontName: String
    public let fontSize: Int
    public let face: UInt16
    public let justification: UInt16
    public let foreground: String
    public let background: String?
    public let alternateBackground: String?
}

public struct QuickReportBorder: Codable, Equatable {
    public let thickness: UInt8
    public let color: String
}

public struct QuickReportCell: Codable {
    public let text: String
    public let operators: UInt16
    public let hidden: Bool
    public let style: QuickReportTextStyle
    public let borders: [QuickReportBorder]
}

public struct QuickReportPageBand: Codable {
    public let height: Int
    public let left: String
    public let center: String
    public let right: String
    public let style: QuickReportTextStyle
    public let hasPicture: Bool
}

public struct QuickReportColumn: Codable {
    public let width: Int
    public let automaticWidth: Bool
    public let repeatedValues: Bool
    public let hidden: Bool
    public let title: String
    public let displayFormat: String
    public let titleHidden: Bool
    public let detailHidden: Bool
    public let titleStyle: QuickReportTextStyle
    public let detailStyle: QuickReportTextStyle
    public let titleBorders: [QuickReportBorder]
    public let detailBorders: [QuickReportBorder]
    public let cells: [QuickReportCell]
    public let tableNumber: Int?
    public let fieldNumber: Int?
    /// Tokenized expressions are deliberately not evaluated or guessed.
    public let formulaBytes: Int
}

public struct QuickReportFileInfo: AnalysisModel {
    public var kind: String { "4d.quick-report" }
    public let fileName: String
    public let littleEndian: Bool
    public let formatVersion: UInt32
    public let streamVersion: UInt32
    public let crossTable: Bool
    public let tableNumber: Int
    public let rowCount: Int
    /// Signed, one-based column numbers: negative means descending.
    public let sorts: [Int]
    public let header: QuickReportPageBand
    public let footer: QuickReportPageBand
    public let columns: [QuickReportColumn]
    public let printerSettingsBytes: Int
    public let notes: [String]
}

public enum QuickReportError: Error, CustomStringConvertible {
    case invalid(String)
    public var description: String {
        switch self {
        case .invalid(let reason): return "Invalid Quick Report: \(reason)"
        }
    }
}

public struct QuickReportFileAnalyzer: FileAnalyzer {
    public init() {}
    public let identifier = "4qr"
    public let contentTypes = ["com.4d.4d.quickReport"]
    public let filenameExtensions = ["4qr"]

    public func analyze(_ source: ByteSource, options: AnalysisOptions) throws -> AnalysisModel {
        guard source.size <= 32 * 1024 * 1024 else {
            throw QuickReportError.invalid("file exceeds the 32 MiB preview limit.")
        }
        return try QuickReportDecoder(data: source.read(at: 0, length: Int(source.size)))
            .decode(fileName: source.url.lastPathComponent)
    }
}

private struct QRChunk {
    let tag: String
    let data: Data
    let children: [QRChunk]

    func one(_ tag: String) throws -> QRChunk {
        let matches = children.filter { $0.tag == tag }
        guard matches.count == 1, let chunk = matches.first else {
            throw QuickReportError.invalid("expected one \(tag) chunk in \(self.tag).")
        }
        return chunk
    }
}

private final class QuickReportDecoder {
    let data: Data
    var littleEndian = true
    var chunkCount = 0
    var unknown = Set<String>()

    init(data: Data) { self.data = data }

    func decode(fileName: String) throws -> QuickReportFileInfo {
        guard data.count >= 16, data.prefix(4) == Data([0x80, 0x1A, 0x00, 0x02]) else {
            throw QuickReportError.invalid("unrecognized document signature (only the chunk-based format is supported).")
        }
        let signature = data.subdata(in: 4..<8)
        if signature == Data("MROF".utf8) { littleEndian = true }
        else if signature == Data("FORM".utf8) { littleEndian = false }
        else { throw QuickReportError.invalid("missing FORM container.") }
        var reader = BinaryReader(data, offset: 4, littleEndian: littleEndian)
        let root = try chunk(&reader, depth: 0)
        guard root.tag == "REPT", reader.remaining == 0 else {
            throw QuickReportError.invalid("invalid REPT container length.")
        }
        var versionReader = cursor(try root.one("Vers").data)
        let version = try versionReader.u32()
        guard version == 0x10000 else {
            throw QuickReportError.invalid("unsupported format version \(version).")
        }
        var streamReader = cursor(try root.one("StVr").data)
        let streamVersion = try streamReader.u32()
        guard (25...28).contains(streamVersion) else {
            throw QuickReportError.invalid("unsupported string stream version \(streamVersion).")
        }
        var info = cursor(try root.one("Info").data)
        let reportKind = try info.u32()
        guard reportKind <= 1 else { throw QuickReportError.invalid("unknown report kind \(reportKind).") }
        let table = Int(try info.u32())
        let rowCount = Int(try info.u32())
        guard rowCount >= 1, rowCount <= 513 else { throw QuickReportError.invalid("invalid row count.") }
        _ = try info.u8()
        let columnChunks = root.children.filter { $0.tag == "Col " }
        guard columnChunks.count <= 512 else { throw QuickReportError.invalid("more than 512 columns.") }
        let columns = try columnChunks.map { try column($0, rowCount: rowCount) }
        var sorts: [Int] = []
        if let sort = root.children.first(where: { $0.tag == "Sort" }) {
            guard sort.data.count % 2 == 0 else { throw QuickReportError.invalid("invalid sort array.") }
            var r = cursor(sort.data)
            while r.remaining > 0 {
                let value = Int(try r.i16())
                guard value != 0, abs(value) <= columns.count else {
                    throw QuickReportError.invalid("sort references an absent column.")
                }
                sorts.append(value)
            }
        }
        guard reportKind == 0 || (columns.count == 3 && rowCount == 3) else {
            throw QuickReportError.invalid("cross-table reports must have a 3 by 3 grid.")
        }
        var notes: [String] = []
        if columns.contains(where: { $0.formulaBytes > 0 }) {
            notes.append("Tokenized formulas are not decoded or executed; formula cells are marked explicitly.")
        }
        if !unknown.isEmpty {
            notes.append("Uninterpreted chunks: " + unknown.sorted().joined(separator: ", ") + ".")
        }
        let header = try band(root.one("Head"))
        let footer = try band(root.one("Futr"))
        if header.hasPicture || footer.hasPicture {
            notes.append("Header/footer pictures are not rendered.")
        }
        let printerBytes = root.children.filter { ["PRPS", "PRPF", "PRNT"].contains($0.tag) }
            .reduce(0) { $0 + $1.data.count }
        return QuickReportFileInfo(fileName: fileName, littleEndian: littleEndian, formatVersion: version,
                                   streamVersion: streamVersion, crossTable: reportKind == 1, tableNumber: table,
                                   rowCount: rowCount, sorts: sorts, header: header, footer: footer, columns: columns,
                                   printerSettingsBytes: printerBytes, notes: notes)
    }

    func cursor(_ bytes: Data) -> BinaryReader { BinaryReader(bytes, littleEndian: littleEndian) }

    func chunk(_ reader: inout BinaryReader, depth: Int) throws -> QRChunk {
        chunkCount += 1
        guard depth <= 8, chunkCount <= 20_000 else { throw QuickReportError.invalid("container complexity limit exceeded.") }
        let rawTag = try reader.bytes(4)
        let tag = String(decoding: littleEndian ? Data(rawTag.reversed()) : rawTag, as: UTF8.self)
        let count = Int(try reader.u32())
        let payload = try reader.bytes(count)
        if count % 2 != 0 { try reader.skip(1) }
        if tag == "FORM" {
            var nested = cursor(payload)
            let rawType = try nested.bytes(4)
            let type = String(decoding: littleEndian ? Data(rawType.reversed()) : rawType, as: UTF8.self)
            var children: [QRChunk] = []
            while nested.remaining > 0 { children.append(try chunk(&nested, depth: depth + 1)) }
            if !["REPT", "Head", "Futr", "Col ", "Brek"].contains(type) { unknown.insert("FORM:\(type)") }
            return QRChunk(tag: type, data: payload, children: children)
        }
        if !["Vers", "StVr", "Mrgn", "Heit", "Strs", "Font", "Info", "Sort", "Tfon", "Lfon",
             "Brdr", "TBrd", "Fild", "Frml", "Outp", "PRPS", "PRPF", "PRNT", "PICT"].contains(tag) {
            unknown.insert(tag)
        }
        return QRChunk(tag: tag, data: payload, children: [])
    }

    func string(_ r: inout BinaryReader) throws -> String {
        let bytes = Int(try r.u32())
        let encoding = try r.u32()
        guard encoding == 2, bytes % 2 == 0, bytes <= 128 * 1024 else {
            throw QuickReportError.invalid("unsupported or oversized serialized string.")
        }
        let raw = try r.bytes(bytes)
        guard let value = String(data: raw, encoding: littleEndian ? .utf16LittleEndian : .utf16BigEndian) else {
            throw QuickReportError.invalid("invalid UTF-16 string.")
        }
        return value
    }

    func color(_ r: inout BinaryReader, optional: Bool = false) throws -> String? {
        let value = try r.u32()
        if optional && value == UInt32.max { return nil }
        // Native COLORREF: the least significant byte is red.
        return String(format: "#%02X%02X%02X", value & 255, (value >> 8) & 255, (value >> 16) & 255)
    }

    func style(_ node: QRChunk) throws -> QuickReportTextStyle {
        var r = cursor(node.data)
        let foreground = try color(&r) ?? "#000000"
        _ = try r.u16()
        let size = Int(try r.u16())
        let justification = try r.u16()
        let face = try r.u16()
        let name = try string(&r)
        let background = try color(&r, optional: true)
        let alternate = try color(&r, optional: true)
        return QuickReportTextStyle(fontName: name, fontSize: size, face: face,
                                    justification: justification, foreground: foreground,
                                    background: background, alternateBackground: alternate)
    }

    func borders(_ node: QRChunk) throws -> [QuickReportBorder] {
        guard node.data.count == 30 else { throw QuickReportError.invalid("invalid border array.") }
        var r = cursor(node.data)
        return try (0..<6).map { _ in
            let thickness = try r.u8()
            let value = try color(&r) ?? "#000000"
            return QuickReportBorder(thickness: thickness, color: value)
        }
    }

    func band(_ node: QRChunk) throws -> QuickReportPageBand {
        var height = cursor(try node.one("Heit").data)
        var strings = cursor(try node.one("Strs").data)
        let left = try string(&strings), center = try string(&strings), right = try string(&strings)
        return QuickReportPageBand(height: Int(try height.u16()), left: left, center: center, right: right,
                                   style: try style(node.one("Font")),
                                   hasPicture: node.children.contains { $0.tag == "PICT" })
    }

    func column(_ node: QRChunk, rowCount: Int) throws -> QuickReportColumn {
        var r = cursor(try node.one("Info").data)
        let width = Int(try r.i16())
        let automatic = try r.u16() != 0
        let repeated = try r.u8() != 0, hidden = try r.u8() != 0
        let title = try string(&r), format = try string(&r)
        let titleHidden = try r.u8() != 0, detailHidden = try r.u8() != 0
        let breaks = node.children.filter { $0.tag == "Brek" }
        guard breaks.count == rowCount else { throw QuickReportError.invalid("inconsistent cell row count.") }
        let cells = try breaks.map { cell -> QuickReportCell in
            var info = cursor(try cell.one("Info").data)
            let text = try string(&info)
            let operators = try info.u16()
            let hidden = try info.u16() != 0
            _ = try info.u8()
            return QuickReportCell(text: text, operators: operators, hidden: hidden,
                                   style: try style(cell.one("Font")), borders: try borders(cell.one("Brdr")))
        }
        var table: Int?, field: Int?
        if let node = node.children.first(where: { $0.tag == "Fild" }) {
            var fieldInfo = cursor(node.data)
            table = Int(try fieldInfo.u32())
            field = Int(try fieldInfo.u32())
            _ = try fieldInfo.u32()
        }
        let formulaBytes = node.children.filter { $0.tag == "Frml" }.reduce(0) { $0 + $1.data.count }
        return QuickReportColumn(width: width, automaticWidth: automatic, repeatedValues: repeated,
                                 hidden: hidden, title: title, displayFormat: format,
                                 titleHidden: titleHidden, detailHidden: detailHidden,
                                 titleStyle: try style(node.one("Tfon")), detailStyle: try style(node.one("Lfon")),
                                 titleBorders: try borders(node.one("TBrd")), detailBorders: try borders(node.one("Brdr")),
                                 cells: cells, tableNumber: table, fieldNumber: field, formulaBytes: formulaBytes)
    }
}
