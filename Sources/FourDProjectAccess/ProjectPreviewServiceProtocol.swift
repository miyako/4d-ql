import Foundation

@objc public protocol ProjectPreviewServiceSessionProtocol {
    func openSession(authorizing: Bool, withReply reply: @escaping (NSXPCListenerEndpoint?, NSString?) -> Void)
}

@objc public protocol ProjectPreviewServiceProtocol {
    func authorizeProject(_ rootURL: NSURL, bookmarkData: NSData,
                          withReply reply: @escaping (NSURL?, NSString?) -> Void)
    func revoke(withReply reply: @escaping (NSString?) -> Void)
    func preview(_ fileURL: NSURL, nonce: NSString, sourceSHA: NSString, rendererBuild: NSString,
                 withReply reply: @escaping (NSString?, NSString?, NSString, NSString, NSString) -> Void)
}

public enum ProjectPreviewServiceTransport {
    public static func sessionInterface() -> NSXPCInterface {
        let interface = NSXPCInterface(with: ProjectPreviewServiceSessionProtocol.self)
        let selector = #selector(ProjectPreviewServiceSessionProtocol.openSession(authorizing:withReply:))
        interface.setClasses(NSSet(array: [NSXPCListenerEndpoint.self]) as! Set<AnyHashable>,
                             for: selector, argumentIndex: 0, ofReply: true)
        interface.setClasses(NSSet(array: [NSString.self]) as! Set<AnyHashable>,
                             for: selector, argumentIndex: 1, ofReply: true)
        return interface
    }

    /// Create while the host holds the user's NSOpenPanel-granted scope. This is a
    /// portable, implicit-scope bookmark, not the host's persistent app-scoped bookmark.
    public static func authorizationBookmark(for rootURL: URL) throws -> Data {
        guard rootURL.isFileURL, rootURL.path.hasPrefix("/") else {
            throw ProjectPreviewExchangeError.invalidRequest
        }
        let data = try rootURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        guard data.count <= 65_536 else { throw ProjectAccessError.invalidBookmark }
        return data
    }

    public static func interface() -> NSXPCInterface {
        let interface = NSXPCInterface(with: ProjectPreviewServiceProtocol.self)
        interface.setClasses(NSSet(array: [NSURL.self]) as! Set<AnyHashable>,
                             for: #selector(ProjectPreviewServiceProtocol.authorizeProject(_:bookmarkData:withReply:)),
                             argumentIndex: 0, ofReply: false)
        interface.setClasses(NSSet(array: [NSData.self]) as! Set<AnyHashable>,
                             for: #selector(ProjectPreviewServiceProtocol.authorizeProject(_:bookmarkData:withReply:)),
                             argumentIndex: 1, ofReply: false)
        interface.setClasses(NSSet(array: [NSURL.self]) as! Set<AnyHashable>,
                             for: #selector(ProjectPreviewServiceProtocol.authorizeProject(_:bookmarkData:withReply:)),
                             argumentIndex: 0, ofReply: true)
        interface.setClasses(NSSet(array: [NSString.self]) as! Set<AnyHashable>,
                             for: #selector(ProjectPreviewServiceProtocol.authorizeProject(_:bookmarkData:withReply:)),
                             argumentIndex: 1, ofReply: true)
        interface.setClasses(NSSet(array: [NSString.self]) as! Set<AnyHashable>,
                             for: #selector(ProjectPreviewServiceProtocol.revoke(withReply:)),
                             argumentIndex: 0, ofReply: true)
        let preview = #selector(ProjectPreviewServiceProtocol.preview(_:nonce:sourceSHA:rendererBuild:withReply:))
        interface.setClasses(NSSet(array: [NSURL.self]) as! Set<AnyHashable>,
                             for: preview, argumentIndex: 0, ofReply: false)
        for index in 1...3 {
            interface.setClasses(NSSet(array: [NSString.self]) as! Set<AnyHashable>,
                                 for: preview, argumentIndex: index, ofReply: false)
        }
        for index in 0...4 {
            interface.setClasses(NSSet(array: [NSString.self]) as! Set<AnyHashable>,
                                 for: preview, argumentIndex: index, ofReply: true)
        }
        return interface
    }

