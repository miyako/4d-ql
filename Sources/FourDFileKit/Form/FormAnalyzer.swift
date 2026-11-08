import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct FormObject: Encodable {
    public var name: String
    public var properties: FormValue
    public var images: [String: String] = [:]
    /// Children paint in declaration order, in container-local coordinates, clipped
    /// to the subform object's width/height. Empty children retain the placeholder.
    public var children: [FormObject] = []
    public var embeddedProperties: FormValue? = nil
    public var source: FormObjectSource? = nil
    var stylesheetContext: String? = nil
    public var type: String { properties["type"]?.string ?? "unknown" }
    private enum CodingKeys: String, CodingKey { case name, properties, images, children, embeddedProperties, source }
}

public struct FormObjectSource: Encodable {
    public var document: String
    public var formName: String
    public var page: Int
    public var tableName: String? = nil
    public var inline: Bool = false
}

public struct FormPage: Encodable {
    public var number: Int
    public var objects: [FormObject]
}

public struct FormAppearance: Encodable {
    public var theme: FormTheme
    public var pages: [FormPage]
}

public struct FormImage: Encodable {
    public var id: String
    public var dataURI: String
    public var width: Double
    public var height: Double
}

public struct FormFileInfo: AnalysisModel {
    public let kind = "4d.form"
    public var fileName: String
    public var formName: String
    public var text: String
    public var properties: FormValue
    public var appearances: [FormAppearance]
    public var images: [FormImage]
    public var dependencies: [String]
    public var warnings: [String]
    public var localizationLanguage: String? = nil
}

public struct FormFileAnalyzer: FileAnalyzer {
    public var preferredLanguages: [String]
    /// No 4D application language is inferred or read from an installed application.
    public init(preferredLanguages: [String] = Locale.preferredLanguages) {
        self.preferredLanguages = preferredLanguages
    }
    public var identifier: String { "4dform" }
    public var contentTypes: [String] { ["com.4d.4d.form"] }
    public var filenameExtensions: [String] { ["4dform"] }

    public func analyze(_ source: ByteSource, options: AnalysisOptions) throws -> AnalysisModel {
        try analyzeForm(source, options: options)
    }

