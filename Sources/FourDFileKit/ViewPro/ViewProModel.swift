import Foundation

public struct ViewProFileInfo: AnalysisModel {
    public let kind = "4d.viewpro"
    public var fileName: String
    public var version: String?
    public var spreadVersion: String?
    public var activeSheet: Int
    public var sheets: [ViewProSheet]
    public var warnings: [String]
}

public struct ViewProSheet: Encodable {
    public var name: String
    public var index: Int
    public var visible: Bool
    public var rowCount: Int
    public var columnCount: Int
    public var cells: [ViewProCell]
    public var rows: [Int: ViewProAxis]
    public var columns: [Int: ViewProAxis]
    public var defaultRowHeight: Double
    public var defaultColumnWidth: Double
    public var defaultStyle: ViewProStyle
    public var spans: [ViewProSpan]
    public var showGridLines: Bool
    public var warnings: [String]
    public var showHorizontalGridLines: Bool = true
    public var showVerticalGridLines: Bool = true
}

public struct ViewProCell: Encodable {
    public var row: Int
    public var column: Int
    public var value: ViewProValue?
    public var formula: String?
    /// Display text saved by 4D, when the export includes formatting information.
    public var formattedText: String?
    public var style: ViewProStyle
    public var link: String?
    public var runs: [ViewProTextRun] = []
}

public enum ViewProValue: Encodable, Equatable {
    case text(String), number(Double), dateSerial(Double), boolean(Bool), error(String)

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let value), .error(let value): try container.encode(value)
        case .number(let value), .dateSerial(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        }
    }

    public var text: String {
        switch self {
        case .text(let value), .error(let value): return value
        case .number(let value), .dateSerial(let value): return String(format: "%.15g", locale: Locale(identifier: "en_US_POSIX"), value)
        case .boolean(let value): return value ? "TRUE" : "FALSE"
        }
    }
}

public struct ViewProTextRun: Encodable {
    public var text: String
    public var style: ViewProStyle
}

public struct ViewProAxis: Encodable {
    public var size: Double?
    public var visible: Bool
    public var style: ViewProStyle
}

public struct ViewProSpan: Encodable {
    public var row: Int
    public var column: Int
    public var rowCount: Int
    public var columnCount: Int
}

/// Only properties understood by the static renderer are retained.
public struct ViewProStyle: Encodable {
    public var font: String?
    public var foreground: String?
    public var background: String?
    public var horizontalAlignment: Int?
    public var verticalAlignment: Int?
    public var wordWrap: Bool?
    public var textDecoration: Int?
    public var formatter: String?
    public var textIndent: Double?
    public var borders: [String: ViewProBorder] = [:]

    public init() {}

    public func merging(_ other: ViewProStyle) -> ViewProStyle {
        var result = self
        result.font = other.font ?? font
        result.foreground = other.foreground ?? foreground
        result.background = other.background ?? background
        result.horizontalAlignment = other.horizontalAlignment ?? horizontalAlignment
        result.verticalAlignment = other.verticalAlignment ?? verticalAlignment
        result.wordWrap = other.wordWrap ?? wordWrap
        result.textDecoration = other.textDecoration ?? textDecoration
        result.formatter = other.formatter ?? formatter
        result.textIndent = other.textIndent ?? textIndent
        result.borders.merge(other.borders) { _, value in value }
        return result
    }
}

public struct ViewProBorder: Encodable {
    public var color: String?
    public var style: Int
}

public enum ViewProError: Error, CustomStringConvertible {
    case invalid(String), limit(String)
    public var description: String {
        switch self {
        case .invalid(let message): return "Invalid 4D View Pro document: \(message)"
        case .limit(let message): return "4D View Pro preview limit: \(message)"
        }
    }
}
