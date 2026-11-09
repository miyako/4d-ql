import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct ImportExportSettingsInfo: AnalysisModel {
    public let kind = "4d.import-export-settings"
    public let fileName: String
    public let root: ImportExportSettingsNode
    public let warnings: [String]
}

public typealias ImportExportSettingsNode = XMLFileNode

public enum ImportExportSettingsError: Error, CustomStringConvertible {
    case invalid(String)

    public var description: String {
        switch self {
        case .invalid(let message): return "invalid 4D import/export settings: \(message)"
        }
    }
}

public struct ImportExportSettingsAnalyzer: FileAnalyzer {
    public init() {}
    public var identifier: String { "4si" }
    public var contentTypes: [String] { ["com.4d.4d.ie-settings"] }
    public var filenameExtensions: [String] { ["4si"] }

    public func analyze(_ source: ByteSource, options: AnalysisOptions) throws -> AnalysisModel {
        guard source.size <= 4 * 1024 * 1024 else {
            throw ImportExportSettingsError.invalid("XML exceeds the 4 MiB size limit")
        }
        var data = try source.read(at: 0, length: Int(source.size))
        var warnings: [String] = []
        let trimmed = data.drop { [0x20, 0x09, 0x0A, 0x0D].contains($0) }
        if trimmed.count != data.count && trimmed.starts(with: Data("<?xml ".utf8)) {
            data = Data(trimmed)
            warnings.append("Ignored whitespace before the XML declaration.")
        }
        if XMLParser.declaresUnreportedEntities(data) {
            throw ImportExportSettingsError.invalid("custom XML entities are not supported")
        }
        let parser = XMLParser(data: data)
        let document = BoundedXMLDocument()
        parser.delegate = document
        // Request entity callbacks so unsupported references are reported, never loaded.
        parser.shouldResolveExternalEntities = XMLParser.reportsExternalEntitiesSafely
        parser.externalEntityResolvingPolicy = .never
        let parsed = parser.parseStrictly()
        if let failure = document.failure { throw ImportExportSettingsError.invalid(failure) }
        guard parsed else {
            throw ImportExportSettingsError.invalid("XML at line \(parser.lineNumber), column \(parser.columnNumber): \(parser.parserError?.localizedDescription ?? "parse failed")")
        }
        guard let root = document.root, root.name == "settings-import-export" else {
            throw ImportExportSettingsError.invalid("expected a <settings-import-export> root element")
        }
        return ImportExportSettingsInfo(fileName: source.url.lastPathComponent, root: root, warnings: warnings)
    }
}
