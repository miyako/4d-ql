import Foundation

/// 4D XLIFF 1.x static references; never reads application bundles or runs
/// SET DATABASE LOCALIZATION. Locale choice is explicitly a preview context.
final class FormLocalization {
    private let dependencies: FormDependencies
    private let preferredLanguages: [String]
    private var translations: [String: String] = [:]
    private var ambiguous = Set<String>()
    private var priorities: [String: Int] = [:]
    private var loaded = false
    private(set) var language: String?
    private static let regions = Set(Locale.isoRegionCodes.map { $0.lowercased() })
    private static let scripts: Set<String> = ["hant", "hans", "latn", "cyrl"]

    init(dependencies: FormDependencies, preferredLanguages: [String]) {
        self.dependencies = dependencies
        self.preferredLanguages = preferredLanguages
    }

    func localize(_ value: FormValue, source: FormObjectSource?, name: String = "") -> FormValue {
        load()
        var result = value
        for key in ["text", "windowTitle", "tooltip"] {
            guard let text = value[key]?.string else { continue }
            result[key] = .string(translate(text, source: source, name: key == "text" ? name : ""))
        }
        if case .array(let labels) = value["labels"] {
            result["labels"] = .array(labels.map { entry in
                guard let text = entry.string else { return entry }
                return .string(translate(text, source: source, name: ""))
            })
        }
        if case .array(let columns) = value["columns"] {
            result["columns"] = .array(columns.map { column in
                var localized = localize(column, source: source)
                for key in ["header", "footer"] {
                    if let child = column[key] { localized[key] = localize(child, source: source, name: child["name"]?.string ?? "") }
                }
                return localized
            })
        }
        return result
    }

