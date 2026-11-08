import Foundation

public struct TextFileInfo: AnalysisModel {
    public enum Format: String, Codable {
        case xml, json
    }

    public let kind = "4d.text"
    public let fileName: String
    public let format: Format
    public let text: String
}

public struct TextFileAnalyzer: FileAnalyzer {
    public let format: TextFileInfo.Format

    public init(format: TextFileInfo.Format) { self.format = format }

    public var identifier: String { format == .xml ? "4dsettings" : "4dproject" }
    public var contentTypes: [String] {
        [format == .xml ? "com.4d.4d.settings" : "com.4d.4d.project"]
    }
    public var filenameExtensions: [String] { [identifier] }

    public func analyze(_ source: ByteSource, options: AnalysisOptions) throws -> AnalysisModel {
        var encoding = String.Encoding.utf8
        let text = try String(contentsOf: source.url, usedEncoding: &encoding)
        return TextFileInfo(fileName: source.url.lastPathComponent, format: format, text: text)
    }
}
