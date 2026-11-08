import Foundation
import FourDFileKit

public struct MethodPresenter: ReportPresenter {
    public let kinds = ["4dm.source"]
    public init() {}

    public func report(for model: AnalysisModel) -> Report? {
        guard let info = model as? MethodFileInfo else { return nil }
        var report = Report(title: info.fileName, subtitle: "4D method / class source")
        report.badges = [Badge("UTF-8"), Badge("4DM")]
        report.stats = [Stat(info.truncated ? "Lines shown" : "Lines", Fmt.n(info.lineCount)),
                        Stat("File size", Fmt.bytes(info.fileSize))]
        var blocks: [Block] = []
        if info.truncated {
            blocks.append(.note("Preview limited to the first 1,000 lines or 256 KiB of source.", .warning))
        }
        if info.source.isEmpty {
            blocks.append(.note("This source file is empty.", .neutral))
        } else {
            blocks.append(.code(info.tokens.map { CodeSpan($0.text, style: style($0.kind)) }))
        }
        report.sections = [Section("Source", blocks)]
        return report
    }

    private func style(_ kind: MethodToken.Kind) -> CodeSpan.Style {
        switch kind {
        case .plain: return .plain
        case .comment: return .comment
        case .processing: return .processing
        case .string: return .string
        case .number: return .number
        case .keyword: return .keyword
        case .variable: return .variable
        case .command: return .command
        case .constant: return .constant
        case .type: return .type
        case .property: return .property
        case .operator: return .operator
        }
    }
}
