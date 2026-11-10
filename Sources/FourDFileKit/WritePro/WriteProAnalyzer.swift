import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// One node of the XHTML saved by 4D Write Pro. Text is a node named
/// `#text` so mixed content keeps its order.
public struct WriteProNode: Encodable {
    public var name: String
    public var attributes: [String: String]
    public var text: String
    public var children: [WriteProNode]

    public init(name: String, attributes: [String: String] = [:], text: String = "", children: [WriteProNode] = []) {
        self.name = name
        self.attributes = attributes
        self.text = text
        self.children = children
    }

    public var isText: Bool { name == "#text" }
    public var classes: [String] { (attributes["class"] ?? "").split(whereSeparator: \.isWhitespace).map(String.init) }

    public func first(_ element: String) -> WriteProNode? {
        if name == element { return self }
        for child in children { if let found = child.first(element) { return found } }
        return nil
    }

    /// Concatenated text of this subtree.
    public var textContent: String { isText ? text : children.map(\.textContent).joined() }
}

public struct WriteProDeclaration: Encodable, Equatable {
    public var name: String
    public var value: String
    public init(_ name: String, _ value: String) { self.name = name; self.value = value }
}

/// `tag`, `.class` or `tag.class`: the only selector forms 4D writes.
public struct WriteProSelector: Encodable, Equatable {
    public var tag: String?
    public var className: String?
    public var specificity: Int { (className == nil ? 0 : 10) + (tag == nil ? 0 : 1) }

    public init(tag: String?, className: String?) {
        self.tag = tag
        self.className = className
    }

    public func matches(tag element: String, classes: [String]) -> Bool {
        if let tag, tag != element { return false }
        if let className, !classes.contains(className) { return false }
        return tag != nil || className != nil
    }
}

public struct WriteProStyleRule: Encodable {
    public var selectorText: String
    public var selectors: [WriteProSelector]
    public var declarations: [WriteProDeclaration]
}

/// A tolerant parser for the CSS subset 4D Write Pro writes.
public enum WriteProCSS {
    public static func rules(_ css: String) -> [WriteProStyleRule] {
        let text = stripComments(css)
        var rules: [WriteProStyleRule] = []
        var index = text.startIndex
        while index < text.endIndex, rules.count < 20_000 {
            guard let open = scan(text, from: index, for: "{") else { break }
            let selectorText = text[index..<open].trimmingCharacters(in: .whitespacesAndNewlines)
            let bodyStart = text.index(after: open)
            let close = scan(text, from: bodyStart, for: "}") ?? text.endIndex
            if !selectorText.hasPrefix("@") {
                let selectors = selectorText.split(separator: ",").compactMap { selector($0.trimmingCharacters(in: .whitespaces)) }
                if !selectors.isEmpty {
                    rules.append(WriteProStyleRule(selectorText: selectorText, selectors: selectors,
                                                   declarations: declarations(String(text[bodyStart..<close]))))
                }
            }
            index = close < text.endIndex ? text.index(after: close) : close
        }
        return rules
    }

    static func selector(_ text: String) -> WriteProSelector? {
        guard !text.isEmpty, text.unicodeScalars.allSatisfy({
            CharacterSet.alphanumerics.contains($0) || "-_.".unicodeScalars.contains($0)
        }) else { return nil }
        let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 1 { return WriteProSelector(tag: text.lowercased(), className: nil) }
        let className = String(parts[1])
        guard !className.isEmpty, !className.contains(".") else { return nil }
        return WriteProSelector(tag: parts[0].isEmpty ? nil : parts[0].lowercased(), className: className)
    }

