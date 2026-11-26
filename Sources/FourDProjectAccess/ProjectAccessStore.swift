import Foundation

public enum ProjectAccessError: LocalizedError {
    case unavailable
    case invalidProject
    case invalidFolder
    case oversizedIndex
    case tooManyProjects
    case invalidBookmark
    case staleBookmark
    case denied

    public var errorDescription: String? {
        switch self {
        case .unavailable: return "The shared project-access container is unavailable. Check the app-group signing configuration."
        case .invalidProject: return "Choose a project folder containing Project/Sources, or its Project folder."
        case .invalidFolder: return "Choose a local folder, not a file or the filesystem root."
        case .oversizedIndex: return "The project-access index exceeds its size limit."
        case .tooManyProjects: return "At most 64 folders can be authorized. Remove an authorization before adding another."
        case .invalidBookmark: return "The saved project authorization does not match this project."
        case .staleBookmark: return "The folder authorization is stale. Authorize its folder again in 4D Quick Look."
        case .denied: return "Project-resource access is unavailable. Launch 4D Quick Look and authorize a folder containing this project."
        }
    }
}

public struct ProjectAccessEntry: Codable {
    public let path: String
    public let bookmark: Data
}

/// Saved read-only folder authorizations, separate from the user's project.
public struct ProjectAccessStore {
    public let documentURL: URL
    private let maximumIndexBytes = 1_048_576

    public init(containerURL: URL) {
        documentURL = containerURL.appendingPathComponent("ProjectAccess.json")
    }

    public static func configured(bundle: Bundle = .main) throws -> ProjectAccessStore {
        guard let identifier = bundle.object(forInfoDictionaryKey: "FourDProjectGroupIdentifier") as? String,
              !identifier.isEmpty,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            throw ProjectAccessError.unavailable
        }
        return ProjectAccessStore(containerURL: container)
    }

    public func entries() throws -> [ProjectAccessEntry] {
        let size: Int
        do {
            size = try documentURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
        guard size <= maximumIndexBytes else { throw ProjectAccessError.oversizedIndex }
        let handle = try FileHandle(forReadingFrom: documentURL)
        let data = try handle.read(upToCount: maximumIndexBytes + 1) ?? Data()
        try handle.close()
        guard data.count <= maximumIndexBytes else { throw ProjectAccessError.oversizedIndex }
        let entries = try JSONDecoder().decode([ProjectAccessEntry].self, from: data)
        guard entries.count <= 64 else { throw ProjectAccessError.tooManyProjects }
        guard entries.allSatisfy({ $0.bookmark.count <= 65_536 && $0.path.hasPrefix("/") }) else {
            throw ProjectAccessError.invalidBookmark
        }
        return entries
    }

    public func authorize(_ selectedURL: URL) throws -> URL {
        let root = try Self.authorizationRoot(for: selectedURL)
        var existing = try entries()
        if !FileManager.default.fileExists(atPath: documentURL.path) {
            try save([])
        }
        let bookmark = try root.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                             includingResourceValuesForKeys: nil, relativeTo: nil)
        guard bookmark.count <= 65_536 else { throw ProjectAccessError.invalidBookmark }
        existing.removeAll { $0.path == root.path }
        guard existing.count < 64 else { throw ProjectAccessError.tooManyProjects }
        existing.append(ProjectAccessEntry(path: root.path, bookmark: bookmark))
        try save(existing)
        return root
    }

    public func removeAll() throws {
        try save([])
    }

    public func hasAuthorization(for fileURL: URL) throws -> Bool {
        try entries().contains { Self.contains(fileURL.standardizedFileURL.path, in: $0.path) }
    }

    public func withAccess<T>(to fileURL: URL, perform body: () throws -> T) throws -> T {
        let filePath = fileURL.standardizedFileURL.path
        let matching = try entries().filter { Self.contains(filePath, in: $0.path) }
        guard let entry = matching.max(by: { $0.path.count < $1.path.count }) else { return try body() }
        var stale = false
        let root = try URL(resolvingBookmarkData: entry.bookmark, options: [.withSecurityScope, .withoutUI],
                           relativeTo: nil, bookmarkDataIsStale: &stale)
        guard !stale else { throw ProjectAccessError.staleBookmark }
        guard root.standardizedFileURL.path == entry.path else { throw ProjectAccessError.invalidBookmark }
        guard root.startAccessingSecurityScopedResource() else { throw ProjectAccessError.denied }
        defer { root.stopAccessingSecurityScopedResource() }
        guard Self.contains(fileURL.resolvingSymlinksInPath().path, in: root.resolvingSymlinksInPath().path) else {
            throw ProjectAccessError.invalidBookmark
        }
        return try body()
    }

    public static func projectRoot(for selectedURL: URL) throws -> URL {
        let selected = selectedURL.resolvingSymlinksInPath().standardizedFileURL
        let root = selected.lastPathComponent == "Project" ? selected.deletingLastPathComponent() : selected
        let sources = root.appendingPathComponent("Project/Sources", isDirectory: true)
        let values = try sources.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true, root.pathComponents.count > 1,
              Self.contains(sources.resolvingSymlinksInPath().path, in: root.path) else {
            throw ProjectAccessError.invalidProject
        }
        return root
    }

    public static func authorizationRoot(for selectedURL: URL) throws -> URL {
        guard selectedURL.isFileURL else { throw ProjectAccessError.invalidFolder }
        let root = selectedURL.resolvingSymlinksInPath().standardizedFileURL
        guard root.pathComponents.count > 1,
              root.path.utf8.count <= 4_096,
              !root.path.contains("\0") else { throw ProjectAccessError.invalidFolder }
        let values = try root.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { throw ProjectAccessError.invalidFolder }
        return root
    }

    public static func contains(_ path: String, in root: String) -> Bool {
        path == root || path.hasPrefix(root + "/")
    }

    private func save(_ entries: [ProjectAccessEntry]) throws {
        let data = try JSONEncoder().encode(entries)
        guard data.count <= maximumIndexBytes else { throw ProjectAccessError.oversizedIndex }
        try FileManager.default.createDirectory(at: documentURL.deletingLastPathComponent(),
                                               withIntermediateDirectories: true)
        try data.write(to: documentURL, options: .atomic)
    }
}
