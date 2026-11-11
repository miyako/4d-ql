import Foundation

/// Editable, lossless representation of the supported Unicode .4qr container.
/// Opaque data is deliberately retained rather than interpreted as 4D code or printer settings.
public struct QuickReportDefinition: Codable {
    public var schemaVersion: Int
    public var littleEndian: Bool
    public var root: QuickReportDefinitionChunk

    public init(schemaVersion: Int = 1, littleEndian: Bool = true, root: QuickReportDefinitionChunk) {
        self.schemaVersion = schemaVersion
        self.littleEndian = littleEndian
        self.root = root
    }
}

public struct QuickReportDefinitionChunk: Codable {
    public var tag: String
    public var payload: QuickReportDefinitionPayload
    public var trailingBytes: Data?
    public var padding: UInt8?

    public init(tag: String, payload: QuickReportDefinitionPayload, trailingBytes: Data? = nil, padding: UInt8? = nil) {
        self.tag = tag
        self.payload = payload
        self.trailingBytes = trailingBytes
        self.padding = padding
    }
}

public struct QuickReportDefinitionBorder: Codable {
    public var thickness: UInt8
    public var color: UInt32

    public init(thickness: UInt8, color: UInt32) {
        self.thickness = thickness
        self.color = color
    }
}

public indirect enum QuickReportDefinitionPayload: Codable {
    case form(type: String, chunks: [QuickReportDefinitionChunk])
    case version(value: UInt32)
    case height(value: UInt16)
    case bandStrings(left: String, center: String, right: String)
    case style(foreground: UInt32, metadata: UInt16, fontSize: UInt16,
               justification: UInt16, face: UInt16, fontName: String,
               background: UInt32, alternateBackground: UInt32)
    case borders(values: [QuickReportDefinitionBorder])
    case reportInfo(kind: UInt32, tableNumber: UInt32, rowCount: UInt32, flag: UInt8)
    case columnInfo(width: Int16, automaticWidth: UInt16, repeatedValues: UInt8, hidden: UInt8,
                    title: String, displayFormat: String, titleHidden: UInt8, detailHidden: UInt8)
    case cellInfo(text: String, operators: UInt16, hidden: UInt16, flag: UInt8)
    case field(tableNumber: UInt32, fieldNumber: UInt32, reserved: UInt32)
    case sorts(columns: [Int16])
    case opaque(bytes: Data)

    fileprivate var kind: String {
        switch self {
        case .form: return "form"
        case .version: return "version"
        case .height: return "height"
        case .bandStrings: return "bandStrings"
        case .style: return "style"
        case .borders: return "borders"
        case .reportInfo: return "reportInfo"
        case .columnInfo: return "columnInfo"
        case .cellInfo: return "cellInfo"
        case .field: return "field"
        case .sorts: return "sorts"
        case .opaque: return "opaque"
        }
    }
}

public enum QuickReportConverter {
    public static let binaryLimit = 32 * 1024 * 1024
    public static let jsonLimit = 128 * 1024 * 1024

    public static func decode(_ data: Data) throws -> QuickReportDefinition {
        guard data.count <= binaryLimit else { throw QuickReportError.invalid("file exceeds the 32 MiB conversion limit.") }
        let decoder = QuickReportDecoder(data: data)
        _ = try decoder.decode(fileName: "")
        guard let root = decoder.root else { throw QuickReportError.invalid("missing report container.") }
        let result = QuickReportDefinition(schemaVersion: 1, littleEndian: decoder.littleEndian,
                                          root: try definition(root, parent: nil, decoder: decoder))
        guard try serialized(result) == data else {
            throw QuickReportError.invalid("document contains data that cannot be represented losslessly in this JSON schema.")
        }
        return result
    }

    public static func encode(_ definition: QuickReportDefinition) throws -> Data {
        guard definition.schemaVersion == 1 else {
            throw QuickReportError.invalid("unsupported JSON schema version \(definition.schemaVersion).")
        }
        guard definition.root.tag == "FORM",
              case .form(type: "REPT", chunks: _) = definition.root.payload else {
            throw QuickReportError.invalid("JSON root must be FORM REPT.")
        }
        let data = try serialized(definition)
        _ = try decode(data)
        return data
    }

    private static func serialized(_ definition: QuickReportDefinition) throws -> Data {
        var writer = QRDefinitionWriter(littleEndian: definition.littleEndian)
        try writer.chunk(definition.root, parent: nil, depth: 0)
        return Data([0x80, 0x1A, 0x00, 0x02]) + writer.data
    }