    private func translate(_ text: String, source: FormObjectSource?, name: String) -> String {
        var explicit: String?
        if text.hasPrefix(":xliff:") {
            explicit = "name:" + String(text.dropFirst(7))
        } else if text.range(of: #"^:[0-9]+,[0-9]+$"#, options: .regularExpression) != nil {
            explicit = "id:" + String(text.dropFirst())
        } else if text.hasPrefix(":") && text.range(of: #"^:[0-9]+,"#, options: .regularExpression) != nil {
            dependencies.warn("Unsupported or ambiguous XLIFF numeric reference \(text).")
            return text
        }
        if let explicit {
            if let translation = translations[explicit], !ambiguous.contains(explicit) { return translation }
            dependencies.warn("Unresolved XLIFF reference \(text); original text retained.")
            return text
        }
        if !text.isEmpty, name.hasPrefix(":xliff:") || name.range(of: #"^:[0-9]+,[0-9]+$"#, options: .regularExpression) != nil {
            let key = name.hasPrefix(":xliff:") ? "name:" + String(name.dropFirst(7)) : "id:" + String(name.dropFirst())
            if let translation = translations[key], !ambiguous.contains(key) { return translation }
            dependencies.warn("Unresolved object-name XLIFF reference \(name); original text retained.")
            return text
        }
        guard !text.isEmpty, !name.isEmpty, let source, !source.inline else { return text }
        let table = source.tableName.map { "[\($0)]" } ?? "[ProjectForm]"
        let key = "object:\(table)/\(source.formName)/\(name)"
        return ambiguous.contains(key) ? text : translations[key] ?? text
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let project = dependencies.project else { return }
        let resources = project.deletingLastPathComponent().appendingPathComponent("Resources")
        guard FileManager.default.fileExists(atPath: resources.path) else { return }
        do {
            let confined = try dependencies.url("/RESOURCES", relativeTo: dependencies.formURL)
            let entries = try directory(confined)
            var folders: [String: [URL]] = [:]
            for entry in entries where entry.pathExtension.lowercased() == "lproj" {
                guard let code = Self.code(entry.deletingPathExtension().lastPathComponent) else {
                    dependencies.warn("Unsupported localization folder \(entry.lastPathComponent).")
                    continue
                }
                folders[code, default: []].append(entry)
            }
            guard !folders.isEmpty else { return }
            var candidates: [String] = []
            for preferred in preferredLanguages {
                guard let code = Self.code(preferred) else {
                    dependencies.warn("Unsupported preview locale \(preferred).")
                    continue
                }
                let parts = code.split(separator: "-")
                for count in stride(from: parts.count, through: 1, by: -1) {
                    candidates.append(parts.prefix(count).joined(separator: "-"))
                }
            }
            let preferredMatch = candidates.first { folders[$0] != nil }
            candidates.append("en")
            var selected = candidates.first { folders[$0] != nil }
            if preferredMatch == nil, selected == "en" {
                dependencies.warn("No preferred XLIFF locale; preview uses English fallback without a 4D application-language context.")
            }
            if selected == nil, folders.count == 1 {
                selected = folders.keys.first
                dependencies.warn("No preferred/English XLIFF locale; using the only available locale \(selected!).")
            }
            guard let selected else {
                dependencies.warn("Ambiguous XLIFF fallback locale; 4D application language/Resources enumeration order is unavailable. Original text retained.")
                return
            }
            let matches = folders[selected] ?? []
            let modern = matches.filter {
                $0.deletingPathExtension().lastPathComponent.lowercased().range(
                    of: #"^[a-z]{2}(?:[-_][a-z]{2,4}){0,2}$"#, options: .regularExpression) != nil
            }
            let preferredFolders = modern.isEmpty ? matches : modern
            guard preferredFolders.count == 1 else {
                dependencies.warn("Ambiguous XLIFF locale folders for \(selected); original text retained.")
                return
            }
            language = selected
            let folder = try dependencies.url("/RESOURCES/" + preferredFolders[0].lastPathComponent, relativeTo: dependencies.formURL)
            let files = try directory(folder).filter { ["xlf", "xliff"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for file in files {
                do {
                    let parser = FormXLIFFParser()
                    let units = try parser.parse(dependencies.read(file))
                    for warning in parser.warnings { dependencies.warn("XLIFF \(file.lastPathComponent): \(warning)") }
                    for unit in units {
                        let target = unit.targetLanguage.flatMap(Self.code)
                        let source = unit.sourceLanguage.flatMap(Self.code)
                        func rank(_ locale: String?) -> Int? {
                            guard let locale, locale == selected || selected.hasPrefix(locale + "-") else { return nil }
                            return selected.split(separator: "-").count - locale.split(separator: "-").count
                        }
                        let text: String?
                        let priority: Int
                        if let targetRank = rank(target) {
                            text = unit.target
                            priority = targetRank
                            if text == nil { dependencies.warn("XLIFF \(file.lastPathComponent): missing target for \(unit.name); original text retained.") }
                        } else if let sourceRank = rank(source), unit.target == nil {
                            text = unit.source
                            priority = sourceRank
                        } else {
                            dependencies.warn("XLIFF \(file.lastPathComponent): unsupported/mismatched target-language for \(selected); original text retained.")
                            text = nil
                            priority = 2
                        }
                        guard let text else { continue }
                        var keys: [String] = []
                        if unit.groups.count == 2, unit.groups[0].name.hasPrefix("[") {
                            keys.append("object:\(unit.groups[0].name)/\(unit.groups[1].name)/\(unit.name)")
                        } else if !unit.name.isEmpty { keys.append("name:" + unit.name) }
                        if let group = unit.groups.last?.id, let id = unit.id { keys.append("id:\(group),\(id)") }
                        for key in keys {
                            if let previousPriority = priorities[key], previousPriority < priority { continue }
                            if let previousPriority = priorities[key], previousPriority > priority {
                                translations[key] = text
                                priorities[key] = priority
                                ambiguous.remove(key)
                            } else if let previous = translations[key], previous != text {
                                ambiguous.insert(key)
                            } else { translations[key] = text; priorities[key] = priority }
                        }
                    }
                } catch { dependencies.warn("XLIFF \(file.lastPathComponent): \(error); original text retained.") }
            }
            for key in ambiguous.sorted() { dependencies.warn("Ambiguous XLIFF translation \(key); original text retained.") }
        } catch { dependencies.warn("XLIFF resources: \(error); original text retained.") }
    }

    private func directory(_ url: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil,
                                                               options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]) else {
            throw FormError.dependency("Cannot read localization directory.")
        }
        var entries: [URL] = []
        while let entry = enumerator.nextObject() as? URL {
            guard entries.count < 256 else { throw FormError.limit("Localization directory exceeds 256 entries.") }
            entries.append(entry)
        }
        return entries
    }

    static func code(_ language: String) -> String? {
        let normalized = language.lowercased().replacingOccurrences(of: "_", with: "-")
        let legacy = ["english": "en", "french": "fr", "german": "de", "japanese": "ja", "chinese": "zh",
                      "spanish": "es", "italian": "it", "korean": "ko", "portuguese": "pt", "dutch": "nl",
                      "russian": "ru", "arabic": "ar", "swedish": "sv", "danish": "da", "finnish": "fi",
                      "norwegian": "no", "polish": "pl", "czech": "cs", "turkish": "tr", "greek": "el",
                      "hebrew": "he", "hungarian": "hu"]
        if let code = legacy[normalized] { return code }
        let supported = Set("af sq ar eu be bg ca zh hr cs da nl en et fo fa fi fr de el he hu is id it ja ko lv lt mk ms mt no nn pl pt ro ru sr sk sl es sv th tr uk ur vi".split(separator: " ").map(String.init))
        let parts = normalized.split(separator: "-", omittingEmptySubsequences: false)
        guard let first = parts.first, supported.contains(String(first)), parts.count <= 3,
              parts.dropFirst().allSatisfy({ regions.contains(String($0)) || scripts.contains(String($0)) }),
              parts.count < 3 || (scripts.contains(String(parts[1])) && regions.contains(String(parts[2]))) else { return nil }
        return normalized
    }
}

private final class FormXLIFFParser: NSObject, XMLParserDelegate {
    private(set) var warnings: [String] = []
    struct Group { var name: String; var id: String? }
    struct Unit {
        var name: String
        var id: String?
        var groups: [Group]
        var sourceLanguage: String?
        var targetLanguage: String?
        var source: String?
        var target: String?
    }
    private var units: [Unit] = []
    private var groups: [Group] = []
    private var unit: Unit?
    private var sourceLanguage: String?
    private var targetLanguage: String?
    private var field: String?
    private var text = ""
    private var depth = 0
    private var nodes = 0
    private var textBytes = 0
    private var valid = true
    private var unsupportedUnit = false
    private var elements: [String] = []

