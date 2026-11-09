import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Static composition only. Inheritance contributes objects from pages 0 and 1,
/// not form properties or methods (4D Design Reference, "Using inherited forms").
final class FormStaticExpansion {
    let dependencies: FormDependencies
    private(set) var contexts: [String: FormValue] = [:]
    private var documents: [URL: FormValue] = [:]
    private var nodes = 0
    private var objects = 0
    private var contextNumbers: [String: Int] = [:]
    private var catalog: [Int: String]?
    private var catalogAttempted = false

    init(dependencies: FormDependencies) { self.dependencies = dependencies }

    func expand(_ value: FormValue, document: URL) throws -> [FormPage] {
        documents[document] = value
        return try pages(value, document: document, identity: document.path, stack: [], depth: 0)
    }

    private func pages(_ value: FormValue, document: URL, identity: String,
                       stack: Set<String>, depth: Int, initialOnly: Bool = false) throws -> [FormPage] {
        guard depth < 64, !stack.contains(identity) else {
            throw FormError.dependency("Static form cycle or depth 64 at \(document.lastPathComponent).")
        }
        try budget(value)
        guard case .object = value, case .array(let definitions) = value["pages"], definitions.count >= 2 else {
            throw FormError.invalid("Static form must contain pages 0 and 1.")
        }
        if !initialOnly {
            for (number, page) in definitions.enumerated() where page != .null {
                guard case .object = page, case .object(let members) = page["objects"],
                      members.allSatisfy({ if case .object = $0.value { return true }; return false }) else {
                    throw FormError.invalid("Page \(number) must contain an objects map with object definitions or be null.")
                }
            }
        }
        var stack = stack
        stack.insert(identity)
        if contextNumbers[identity] == nil { contextNumbers[identity] = contextNumbers.count }
        let key = String(document.path.dropFirst(dependencies.root.path.count + 1)) +
            (identity == document.path ? "" : "#inline-\(contextNumbers[identity]!)")
        contexts[key] = value
        let conventional = document.lastPathComponent.lowercased() == "form.4dform"
        let formName = value["name"]?.string ?? (conventional ? document.deletingLastPathComponent().lastPathComponent : document.deletingPathExtension().lastPathComponent)
        let tableParts = document.pathComponents
        let tableIndex = tableParts.firstIndex(of: "TableForms")
        var tableName = tableIndex.flatMap { tableParts.indices.contains($0 + 1) ? tableParts[$0 + 1] : nil }
        if let number = tableName.flatMap(Int.init) {
            do { tableName = try tables()[number] ?? tableName }
            catch { dependencies.warn("Table form source: \(error); automatic named-table localization is unavailable.") }
        }
        var result: [FormPage] = []
        if definitions.count > 17 && !initialOnly { dependencies.warn("Showing page 0 and the first 16 numbered pages of \(definitions.count - 1).") }
        for (number, page) in definitions.prefix(initialOnly ? 2 : 17).enumerated() {
            if page == .null { result.append(FormPage(number: number, objects: [])); continue }
            guard case .object(let members) = page["objects"] else {
                throw FormError.invalid("Page \(number) must contain an objects map or be null.")
            }
            var items: [FormObject] = []
            for member in members {
                guard case .object = member.value else { throw FormError.invalid("Object \(member.name) must be an object.") }
                guard objects < 1_000 else {
                    dependencies.warn("Showing at most 1,000 static form objects; original JSON retains all objects.")
                    break
                }
                objects += 1
                var object = FormObject(name: member.name, properties: member.value)
                object.stylesheetContext = key
                object.source = FormObjectSource(document: key, formName: formName, page: number, tableName: tableName,
                                                 inline: identity != document.path)
                if object.type == "subform" {
                    if nonempty(object.properties["listForm"]) || nonempty(object.properties["table"]) {
                        dependencies.warn("Subform \(member.name): list/table data is not executed; showing a placeholder.")
                    } else if nonempty(object.properties["detailForm"]) {
                        do {
                            let child = try target(object.properties["detailForm"]!, table: nil, document: document)
                            object.children = try pages(child.value, document: child.url, identity: child.identity,
                                                        stack: stack, depth: depth + 1, initialOnly: true).flatMap(\.objects)
                            object.embeddedProperties = child.value
                            if case .object = object.properties["detailForm"] {
                                dependencies.warn("Subform \(member.name): inline detailForm object is noncanonical .4DForm schema (detailForm requires a string). Expanding documented dynamic-form object input as a static approximation; the native editor may show a placeholder. No OBJECT SET SUBFORM command is executed.")
                            }
                            if child.value["pages"]!.values.count > 2 {
                                dependencies.warn("Subform \(member.name): showing initial page 1 and background page 0; no page-changing methods are executed.")
                            }
                        } catch {
                            dependencies.warn("Subform \(member.name): \(error); showing a placeholder.")
                        }
                    } else {
                        dependencies.warn("Subform \(member.name): no static detailForm; showing a placeholder.")
                    }
                }
                items.append(object)
            }
            result.append(FormPage(number: number, objects: items))
        }
        if nonempty(value["inheritedForm"]) {
            do {
                let inherited = try target(value["inheritedForm"]!, table: value["inheritedFormTable"], document: document)
                let background = try pages(inherited.value, document: inherited.url, identity: inherited.identity,
                                           stack: stack, depth: depth + 1, initialOnly: true).flatMap(\.objects).map { object in
                    var inheritedObject = object
                    // Like colorScheme/windowTitle, inherited form-level css is
                    // not a property of the receiving form.
                    inheritedObject.stylesheetContext = key
                    return inheritedObject
                }
                result[0].objects.insert(contentsOf: background, at: 0)
                if case .object = value["inheritedForm"] {
                    dependencies.warn("Inherited form: inline inheritedForm object is noncanonical .4DForm schema (inheritedForm requires a string). Expanding documented object input as a static approximation, not native editor equivalence.")
                }
            } catch {
                dependencies.warn("Inherited form: \(error); local objects are retained.")
            }
        }
        return result
    }