    public func analyzeForm(_ source: ByteSource, options: AnalysisOptions = .preview) throws -> FormFileInfo {
        guard source.size <= 4 * 1024 * 1024 else { throw FormError.limit("Form exceeds 4 MiB.") }
        var data = try source.read(at: 0, length: Int(source.size))
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { data.removeFirst(3) }
        var parser = try FormJSONParser(data)
        let original = try parser.parse()
        guard case .object = original else { throw FormError.invalid("Root must be an object.") }
        let url = source.url.standardizedFileURL.resolvingSymlinksInPath()
        let dependencies = FormDependencies(formURL: url)
        let resolved = try FormPointerResolver(dependencies: dependencies).resolve(original, document: url)
        if let scheme = resolved["colorScheme"], scheme.string != "light" && scheme.string != "dark" {
            throw FormError.invalid("colorScheme must be light or dark.")
        }
        let expansion = FormStaticExpansion(dependencies: dependencies)
        let rawPages = try expansion.expand(resolved, document: url)
        var stylesheet = FormStylesheet(dependencies: dependencies)
        if let sources = dependencies.sources {
            if !FileManager.default.isReadableFile(atPath: sources.path) {
                dependencies.warn("Project stylesheets are inaccessible. Quick Look may grant access only to the selected form.")
            }
            for name in ["styleSheets.css", "styleSheets_mac.css"] {
                let cssURL = sources.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: cssURL.path) {
                    try loadCSS(cssURL, stylesheet: &stylesheet, dependencies: dependencies)
                }
            }
        }
        var stylesheets: [String: FormStylesheet] = [:]
        func usedContexts(_ objects: [FormObject]) -> Set<String> {
            objects.reduce(into: Set<String>()) { result, object in
                if let key = object.stylesheetContext { result.insert(key) }
                result.formUnion(usedContexts(object.children))
            }
        }
        var contextKeys = usedContexts(rawPages.flatMap(\.objects))
        contextKeys.insert(String(url.path.dropFirst(dependencies.root.path.count + 1)))
        for key in contextKeys.sorted() {
            var formStylesheet = stylesheet
            try loadFormCSS(expansion.contexts[key]!, stylesheet: &formStylesheet, dependencies: dependencies, document: url)
            stylesheets[key] = formStylesheet
        }
        func styledCount(_ objects: [FormObject]) -> Int {
            objects.reduce(0) { count, object in
                count + 1 + styledCount(object.children) +
                (object.properties["columns"]?.values.reduce(0) { $0 + 1 + ($1["header"] == nil ? 0 : 1) + ($1["footer"] == nil ? 0 : 1) } ?? 0)
            }
        }
        let count = styledCount(rawPages.flatMap(\.objects))
        guard count * max(1, stylesheets.values.map { $0.rules.count }.max() ?? 0) * 4 <= 1_000_000 else {
            throw FormError.limit("Form/CSS combination exceeds 1,000,000 rule matches.")
        }
        let imageLoader = FormImageLoader(dependencies: dependencies, document: url)
        let localization = FormLocalization(dependencies: dependencies, preferredLanguages: preferredLanguages)
        var appearances: [FormAppearance] = []
        for theme in FormTheme.allCases {
            var remaining = 1_000
            var themedPages: [FormPage] = []
            for page in rawPages.prefix(17) {
                var objects: [FormObject] = []
                for object in page.objects.prefix(remaining) {
                    var styled = object
                    styled = try style(object, theme: theme, form: resolved, stylesheets: stylesheets,
                                       fallback: stylesheet, localization: localization, imageLoader: imageLoader)
                    objects.append(styled)
                }
                remaining -= objects.count
                themedPages.append(FormPage(number: page.number, objects: objects))
            }
            appearances.append(FormAppearance(theme: theme, pages: themedPages))
        }
        let conventional = url.lastPathComponent.lowercased() == "form.4dform"
        var info = FormFileInfo(fileName: url.lastPathComponent,
                            formName: resolved["name"]?.string ?? (conventional ? url.deletingLastPathComponent().lastPathComponent : url.deletingPathExtension().lastPathComponent),
                            text: String(decoding: data, as: UTF8.self), properties: localization.localize(resolved, source: nil),
                            appearances: appearances, images: imageLoader.images,
                            dependencies: dependencies.loadedPaths, warnings: dependencies.warnings)
        info.localizationLanguage = localization.language
        return info
    }

    private func style(_ object: FormObject, theme: FormTheme, form: FormValue,
                       stylesheets: [String: FormStylesheet], fallback: FormStylesheet,
                       localization: FormLocalization, imageLoader: FormImageLoader,
                       visible: Bool = true) throws -> FormObject {
        let effectiveTheme: FormTheme
        if form["colorScheme"]?.string == "dark" { effectiveTheme = theme.glass ? .glassDark : .classicDark }
        else if form["colorScheme"]?.string == "light" { effectiveTheme = theme.glass ? .glassLight : .classicLight }
        else { effectiveTheme = theme }
        let stylesheet = object.stylesheetContext.flatMap { stylesheets[$0] } ?? fallback
        var styled = object
        styled.properties = stylesheet.apply(object.properties, name: object.name, type: object.type, theme: effectiveTheme)
        if case .array(let columns) = styled.properties["columns"] {
            styled.properties["columns"] = .array(columns.map { column in
                var result = stylesheet.apply(column, name: column["name"]?.string ?? "", type: "column", theme: effectiveTheme)
                for child in ["header", "footer"] {
                    if let definition = column[child] {
                        result[child] = stylesheet.apply(definition, name: definition["name"]?.string ?? "", type: child, theme: effectiveTheme)
                    }
                }
                return result
            })
        }
        styled.properties = localization.localize(styled.properties, source: object.source, name: object.name)
        let visible = visible && styled.properties["visibility"]?.string != "hidden" && styled.properties["display"]?.bool != false
        if visible {
            for property in ["picture", "icon", "customBackgroundPicture"] {
                if let path = styled.properties[property]?.string,
                   let id = try imageLoader.load(path, dark: effectiveTheme.dark) { styled.images[property] = id }
            }
        }
        if let embedded = styled.embeddedProperties {
            var childForm = embedded
            if let scheme = embedded["colorScheme"], scheme.string != "light" && scheme.string != "dark" {
                imageLoader.dependencies.warn("Subform colorScheme is invalid; inheriting the parent preview theme.")
                childForm["colorScheme"] = form["colorScheme"]
            } else if embedded["colorScheme"] == nil { childForm["colorScheme"] = form["colorScheme"] }
            styled.children = try styled.children.map {
                try style($0, theme: effectiveTheme, form: childForm, stylesheets: stylesheets,
                          fallback: stylesheet, localization: localization, imageLoader: imageLoader, visible: visible)
            }
        }
        return styled
    }

    private func loadFormCSS(_ form: FormValue, stylesheet: inout FormStylesheet,
                             dependencies: FormDependencies, document: URL) throws {
        guard let css = form["css"] else { return }
        let entries: [FormValue]
        if case .array(let list) = css { entries = list } else { entries = [css] }
        for entry in entries {
            if entry["media"]?.string == "windows" { continue }
            guard let path = entry.string ?? entry["path"]?.string else {
                dependencies.warn("Invalid form CSS reference.")
                continue
            }
            do { try loadCSS(dependencies.url(path, relativeTo: document), stylesheet: &stylesheet, dependencies: dependencies) }
            catch let error as FormError {
                if case .limit = error { throw error }
                dependencies.warn("Stylesheet \(path): \(error)")
            } catch { dependencies.warn("Stylesheet \(path): \(error)") }
        }
    }

    private func loadCSS(_ url: URL, stylesheet: inout FormStylesheet, dependencies: FormDependencies) throws {
        do {
            let data = try dependencies.read(url)
            guard let text = String(data: data, encoding: .utf8) else { throw FormError.dependency("CSS is not UTF-8.") }
            try stylesheet.append(text, document: url)
        } catch let error as FormError {
            if case .limit = error { throw error }
            dependencies.warn("Stylesheet \(url.lastPathComponent): \(error)")
        } catch { dependencies.warn("Stylesheet \(url.lastPathComponent): \(error)") }
    }
}

