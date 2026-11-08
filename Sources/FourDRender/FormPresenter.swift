import Foundation
import FourDFileKit

public struct FormPreview {
    public var name: String
    public var properties: FormValue
    public var appearances: [FormAppearance]
    public var images: [FormImage]
}

public struct FormPresenter: ReportPresenter {
    public init() {}
    public var kinds: [String] { ["4d.form"] }

    public func report(for model: AnalysisModel) -> Report? {
        guard let form = model as? FormFileInfo else { return nil }
        var report = Report(title: form.formName, subtitle: "4D Form")
        var blocks: [Block] = [
            .formPreview(FormPreview(name: form.formName, properties: form.properties,
                                     appearances: form.appearances, images: form.images))
        ]
        var notes = form.warnings
        notes += FormPreviewRenderer.diagnostics(form)
        if !notes.isEmpty {
            blocks.append(.disclosure(summary: "Preview notices", detail: "\(notes.count)",
                                      blocks: notes.map { .note($0, .warning) }))
        }
        blocks.append(.disclosure(summary: "Form details", detail: nil, blocks: [
            .keyValues([
                KeyValue("Pages", "\(max(0, (form.properties["pages"]?.values.count ?? 1) - 1))"),
                KeyValue("Color scheme", form.properties["colorScheme"]?.string ?? "Inherited"),
                KeyValue("Destination", form.properties["destination"]?.string ?? "Not specified"),
                KeyValue("Dependencies loaded", "\(form.dependencies.count)")
            ]),
            .text("Approximate macOS editor layout with stylesheets applied. Expressions and methods are not executed; bound controls show their saved expressions, not runtime values."),
            .text(form.dependencies.joined(separator: "\n"))
        ]))
        let source = String(form.text.prefix(256 * 1024))
        var sourceBlocks: [Block] = [.sourceCode(source, language: .json)]
        if source.count < form.text.count { sourceBlocks.insert(.note("Original JSON display truncated to 256 Ki characters.", .warning), at: 0) }
        blocks.append(.disclosure(summary: "Original JSON", detail: nil, blocks: sourceBlocks))
        report.sections = [Section("", blocks)]
        return report
    }
}