    /// Splits `a:b;c:d` at semicolons outside quotes and parentheses.
    public static func declarations(_ text: String) -> [WriteProDeclaration] {
        var result: [WriteProDeclaration] = []
        var current = ""
        var quote: Character?
        var depth = 0
        func flush() {
            if let colon = current.firstIndex(of: ":") {
                let name = current[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let value = current[current.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty, !value.isEmpty { result.append(WriteProDeclaration(name, value)) }
            }
            current = ""
        }
        for ch in text {
            if let q = quote {
                if ch == q { quote = nil }
            } else if ch == "'" || ch == "\"" {
                quote = ch
            } else if ch == "(" {
                depth += 1
            } else if ch == ")" {
                depth = max(0, depth - 1)
            } else if ch == ";" && depth == 0 {
                flush()
                continue
            }
            current.append(ch)
        }
        flush()
        return result
    }

    /// Splits a value at spaces, keeping quoted strings and functions whole.
    public static func components(_ value: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var quote: Character?
        var depth = 0
        for ch in value {
            if let q = quote {
                current.append(ch)
                if ch == q { quote = nil }
                continue
            }
            if ch == "'" || ch == "\"" { quote = ch }
            if ch == "(" { depth += 1 }
            if ch == ")" { depth = max(0, depth - 1) }
            if ch.isWhitespace && depth == 0 {
                if !current.isEmpty { parts.append(current); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }

    /// Removes one level of CSS string quotes and decodes HTML-escaped quotes.
    public static func unquote(_ value: String) -> String {
        var v = value.trimmingCharacters(in: .whitespaces)
        if v.count >= 2, let f = v.first, let l = v.last, f == l, f == "'" || f == "\"" {
            v = String(v.dropFirst().dropLast())
        }
        return v.replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func scan(_ text: String, from start: String.Index, for target: Character) -> String.Index? {
        var quote: Character?
        var index = start
        while index < text.endIndex {
            let ch = text[index]
            if let q = quote { if ch == q { quote = nil } }
            else if ch == "'" || ch == "\"" { quote = ch }
            else if ch == target { return index }
            index = text.index(after: index)
        }
        return nil
    }

    private static func stripComments(_ css: String) -> String {
        guard css.contains("/*") else { return css }
        var out = ""
        var rest = Substring(css)
        while let open = rest.range(of: "/*") {
            out += rest[..<open.lowerBound]
            guard let close = rest[open.upperBound...].range(of: "*/") else { return out }
            rest = rest[close.upperBound...]
        }
        return out + rest
    }
}

/// The analysed contents of a `.4wp` archive (or of bare 4D Write Pro XHTML).
public struct WriteProFileInfo: AnalysisModel {
    public let kind = "4d.writepro"
    public var fileName: String
    /// Name of the XHTML entry inside the archive; nil for a bare XHTML file.
    public var htmlEntry: String?
    public var archiveEntries: [String]
    public var title: String
    public var metadata: [WriteProDeclaration]
    /// Bookmark name -> [start, end] character offsets.
    public var bookmarks: [String: [Int]]
    /// Decoded `-d4-custom` user attributes (JSON text), when present.
    public var customAttributes: String?
    public var version: String?
    public var rules: [WriteProStyleRule]
    public var body: WriteProNode
    /// Archive images by entry name, as data URIs.
    public var resources: [String: String]
    public var html: String
    public var warnings: [String]

    /// Cascaded declarations from the document style sheet, lowest precedence first.
    public func declarations(tag: String, classes: [String]) -> [WriteProDeclaration] {
        let matching = rules.enumerated().compactMap { index, rule -> (Int, Int, [WriteProDeclaration])? in
            let best = rule.selectors.filter { $0.matches(tag: tag, classes: classes) }.map(\.specificity).max()
            return best.map { ($0, index, rule.declarations) }
        }
        return matching.sorted { ($0.0, $0.1) < ($1.0, $1.1) }.flatMap(\.2)
    }

    /// Declarations of rules addressed by an exact selector, e.g. `div.section0`.
    public func rule(tag: String, className: String) -> [WriteProDeclaration] {
        rules.filter { $0.selectors.contains(WriteProSelector(tag: tag, className: className)) }.flatMap(\.declarations)
    }

    public func hasClass(_ className: String) -> Bool {
        rules.contains { $0.selectors.contains { $0.className == className } }
    }

    /// Resolves an `<img src>` or CSS `url()` value to something a sandboxed preview may display.
    public func imageSource(_ raw: String) -> WriteProImageSource {
        let src = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if src.isEmpty { return .unavailable("empty source") }
        let lower = src.lowercased()
        if lower.hasPrefix("data:") { return Self.dataImage(src) }
        if lower.hasPrefix("http:") || lower.hasPrefix("https:") || lower.hasPrefix("ftp:") { return .remote(src) }
        if lower.contains(":") { return .unavailable("unsupported URL scheme") }
        var path = src.removingPercentEncoding ?? src
        while path.hasPrefix("./") { path.removeFirst(2) }
        if let uri = resources[path] { return .data(uri) }
        if let key = resources.keys.sorted().first(where: { $0.hasSuffix("/" + path) }) { return .data(resources[key]!) }
        return .unavailable("archive entry \(path) not found")
    }

    static let displayableImageTypes: Set<String> = [
        "image/png", "image/jpeg", "image/jpg", "image/gif", "image/bmp", "image/tiff", "image/webp", "image/svg+xml", "image/heic", "image/x-icon"
    ]

    static func dataImage(_ uri: String) -> WriteProImageSource {
        guard let comma = uri.firstIndex(of: ",") else { return .unavailable("malformed data URI") }
        let header = uri[uri.index(uri.startIndex, offsetBy: 5)..<comma].lowercased()
        let parts = header.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.contains("base64"), let mime = parts.first else { return .unavailable("data URI is not base64") }
        let payload = uri[uri.index(after: comma)...].filter { !$0.isWhitespace }
        guard payload.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "/" || $0 == "=") }) else {
            return .unavailable("data URI payload is not base64")
        }
        if displayableImageTypes.contains(mime) { return .data("data:\(mime);base64,\(payload)") }
        if mime == "application/4dpicture", let data = Data(base64Encoded: String(payload)),
           let embedded = embeddedImage(in: data) {
            return .data(embedded)
        }
        return .unavailable(mime)
    }

    /// 4D picture containers (`TCP4…`) wrap a standard codec stream; preview the first one found.
    static func embeddedImage(in data: Data) -> String? {
        let signatures: [([UInt8], String)] = [([0x89, 0x50, 0x4E, 0x47], "image/png"), ([0xFF, 0xD8, 0xFF], "image/jpeg"),
                                               ([0x47, 0x49, 0x46, 0x38], "image/gif"), ([0x49, 0x49, 0x2A, 0x00], "image/tiff"),
                                               ([0x4D, 0x4D, 0x00, 0x2A], "image/tiff")]
        let bytes = [UInt8](data)
        var best: (Int, String)?
        for (signature, mime) in signatures {
            guard bytes.count >= signature.count else { continue }
            for index in 0...(bytes.count - signature.count) where bytes[index] == signature[0] {
                if Array(bytes[index..<(index + signature.count)]) == signature {
                    if best == nil || index < best!.0 { best = (index, mime) }
                    break
                }
            }
        }
        guard let (offset, mime) = best else { return nil }
        return "data:\(mime);base64,\(Data(bytes[offset...]).base64EncodedString())"
    }
}

public enum WriteProImageSource: Equatable {
    case data(String)
    case remote(String)
    case unavailable(String)
}

public enum WriteProError: Error, CustomStringConvertible {
    case invalid(String)
    public var description: String {
        switch self { case .invalid(let message): return "Invalid 4D Write Pro document: \(message)" }
    }
}

public struct WriteProFileAnalyzer: FileAnalyzer {
    public static let maxHTMLBytes = 48 * 1024 * 1024
    public static let maxResourceBytes = 16 * 1024 * 1024
    public static let maxTotalResourceBytes = 48 * 1024 * 1024

    public init() {}
    public var identifier: String { "4wp" }
    public var contentTypes: [String] { ["com.4d.4d.WriteProDocument"] }
    public var filenameExtensions: [String] { ["4wp"] }

    public func canAnalyze(_ source: ByteSource) -> Bool {
        if ZipArchive.looksLikeZip(source) { return true }
        guard let head = try? source.readAvailable(at: 0, length: 512) else { return false }
        return String(decoding: head, as: UTF8.self).lowercased().contains("<html")
    }

    public func analyze(_ source: ByteSource, options: AnalysisOptions) throws -> AnalysisModel {
        var warnings: [String] = []
        var resources: [String: String] = [:]
        var entries: [String] = []
        var htmlEntry: String?
        let data: Data
        if ZipArchive.looksLikeZip(source) {
            let zip = try ZipArchive(source)
            entries = zip.entries.map(\.name)
            let pages = zip.entries.filter {
                !$0.isDirectory && ["html", "htm", "xhtml"].contains(Self.pathExtension($0.name))
            }
            guard let page = pages.min(by: {
                ($0.name.split(separator: "/").count, $0.name) < ($1.name.split(separator: "/").count, $1.name)
            }) else { throw WriteProError.invalid("the archive contains no XHTML document") }
            htmlEntry = page.name
            data = try zip.data(for: page, limit: Self.maxHTMLBytes)
            var total = 0
            for entry in zip.entries where !entry.isDirectory && entry.name != page.name {
                guard let mime = Self.imageType(Self.pathExtension(entry.name)) else { continue }
                guard entry.uncompressedSize <= Self.maxResourceBytes,
                      total + entry.uncompressedSize <= Self.maxTotalResourceBytes else {
                    warnings.append("Archive image \(entry.name) was skipped because it exceeds the preview size budget.")
                    continue
                }
                do {
                    let bytes = try zip.data(for: entry, limit: Self.maxResourceBytes)
                    total += bytes.count
                    resources[entry.name] = "data:\(mime);base64,\(bytes.base64EncodedString())"
                } catch {
                    warnings.append("Archive image \(entry.name) could not be read: \(error)")
                }
            }
        } else {
            guard source.size <= Int64(Self.maxHTMLBytes) else {
                throw WriteProError.invalid("XHTML exceeds \(Self.maxHTMLBytes / 1_048_576) MiB")
            }
            data = try source.read(at: 0, length: Int(source.size))
        }
        var info = try Self.parse(data, fileName: source.url.lastPathComponent)
        info.htmlEntry = htmlEntry
        info.archiveEntries = entries
        info.resources = resources
        info.warnings = warnings + info.warnings
        let formulaStreams = entries.filter { $0.lowercased().hasSuffix(".4dfo") }.count
        if formulaStreams > 0 {
            info.warnings.append("\(formulaStreams) compiled formula stream(s) (.4dfo) are shown by reference only; their source is not decoded.")
        }
        return info
    }

    static func pathExtension(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), !name[dot...].contains("/") else { return "" }
        return name[name.index(after: dot)...].lowercased()
    }

    public static func imageType(_ ext: String) -> String? {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "bmp": return "image/bmp"
        case "tif", "tiff": return "image/tiff"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "heic": return "image/heic"
        default: return nil
        }
    }

    /// Parses 4D Write Pro XHTML. Public so tests can feed authored XHTML directly.
    public static func parse(_ data: Data, fileName: String) throws -> WriteProFileInfo {
        guard var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            throw WriteProError.invalid("XHTML must be UTF-8 or UTF-16")
        }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        guard !text.contains("<!ENTITY") else { throw WriteProError.invalid("custom XML entities are not supported") }
        let source = text
        // XHTML may use HTML named entities that an XML parser rejects.
        if text.contains("&") {
            for (name, value) in Self.htmlEntities { text = text.replacingOccurrences(of: "&\(name);", with: value) }
        }
        let parser = XMLParser(data: Data(text.utf8))
        let tree = MixedContentTree()
        parser.delegate = tree
        parser.shouldResolveExternalEntities = XMLParser.reportsExternalEntitiesSafely
        parser.externalEntityResolvingPolicy = .never
        let parsed = parser.parseStrictly()
        if let failure = tree.failure { throw WriteProError.invalid(failure) }
        guard parsed, let root = tree.root else {
            throw WriteProError.invalid("XHTML is not well-formed" + (parser.parserError.map { " (\($0.localizedDescription))" } ?? ""))
        }
        guard root.name == "html" else { throw WriteProError.invalid("root element is <\(root.name)>, not <html>") }
        let head = root.children.first { $0.name == "head" }
        let body = root.children.first { $0.name == "body" } ?? WriteProNode(name: "body")
        let css = head?.children.filter { $0.name == "style" }.map(\.textContent).joined(separator: "\n") ?? ""
        let rules = WriteProCSS.rules(css)
        var metadata: [WriteProDeclaration] = []
        var bookmarks: [String: [Int]] = [:]
        var warnings: [String] = []
        for meta in head?.children.filter({ $0.name == "meta" }) ?? [] {
            guard let name = meta.attributes["name"], let content = meta.attributes["content"] else { continue }
            if name == "bookmarks" {
                if let json = try? JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: [Any]] {
                    for (key, range) in json { bookmarks[key] = range.compactMap { ($0 as? NSNumber)?.intValue } }
                } else {
                    warnings.append("Bookmark metadata is not valid JSON.")
                }
            } else {
                metadata.append(WriteProDeclaration(name, content))
            }
        }
        let bodyRule = rules.filter { $0.selectors.contains(WriteProSelector(tag: "body", className: nil)) }.flatMap(\.declarations)
        var custom: String?
        if let encoded = bodyRule.last(where: { $0.name == "-d4-custom" }).map({ WriteProCSS.unquote($0.value) }),
           let decoded = Data(base64Encoded: encoded) {
            custom = String(data: decoded, encoding: .utf8)
        }
        let title = head?.children.first { $0.name == "title" }?.textContent.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return WriteProFileInfo(fileName: fileName, htmlEntry: nil, archiveEntries: [], title: title, metadata: metadata,
                                bookmarks: bookmarks, customAttributes: custom,
                                version: bodyRule.last(where: { $0.name == "-d4-version" })?.value,
                                rules: rules, body: body, resources: [:], html: source, warnings: warnings)
    }

    private static let htmlEntities: [(String, String)] = [
        ("nbsp", "\u{00A0}"), ("ensp", "\u{2002}"), ("emsp", "\u{2003}"), ("thinsp", "\u{2009}"),
        ("shy", "\u{00AD}"), ("copy", "©"), ("reg", "®"), ("trade", "™"),
        ("hellip", "…"), ("mdash", "—"), ("ndash", "–"), ("lsquo", "‘"), ("rsquo", "’"),
        ("ldquo", "“"), ("rdquo", "”"), ("laquo", "«"), ("raquo", "»"), ("bull", "•"),
        ("euro", "€"), ("pound", "£"), ("yen", "¥"), ("deg", "°"), ("middot", "·"), ("times", "×"),
    ]
}

