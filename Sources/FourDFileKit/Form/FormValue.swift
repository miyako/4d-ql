import Foundation

public struct FormMember: Encodable, Equatable {
    public var name: String
    public var value: FormValue
}

/// Object members retain declaration order: in a form this is the paint order.
public indirect enum FormValue: Encodable, Equatable {
    case string(String), integer(Int64), number(Double), bool(Bool), null
    case array([FormValue]), object([FormMember])

    public subscript(_ name: String) -> FormValue? {
        get { members.first { $0.name == name }?.value }
        set {
            guard case .object(var items) = self else { return }
            if let index = items.firstIndex(where: { $0.name == name }) {
                if let newValue { items[index].value = newValue } else { items.remove(at: index) }
            } else if let newValue { items.append(FormMember(name: name, value: newValue)) }
            self = .object(items)
        }
    }

    public var members: [FormMember] { if case .object(let v) = self { return v }; return [] }
    public var values: [FormValue] { if case .array(let v) = self { return v }; return [] }
    public var string: String? { if case .string(let v) = self { return v }; return nil }
    public var bool: Bool? { if case .bool(let v) = self { return v }; return nil }
    public var double: Double? {
        switch self {
        case .integer(let v): return Double(v)
        case .number(let v): return v
        default: return nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .integer(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        case .array(let v): try c.encode(v)
        case .object(let v):
            try c.encode(Dictionary(uniqueKeysWithValues: v.map { ($0.name, $0.value) }))
        }
    }
}

public enum FormError: Error, CustomStringConvertible {
    case invalid(String), limit(String), dependency(String)
    public var description: String {
        switch self {
        case .invalid(let s): return "Invalid 4D form: \(s)"
        case .limit(let s): return "4D form preview limit: \(s)"
        case .dependency(let s): return "4D form dependency: \(s)"
        }
    }
}

struct FormJSONParser {
    private let bytes: [UInt8]
    private var position = 0
    private var nodes = 0

    init(_ data: Data) throws {
        guard String(data: data, encoding: .utf8) != nil else { throw FormError.invalid("JSON is not UTF-8.") }
        bytes = Array(data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data)
    }

    mutating func parse() throws -> FormValue {
        let result = try value(depth: 0)
        whitespace()
        guard position == bytes.count else { throw FormError.invalid("Trailing JSON content.") }
        return result
    }

    private mutating func whitespace() {
        while position < bytes.count, [9, 10, 13, 32].contains(bytes[position]) { position += 1 }
    }

    private mutating func take(_ byte: UInt8) -> Bool {
        whitespace()
        guard position < bytes.count, bytes[position] == byte else { return false }
        position += 1
        return true
    }

    private mutating func string() throws -> String {
        whitespace()
        let start = position
        guard take(34) else { throw FormError.invalid("Expected a JSON string.") }
        while position < bytes.count {
            let byte = bytes[position]
            position += 1
            if byte == 92 {
                guard position < bytes.count else { break }
                position += 1
            } else if byte == 34 {
                return try JSONDecoder().decode(String.self, from: Data(bytes[start..<position]))
            }
        }
        throw FormError.invalid("Unterminated JSON string.")
    }

    private mutating func value(depth: Int) throws -> FormValue {
        nodes += 1
        guard depth <= 64, nodes <= 100_000 else { throw FormError.limit("JSON depth 64 or 100,000 values exceeded.") }
        whitespace()
        guard position < bytes.count else { throw FormError.invalid("Unexpected end of JSON.") }
        if bytes[position] == 34 { return .string(try string()) }
        if take(123) {
            var members: [FormMember] = []
            var names = Set<String>()
            if take(125) { return .object(members) }
            repeat {
                let name = try string()
                guard names.insert(name).inserted else { throw FormError.invalid("Duplicate JSON key: \(name)") }
                guard take(58) else { throw FormError.invalid("Expected ':'.") }
                members.append(FormMember(name: name, value: try value(depth: depth + 1)))
                if take(125) { return .object(members) }
            } while take(44)
            throw FormError.invalid("Expected ',' or '}'.")
        }
        if take(91) {
            var values: [FormValue] = []
            if take(93) { return .array(values) }
            repeat {
                values.append(try value(depth: depth + 1))
                if take(93) { return .array(values) }
            } while take(44)
            throw FormError.invalid("Expected ',' or ']'.")
        }
        let start = position
        while position < bytes.count, ![9, 10, 13, 32, 44, 93, 125].contains(bytes[position]) { position += 1 }
        let token = try JSONDecoder().decode(QueryValue.self, from: Data(bytes[start..<position]))
        switch token {
        case .string(let v): return .string(v)
        case .integerNumber(let v): return .integer(v)
        case .number(let v): return .number(v)
        case .bool(let v): return .bool(v)
        case .null: return .null
        default: throw FormError.invalid("Expected a scalar.")
        }
    }
}
