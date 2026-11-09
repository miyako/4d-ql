import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct LabelObject: Encodable {
    public var type: String
    public var attributes: [String: String]
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var image: FormImage?
}

public struct LabelLayout: Encodable {
    public var width: Double
    public var height: Double
    public var columns: Int
    public var rows: Int
    public var start: Int
    public var copies: Int
    public var left: Double
    public var top: Double
    public var right: Double
    public var bottom: Double
    public var horizontalGap: Double
    public var verticalGap: Double
    public var vertical: Bool
    public var landscape: Bool
    public var unit: String
    public var sheetWidth: Double { left + Double(columns) * width + Double(columns - 1) * horizontalGap + right }
    public var sheetHeight: Double { top + Double(rows) * height + Double(rows - 1) * verticalGap + bottom }
}

public struct LabelFileInfo: AnalysisModel {
    public let kind = "4d.label"
    public var fileName: String
    public var text: String
    public var root: XMLFileNode
    public var layout: LabelLayout
    public var objects: [LabelObject]
    public var form: FormFileInfo?
    public var warnings: [String]
}

public enum LabelError: Error, CustomStringConvertible {
    case invalid(String)
    public var description: String {
        switch self { case .invalid(let message): return "Invalid 4D label: \(message)" }
    }
}

public struct LabelFileAnalyzer: FileAnalyzer {
    public init() {}
    public var identifier: String { "4lbp" }
    public var contentTypes: [String] { ["com.4d.4d.labelFile"] }
    public var filenameExtensions: [String] { ["4lbp"] }