    func parse(_ data: Data) throws -> [Unit] {
        guard let xml = String(data: data, encoding: .utf8),
              !xml.contains("<!DOCTYPE"), !xml.contains("<!ENTITY") else {
            throw FormError.dependency("XLIFF must be UTF-8 without DTD/entities.")
        }
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        parser.delegate = self
        guard parser.parse(), valid, depth == 0 else {
            throw FormError.dependency("Invalid/unsupported XLIFF (1.x plain text only; 20,000 XML nodes, depth 64, 1 MiB text).")
        }
        return units
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String]) {
        depth += 1
        nodes += 1
        let parent = elements.last
        elements.append(name)
        if depth > 64 || nodes > 20_000 { valid = false; parser.abortParsing(); return }
        if depth == 1, name != "xliff" || !["1.0", "1.1", "1.2"].contains(attributes["version"] ?? "") {
            valid = false; parser.abortParsing(); return
        }
        if let namespaceURI, !namespaceURI.isEmpty,
           !["urn:oasis:names:tc:xliff:document:1.0", "urn:oasis:names:tc:xliff:document:1.1", "urn:oasis:names:tc:xliff:document:1.2"].contains(namespaceURI) {
            valid = false; parser.abortParsing(); return
        }
        if field != nil { unsupportedUnit = true }
        switch name {
        case "file":
            guard parent == "xliff" else { valid = false; parser.abortParsing(); return }
            sourceLanguage = attributes["source-language"]
            targetLanguage = attributes["target-language"]
        case "body":
            guard parent == "file" else { valid = false; parser.abortParsing(); return }
        case "group":
            guard parent == "body" || parent == "group" else { valid = false; parser.abortParsing(); return }
            groups.append(Group(name: attributes["resname"] ?? "", id: attributes["id"]))
        case "trans-unit":
            guard unit == nil, parent == "body" || parent == "group" else { valid = false; parser.abortParsing(); return }
            unit = Unit(name: attributes["resname"] ?? "", id: attributes["id"], groups: groups,
                        sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
            unsupportedUnit = attributes["translate"] == "no"
        case "source", "target":
            guard parent == "trans-unit" else {
                if field != nil { unsupportedUnit = true; return }
                valid = false; parser.abortParsing(); return
            }
            if unit != nil {
                if (name == "source" ? unit?.source : unit?.target) != nil { unsupportedUnit = true }
                field = name
                text = ""
                if let language = attributes["xml:lang"] {
                    if name == "source" { unit?.sourceLanguage = language } else { unit?.targetLanguage = language }
                }
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBytes += string.utf8.count
        if textBytes > 1_048_576 { valid = false; parser.abortParsing(); return }
        if field != nil { text += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let string = String(data: CDATABlock, encoding: .utf8) else { valid = false; parser.abortParsing(); return }
        self.parser(parser, foundCharacters: string)
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
        if name == field {
            if name == "source" { unit?.source = text } else { unit?.target = text }
            field = nil
        }
        if name == "trans-unit" {
            if unsupportedUnit { warnings.append("Unsupported inline content/translate=no for \(unit?.name ?? "unit"); original text retained.") }
            else if let unit { units.append(unit) }
            unit = nil
        }
        if name == "group", !groups.isEmpty { groups.removeLast() }
        if !elements.isEmpty { elements.removeLast() }
        depth -= 1
    }

    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) { valid = false; parser.abortParsing() }
    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) { valid = false; parser.abortParsing() }
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? { valid = false; parser.abortParsing(); return nil }
}