private final class FormImageLoader {
    let dependencies: FormDependencies
    let document: URL
    private(set) var images: [FormImage] = []
    private var loaded: [URL: String] = [:]
    private var failed = Set<String>()
    private var encodedBytes = 0

    init(dependencies: FormDependencies, document: URL) {
        self.dependencies = dependencies
        self.document = document
    }

    func load(_ path: String, dark: Bool) throws -> String? {
        let key = "\(dark):\(path)"
        if failed.contains(key) { return nil }
        do {
            var url = try dependencies.url(path, relativeTo: document)
            if dark {
                let darkPath = url.deletingPathExtension().lastPathComponent + "_dark." + url.pathExtension
                let candidate = url.deletingLastPathComponent().appendingPathComponent(darkPath)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    url = try dependencies.url(String(candidate.path.dropFirst(dependencies.root.path.count + 1)), relativeTo: dependencies.root.appendingPathComponent("file"))
                }
            }
            if let id = loaded[url] { return id }
            guard images.count < 64 else { throw FormError.limit("64 preview images exceeded.") }
            let data = try dependencies.read(url)
            let image: FormImage
            let id = "form-image-\(images.count)"
            if url.pathExtension.lowercased() == "svg" {
                let validator = FormSVGValidator()
                let parser = XMLParser(data: data)
                parser.shouldResolveExternalEntities = false
                parser.delegate = validator
                let text = String(decoding: data, as: UTF8.self)
                guard data.count <= 512 * 1024, !text.contains("<!DOCTYPE"), parser.parse(), validator.safe else {
                    throw FormError.dependency("SVG has unsupported external/active content or invalid XML.")
                }
                image = FormImage(id: id, dataURI: "data:image/svg+xml;base64," + data.base64EncodedString(),
                                  width: validator.width, height: validator.height)
            } else {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                      let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
                      width.doubleValue > 0, height.doubleValue > 0,
                      width.doubleValue * height.doubleValue <= 32_000_000,
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 2_048
                      ] as CFDictionary) else { throw FormError.dependency("Unsupported image or image exceeds 32 megapixels.") }
                let output = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
                    throw FormError.dependency("Cannot create preview image.")
                }
                CGImageDestinationAddImage(destination, thumbnail, nil)
                guard CGImageDestinationFinalize(destination) else { throw FormError.dependency("Cannot encode preview image.") }
                guard output.length <= 4 * 1024 * 1024 else { throw FormError.limit("Converted image exceeds 4 MiB.") }
                image = FormImage(id: id, dataURI: "data:image/png;base64," + (output as Data).base64EncodedString(),
                                  width: width.doubleValue, height: height.doubleValue)
            }
            encodedBytes += image.dataURI.utf8.count
            guard encodedBytes <= 24 * 1024 * 1024 else { throw FormError.limit("Embedded preview images exceed 24 MiB.") }
            images.append(image)
            loaded[url] = id
            return id
        } catch let error as FormError {
            if case .limit = error { throw error }
            dependencies.warn("Picture \(path): \(error)")
        } catch { dependencies.warn("Picture \(path): \(error)") }
        failed.insert(key)
        return nil
    }
}

