import CryptoKit
import Darwin
import Foundation

public enum ProjectPreviewExchangeError: LocalizedError, Equatable {
    case invalidRequest
    case invalidReply
    case unsupportedVersion
    case sourceChanged
    case oversizedFile
    case oversizedHTML
    case queueFull
    case storageFull
    case scanLimitExceeded
    case timedOut
    case remoteFailure(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRequest: return "The project preview request is invalid."
        case .invalidReply: return "The project preview reply does not match this request."
        case .unsupportedVersion: return "The project preview protocol version is unsupported."
        case .sourceChanged: return "The selected form changed while preparing its preview."
        case .oversizedFile: return "The project preview file exceeds its size limit."
        case .oversizedHTML: return "The project preview HTML exceeds its size limit."
        case .queueFull: return "The project preview request queue is full."
        case .storageFull: return "The shared project preview storage is full."
        case .scanLimitExceeded: return "The shared project preview directory contains too many files."
        case .timedOut: return "The authorized host did not return a fresh project preview in time."
        case .remoteFailure(let message): return message
        }
    }
}

/// No bookmark crosses the process boundary. The host must authorize and confine `path`
/// before reading it, match `rendererBuild` to its startup-captured CFBundleVersion, and
/// verify the selected source before and after dependency analysis.
public struct ProjectPreviewRequest: Codable, Equatable, Sendable {
    public let id: String
    public let path: String
    public let sourceSHA: String
    public let rendererBuild: String
    public let version: Int

    public init(id: String, path: String, sourceSHA: String, rendererBuild: String, version: Int = 1) {
        self.id = id
        self.path = path
        self.sourceSHA = sourceSHA
        self.rendererBuild = rendererBuild
        self.version = version
    }
}

public struct ProjectPreviewReply: Codable, Equatable, Sendable {
    public let id: String
    public let sourceSHA: String
    public let rendererBuild: String
    public let version: Int
    public let html: String?
    public let error: String?

    public init(id: String, sourceSHA: String, rendererBuild: String, version: Int = 1,
                html: String? = nil, error: String? = nil) {
        self.id = id
        self.sourceSHA = sourceSHA
        self.rendererBuild = rendererBuild
        self.version = version
        self.html = html
        self.error = error
    }
}

/// A bounded, atomic, fresh-nonce exchange in an already authorized app-group container.
/// Files are data only; this type never executes project methods or launches a runtime.
public struct ProjectPreviewExchange: Sendable {
    public static let version = 1
    public static let maximumSourceBytes = 4 * 1_024 * 1_024
    public static let maximumRequestBytes = 16 * 1_024
    public static let maximumHTMLBytes = 32 * 1_024 * 1_024
    public static let maximumReplyBytes = 48 * 1_024 * 1_024
    public static let maximumStorageBytes = 256 * 1_024 * 1_024
    public static let maximumPendingRequests = 32
    public static let maximumScannedFiles = 1_024
    public static let expirySeconds: TimeInterval = 60
    public let directoryURL: URL

    public init(containerURL: URL) {
        directoryURL = Self.appGroupURL(container: containerURL)
    }

    public static func appGroupURL(container: URL) -> URL {
        container.appendingPathComponent("ProjectPreviewExchange", isDirectory: true)
    }

    /// The authorized host can bootstrap storage before the extension posts its first request.
    /// Existing directories and lock files are opened without creation or permission changes.
    public func prepareStorage() throws {
        try withLock { }
    }

    /// Reads only the selected source (not its dependencies) and atomically posts a new nonce.
    public func prepareRequest(fileURL: URL, rendererBuild: String) throws -> ProjectPreviewRequest {
        guard fileURL.isFileURL, fileURL.path.hasPrefix("/"), Self.validRendererBuild(rendererBuild) else {
            throw ProjectPreviewExchangeError.invalidRequest
        }
        let data = try Self.readBounded(fileURL, maximum: Self.maximumSourceBytes)
        let request = ProjectPreviewRequest(id: UUID().uuidString, path: fileURL.standardizedFileURL.path,
                                            sourceSHA: Self.hash(data), rendererBuild: rendererBuild)
        try writeRequest(request)
        return request
    }