    private func nonempty(_ value: FormValue?) -> Bool {
        guard let value, value != .null else { return false }
        if value.double == 0 { return false }
        if let string = value.string { return !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return true
    }

    private func target(_ reference: FormValue, table: FormValue?, document: URL) throws -> (value: FormValue, url: URL, identity: String) {
        if case .object = reference {
            // The inline object's paths have already been resolved with its owner.
            return (reference, document, document.path + ":inline:\(nodes):\(objects)")
        }
        guard let name = reference.string, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FormError.dependency("Dynamic or invalid form reference.")
        }
        let url: URL
        if name.contains("/") || ["json", "4dform"].contains((name as NSString).pathExtension.lowercased()) {
            // Pointer resolution rebases dependency paths to the selected form.
            url = try dependencies.url(name, relativeTo: dependencies.formURL)
        } else {
            guard !name.contains(":"), !name.contains("\\"), name != ".", name != "..",
                  let sources = dependencies.sources else {
                throw FormError.dependency("Unavailable project form \(name) (dynamic/component references are not evaluated).")
            }
            if nonempty(table) {
                let number: Int
                if let numeric = table?.double, numeric > 0, numeric.rounded() == numeric, numeric <= 32_767 {
                    number = Int(numeric)
                } else if let name = table?.string {
                    let plain = name.hasPrefix("[") && name.hasSuffix("]") ? String(name.dropFirst().dropLast()) : name
                    let matches = try tables().filter { $0.value == plain }
                    guard matches.count == 1, let match = matches.first else {
                        throw FormError.dependency("Missing or ambiguous static inherited table \(name).")
                    }
                    number = match.key
                } else { throw FormError.dependency("Dynamic or invalid inherited table.") }
                let base = sources.appendingPathComponent("TableForms/\(number)")
                let candidates = ["Input", "Output"].map { base.appendingPathComponent("\($0)/\(name)/form.4DForm") }
                    .filter { FileManager.default.fileExists(atPath: $0.path) }
                guard candidates.count == 1 else {
                    throw FormError.dependency("Missing or ambiguous inherited table form \(name).")
                }
                url = candidates[0]
            } else { url = sources.appendingPathComponent("Forms/\(name)/form.4DForm") }
        }
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        if let value = documents[canonical] { return (value, canonical, canonical.path) }
        var parser = try FormJSONParser(dependencies.read(canonical))
        let original = try parser.parse()
        let value = try FormPointerResolver(dependencies: dependencies).resolve(original, document: canonical)
        documents[canonical] = value
        return (value, canonical, canonical.path)
    }

    private func budget(_ value: FormValue, depth: Int = 0) throws {
        nodes += 1
        guard nodes <= 100_000, depth <= 64 else { throw FormError.limit("Static expansion exceeds 100,000 values or depth 64.") }
        for member in value.members { try budget(member.value, depth: depth + 1) }
        for item in value.values { try budget(item, depth: depth + 1) }
    }

    private func tables() throws -> [Int: String] {
        if let catalog { return catalog }
        guard !catalogAttempted, let sources = dependencies.sources else {
            throw FormError.dependency("Static table catalog unavailable.")
        }
        catalogAttempted = true
        let data = try dependencies.read(sources.appendingPathComponent("catalog.4DCatalog"))
        let reader = FormTableNames()
        catalog = try reader.parse(data)
        return catalog!
    }
}

private final class FormTableNames: NSObject, XMLParserDelegate {
    private var names: [Int: String] = [:]
    private var depth = 0
    private var count = 0
    private var valid = true

    func parse(_ data: Data) throws -> [Int: String] {
        guard let text = String(data: data, encoding: .utf8),
              !text.contains("<!DOCTYPE"), !text.contains("<!ENTITY") else {
            throw FormError.dependency("Table catalog must be UTF-8 without DTD/entities.")
        }
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        parser.delegate = self
        guard parser.parseStrictly(), valid else { throw FormError.dependency("Invalid static table catalog (20,000 nodes/depth 64).") }
        return names
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String]) {
        guard valid else { return }
        depth += 1
        count += 1
        if count > 20_000 || depth > 64 || (depth == 1 && name != "base") {
            valid = false; parser.stopFromDelegate(); return
        }
        if depth == 2, name == "table", let number = attributes["id"].flatMap(Int.init),
           number > 0, number <= 32_767, let name = attributes["name"] {
            if names[number] != nil { valid = false; parser.stopFromDelegate() }
            else { names[number] = name }
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) { depth -= 1 }
    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) { valid = false; parser.stopFromDelegate() }
    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) { valid = false; parser.stopFromDelegate() }
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? { valid = false; parser.stopFromDelegate(); return nil }
}
