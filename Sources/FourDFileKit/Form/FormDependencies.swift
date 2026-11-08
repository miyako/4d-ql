import Foundation

final class FormDependencies {
    let formURL: URL
    let root: URL
    let sources: URL?
    let project: URL?
    private(set) var warnings: [String] = []
    private(set) var loadedPaths: [String] = []
    private var cache: [URL: Data] = [:]
    private var bytesRead = 0
    private var attempts = Set<URL>()

    init(formURL: URL) {
        let form = formURL.standardizedFileURL.resolvingSymlinksInPath()
        self.formURL = form
        var folder = form.deletingLastPathComponent()
        var found: URL?
        // Only recognize the conventional Project/Sources tree, not an arbitrary
        // ancestor named Sources (which would grant much broader file access).
        for _ in 0..<8 {
            if folder.lastPathComponent == "Sources", folder.deletingLastPathComponent().lastPathComponent == "Project" {
                found = folder
                break
            }
            let parent = folder.deletingLastPathComponent()
            if parent == folder { break }
            folder = parent
        }
        sources = found
        project = found?.deletingLastPathComponent()
        root = found?.deletingLastPathComponent().deletingLastPathComponent() ?? form.deletingLastPathComponent()
    }

    func warn(_ text: String) {
        if warnings.count < 100, !warnings.contains(text) { warnings.append(text) }
    }

    func url(_ path: String, relativeTo document: URL) throws -> URL {
        guard !path.isEmpty, !path.contains("\0"), !path.contains("\\"),
              !path.contains("://"), !path.hasPrefix("var:"), !path.hasPrefix("file:") else {
            throw FormError.dependency("Unsupported path \(path).")
        }
        let target: URL
        if path.hasPrefix("/") {
            let parts = path.split(separator: "/", omittingEmptySubsequences: true)
            guard let prefix = parts.first else { throw FormError.dependency("Empty path.") }
            let base: URL?
            switch prefix {
            case "SOURCES": base = sources
            case "PROJECT": base = project
            case "RESOURCES": base = project?.deletingLastPathComponent().appendingPathComponent("Resources")
            case "PACKAGE": base = project?.deletingLastPathComponent()
            default: base = nil
            }
            guard let base else { throw FormError.dependency("Unavailable filesystem prefix in \(path).") }
            target = base.appendingPathComponent(parts.dropFirst().joined(separator: "/"))
        } else {
            target = document.deletingLastPathComponent().appendingPathComponent(path)
        }
        let resolved = target.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(root.path + "/") else {
            throw FormError.dependency("Path escapes the preview's project/form folder: \(path).")
        }
        return resolved
    }

    func read(_ requestedURL: URL) throws -> Data {
        let url = requestedURL.standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(root.path + "/") else {
            throw FormError.dependency("Path escapes the preview's project/form folder: \(requestedURL.lastPathComponent).")
        }
        if let data = cache[url] { return data }
        attempts.insert(url)
        guard attempts.count <= 64 else { throw FormError.limit("64 dependency files exceeded.") }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw FormError.dependency("Not a regular file: \(url.lastPathComponent).")
        }
        let source = try ByteSource(url: url)
        guard source.size <= 4 * 1024 * 1024, bytesRead + Int(source.size) <= 16 * 1024 * 1024 else {
            throw FormError.limit("Dependency exceeds 4 MiB or total dependencies exceed 16 MiB.")
        }
        let data = try source.read(at: 0, length: Int(source.size))
        bytesRead += data.count
        cache[url] = data
        loadedPaths.append(String(url.path.dropFirst(root.path.count + 1)))
        return data
    }

    func rebase(_ path: String, from document: URL) throws -> String {
        if path.hasPrefix("/") || document == formURL || path.hasPrefix("var:") { return path }
        let target = try url(path, relativeTo: document).pathComponents
        let base = formURL.deletingLastPathComponent().pathComponents
        var common = 0
        while common < min(target.count, base.count), target[common] == base[common] { common += 1 }
        return (Array(repeating: "..", count: base.count-common) + target.dropFirst(common)).joined(separator: "/")
    }
}

final class FormPointerResolver {
    private let dependencies: FormDependencies
    private var documents: [URL: FormValue] = [:]
    private var nodes = 0

    init(dependencies: FormDependencies) { self.dependencies = dependencies }

