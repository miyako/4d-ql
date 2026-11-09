import Foundation

public struct TextFileInfo: AnalysisModel {
    public enum Format: String, Codable {
        case xml, json
    }

    public enum DocumentType: String, Codable {
        case settings, project, link, preferences

        public var format: Format { self == .project ? .json : .xml }
    }

    public let kind = "4d.text"
    public let fileName: String
    public let documentType: DocumentType
    public let format: Format
    public let text: String
}

public struct TextFileAnalyzer: FileAnalyzer {
    public let documentType: TextFileInfo.DocumentType
    public var format: TextFileInfo.Format { documentType.format }

    public init(format: TextFileInfo.Format) {
        self.init(documentType: format == .xml ? .settings : .project)
    }

    public init(documentType: TextFileInfo.DocumentType) { self.documentType = documentType }

    public var identifier: String { "4d" + documentType.rawValue }
    public var contentTypes: [String] {
        ["com.4d.4d." + (documentType == .link ? "database-shortcut" : documentType.rawValue)]
    }
    public var filenameExtensions: [String] { [identifier] }

    public func analyze(_ source: ByteSource, options: AnalysisOptions) throws -> AnalysisModel {
        var encoding = String.Encoding.utf8
        let text = try String(contentsOf: source.url, usedEncoding: &encoding)
        return TextFileInfo(fileName: source.url.lastPathComponent, documentType: documentType, format: format, text: text)
    }
}