    public static func verifySource(fileURL: URL, expectedHash: String) throws {
        guard fileURL.isFileURL, fileURL.path.hasPrefix("/"), validHash(expectedHash) else {
            throw ProjectPreviewExchangeError.invalidRequest
        }
        let data = try readBounded(fileURL, maximum: maximumSourceBytes)
        guard hash(data) == expectedHash else { throw ProjectPreviewExchangeError.sourceChanged }
    }

    public func writeRequest(_ request: ProjectPreviewRequest) throws {
        try Self.validate(request)
        let data = try JSONEncoder().encode(request)
        guard data.count <= Self.maximumRequestBytes else { throw ProjectPreviewExchangeError.oversizedFile }
        try withLock {
            try cleanupExpiredUnlocked()
            let files = try scan()
            guard files.filter({ Self.nonce(in: $0.lastPathComponent, kind: "request") != nil }).count
                    < Self.maximumPendingRequests else { throw ProjectPreviewExchangeError.queueFull }
            let url = requestURL(id: request.id)
            // Reusing a nonce would allow a previous reply to masquerade as fresh HTML.
            guard try !Self.exists(url), try !Self.exists(replyURL(id: request.id)) else {
                throw ProjectPreviewExchangeError.invalidRequest
            }
            try checkStorage(files: files, replacing: url, with: data.count)
            try data.write(to: url, options: .atomic)
        }
    }

