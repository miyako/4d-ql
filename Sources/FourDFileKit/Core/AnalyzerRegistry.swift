import Foundation

public enum AnalyzerError: Error, CustomStringConvertible {
    case unsupported(String)
    case notRecognized(String)
    public var description: String {
        switch self {
        case .unsupported(let what): return "no analyzer for \(what)"
        case .notRecognized(let what): return "\(what) is not in a recognised format"
        }
    }
}

/// Maps a file (by UTI, then extension) to the analyzer that understands it.
public final class AnalyzerRegistry {
    public private(set) var analyzers: [FileAnalyzer] = []

    public init(_ analyzers: [FileAnalyzer] = []) { self.analyzers = analyzers }

    public func register(_ analyzer: FileAnalyzer) { analyzers.append(analyzer) }

    /// All analyzers known to this build. Append new formats here.
    public static let `default` = AnalyzerRegistry([
        DataFileAnalyzer(),
        StructureFileAnalyzer(),
        CatalogAnalyzer(),
        TextFileAnalyzer(format: .xml),
        TextFileAnalyzer(format: .json),
        QueryFileAnalyzer(),
        MethodFileAnalyzer(),
    ])

    public var allContentTypes: [String] { analyzers.flatMap(\.contentTypes) }

    public func candidates(contentType: String?, url: URL) -> [FileAnalyzer] {
        let ext = url.pathExtension.lowercased()
        var result: [FileAnalyzer] = []
        if let uti = contentType {
            result += analyzers.filter { $0.contentTypes.contains(uti) }
        }
        result += analyzers.filter { a in a.filenameExtensions.contains(ext) && !result.contains { $0.identifier == a.identifier } }
        return result
    }

    public func analyze(url: URL, contentType: String? = nil, options: AnalysisOptions = .preview) throws -> AnalysisModel {
        let candidates = candidates(contentType: contentType, url: url)
        guard !candidates.isEmpty else { throw AnalyzerError.unsupported(url.lastPathComponent) }
        let source = try ByteSource(url: url)
        for analyzer in candidates where analyzer.canAnalyze(source) {
            return try analyzer.analyze(source, options: options)
        }
        throw AnalyzerError.notRecognized(url.lastPathComponent)
    }
}
