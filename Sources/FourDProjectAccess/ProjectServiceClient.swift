import Foundation

private final class ProjectServiceReply<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var connection: NSXPCConnection?
    var timeout: DispatchWorkItem?

    init(_ continuation: CheckedContinuation<Value, Error>, connection: NSXPCConnection) {
        self.continuation = continuation
        self.connection = connection
    }

    func finish(_ result: Result<Value, Error>) {
        lock.lock()
        guard let continuation else { lock.unlock(); return }
        let connection = self.connection
        self.continuation = nil
        self.connection = nil
        timeout?.cancel()
        timeout = nil
        lock.unlock()
        connection?.interruptionHandler = nil
        connection?.invalidationHandler = nil
        connection?.invalidate()
        continuation.resume(with: result)
    }
}

public struct ProjectServiceClient {
    public let serviceName: String
    public let rendererBuild: String

    public init(bundle: Bundle = .main) throws {
        guard let identifier = bundle.bundleIdentifier else { throw ProjectAccessError.unavailable }
        let base = identifier.hasSuffix(".Preview") ? String(identifier.dropLast(".Preview".count)) : identifier
        serviceName = base + ".ProjectPreviewService"
        rendererBuild = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development"
    }

    public func authorize(_ selectedURL: URL) async throws -> URL {
        let root = try ProjectAccessStore.authorizationRoot(for: selectedURL)
        if root.lastPathComponent == "Project",
           FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path) {
            throw Self.error("Choose the package folder containing Project and Resources, not the Project subfolder, so the read-only grant includes its resources.")
        }
        let bookmark = try ProjectPreviewServiceTransport.authorizationBookmark(for: selectedURL)
        return try await call(authorizing: true) { proxy, completion in
            proxy.authorizeProject(selectedURL as NSURL, bookmarkData: bookmark as NSData) { root, error in
                if let error { completion(.failure(Self.error(error as String))) }
                else if let root { completion(.success(root as URL)) }
                else { completion(.failure(ProjectAccessError.invalidBookmark)) }
            }
        }
    }

    public func revoke() async throws {
        let _: Void = try await call(authorizing: true) { proxy, completion in
            proxy.revoke { error in
                if let error { completion(.failure(Self.error(error as String))) }
                else { completion(.success(())) }
            }
        }
    }

    public func preview(_ fileURL: URL) async throws -> String {
        let deadline = ProcessInfo.processInfo.systemUptime + 4
        let nonce = UUID().uuidString
        let hash = try ProjectPreviewExchange.sourceHash(fileURL: fileURL)
        return try await call(deadline: deadline) { proxy, completion in
            proxy.preview(fileURL as NSURL, nonce: nonce as NSString, sourceSHA: hash as NSString,
                          rendererBuild: rendererBuild as NSString) { html, error, replyNonce, replySHA, replyBuild in
                guard replyNonce as String == nonce, replySHA as String == hash,
                      replyBuild as String == rendererBuild else {
                    completion(.failure(Self.error("The project preview reply does not match this request.")))
                    return
                }
                if let error { completion(.failure(Self.error(error as String))) }
                else if let html, html.lengthOfBytes(using: String.Encoding.utf8.rawValue) <= 33_554_432 {
                    completion(.success(html as String))
                } else {
                    completion(.failure(Self.error("The project preview reply is missing or exceeds its size limit.")))
                }
            }
        }
    }

    private func call<Value>(authorizing: Bool = false, deadline: TimeInterval? = nil,
                             _ invoke: @escaping (ProjectPreviewServiceProtocol, @escaping (Result<Value, Error>) -> Void) -> Void) async throws -> Value {
        let deadline = deadline ?? ProcessInfo.processInfo.systemUptime + 4
        let endpoint: NSXPCListenerEndpoint = try await rpc(
            connection: NSXPCConnection(serviceName: serviceName),
            interface: ProjectPreviewServiceTransport.sessionInterface(),
            proxyType: ProjectPreviewServiceSessionProtocol.self,
            timeout: max(0, deadline - ProcessInfo.processInfo.systemUptime)
        ) { proxy, completion in
            proxy.openSession(authorizing: authorizing) { endpoint, error in
                if let error { completion(.failure(Self.error(error as String))) }
                else if let endpoint { completion(.success(endpoint)) }
                else { completion(.failure(ProjectAccessError.unavailable)) }
            }
        }
        return try await rpc(connection: NSXPCConnection(listenerEndpoint: endpoint),
                             interface: ProjectPreviewServiceTransport.interface(),
                             proxyType: ProjectPreviewServiceProtocol.self,
                             timeout: max(0, deadline - ProcessInfo.processInfo.systemUptime), invoke)
    }

    private func rpc<Value, Proxy>(connection: NSXPCConnection, interface: NSXPCInterface,
                                   proxyType: Proxy.Type, timeout seconds: TimeInterval,
                                   _ invoke: @escaping (Proxy, @escaping (Result<Value, Error>) -> Void) -> Void) async throws -> Value {
        guard seconds > 0 else { throw Self.error("The project preview service did not respond within four seconds.") }
        return try await withCheckedThrowingContinuation { continuation in
            connection.remoteObjectInterface = interface
            let reply = ProjectServiceReply(continuation, connection: connection)
            connection.interruptionHandler = { reply.finish(.failure(Self.error("The project preview service was interrupted."))) }
            connection.invalidationHandler = { reply.finish(.failure(Self.error("The project preview service could not be reached."))) }
            let timeout = DispatchWorkItem { reply.finish(.failure(Self.error("The project preview service did not respond within four seconds."))) }
            reply.timeout = timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: timeout)
            connection.resume()
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ reply.finish(.failure($0)) }) as? Proxy else {
                reply.finish(.failure(ProjectAccessError.unavailable))
                return
            }
            invoke(proxy) { reply.finish($0) }
        }
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "FourDProjectPreview", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
