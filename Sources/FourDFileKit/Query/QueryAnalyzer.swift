import Foundation

public indirect enum QueryValue: Codable, Equatable {
    case string(String), integerNumber(Int64), number(Double), bool(Bool), null
    case array([QueryValue]), object([String: QueryValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Int64.self) { self = .integerNumber(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode([QueryValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: QueryValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .integerNumber(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public var integer: Int? {
        switch self {
        case .string(let value): return Int(value)
        case .integerNumber(let value): return Int(exactly: value)
        case .number(let value): return Int(exactly: value)
        default: return nil
        }
    }
}

public struct QueryFileInfo: AnalysisModel {
    public let kind = "4d.query"
    public let fileName: String
    public let text: String
    public let properties: [String: QueryValue]
    public let lines: [[String: QueryValue]]
}

public enum QueryFileError: Error, CustomStringConvertible {
    case tooLarge, invalidUTF8, invalidStructure(String)

    public var description: String {
        switch self {
        case .tooLarge: return "Saved query exceeds the 4 MiB preview limit."
        case .invalidUTF8: return "Saved query is not valid UTF-8 JSON."
        case .invalidStructure(let reason): return "Invalid saved query: \(reason)"
        }
    }
}

public struct QueryFileAnalyzer: FileAnalyzer {
    public init() {}
    public var identifier: String { "4df" }
    public var contentTypes: [String] { ["com.4d.4d.queryFile"] }
    public var filenameExtensions: [String] { ["4df"] }

    public func analyze(_ source: ByteSource, options: AnalysisOptions) throws -> AnalysisModel {
        guard source.size <= 4 * 1024 * 1024 else { throw QueryFileError.tooLarge }
        var data = try source.read(at: 0, length: Int(source.size))
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { data.removeFirst(3) }
        guard let text = String(data: data, encoding: .utf8) else { throw QueryFileError.invalidUTF8 }
        let properties = try JSONDecoder().decode([String: QueryValue].self, from: data)
        guard let mainTable = properties["mainTable"]?.integer, mainTable > 0 else {
            throw QueryFileError.invalidStructure("mainTable must be a positive table number.")
        }
        guard case .array(let values) = properties["lines"] else {
            throw QueryFileError.invalidStructure("lines must be an array.")
        }
        let lines = try values.enumerated().map { index, value -> [String: QueryValue] in
            guard case .object(let line) = value else {
                throw QueryFileError.invalidStructure("line \(index + 1) must be an object.")
            }
            return line
        }
        return QueryFileInfo(fileName: source.url.lastPathComponent, text: text,
                             properties: properties, lines: lines)
    }
}