private final class FormSVGValidator: NSObject, XMLParserDelegate {
    var safe = true
    var width: Double = 100
    var height: Double = 100
    private var count = 0
    private var depth = 0
    private var foundRoot = false
    private let elements: Set<String> = ["svg", "g", "defs", "path", "rect", "circle", "ellipse", "line", "polyline", "polygon",
                                          "text", "tspan", "title", "desc", "use", "symbol", "clipPath", "mask", "linearGradient",
                                          "radialGradient", "stop"]

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String]) {
        count += 1
        depth += 1
        if !foundRoot {
            foundRoot = true
            if elementName != "svg" { safe = false }
            if let w = attributes["width"].flatMap(Double.init), let h = attributes["height"].flatMap(Double.init), w > 0, h > 0, w.isFinite, h.isFinite {
                width = min(w, 32_768); height = min(h, 32_768)
            } else if let viewBox = attributes["viewBox"] {
                let parts = viewBox.split { $0.isWhitespace || $0 == "," }.compactMap { Double($0) }
                if parts.count == 4, parts[2] > 0, parts[3] > 0, parts.allSatisfy(\.isFinite) {
                    width = min(parts[2], 32_768); height = min(parts[3], 32_768)
                }
            }
        }
        if !elements.contains(elementName) || count > 20_000 || depth > 64 { safe = false }
        for (key, value) in attributes {
            if key.lowercased().hasPrefix("on") { safe = false }
            if key == "href" || key == "xlink:href", !value.hasPrefix("#") { safe = false }
            if value.lowercased().contains("url(") {
                let stripped = value.replacingOccurrences(of: #"url\(\s*['"]?#[-\w]+['"]?\s*\)"#, with: "", options: .regularExpression)
                if stripped.lowercased().contains("url(") { safe = false }
            }
            if key == "style", value.contains("@") { safe = false }
        }
        if !safe { parser.abortParsing() }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { depth -= 1 }
    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) { safe = false; parser.abortParsing() }
    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) { safe = false; parser.abortParsing() }
}
