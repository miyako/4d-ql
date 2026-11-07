import Foundation
import FourDFileKit

/// File -> analyzer -> presenter -> HTML. The single entry point used by the
/// Quick Look extension and the command line tool.
public struct PreviewPipeline {
    public var analyzers: AnalyzerRegistry
    public var presenters: PresenterRegistry
    public var renderer: HTMLRenderer

    public init(analyzers: AnalyzerRegistry = .default,
                presenters: PresenterRegistry = .default,
                renderer: HTMLRenderer = HTMLRenderer()) {
        self.analyzers = analyzers
        self.presenters = presenters
        self.renderer = renderer
    }

    public func report(for url: URL, contentType: String? = nil, options: AnalysisOptions = .preview) -> Report {
        do {
            let model = try analyzers.analyze(url: url, contentType: contentType, options: options)
            return presenters.report(for: model)
        } catch {
            return PresenterRegistry.errorReport(fileName: url.lastPathComponent, error: error)
        }
    }

    public func html(for url: URL, contentType: String? = nil, options: AnalysisOptions = .preview) -> String {
        renderer.render(report(for: url, contentType: contentType, options: options))
    }
}
