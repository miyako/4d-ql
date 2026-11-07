import Foundation

/// The output of an analyzer: a typed, presentation-free description of a file.
///
/// Each file family defines its own model. Renderers look the model up by `kind`,
/// so presentation can evolve without touching the parsers, and the same model
/// can be dumped as JSON for debugging or other tools.
public protocol AnalysisModel: Encodable {
    /// Stable identifier used by renderers to pick a presenter, e.g. "db4d.data".
    var kind: String { get }
}

extension AnalysisModel {
    public func jsonData(pretty: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : []
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}

public struct AnalysisOptions: Sendable {
    /// Upper bound on records walked for statistics. Keeps previews fast on huge files.
    public var maxRecordsToScan: Int
    /// Wall-clock budget for optional, expensive passes (seconds).
    public var timeBudget: TimeInterval

    public init(maxRecordsToScan: Int = 20_000, timeBudget: TimeInterval = 1.5) {
        self.maxRecordsToScan = maxRecordsToScan
        self.timeBudget = timeBudget
    }

    public static let preview = AnalysisOptions()
    public static let thorough = AnalysisOptions(maxRecordsToScan: .max, timeBudget: .infinity)
}

/// One analyzer per file family. Add a new format by conforming a type to this
/// protocol and registering it in `AnalyzerRegistry.default`.
public protocol FileAnalyzer {
    /// Short identifier, e.g. "4dd".
    var identifier: String { get }
    /// Uniform Type Identifiers handled (as declared by 4D.app).
    var contentTypes: [String] { get }
    /// Lower-case filename extensions handled, used when no UTI is known.
    var filenameExtensions: [String] { get }
    /// Cheap content sniff (magic number). Return false to let another analyzer try.
    func canAnalyze(_ source: ByteSource) -> Bool
    func analyze(_ source: ByteSource, options: AnalysisOptions) throws -> AnalysisModel
}

extension FileAnalyzer {
    public func canAnalyze(_ source: ByteSource) -> Bool { true }
}