    public func analyze(_ source: ByteSource, options: AnalysisOptions) throws -> AnalysisModel {
        guard source.size <= 4 * 1024 * 1024 else { throw LabelError.invalid("XML exceeds 4 MiB.") }
        let data = try source.read(at: 0, length: Int(source.size))
        let encoding: String.Encoding
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) { encoding = .utf16 }
        else if data.starts(with: [0, 60]) { encoding = .utf16BigEndian }
        else if data.starts(with: [60, 0]) { encoding = .utf16LittleEndian }
        else { encoding = .utf8 }
        guard let text = String(data: data, encoding: encoding) else {
            throw LabelError.invalid("XML source must use UTF-8 or UTF-16.")
        }
        guard !text.contains("<!ENTITY") else {
            throw LabelError.invalid("Custom XML entities are not supported.")
        }
        let parser = XMLParser(data: data)
        let document = BoundedXMLDocument()
        parser.delegate = document
        parser.shouldResolveExternalEntities = XMLParser.reportsExternalEntitiesSafely
        parser.externalEntityResolvingPolicy = .never
        let parsed = parser.parseStrictly()
        if let failure = document.failure { throw LabelError.invalid(failure) }
        guard parsed, let root = document.root, root.name == "label" else {
            throw LabelError.invalid("Expected a complete <label> XML document; binary .4lb files are not supported.")
        }
        var warnings: [String] = []
        func child(_ name: String) throws -> [String: String] {
            let nodes = root.children.filter { $0.name == name }
            guard nodes.count <= 1 else { throw LabelError.invalid("Duplicate <\(name)> element.") }
            return nodes.first?.attributes ?? [:]
        }
        func number(_ attributes: [String: String], _ key: String, _ fallback: Double,
                    range: ClosedRange<Double> = 0...8_192) throws -> Double {
            guard let text = attributes[key] else { return fallback }
            guard let value = Double(text), value.isFinite, range.contains(value) else {
                throw LabelError.invalid("\(key) must be a finite number in \(range).")
            }
            return value
        }
        func count(_ attributes: [String: String], _ key: String, _ fallback: Int, maximum: Int) throws -> Int {
            let value = try number(attributes, key, Double(fallback), range: 1...Double(maximum))
            guard value.rounded() == value else { throw LabelError.invalid("\(key) must be an integer.") }
            return Int(value)
        }
        func boolean(_ attributes: [String: String], _ key: String, _ fallback: Bool = false) throws -> Bool {
            guard let text = attributes[key] else { return fallback }
            guard ["true", "false"].contains(text) else { throw LabelError.invalid("\(key) must be true or false.") }
            return text == "true"
        }
        let size = try child("size"), margin = try child("margin"), gap = try child("gap")
        let setting = try child("setting"), formReference = try child("form")
        let version = try count(root.attributes, "version", 1, maximum: 2)
        let layout = LabelLayout(
            width: try number(size, "width", 255, range: 1...8_192),
            height: try number(size, "height", 113, range: 1...8_192),
            columns: try count(root.attributes, "columns", 2, maximum: 400),
            rows: try count(root.attributes, "rows", 7, maximum: 400),
            start: try count(root.attributes, "start", 1, maximum: 160_000),
            copies: try count(root.attributes, "labels-per-record", 1, maximum: 100_000),
            left: try number(margin, "left", 30), top: try number(margin, "top", 30),
            right: try number(margin, "right", 30), bottom: try number(margin, "bottom", 60),
            horizontalGap: try number(gap, "horizontal", 0), verticalGap: try number(gap, "vertical", 0),
            vertical: try boolean(setting, "vertical"), landscape: try boolean(setting, "landscape"),
            unit: size["unit"] ?? "pt")
        guard layout.columns * layout.rows <= 400,
              layout.sheetWidth <= 8_192, layout.sheetHeight <= 8_192 else {
            throw LabelError.invalid("Sheet exceeds 400 labels or 8,192 points per side.")
        }
        if layout.start > layout.columns * layout.rows {
            warnings.append("Starting position is outside this sheet; no active labels are shown.")
        }
        let containers = root.children.filter { $0.name == "objects" }
        guard containers.count <= 1 else { throw LabelError.invalid("Duplicate <objects> element.") }
        let nodes = containers.first?.children ?? []
        guard nodes.count <= 1_000 else { throw LabelError.invalid("More than 1,000 label objects.") }
        var objects: [LabelObject] = []
        var imageBytes = 0
        for (index, node) in nodes.enumerated() {
            guard node.name == "object" else {
                warnings.append("Unsupported label element <\(node.name)> omitted.")
                continue
            }
            var a = node.attributes
            let type = a["type"] ?? "unknown"
            let left = try number(a, "left", 0, range: -32_768...32_768)
            let top = try number(a, "top", 0, range: -32_768...32_768)
            let right = try number(a, "right", left, range: -32_768...32_768)
            let bottom = try number(a, "bottom", top, range: -32_768...32_768)
            guard right >= left, bottom >= top else { throw LabelError.invalid("Reversed bounds on object \(index + 1).") }
            for key in ["stroke-width", "font-size", "rx", "ry"] {
                _ = try number(a, key, 0)
            }
            for key in ["stroke-opacity", "fill-opacity"] { _ = try number(a, key, 1, range: 0...1) }
            if type == "polyline" {
                let parts = (a["data"] ?? "").split { $0 == "," || $0.isWhitespace }
                let points = parts.compactMap { Double($0) }
                guard points.count == parts.count, points.count >= 4, points.count <= 4_096,
                      points.count % 2 == 0, points.allSatisfy({ $0.isFinite && abs($0) <= 32_768 }) else {
                    throw LabelError.invalid("Polyline \(index + 1) requires 4-4,096 bounded coordinate scalars in pairs.")
                }
            }
            for key in ["stroke-color", "fill-color", "font-color"] {
                if let color = a[key],
                   color.range(of: #"^(?:#[0-9a-fA-F]{3,8}|[A-Za-z]+|rgba?\(\s*[\d.%]+\s*,\s*[\d.%]+\s*,\s*[\d.%]+(?:\s*,\s*[\d.]+)?\s*\))$"#, options: .regularExpression) == nil {
                    warnings.append("Object \(index + 1) has an unsupported \(key); a safe default is used.")
                }
            }
            if (a["value"]?.utf16.count ?? 0) > 4_096 {
                warnings.append("Long label text is clipped to 4,096 UTF-16 units and at most 100 lines.")
            }
            if try number(a, "font-size", 12) > 256 {
                warnings.append("Object \(index + 1) font size is limited to 256 points.")
            }
            if type == "variable", a["field-type"] == "3" {
                warnings.append("Picture fields are not loaded; their saved expressions are shown.")
            }
            if version == 1, type == "round-rect" { a["rx"] = "6"; a["ry"] = "6" }
            var image: FormImage?
            if type == "image", let encoded = a["image-data"], !encoded.isEmpty {
                if let bytes = Data(base64Encoded: encoded.filter { !$0.isWhitespace }) {
                    do {
                        let converted = try FormRasterImage.convert(bytes)
                        imageBytes += converted.png.count
                        guard imageBytes <= 16 * 1024 * 1024 else { throw LabelError.invalid("Embedded images exceed 16 MiB.") }
                        image = FormImage(id: "label-image-\(index)", dataURI: "data:image/png;base64," + converted.png.base64EncodedString(),
                                          width: converted.width, height: converted.height)
                    } catch let error as FormError {
                        warnings.append("Image \(index + 1) omitted: \(error)")
                    }
                } else { warnings.append("Image \(index + 1) has invalid base64 data.") }
            }
            if type == "image", image == nil, a["image-data"]?.isEmpty != false {
                warnings.append("Image \(index + 1) has no embedded picture; external images are not loaded.")
            }
            if !["rect", "round-rect", "oval", "line", "polyline", "text", "variable", "image"].contains(type) {
                warnings.append("Unsupported label object type: \(type).")
            }
            if type == "variable" { warnings.append("Fields and formulas show saved expressions, not record values; they are not evaluated.") }
            objects.append(LabelObject(type: type, attributes: a,
                                       // 4D saves positions in its fixed 348 x 191 editor matrix.
                                       x: left - 237 - (348 - layout.width) / 2,
                                       y: top - 55 - (191 - layout.height) / 2,
                                       width: right - left, height: bottom - top, image: image))
        }
        var form: FormFileInfo?
        if let name = formReference["name"], !name.isEmpty {
            do {
                let url = try Self.formURL(name: name, label: source.url)
                form = try FormFileAnalyzer(platforms: FormPlatform.previewPlatforms).analyzeForm(ByteSource(url: url), options: options)
            } catch {
                warnings.append("Referenced form \(name) could not be loaded: \(error)")
            }
            if try boolean(setting, "auto-width") {
                warnings.append("Automatic form layout depends on the selected printer; the sheet uses the saved rows, columns and dimensions.")
            }
        }
        if let method = try child("method")["name"], !method.isEmpty {
            warnings.append("Label method \(method) is not executed.")
        }
        if !root.children.filter({ !["setting", "size", "margin", "gap", "form", "method", "objects", "selects"].contains($0.name) }).isEmpty {
            warnings.append("Additional saved settings are preserved in the XML but are not rendered.")
        }
        return LabelFileInfo(fileName: source.url.lastPathComponent, text: text,
                             root: root, layout: layout, objects: objects, form: form,
                             warnings: warnings.reduce(into: []) { if !$0.contains($1) { $0.append($1) } })
    }

    private static func formURL(name: String, label: URL) throws -> URL {
        guard !name.contains("/"), !name.contains("\\"), !name.contains("\0"), name != ".", name != ".." else {
            throw LabelError.invalid("Invalid saved form name.")
        }
        let label = label.standardizedFileURL.resolvingSymlinksInPath()
        var folder = label.deletingLastPathComponent()
        var sources: URL?
        for _ in 0..<8 {
            if folder.lastPathComponent == "Sources", folder.deletingLastPathComponent().lastPathComponent == "Project" {
                sources = folder; break
            }
            if folder.lastPathComponent == "Resources" {
                sources = folder.deletingLastPathComponent().appendingPathComponent("Project/Sources"); break
            }
            folder.deleteLastPathComponent()
        }
        guard let sources else { throw LabelError.invalid("No containing Project/Sources or Resources folder; authorize and preview the label within its project.") }
        let root = sources.deletingLastPathComponent().deletingLastPathComponent()
        let tables = sources.appendingPathComponent("TableForms")
        let directories = try FileManager.default.contentsOfDirectory(at: tables, includingPropertiesForKeys: nil)
        guard directories.count <= 64 else { throw LabelError.invalid("More than 64 table-form folders.") }
        let matches = directories.filter { directory in
            FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).appendingPathComponent("form.4DForm").path)
        }.map { $0.appendingPathComponent(name).appendingPathComponent("form.4DForm").resolvingSymlinksInPath() }
        guard matches.count == 1, let match = matches.first, match.path.hasPrefix(root.path + "/") else {
            throw LabelError.invalid("Saved table form is missing, ambiguous or outside the project.")
        }
        return match
    }
}
