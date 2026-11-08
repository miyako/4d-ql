import Foundation
import FourDFileKit

/// Turns one kind of analysis model into a Report.
public protocol ReportPresenter {
    /// Model kinds handled, e.g. ["db4d.data"].
    var kinds: [String] { get }
    func report(for model: AnalysisModel) -> Report?
}

/// Picks the presenter for a model. Register new presenters here when adding formats.
public final class PresenterRegistry {
    public private(set) var presenters: [ReportPresenter]

    public init(_ presenters: [ReportPresenter]) { self.presenters = presenters }

    public static let `default` = PresenterRegistry([DB4DPresenter(), CatalogPresenter()])

    public func register(_ p: ReportPresenter) { presenters.append(p) }

    public func report(for model: AnalysisModel) -> Report {
        for p in presenters where p.kinds.contains(model.kind) {
            if let r = p.report(for: model) { return r }
        }
        var r = Report(title: model.kind)
        r.sections = [Section("Raw", [.text((try? String(decoding: model.jsonData(), as: UTF8.self)) ?? "")])]
        return r
    }

    /// Page shown when a file could not be analyzed.
    public static func errorReport(fileName: String, error: Error) -> Report {
        var r = Report(title: fileName, subtitle: "No preview available")
        r.sections = [Section("Problem", [.note(String(describing: error), .warning)])]
        return r
    }
}

enum Fmt {
    static let number: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    static func n<T: BinaryInteger>(_ v: T) -> String { number.string(from: NSNumber(value: Int64(v))) ?? "\(v)" }

    static func bytes(_ v: Int64) -> String { ByteCountFormatter.string(fromByteCount: v, countStyle: .file) }

    static func plural(_ v: Int, _ one: String, _ many: String? = nil) -> String {
        "\(n(v)) \(v == 1 ? one : (many ?? one + "s"))"
    }

    static func percent(_ fraction: Double) -> String {
        let p = fraction * 100
        return p > 0 && p < 1 ? "<1%" : String(format: "%.0f%%", p)
    }
}
