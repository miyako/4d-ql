import FourDFileKit

public struct TextFilePresenter: ReportPresenter {
    public init() {}

    public var kinds: [String] { ["4d.text"] }

    public func report(for model: AnalysisModel) -> Report? {
        guard let info = model as? TextFileInfo else { return nil }
        var report = Report(title: info.fileName, subtitle: info.format == .xml ? "4D Settings (XML)" : "4D Project (JSON)")
        report.sections = [Section("Contents", [.sourceCode(info.text, language: info.format == .xml ? .xml : .json)])]
        return report
    }
}
