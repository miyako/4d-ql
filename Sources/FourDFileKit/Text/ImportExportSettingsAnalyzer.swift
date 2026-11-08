import Foundation

public struct ImportExportSettingsInfo: AnalysisModel {
    public let kind = "4d.import-export-settings"
    public let fileName: String
    public let root: ImportExportSettingsNode
    public let warnings: [String]
}

public struct ImportExportSettingsNode: Codable {
    public let name: String
    public let attributes: [String: String]
    public var children: [ImportExportSettingsNode] = []
    public var text: String = ""
}

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
        let parser = XMLParser(data: data)
        let document = ImportExportSettingsDocument()
        parser.delegate = document
        // Request entity callbacks so unsupported references are reported, never loaded.
        parser.shouldResolveExternalEntities = true
        parser.externalEntityResolvingPolicy = .never
        let parsed = parser.parse()
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

private final class ImportExportSettingsDocument: NSObject, XMLParserDelegate {
    var root: ImportExportSettingsNode?
    var failure: String?
    private var stack: [ImportExportSettingsNode] = []
    private var elementCount = 0

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        elementCount += 1
        guard elementCount <= 20_000, stack.count < 32 else {
            failure = "XML exceeds the element or nesting limit"
            parser.abortParsing()
            return
        }
        stack.append(ImportExportSettingsNode(name: elementName, attributes: attributeDict))
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if !stack.isEmpty { stack[stack.count - 1].text += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if !stack.isEmpty { stack[stack.count - 1].text += String(decoding: CDATABlock, as: UTF8.self) }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard let node = stack.popLast() else { return }
        if stack.isEmpty { root = node } else { stack[stack.count - 1].children.append(node) }
    }

    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
        rejectEntity(parser)
    }

    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) {
        rejectEntity(parser)
    }

    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
        rejectEntity(parser)
        return nil
    }

    private func rejectEntity(_ parser: XMLParser) {
        failure = "custom XML entities are not supported"
        parser.abortParsing()
    }
}