    /// A missing exchange directory is normal before the first request. Other I/O failures throw.
    public func pendingRequests() throws -> [ProjectPreviewRequest] {
        let urls = try scan().filter { Self.nonce(in: $0.lastPathComponent, kind: "request") != nil }
        guard urls.count <= Self.maximumPendingRequests else { throw ProjectPreviewExchangeError.queueFull }
        return try urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).compactMap { url in
            do {
                return try readRequest(at: url)
            } catch let error as NSError where Self.isMissing(error) {
                // A requesting extension may cancel and remove its own nonce during enumeration.
                return nil
            }
        }
    }

    public func readRequest(at url: URL) throws -> ProjectPreviewRequest {
        guard url.deletingLastPathComponent().standardizedFileURL == directoryURL.standardizedFileURL,
              let id = Self.nonce(in: url.lastPathComponent, kind: "request") else {
            throw ProjectPreviewExchangeError.invalidRequest
        }
        let data = try Self.readBounded(url, maximum: Self.maximumRequestBytes)
        try Self.checkKeys(data, allowed: ["id", "path", "sourceSHA", "rendererBuild", "version"])
        let request = try JSONDecoder().decode(ProjectPreviewRequest.self, from: data)
        try Self.validate(request)
        guard request.id == id else { throw ProjectPreviewExchangeError.invalidRequest }
        return request
    }

    public func respond(to request: ProjectPreviewRequest, html: String) throws {
        guard html.utf8.count <= Self.maximumHTMLBytes else { throw ProjectPreviewExchangeError.oversizedHTML }
        try writeReply(ProjectPreviewReply(id: request.id, sourceSHA: request.sourceSHA,
                                           rendererBuild: request.rendererBuild, html: html), to: request)
    }

    public func respond(to request: ProjectPreviewRequest, error: String) throws {
        try writeReply(ProjectPreviewReply(id: request.id, sourceSHA: request.sourceSHA,
                                           rendererBuild: request.rendererBuild, error: error), to: request)
    }

    public func waitForReply(to request: ProjectPreviewRequest, timeout: TimeInterval = 4) async throws -> String {
        try Self.validate(request)
        guard timeout.isFinite, timeout > 0 else { throw ProjectPreviewExchangeError.timedOut }
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(min(timeout, 4) * 1_000_000_000)
        while true {
            try Task.checkCancellation()
            if DispatchTime.now().uptimeNanoseconds >= deadline { throw ProjectPreviewExchangeError.timedOut }
            do {
                let reply = try readReply(to: request)
                if let error = reply.error { throw ProjectPreviewExchangeError.remoteFailure(error) }
                guard let html = reply.html else { throw ProjectPreviewExchangeError.invalidReply }
                return html
            } catch let error as NSError where Self.isMissing(error) {
                // Only ENOENT means "not yet". Permissions and malformed replies are visible errors.
            }
            let remaining = deadline - min(deadline, DispatchTime.now().uptimeNanoseconds)
            try await Task.sleep(nanoseconds: min(100_000_000, remaining))
        }
    }

    public func readReply(to request: ProjectPreviewRequest) throws -> ProjectPreviewReply {
        try Self.validate(request)
        let requestFile = requestURL(id: request.id)
        guard try readRequest(at: requestFile) == request, try !Self.isExpired(requestFile) else {
            throw ProjectPreviewExchangeError.invalidReply
        }
        let url = replyURL(id: request.id)
        let data = try Self.readBounded(url, maximum: Self.maximumReplyBytes)
        try Self.checkKeys(data, allowed: ["id", "sourceSHA", "rendererBuild", "version", "html", "error"])
        let reply = try JSONDecoder().decode(ProjectPreviewReply.self, from: data)
        try Self.validate(reply)
        guard reply.id == request.id, reply.sourceSHA == request.sourceSHA,
              reply.rendererBuild == request.rendererBuild,
              reply.version == request.version else { throw ProjectPreviewExchangeError.invalidReply }
        guard try !Self.isExpired(url) else { throw ProjectPreviewExchangeError.invalidReply }
        return reply
    }

    public func cleanup(request: ProjectPreviewRequest) throws {
        try Self.validate(request)
        // Derive both names only from a validated nonce, never from the untrusted source path.
        try withLock {
            try Self.removeIfPresent(requestURL(id: request.id))
            try Self.removeIfPresent(replyURL(id: request.id))
        }
    }

    public func cleanupExpired() throws {
        guard try Self.exists(directoryURL) else { return }
        try withLock { try cleanupExpiredUnlocked() }
    }

    public func requestURL(id: String) -> URL {
        directoryURL.appendingPathComponent("request-\(id).json")
    }

    public func replyURL(id: String) -> URL {
        directoryURL.appendingPathComponent("reply-\(id).json")
    }

    private func writeReply(_ reply: ProjectPreviewReply, to request: ProjectPreviewRequest) throws {
        try Self.validate(request)
        try Self.validate(reply)
        let data = try JSONEncoder().encode(reply)
        guard data.count <= Self.maximumReplyBytes else { throw ProjectPreviewExchangeError.oversizedFile }
        try withLock {
            let current = try readRequest(at: requestURL(id: request.id))
            guard current == request, try !Self.isExpired(requestURL(id: request.id)) else {
                throw ProjectPreviewExchangeError.invalidRequest
            }
            let url = replyURL(id: request.id)
            guard try !Self.exists(url) else { throw ProjectPreviewExchangeError.invalidReply }
            try checkStorage(files: scan(), replacing: url, with: data.count)
            try data.write(to: url, options: .atomic)
        }
    }

    private func checkStorage(files: [URL], replacing: URL, with bytes: Int) throws {
        var total = bytes
        for url in files where url != replacing {
            let attributes = try Self.attributes(url)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? NSNumber else {
                throw ProjectPreviewExchangeError.invalidRequest
            }
            guard size.int64Value >= 0, size.int64Value <= Int64(Self.maximumStorageBytes - total) else {
                throw ProjectPreviewExchangeError.storageFull
            }
            total += size.intValue
        }
    }

    private func cleanupExpiredUnlocked() throws {
        var inspectedBytes = 0
        for url in try scan() {
            let kind: String
            if Self.nonce(in: url.lastPathComponent, kind: "request") != nil { kind = "request" }
            else if Self.nonce(in: url.lastPathComponent, kind: "reply") != nil { kind = "reply" }
            else { continue }
            let attributes = try Self.attributes(url)
            var remove = try Self.isExpired(url)
                || attributes[.type] as? FileAttributeType != .typeRegular
            if !remove {
                let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
                let maximum = kind == "request" ? Self.maximumRequestBytes : Self.maximumReplyBytes
                if size < 0 || size > maximum {
                    try Self.removeIfPresent(url)
                    continue
                }
                guard size <= Int64(Self.maximumStorageBytes - inspectedBytes) else {
                    throw ProjectPreviewExchangeError.storageFull
                }
                inspectedBytes += Int(size)
                do {
                    if kind == "request" { _ = try readRequest(at: url) }
                    else {
                        let data = try Self.readBounded(url, maximum: Self.maximumReplyBytes)
                        try Self.checkKeys(data, allowed: ["id", "sourceSHA", "rendererBuild", "version", "html", "error"])
                        let reply = try JSONDecoder().decode(ProjectPreviewReply.self, from: data)
                        try Self.validate(reply)
                        guard reply.id == Self.nonce(in: url.lastPathComponent, kind: kind) else {
                            throw ProjectPreviewExchangeError.invalidReply
                        }
                    }
                } catch is DecodingError {
                    remove = true
                } catch is ProjectPreviewExchangeError {
                    remove = true
                }
            }
            if remove { try Self.removeIfPresent(url) }
        }
    }

    /// Enumeration stops after a fixed number of directory entries, including unrelated junk.
    private func scan() throws -> [URL] {
        guard try Self.exists(directoryURL) else { return [] }
        let attributes = try Self.attributes(directoryURL)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw ProjectPreviewExchangeError.invalidRequest
        }
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(at: directoryURL,
            includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants],
            errorHandler: { _, error in enumerationError = error; return false }) else {
            throw CocoaError(.fileReadUnknown)
        }
        var files: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            guard files.count < Self.maximumScannedFiles else { throw ProjectPreviewExchangeError.scanLimitExceeded }
            files.append(url)
        }
        if let error = enumerationError { throw error }
        return files
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        if try !Self.exists(directoryURL) {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        guard try Self.attributes(directoryURL)[.type] as? FileAttributeType == .typeDirectory else {
            throw ProjectPreviewExchangeError.invalidRequest
        }
        let lockPath = directoryURL.appendingPathComponent(".lock").path
        var descriptor = open(lockPath, O_RDWR | O_NOFOLLOW | O_NONBLOCK)
        if descriptor < 0, errno == ENOENT {
            descriptor = open(lockPath, O_CREAT | O_RDWR | O_NOFOLLOW | O_NONBLOCK, 0o600)
        }
        guard descriptor >= 0 else { throw Self.posixError() }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw Self.posixError() }
        guard (info.st_mode & S_IFMT) == S_IFREG else { throw ProjectPreviewExchangeError.invalidRequest }
        guard flock(descriptor, LOCK_EX) == 0 else { throw Self.posixError() }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }

    private static func readBounded(_ url: URL, maximum: Int) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw posixError() }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw posixError() }
        guard (info.st_mode & S_IFMT) == S_IFREG else { throw ProjectPreviewExchangeError.invalidRequest }
        guard info.st_size >= 0, info.st_size <= maximum else { throw ProjectPreviewExchangeError.oversizedFile }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: min(maximum + 1, 65_536))
        while true {
            let count = read(descriptor, &buffer, min(buffer.count, maximum + 1 - data.count))
            if count < 0 {
                if errno == EINTR { continue }
                throw posixError()
            }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
            guard data.count <= maximum else { throw ProjectPreviewExchangeError.oversizedFile }
        }
        return data
    }

    private static func validate(_ request: ProjectPreviewRequest) throws {
        guard request.version == version else { throw ProjectPreviewExchangeError.unsupportedVersion }
        guard validID(request.id), validHash(request.sourceSHA), validRendererBuild(request.rendererBuild),
              request.path.hasPrefix("/"),
              !request.path.utf8.contains(0), URL(fileURLWithPath: request.path).standardizedFileURL.path == request.path else {
            throw ProjectPreviewExchangeError.invalidRequest
        }
    }

    private static func validate(_ reply: ProjectPreviewReply) throws {
        guard reply.version == version else { throw ProjectPreviewExchangeError.unsupportedVersion }
        guard validID(reply.id), validHash(reply.sourceSHA), validRendererBuild(reply.rendererBuild),
              (reply.html == nil) != (reply.error == nil) else {
            throw ProjectPreviewExchangeError.invalidReply
        }
        if let html = reply.html, html.utf8.count > maximumHTMLBytes {
            throw ProjectPreviewExchangeError.oversizedHTML
        }
    }

    private static func validID(_ id: String) -> Bool { UUID(uuidString: id)?.uuidString == id }
    private static func validHash(_ hash: String) -> Bool {
        hash.utf8.count == 64 && hash.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func validRendererBuild(_ build: String) -> Bool {
        !build.isEmpty && build.utf8.count <= 128 && build.utf8.allSatisfy { (33...126).contains($0) }
    }
    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func nonce(in name: String, kind: String) -> String? {
        guard name.hasPrefix(kind + "-"), name.hasSuffix(".json") else { return nil }
        let id = String(name.dropFirst(kind.count + 1).dropLast(5))
        return validID(id) ? id : nil
    }
    private static func attributes(_ url: URL) throws -> [FileAttributeKey: Any] {
        try FileManager.default.attributesOfItem(atPath: url.path)
    }
    private static func exists(_ url: URL) throws -> Bool {
        do { _ = try attributes(url); return true }
        catch let error as NSError where isMissing(error) { return false }
    }
    private static func isExpired(_ url: URL) throws -> Bool {
        guard let date = try attributes(url)[.modificationDate] as? Date else {
            throw ProjectPreviewExchangeError.invalidRequest
        }
        return Date().timeIntervalSince(date) > expirySeconds
    }
    private static func removeIfPresent(_ url: URL) throws {
        do { try FileManager.default.removeItem(at: url) }
        catch let error as NSError where isMissing(error) { }
    }
    private static func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    private static func isMissing(_ error: NSError) -> Bool {
        if error.domain == NSPOSIXErrorDomain { return error.code == Int(ENOENT) }
        if error.domain == NSCocoaErrorDomain {
            return error.code == CocoaError.fileNoSuchFile.rawValue || error.code == CocoaError.fileReadNoSuchFile.rawValue
        }
        return false
    }

    /// Foundation's decoder accepts duplicate JSON keys. Reject them before decoding so a
    /// nonce/hash cannot mean different things to different implementations of the protocol.
    private static func checkKeys(_ data: Data, allowed: Set<String>) throws {
        let bytes = [UInt8](data)
        var depth = 0
        var index = 0
        var keys = Set<String>()
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 34 {
                let start = index
                index += 1
                while index < bytes.count {
                    if bytes[index] == 92 { index += 2; continue }
                    if bytes[index] == 34 { break }
                    index += 1
                }
                guard index < bytes.count else { throw ProjectPreviewExchangeError.invalidRequest }
                let end = index
                index += 1
                while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
                if depth == 1, index < bytes.count, bytes[index] == 58 {
                    let key = try JSONDecoder().decode(String.self, from: Data(bytes[start...end]))
                    guard allowed.contains(key), keys.insert(key).inserted else {
                        throw ProjectPreviewExchangeError.invalidRequest
                    }
                }
                continue
            }
            if byte == 123 || byte == 91 { depth += 1 }
            if byte == 125 || byte == 93 { depth -= 1 }
            index += 1
        }
    }
}