    public static func codeSigningRequirement(identifiers: [String], teamIdentifier: String) throws -> String {
        func valid(_ text: String) -> Bool {
            !text.isEmpty && text.utf8.count <= 255 && text.utf8.allSatisfy {
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                    || $0 == 46 || $0 == 45 || $0 == 95
            }
        }
        guard !identifiers.isEmpty, identifiers.count <= 2, identifiers.allSatisfy(valid),
              valid(teamIdentifier) else { throw ProjectAccessError.denied }
        let identifiers = identifiers.map { "identifier \"\($0)\"" }.joined(separator: " or ")
        return "anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\" and (\(identifiers))"
    }

    public static func validatePreview(fileURL: URL, nonce: String, sourceSHA: String,
                                       rendererBuild: String, expectedRendererBuild: String) throws {
        guard fileURL.isFileURL, fileURL.path.hasPrefix("/"), fileURL.path.utf8.count <= 4_096,
              !fileURL.path.utf8.contains(0), fileURL.path == fileURL.standardizedFileURL.path,
              fileURL.pathExtension.lowercased() == "4dform",
              UUID(uuidString: nonce)?.uuidString == nonce,
              sourceSHA.utf8.count == 64,
              sourceSHA.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              !rendererBuild.isEmpty, rendererBuild.utf8.count <= 128,
              rendererBuild.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw ProjectPreviewExchangeError.invalidRequest
        }
        guard rendererBuild == expectedRendererBuild else {
            throw ProjectPreviewExchangeError.remoteFailure("The project preview service build does not match this extension. Relaunch the updated application.")
        }
    }

    public static func renderVerified(fileURL: URL, expectedHash: String,
                                      render: (URL) throws -> String) throws -> String {
        try ProjectPreviewExchange.verifySource(fileURL: fileURL, expectedHash: expectedHash)
        let html = try render(fileURL)
        try ProjectPreviewExchange.verifySource(fileURL: fileURL, expectedHash: expectedHash)
        guard html.utf8.count <= ProjectPreviewExchange.maximumHTMLBytes else {
            throw ProjectPreviewExchangeError.oversizedHTML
        }
        return html
    }
}

/// One process-wide queue shared by every accepted connection. The service owns all
/// persistent scoped bookmarks; clients receive neither bookmarks nor root filesystem scope.
public final class ProjectPreviewServiceEndpoint: NSObject, ProjectPreviewServiceProtocol {
    private let store: () throws -> ProjectAccessStore
    private let rendererBuild: String
    private let render: (URL) throws -> String
    private let work = ProjectPreviewServiceWorkQueue()

    public init(rendererBuild: String, store: @escaping () throws -> ProjectAccessStore,
                render: @escaping (URL) throws -> String) {
        self.rendererBuild = rendererBuild
        self.store = store
        self.render = render
    }

    public func previewOnlyEndpoint() -> ProjectPreviewServiceProtocol {
        ProjectPreviewReadOnlyEndpoint(endpoint: self)
    }

    public func authorizeProject(_ rootURL: NSURL, bookmarkData: NSData,
                                 withReply reply: @escaping (NSURL?, NSString?) -> Void) {
        guard bookmarkData.length > 0, bookmarkData.length <= 65_536,
              (rootURL as URL).isFileURL, (rootURL as URL).path.utf8.count <= 4_096 else {
            reply(nil, Self.message(ProjectAccessError.invalidBookmark))
            return
        }
        let accepted = work.submit {
            do {
                var stale = false
                let resolved = try URL(resolvingBookmarkData: bookmarkData as Data, options: [.withoutUI],
                                       relativeTo: nil, bookmarkDataIsStale: &stale)
                guard !stale, resolved.isFileURL,
                      resolved.standardizedFileURL.path == (rootURL as URL).standardizedFileURL.path else {
                    throw ProjectAccessError.invalidBookmark
                }
                guard resolved.startAccessingSecurityScopedResource() else {
                    throw ProjectPreviewExchangeError.remoteFailure("The service could not activate the selected project's transferred scope. Select the project again in the host.")
                }
                defer { resolved.stopAccessingSecurityScopedResource() }
                let root = try self.store().authorize(resolved)
                reply(root as NSURL, nil)
            } catch { reply(nil, Self.message(error)) }
        }
        if !accepted { reply(nil, Self.message(ProjectPreviewExchangeError.queueFull)) }
    }