    public static func json(from data: Data) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let json = try encoder.encode(decode(data))
        guard json.count < jsonLimit else { throw QuickReportError.invalid("JSON exceeds the 128 MiB conversion limit.") }
        return json + Data([10])
    }

    public static func binary(from json: Data) throws -> Data {
        guard json.count <= jsonLimit else { throw QuickReportError.invalid("JSON exceeds the 128 MiB conversion limit.") }
        let definition = try JSONDecoder().decode(QuickReportDefinition.self, from: json)
        let canonical = try JSONEncoder().encode(definition)
        try validateKeys(JSONSerialization.jsonObject(with: json),
                         against: JSONSerialization.jsonObject(with: canonical), path: "$")
        return try encode(definition)
    }

    // Codable normally ignores unknown keys; a typo in an editable definition must not disappear silently.
    private static func validateKeys(_ input: Any, against canonical: Any, path: String) throws {
        if let input = input as? [String: Any], let canonical = canonical as? [String: Any] {
            var allowed = Set(canonical.keys)
            if canonical["tag"] != nil, canonical["payload"] != nil {
                allowed.formUnion(["padding", "trailingBytes"])
            }
            for (key, value) in input {
                guard allowed.contains(key) else {
                    throw QuickReportError.invalid("unknown JSON property \(path).\(key).")
                }
                if let expected = canonical[key] {
                    try validateKeys(value, against: expected, path: "\(path).\(key)")
                }
            }
        } else if let input = input as? [Any], let canonical = canonical as? [Any] {
            for (index, pair) in zip(input, canonical).enumerated() {
                try validateKeys(pair.0, against: pair.1, path: "\(path)[\(index)]")
            }
        }
    }

    fileprivate static func kind(tag: String, parent: String?) -> String {
        switch (tag, parent) {
        case ("FORM", _): return "form"
        case ("Vers", "REPT"), ("StVr", "REPT"): return "version"
        case ("Heit", "Head"), ("Heit", "Futr"): return "height"
        case ("Strs", "Head"), ("Strs", "Futr"): return "bandStrings"
        case ("Font", "Head"), ("Font", "Futr"), ("Font", "Brek"),
             ("Tfon", "Col "), ("Lfon", "Col "): return "style"
        case ("Brdr", "Col "), ("TBrd", "Col "), ("Brdr", "Brek"): return "borders"
        case ("Info", "REPT"): return "reportInfo"
        case ("Info", "Col "): return "columnInfo"
        case ("Info", "Brek"): return "cellInfo"
        case ("Fild", "Col "): return "field"
        case ("Sort", "REPT"): return "sorts"
        default: return "opaque"
        }
    }

    private static func definition(_ node: QRChunk, parent: String?,
                                   decoder: QuickReportDecoder) throws -> QuickReportDefinitionChunk {
        // FORM types are stored in QRChunk.tag by the shared binary parser.
        let form = node.isForm
        let tag = form ? "FORM" : node.tag
        var r = decoder.cursor(node.data)
        let payload: QuickReportDefinitionPayload
        if form {
            payload = .form(type: node.tag, chunks: try node.children.map {
                try definition($0, parent: node.tag, decoder: decoder)
            })
            try r.skip(r.remaining)
        } else {
            switch kind(tag: tag, parent: parent) {
            case "version": payload = .version(value: try r.u32())
            case "height": payload = .height(value: try r.u16())
            case "bandStrings":
                payload = .bandStrings(left: try decoder.string(&r), center: try decoder.string(&r),
                                       right: try decoder.string(&r))
            case "style":
                payload = .style(foreground: try r.u32(), metadata: try r.u16(), fontSize: try r.u16(),
                                 justification: try r.u16(), face: try r.u16(), fontName: try decoder.string(&r),
                                 background: try r.u32(), alternateBackground: try r.u32())
            case "borders":
                payload = .borders(values: try (0..<6).map { _ in
                    QuickReportDefinitionBorder(thickness: try r.u8(), color: try r.u32())
                })
            case "reportInfo":
                payload = .reportInfo(kind: try r.u32(), tableNumber: try r.u32(), rowCount: try r.u32(),
                                      flag: try r.u8())
            case "columnInfo":
                payload = .columnInfo(width: try r.i16(), automaticWidth: try r.u16(),
                                      repeatedValues: try r.u8(), hidden: try r.u8(),
                                      title: try decoder.string(&r), displayFormat: try decoder.string(&r),
                                      titleHidden: try r.u8(), detailHidden: try r.u8())
            case "cellInfo":
                payload = .cellInfo(text: try decoder.string(&r), operators: try r.u16(),
                                    hidden: try r.u16(), flag: try r.u8())
            case "field":
                payload = .field(tableNumber: try r.u32(), fieldNumber: try r.u32(), reserved: try r.u32())
            case "sorts":
                var columns: [Int16] = []
                guard r.remaining % 2 == 0 else { throw QuickReportError.invalid("invalid sort array.") }
                while r.remaining > 0 { columns.append(try r.i16()) }
                payload = .sorts(columns: columns)
            default: payload = .opaque(bytes: try r.bytes(r.remaining))
            }
        }
        let trailing = try r.bytes(r.remaining)
        return QuickReportDefinitionChunk(tag: tag, payload: payload,
                                          trailingBytes: trailing.isEmpty ? nil : trailing, padding: node.padding)
    }
}