    func resolve(_ value: FormValue, document: URL) throws -> FormValue {
        documents[document] = value
        return try walk(value, document: document, stack: [], depth: 0)
    }

    private func walk(_ value: FormValue, document: URL, stack: Set<String>, depth: Int) throws -> FormValue {
        nodes += 1
        guard nodes <= 100_000, depth <= 64 else { throw FormError.limit("Expanded JSON exceeds 100,000 values or depth 64.") }
        switch value {
        case .array(let items):
            return .array(try items.map { try walk($0, document: document, stack: stack, depth: depth + 1) })
        case .object(let members):
            var result = value
            if let ref = value["$ref"]?.string {
                do {
                    let parts = ref.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                    let target = parts[0].isEmpty ? document : try dependencies.url(String(parts[0]), relativeTo: document)
                    let fragment = parts.count > 1 ? String(parts[1]) : ""
                    guard let pointer = fragment.removingPercentEncoding else { throw FormError.invalid("Invalid pointer encoding.") }
                    let key = target.path + "#" + pointer
                    guard !stack.contains(key) else { throw FormError.dependency("Cyclic JSON pointer \(ref).") }
                    if documents[target] == nil {
                        var parser = try FormJSONParser(dependencies.read(target))
                        documents[target] = try parser.parse()
                    }
                    guard var referenced = documents[target] else { throw FormError.dependency("Missing pointer document.") }
                    if !pointer.isEmpty {
                        guard pointer.hasPrefix("/") else { throw FormError.invalid("Pointer must start with '/'.") }
                        for part in pointer.dropFirst().components(separatedBy: "/") {
                            // RFC 6901 permits only ~0 and ~1 escapes.
                            guard part.range(of: "~(?![01])", options: .regularExpression) == nil else {
                                throw FormError.invalid("Invalid JSON pointer escape.")
                            }
                            let name = part.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
                            if case .array(let items) = referenced {
                                guard let index = Int(name), index >= 0, index < items.count,
                                      name == String(index) else { throw FormError.dependency("Missing pointer array index \(name).") }
                                referenced = items[index]
                            } else {
                                guard let next = referenced[name] else { throw FormError.dependency("Missing pointer member \(name).") }
                                referenced = next
                            }
                        }
                    }
                    var nextStack = stack
                    nextStack.insert(key)
                    result = try walk(referenced, document: target, stack: nextStack, depth: depth + 1)
                    // Forms use merge semantics: local properties override templates.
                    if case .object = result {
                        for member in members where member.name != "$ref" {
                            let local = try walk(member.value, document: document, stack: stack, depth: depth + 1)
                            result[member.name] = rebaseProperty(member.name, value: local, document: document)
                        }
                    }
                    return result
                } catch let error as FormError {
                    if case .limit = error { throw error }
                    dependencies.warn("Unresolved $ref \(ref): \(error)")
                } catch {
                    dependencies.warn("Unresolved $ref \(ref): \(error)")
                }
            }
            var object = FormValue.object(try members.map {
                FormMember(name: $0.name, value: try walk($0.value, document: document, stack: stack, depth: depth + 1))
            })
            for key in ["picture", "icon", "customBackgroundPicture", "path", "inheritedForm", "detailForm", "listForm"] {
                if let value = object[key] { object[key] = rebaseProperty(key, value: value, document: document) }
            }
            if let css = object["css"] {
                object["css"] = rebaseProperty("css", value: css, document: document)
            }
            return object
        default: return value
        }
    }

    private func rebaseProperty(_ name: String, value: FormValue, document: URL) -> FormValue {
        guard ["picture", "icon", "customBackgroundPicture", "path", "css", "inheritedForm", "detailForm", "listForm"].contains(name) else { return value }
        if name == "css", case .array(let entries) = value {
            return .array(entries.map { rebaseProperty("css", value: $0, document: document) })
        }
        guard let path = value.string else { return value }
        if ["inheritedForm", "detailForm", "listForm"].contains(name),
           !path.contains("/"), !["json", "4dform"].contains((path as NSString).pathExtension.lowercased()) { return value }
        do { return .string(try dependencies.rebase(path, from: document)) }
        catch { dependencies.warn("Cannot rebase \(name) \(path): \(error)"); return value }
    }
}