    public func revoke(withReply reply: @escaping (NSString?) -> Void) {
        let accepted = work.submit {
            do { try self.store().removeAll(); reply(nil) }
            catch { reply(Self.message(error)) }
        }
        if !accepted { reply(Self.message(ProjectPreviewExchangeError.queueFull)) }
    }

    public func preview(_ fileURL: NSURL, nonce: NSString, sourceSHA: NSString, rendererBuild: NSString,
                        withReply reply: @escaping (NSString?, NSString?, NSString, NSString, NSString) -> Void) {
        func respond(_ html: NSString?, _ error: NSString?) {
            reply(html, error, String((nonce as String).prefix(36)) as NSString,
                  String((sourceSHA as String).prefix(64)) as NSString,
                  String((rendererBuild as String).prefix(128)) as NSString)
        }
        do {
            try ProjectPreviewServiceTransport.validatePreview(fileURL: fileURL as URL, nonce: nonce as String,
                sourceSHA: sourceSHA as String, rendererBuild: rendererBuild as String,
                expectedRendererBuild: self.rendererBuild)
        } catch { respond(nil, Self.message(error)); return }
        let accepted = work.submit {
            do {
                let url = fileURL as URL
                let store = try self.store()
                guard try store.hasAuthorization(for: url) else { throw ProjectAccessError.denied }
                let html = try store.withAccess(to: url) {
                    try ProjectPreviewServiceTransport.renderVerified(fileURL: url, expectedHash: sourceSHA as String,
                                                                      render: self.render)
                }
                respond(html as NSString, nil)
            } catch { respond(nil, Self.message(error)) }
        }
        if !accepted { respond(nil, Self.message(ProjectPreviewExchangeError.queueFull)) }
    }

    private static func message(_ error: Error) -> NSString {
        let text = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        return String(text.prefix(1_024)) as NSString
    }
}

private final class ProjectPreviewReadOnlyEndpoint: NSObject, ProjectPreviewServiceProtocol {
    private let endpoint: ProjectPreviewServiceEndpoint

    init(endpoint: ProjectPreviewServiceEndpoint) { self.endpoint = endpoint }

    func authorizeProject(_ rootURL: NSURL, bookmarkData: NSData,
                          withReply reply: @escaping (NSURL?, NSString?) -> Void) {
        reply(nil, "Project authorization is available only through the signed hosting application.")
    }

    func revoke(withReply reply: @escaping (NSString?) -> Void) {
        reply("Project authorization is available only through the signed hosting application.")
    }

    func preview(_ fileURL: NSURL, nonce: NSString, sourceSHA: NSString, rendererBuild: NSString,
                 withReply reply: @escaping (NSString?, NSString?, NSString, NSString, NSString) -> Void) {
        endpoint.preview(fileURL, nonce: nonce, sourceSHA: sourceSHA, rendererBuild: rendererBuild, withReply: reply)
    }
}

final class ProjectPreviewServiceWorkQueue {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "FourDProjectPreviewService.requests")
    private var pending = 0

    func submit(_ body: @escaping () -> Void) -> Bool {
        lock.lock()
        guard pending < 32 else { lock.unlock(); return false }
        pending += 1
        lock.unlock()
        queue.async {
            defer {
                self.lock.lock()
                self.pending -= 1
                self.lock.unlock()
            }
            body()
        }
        return true
    }
}
