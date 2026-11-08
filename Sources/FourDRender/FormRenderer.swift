import Foundation
import FourDFileKit

public struct FormRenderOptions {
    public var initialTheme: FormTheme?
    public var initialPage: Int?

    public init(initialTheme: FormTheme? = nil, initialPage: Int? = nil) {
        self.initialTheme = initialTheme
        self.initialPage = initialPage
    }
}

public enum FormRenderError: LocalizedError {
    case noAppearance
    case invalidColorScheme
    case unavailableTheme(FormTheme)
    case unavailablePage(Int)

    public var errorDescription: String? {
        switch self {
        case .noAppearance: return "The form has no renderable appearance or pages."
        case .invalidColorScheme: return "The form's colorScheme must be light or dark."
        case .unavailableTheme(let theme): return "The requested \(theme.label) appearance is unavailable or conflicts with the form's colorScheme."
        case .unavailablePage(let page): return "Page \(page) is not present in the form."
        }
    }
}

/// Versioned export boundary. Paint order is represented by object arrays,
/// including subform children. Appearance properties are macOS reference styles.
public struct FormRenderDocument: Encodable {
    public let schemaVersion = 1
    public let referencePlatform = "macOS"
    public let initialTheme: FormTheme?
    public let initialPage: Int?
    public let form: FormFileInfo
    public let notices: [String]

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

public struct FormRenderResult {
    public let html: String
    public let document: FormRenderDocument
}

/// Standalone, in-process rendering. No Quick Look, XPC, hosting app or 4D
/// application is consulted; the caller supplies normal filesystem access.
public struct FormRenderer {
    public init() {}

    public func analyze(url: URL, preferredLanguages: [String] = Locale.preferredLanguages) throws -> FormFileInfo {
        try FormFileAnalyzer(preferredLanguages: preferredLanguages).analyzeForm(ByteSource(url: url))
    }

    public func render(url: URL, preferredLanguages: [String] = Locale.preferredLanguages,
                       options: FormRenderOptions = FormRenderOptions()) throws -> FormRenderResult {
        try render(form: analyze(url: url, preferredLanguages: preferredLanguages), options: options)
    }

    public func render(form: FormFileInfo, options: FormRenderOptions = FormRenderOptions()) throws -> FormRenderResult {
        let scheme = form.properties["colorScheme"]?.string
        guard form.properties["colorScheme"] == nil || scheme == "light" || scheme == "dark" else {
            throw FormRenderError.invalidColorScheme
        }
        let appearances = form.appearances.filter { scheme == nil || $0.theme.dark == (scheme == "dark") }
        guard !appearances.isEmpty, appearances.allSatisfy({ !$0.pages.isEmpty }) else {
            throw FormRenderError.noAppearance
        }
        if let theme = options.initialTheme, !appearances.contains(where: { $0.theme == theme }) {
            throw FormRenderError.unavailableTheme(theme)
        }
        if let page = options.initialPage,
           !appearances.allSatisfy({ $0.pages.contains { $0.number == page } }) {
            throw FormRenderError.unavailablePage(page)
        }
        let report = FormPresenter().formReport(form, initialTheme: options.initialTheme, initialPage: options.initialPage)
        let document = FormRenderDocument(initialTheme: options.initialTheme, initialPage: options.initialPage,
                                          form: form, notices: form.warnings + FormPreviewRenderer.diagnostics(form))
        return FormRenderResult(html: HTMLRenderer().render(report), document: document)
    }
}