private struct QRDefinitionWriter {
    let littleEndian: Bool
    var data = Data()
    var chunkCount = 0

    mutating func integer<T: FixedWidthInteger>(_ value: T) {
        let count = MemoryLayout<T>.size
        for index in 0..<count {
            data.append(UInt8(truncatingIfNeeded: value >> ((littleEndian ? index : count - 1 - index) * 8)))
        }
    }

    mutating func fourCC(_ value: String) throws {
        let bytes = Array(value.utf8)
        guard bytes.count == 4, bytes.allSatisfy({ (32...126).contains($0) }) else {
            throw QuickReportError.invalid("FourCC must contain exactly four printable ASCII bytes.")
        }
        data.append(contentsOf: littleEndian ? Array(bytes.reversed()) : bytes)
    }

    mutating func string(_ value: String) throws {
        let units = value.utf16
        guard units.count <= 64 * 1024 else { throw QuickReportError.invalid("string exceeds 128 KiB.") }
        integer(UInt32(units.count * 2))
        integer(UInt32(2))
        for unit in units { integer(unit) }
    }

    mutating func chunk(_ node: QuickReportDefinitionChunk, parent: String?, depth: Int) throws {
        chunkCount += 1
        guard depth <= 8, chunkCount <= 20_000 else {
            throw QuickReportError.invalid("container complexity limit exceeded.")
        }
        guard node.payload.kind == QuickReportConverter.kind(tag: node.tag, parent: parent) else {
            throw QuickReportError.invalid("payload type does not match \(node.tag) in \(parent ?? "document").")
        }
        var payload = QRDefinitionWriter(littleEndian: littleEndian, chunkCount: chunkCount)
        try payload.write(node.payload, depth: depth)
        chunkCount = payload.chunkCount
        if let trailing = node.trailingBytes {
            guard node.payload.kind != "form", node.payload.kind != "opaque" else {
                throw QuickReportError.invalid("trailingBytes is only valid for decoded leaf payloads.")
            }
            payload.data.append(trailing)
        }
        guard payload.data.count <= QuickReportConverter.binaryLimit,
              data.count + payload.data.count + 8 + payload.data.count % 2 <= QuickReportConverter.binaryLimit - 4 else {
            throw QuickReportError.invalid("file exceeds the 32 MiB conversion limit.")
        }
        try fourCC(node.tag)
        integer(UInt32(payload.data.count))
        data.append(payload.data)
        if payload.data.count % 2 != 0 { integer(node.padding ?? 0) }
    }

    mutating func write(_ payload: QuickReportDefinitionPayload, depth: Int) throws {
        switch payload {
        case .form(let type, let chunks):
            try fourCC(type)
            for child in chunks { try chunk(child, parent: type, depth: depth + 1) }
        case .version(let value): integer(value)
        case .height(let value): integer(value)
        case .bandStrings(let left, let center, let right):
            try string(left); try string(center); try string(right)
        case .style(let foreground, let metadata, let size, let justification, let face,
                    let name, let background, let alternate):
            integer(foreground); integer(metadata); integer(size); integer(justification); integer(face)
            try string(name)
            integer(background); integer(alternate)
        case .borders(let values):
            guard values.count == 6 else { throw QuickReportError.invalid("expected six borders.") }
            for value in values { integer(value.thickness); integer(value.color) }
        case .reportInfo(let kind, let table, let rows, let flag):
            integer(kind); integer(table); integer(rows); integer(flag)
        case .columnInfo(let width, let automatic, let repeated, let hidden, let title, let format,
                         let titleHidden, let detailHidden):
            integer(width); integer(automatic); integer(repeated); integer(hidden)
            try string(title); try string(format)
            integer(titleHidden); integer(detailHidden)
        case .cellInfo(let text, let operators, let hidden, let flag):
            try string(text)
            integer(operators); integer(hidden); integer(flag)
        case .field(let table, let field, let reserved):
            integer(table); integer(field); integer(reserved)
        case .sorts(let columns):
            for column in columns { integer(column) }
        case .opaque(let bytes):
            guard bytes.count <= QuickReportConverter.binaryLimit else {
                throw QuickReportError.invalid("opaque payload exceeds 32 MiB.")
            }
            data.append(bytes)
        }
    }
}
