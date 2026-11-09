import Foundation
import FourDFileKit

public struct FormPreview {
    public var name: String
    public var properties: FormValue
    public var appearances: [FormAppearance]
    public var images: [FormImage]
    public var initialTheme: FormTheme? = nil
    public var initialPage: Int? = nil
    /// Platform whose native appearances the preview reproduces.
    public var platform: FormPlatform = .macOS
}

public struct FormPresenter: ReportPresenter {
    public init() {}
    public var kinds: [String] { ["4d.form"] }

    public func report(for model: AnalysisModel) -> Report? {
        guard let form = model as? FormFileInfo else { return nil }
        return formReport(form)
    }

    public func formReport(_ form: FormFileInfo, initialTheme: FormTheme? = nil, initialPage: Int? = nil) -> Report {
        var report = Report(title: form.formName, subtitle: "4D Form")
        var blocks: [Block] = [
            .formPreview(FormPreview(name: form.formName, properties: form.properties,
                                     appearances: form.appearances, images: form.images,
                                     initialTheme: initialTheme, initialPage: initialPage,
                                     platform: form.platform))
        ]
        var notes = form.warnings
        notes += FormPreviewRenderer.diagnostics(form)
        if !notes.isEmpty {
            blocks.insert(.note("Some resources or form features could not be reproduced. See Preview notices for details.", .warning), at: 0)
            blocks.append(.disclosure(summary: "Preview notices", detail: "\(notes.count)",
                                      blocks: notes.map { .note($0, .warning) }))
        }
        blocks.append(.disclosure(summary: "Form details", detail: nil, blocks: [
            .keyValues([
                KeyValue("Pages", "\(max(0, (form.properties["pages"]?.values.count ?? 1) - 1))"),
                KeyValue("Color scheme", form.properties["colorScheme"]?.string ?? "Inherited"),
                KeyValue("Destination", form.properties["destination"]?.string ?? "Not specified"),
                KeyValue("Localization", form.localizationLanguage ?? "No project translation selected"),
                KeyValue("Dependencies loaded", "\(form.dependencies.count)")
            ]),
            .text(Self.layoutDescription(form)),
            .text(form.dependencies.joined(separator: "\n"))
        ]))
        let source = String(form.text.prefix(256 * 1024))
        var sourceBlocks: [Block] = [.sourceCode(source, language: .json)]
        if source.count < form.text.count { sourceBlocks.insert(.note("Original JSON display truncated to 256 Ki characters.", .warning), at: 0) }
        blocks.append(.disclosure(summary: "Original JSON", detail: nil, blocks: sourceBlocks))
        report.sections = [Section("", blocks)]
        return report
    }

    static func layoutDescription(_ form: FormFileInfo) -> String {
        let platforms = form.platforms.isEmpty ? [form.platform] : form.platforms
        var text = platforms.count > 1
            ? "Approximate \(platforms.map(\.label).joined(separator: " and ")) editor layouts with each platform's stylesheets applied."
            : "Approximate \(form.platform.label) editor layout with stylesheets applied."
        text += " Expressions and methods are not executed; bound controls show their saved expressions, not runtime values."
        if platforms.contains(.windows) && FormSubstituteFont.isNeeded {
            text += " Segoe UI is not installed, so Windows text uses Selawik, its metric-compatible open-source substitute; glyph shapes differ slightly."
        }
        return text
    }
}