/// Builds a node tree that keeps text and element children in document order.
private final class MixedContentTree: NSObject, XMLParserDelegate {
    var root: WriteProNode?
    var failure: String?
    private var stack: [WriteProNode] = []
    private var count = 0

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        guard failure == nil else { return }
        count += 1
        guard count <= 250_000, stack.count < 64 else {
            failure = "XHTML exceeds the element or nesting limit"
            parser.stopFromDelegate()
            return
        }
        let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
        stack.append(WriteProNode(name: local.lowercased(), attributes: attributeDict))
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { append(string) }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { append(String(decoding: CDATABlock, as: UTF8.self)) }

    private func append(_ string: String) {
        guard failure == nil, !stack.isEmpty else { return }
        let top = stack.count - 1
        if let last = stack[top].children.last, last.isText {
            stack[top].children[stack[top].children.count - 1].text += string
        } else {
            stack[top].children.append(WriteProNode(name: "#text", text: string))
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard failure == nil, let node = stack.popLast() else { return }
        if stack.isEmpty { root = node } else { stack[stack.count - 1].children.append(node) }
    }

    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) { reject(parser) }
    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) { reject(parser) }
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? { reject(parser); return nil }

    private func reject(_ parser: XMLParser) {
        failure = "custom XML entities are not supported"
        parser.stopFromDelegate()
    }
}
