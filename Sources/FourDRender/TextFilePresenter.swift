import FourDFileKit

public struct TextFilePresenter: ReportPresenter {
    public init() {}

    public var kinds: [String] { ["4d.text"] }

    public func report(for model: AnalysisModel) -> Report? {
        guard let info = model as? TextFileInfo else { return nil }
        let subtitle: String
        switch info.documentType {
        case .settings: subtitle = "4D Settings (XML)"
        case .project: subtitle = "4D Project (JSON)"
        case .link: subtitle = "4D Link (XML)"
        case .preferences: subtitle = "4D Preferences (XML)"
        }
        var report = Report(title: info.fileName, subtitle: subtitle)
        report.sections = [Section("Contents", [.sourceCode(info.text, language: info.format == .xml ? .xml : .json)])]
        return report
    }
}
