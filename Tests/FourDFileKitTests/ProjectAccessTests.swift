#if os(macOS)
import Darwin
import Foundation
import XCTest
@testable import FourDProjectAccess

final class ProjectAccessTests: XCTestCase {
    private var root: URL!
    private var exchange: ProjectPreviewExchange!
    private var source: URL!

    override func setUpWithError() throws {
        // Do not touch the real app-group container or prompt CLI filesystem/TCC access.
        root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".project-exchange-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        exchange = ProjectPreviewExchange(containerURL: root)
        source = root.appendingPathComponent("form.4DForm")
        try Data("{}".utf8).write(to: source)
    }

    override func tearDownWithError() throws {
        if let root { try FileManager.default.removeItem(at: root) }
    }

    private func post() throws -> ProjectPreviewRequest {
        try exchange.prepareRequest(fileURL: source, rendererBuild: "test-build")
    }

    func testAuthorizationRootAcceptsParentFolderWithoutProjectSources() throws {
        XCTAssertEqual(try ProjectAccessStore.authorizationRoot(for: root),
                       root.resolvingSymlinksInPath().standardizedFileURL)
        let link = root.appendingPathComponent("folder-link")
        let folder = root.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
        XCTAssertEqual(try ProjectAccessStore.authorizationRoot(for: link).path,
                       folder.resolvingSymlinksInPath().standardizedFileURL.path)
    }

    func testAuthorizationRootRejectsFilesFilesystemRootAndRemoteURLs() throws {
        for url in [source!, URL(fileURLWithPath: "/", isDirectory: true),
                    URL(string: "https://example.invalid/projects")!] {
            XCTAssertThrowsError(try ProjectAccessStore.authorizationRoot(for: url)) {
                guard case ProjectAccessError.invalidFolder = $0 else {
                    return XCTFail("Expected invalid-folder error, got \($0)")
                }
            }
        }
        XCTAssertThrowsError(try ProjectAccessStore.authorizationRoot(for: root.appendingPathComponent("missing")))
    }

    func testSavedParentFolderCoversMultipleProjectsButNotSiblingPaths() throws {
        let store = ProjectAccessStore(containerURL: root)
        let folder = root.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        XCTAssertEqual(try store.authorize(folder), folder.standardizedFileURL)
        let reopened = ProjectAccessStore(containerURL: root)
        for project in ["First", "Second"] {
            let form = folder.appendingPathComponent("\(project)/Project/Sources/Forms/Test/form.4DForm")
            XCTAssertTrue(try reopened.hasAuthorization(for: form))
        }
        XCTAssertFalse(try reopened.hasAuthorization(for:
            root.appendingPathComponent("projects-other/Project/Sources/form.4DForm")))
        XCTAssertFalse(try reopened.hasAuthorization(for: source))
        _ = try reopened.authorize(folder)
        XCTAssertEqual(try reopened.entries().count, 1)
        try reopened.removeAll()
        XCTAssertFalse(try store.hasAuthorization(for: folder.appendingPathComponent("First/form.4DForm")))
    }

    private func writeReply(_ reply: ProjectPreviewReply, named id: String) throws {
        try JSONEncoder().encode(reply).write(to: exchange.replyURL(id: id), options: .atomic)
    }

    private func assertError(_ expected: ProjectPreviewExchangeError, _ body: () throws -> Void,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) {
            XCTAssertEqual($0 as? ProjectPreviewExchangeError, expected, file: file, line: line)
        }
    }

    func testMissingDirectoryMeansNoPendingRequests() throws {
        XCTAssertEqual(try exchange.pendingRequests(), [])
        try exchange.cleanupExpired()
        XCTAssertFalse(FileManager.default.fileExists(atPath: exchange.directoryURL.path))
        let request = try post()
        XCTAssertEqual(try exchange.pendingRequests(), [request])
    }

    func testHostStorageBootstrapPreservesExistingDirectoryAndLockPermissions() throws {
        try exchange.prepareStorage()
        let lock = exchange.directoryURL.appendingPathComponent(".lock")
        XCTAssertTrue(FileManager.default.fileExists(atPath: lock.path))
        XCTAssertEqual(try exchange.pendingRequests(), [])
        try FileManager.default.setAttributes([.posixPermissions: 0o750], ofItemAtPath: exchange.directoryURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: lock.path)
        try exchange.prepareStorage()
        _ = try post()
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: exchange.directoryURL.path)[.posixPermissions] as? Int, 0o750)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: lock.path)[.posixPermissions] as? Int, 0o640)
    }

    func testActualSHA256AndChangedSource() throws {
        let request = try post()
        XCTAssertEqual(request.sourceSHA, "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a")
        try ProjectPreviewExchange.verifySource(fileURL: source, expectedHash: request.sourceSHA)
        try Data("{\"changed\":true}".utf8).write(to: source)
        assertError(.sourceChanged) {
            try ProjectPreviewExchange.verifySource(fileURL: source, expectedHash: request.sourceSHA)
        }
        let changed = try post()
        XCTAssertNotEqual(changed.sourceSHA, request.sourceSHA)
        XCTAssertNotEqual(changed.id, request.id)
    }

    func testServiceSourceHashUsesBoundedRegularFileReader() throws {
        XCTAssertEqual(try ProjectPreviewExchange.sourceHash(fileURL: source),
                       "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a")
        let handle = try FileHandle(forWritingTo: source)
        try handle.truncate(atOffset: UInt64(ProjectPreviewExchange.maximumSourceBytes + 1))
        try handle.close()
        assertError(.oversizedFile) { _ = try ProjectPreviewExchange.sourceHash(fileURL: source) }
        let link = root.appendingPathComponent("linked.4DForm")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        XCTAssertThrowsError(try ProjectPreviewExchange.sourceHash(fileURL: link))
        XCTAssertThrowsError(try ProjectPreviewExchange.sourceHash(fileURL: root))
    }

    func testServiceClientRejectsOversizedSourceBeforeOpeningXPC() async throws {
        let handle = try FileHandle(forWritingTo: source)
        try handle.truncate(atOffset: UInt64(ProjectPreviewExchange.maximumSourceBytes + 1))
        try handle.close()
        do {
            _ = try await ProjectServiceClient().preview(source)
            XCTFail("Oversized forms must be rejected before XPC.")
        } catch {
            XCTAssertEqual(error as? ProjectPreviewExchangeError, .oversizedFile)
        }
    }

    func testFreshReplyRoundTripAndOwnCleanup() async throws {
        let request = try post()
        let other = try post()
        try exchange.respond(to: request, html: "<html>fresh</html>")
        let html = try await exchange.waitForReply(to: request)
        XCTAssertEqual(html, "<html>fresh</html>")
        try exchange.cleanup(request: request)
        XCTAssertFalse(FileManager.default.fileExists(atPath: exchange.replyURL(id: request.id).path))
        XCTAssertEqual(try exchange.pendingRequests(), [other])
    }

    func testOldOtherNonceCannotSatisfyNewRequest() async throws {
        let old = try post()
        try exchange.respond(to: old, html: "stale")
        let fresh = try post()
        do {
            _ = try await exchange.waitForReply(to: fresh, timeout: 0.12)
            XCTFail("Old HTML must not satisfy a fresh request")
        } catch {
            XCTAssertEqual(error as? ProjectPreviewExchangeError, .timedOut)
        }
    }

    func testDelayedAtomicReplyAndCancellation() async throws {
        let request = try post()
        let exchange = self.exchange!
        let responder = Task {
            try await Task.sleep(nanoseconds: 120_000_000)
            try exchange.respond(to: request, html: "fresh dependencies")
        }
        let html = try await exchange.waitForReply(to: request)
        try await responder.value
        XCTAssertEqual(html, "fresh dependencies")
        let waiting = try post()
        let task = Task { try await exchange.waitForReply(to: waiting) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation must propagate") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testExplicitHostAuthorizationError() async throws {
        let request = try post()
        try exchange.respond(to: request, error: "Authorize this project in the host.")
        do { _ = try await exchange.waitForReply(to: request); XCTFail("Expected visible host error") }
        catch { XCTAssertEqual(error as? ProjectPreviewExchangeError, .remoteFailure("Authorize this project in the host.")) }
    }

    func testNonceAndHashMismatchesRejected() throws {
        let request = try post()
        try writeReply(ProjectPreviewReply(id: UUID().uuidString, sourceSHA: request.sourceSHA,
                                           rendererBuild: request.rendererBuild, html: "stale"),
                       named: request.id)
        assertError(.invalidReply) { _ = try exchange.readReply(to: request) }
        try writeReply(ProjectPreviewReply(id: request.id, sourceSHA: String(repeating: "0", count: 64),
                                           rendererBuild: request.rendererBuild, html: "stale"),
                       named: request.id)
        assertError(.invalidReply) { _ = try exchange.readReply(to: request) }
        try writeReply(ProjectPreviewReply(id: request.id, sourceSHA: request.sourceSHA,
                                           rendererBuild: request.rendererBuild, version: 2, html: "stale"),
                       named: request.id)
        assertError(.unsupportedVersion) { _ = try exchange.readReply(to: request) }
    }

    func testCatalogSourceUsesCatalogSizeLimitAndVerifiesChanges() throws {
        let catalog = root.appendingPathComponent("catalog.4DCatalog")
        try Data(repeating: 32, count: ProjectPreviewExchange.maximumSourceBytes + 1).write(to: catalog)
        let request = try exchange.prepareRequest(fileURL: catalog, rendererBuild: "test-build")
        try ProjectPreviewExchange.verifySource(fileURL: catalog, expectedHash: request.sourceSHA)
        try Data("<base/>".utf8).write(to: catalog)
        assertError(.sourceChanged) {
            try ProjectPreviewExchange.verifySource(fileURL: catalog, expectedHash: request.sourceSHA)
        }
        let handle = try FileHandle(forWritingTo: catalog)
        try handle.truncate(atOffset: UInt64(ProjectPreviewExchange.maximumCatalogBytes + 1))
        try handle.close()
        assertError(.oversizedFile) {
            _ = try exchange.prepareRequest(fileURL: catalog, rendererBuild: "test-build")
        }
    }

    func testReplyCannotContainBothHTMLAndError() throws {
        let request = try post()
        try writeReply(ProjectPreviewReply(id: request.id, sourceSHA: request.sourceSHA,
                                           rendererBuild: request.rendererBuild, html: "x", error: "y"),
                       named: request.id)
        assertError(.invalidReply) { _ = try exchange.readReply(to: request) }
    }

    func testCorruptJSONIsVisibleNotTimeout() async throws {
        let request = try post()
        try Data("{".utf8).write(to: exchange.replyURL(id: request.id))
        do { _ = try await exchange.waitForReply(to: request); XCTFail("Expected malformed JSON error") }
        catch { XCTAssertTrue(error is DecodingError) }
        try Data("{".utf8).write(to: exchange.requestURL(id: request.id))
        XCTAssertThrowsError(try exchange.pendingRequests())
    }

    func testDuplicateSourceAndNonceKeysRejected() throws {
        let request = try post()
        let duplicate = """
        {"id":"\(request.id)","path":"\(source.path)","sourceSHA":"\(request.sourceSHA)",
        "sourceSHA":"\(request.sourceSHA)","rendererBuild":"test-build","version":1}
        """
        try Data(duplicate.utf8).write(to: exchange.requestURL(id: request.id))
        assertError(.invalidRequest) { _ = try exchange.pendingRequests() }
        let duplicateID = """
        {"id":"\(request.id)","\\u0069d":"\(request.id)","sourceSHA":"\(request.sourceSHA)",
        "rendererBuild":"test-build","html":"x","version":1}
        """
        try Data(duplicateID.utf8).write(to: exchange.replyURL(id: request.id))
        assertError(.invalidRequest) { _ = try exchange.readReply(to: request) }
    }

    func testMalformedPathsVersionsAndNonceCannotWriteOutsideExchange() throws {
        let request = try post()
        for path in ["relative/form.4DForm", "/root/../outside", "/a\0b"] {
            assertError(.invalidRequest) {
                try exchange.writeRequest(ProjectPreviewRequest(id: UUID().uuidString, path: path,
                                                               sourceSHA: request.sourceSHA, rendererBuild: "test-build"))
            }
        }
        assertError(.invalidRequest) {
            try exchange.writeRequest(ProjectPreviewRequest(id: "../outside", path: source.path,
                                                           sourceSHA: request.sourceSHA, rendererBuild: "test-build"))
        }
        assertError(.unsupportedVersion) {
            try exchange.writeRequest(ProjectPreviewRequest(id: UUID().uuidString, path: source.path,
                                                           sourceSHA: request.sourceSHA, rendererBuild: "test-build", version: 2))
        }
        assertError(.invalidRequest) { try exchange.writeRequest(request) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("outside.json").path))
    }

    func testFilenameMustMatchEncodedNonceAndCanonicalUUID() throws {
        let request = try post()
        let otherID = UUID().uuidString
        try JSONEncoder().encode(request).write(to: exchange.requestURL(id: otherID))
        assertError(.invalidRequest) { _ = try exchange.pendingRequests() }
        XCTAssertThrowsError(try exchange.readRequest(at: exchange.requestURL(id: request.id.lowercased())))
        try FileManager.default.removeItem(at: exchange.requestURL(id: otherID))
        try Data("not a request".utf8).write(to: exchange.directoryURL.appendingPathComponent("request-not-a-uuid.json"))
        XCTAssertEqual(try exchange.pendingRequests(), [request])
    }

    func testSourceAndRequestReadBounds() throws {
        try Data(repeating: 120, count: ProjectPreviewExchange.maximumSourceBytes).write(to: source)
        _ = try post()
        try Data(repeating: 120, count: ProjectPreviewExchange.maximumSourceBytes + 1).write(to: source)
        assertError(.oversizedFile) { _ = try post() }
        let id = UUID().uuidString
        try Data(repeating: 32, count: ProjectPreviewExchange.maximumRequestBytes + 1)
            .write(to: exchange.requestURL(id: id))
        assertError(.oversizedFile) { _ = try exchange.readRequest(at: exchange.requestURL(id: id)) }
    }

    func testHTMLAndReplyReadBounds() throws {
        let request = try post()
        assertError(.oversizedHTML) {
            try exchange.respond(to: request, html: String(repeating: "x", count: ProjectPreviewExchange.maximumHTMLBytes + 1))
        }
        let url = exchange.replyURL(id: request.id)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(ProjectPreviewExchange.maximumReplyBytes + 1))
        try handle.close()
        assertError(.oversizedFile) { _ = try exchange.readReply(to: request) }
        try exchange.cleanupExpired()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testBoundedQueueAndConcurrentAtomicReads() throws {
        for _ in 0..<ProjectPreviewExchange.maximumPendingRequests { _ = try post() }
        XCTAssertEqual(try exchange.pendingRequests().count, ProjectPreviewExchange.maximumPendingRequests)
        assertError(.queueFull) { _ = try post() }
        let requests = try exchange.pendingRequests()
        let failures = LockedFailures()
        let exchange = self.exchange!
        DispatchQueue.concurrentPerform(iterations: 64) { index in
            do {
                if index < requests.count { try exchange.respond(to: requests[index], html: "reply-\(index)") }
                else { XCTAssertEqual(try exchange.pendingRequests().count, requests.count) }
            } catch { failures.append(error) }
        }
        XCTAssertTrue(failures.errors.isEmpty, "\(failures.errors)")
        for (index, request) in requests.enumerated() {
            XCTAssertEqual(try exchange.readReply(to: request).html, "reply-\(index)")
        }
    }

    func testConcurrentRequestPublicationAndReplyReaders() async throws {
        let exchange = self.exchange!
        let source = self.source!
        let failures = LockedFailures()
        DispatchQueue.concurrentPerform(iterations: 64) { index in
            do {
                if index < 32 { _ = try exchange.prepareRequest(fileURL: source, rendererBuild: "test-build") }
                else { _ = try exchange.pendingRequests() }
            } catch { failures.append(error) }
        }
        XCTAssertTrue(failures.errors.isEmpty, "\(failures.errors)")
        let requests = try exchange.pendingRequests()
        XCTAssertEqual(requests.count, 32)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for request in requests {
                group.addTask {
                    let html = try await exchange.waitForReply(to: request)
                    XCTAssertEqual(html, "atomic-\(request.id)")
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 100_000_000)
                for request in requests { try exchange.respond(to: request, html: "atomic-\(request.id)") }
            }
            try await group.waitForAll()
        }
    }

    func testExpiredRequestCannotAcceptFreshlyDatedReply() throws {
        let request = try post()
        try writeReply(ProjectPreviewReply(id: request.id, sourceSHA: request.sourceSHA,
                                           rendererBuild: request.rendererBuild, html: "old request"),
                       named: request.id)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -61)],
                                             ofItemAtPath: exchange.requestURL(id: request.id).path)
        assertError(.invalidReply) { _ = try exchange.readReply(to: request) }
        assertError(.invalidRequest) { try exchange.respond(to: request, html: "must reject") }
    }

    func testStorageBudgetIncludesUnrelatedRegularFiles() throws {
        _ = try post()
        let url = exchange.directoryURL.appendingPathComponent("junk")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(ProjectPreviewExchange.maximumStorageBytes))
        try handle.close()
        assertError(.storageFull) { _ = try post() }
    }

    func testBoundedEnumerationOfJunk() throws {
        _ = try post()
        for index in 0..<ProjectPreviewExchange.maximumScannedFiles {
            try Data().write(to: exchange.directoryURL.appendingPathComponent("junk-\(index)"))
        }
        assertError(.scanLimitExceeded) { _ = try exchange.pendingRequests() }
        assertError(.scanLimitExceeded) { try exchange.cleanupExpired() }
    }

    func testExpiredAndInvalidOwnedFilesCleanedButUnrelatedFilesRemain() throws {
        let expired = try post()
        let fresh = try post()
        try exchange.respond(to: expired, html: "old")
        for url in [exchange.requestURL(id: expired.id), exchange.replyURL(id: expired.id)] {
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -61)], ofItemAtPath: url.path)
        }
        assertError(.invalidReply) { _ = try exchange.readReply(to: expired) }
        let invalid = exchange.requestURL(id: UUID().uuidString)
        try Data("garbage".utf8).write(to: invalid)
        let unrelated = exchange.directoryURL.appendingPathComponent("request-not-a-uuid.json")
        try Data("garbage".utf8).write(to: unrelated)
        try exchange.cleanupExpired()
        XCTAssertEqual(try exchange.pendingRequests(), [fresh])
        XCTAssertFalse(FileManager.default.fileExists(atPath: invalid.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: exchange.replyURL(id: expired.id).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testSymlinksAndNonRegularFilesAreNotRead() throws {
        let request = try post()
        let url = exchange.replyURL(id: request.id)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: source)
        XCTAssertThrowsError(try exchange.readReply(to: request)) {
            XCTAssertEqual(($0 as NSError).domain, NSPOSIXErrorDomain)
            XCTAssertEqual(($0 as NSError).code, Int(ELOOP))
        }
        try exchange.cleanupExpired()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(mkfifo(url.path, 0o600), 0)
        assertError(.invalidRequest) { _ = try exchange.readReply(to: request) }
    }

    func testPermissionErrorsAreDistinctFromMissingReplies() async throws {
        // macOS's test runner normally runs as the current non-root developer.
        guard geteuid() != 0 else { throw XCTSkip("Root bypasses Unix read permissions") }
        let request = try post()
        let url = exchange.replyURL(id: request.id)
        try Data("{}".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        defer { _ = chmod(url.path, 0o600) }
        do { _ = try await exchange.waitForReply(to: request); XCTFail("Expected permission failure, not timeout") }
        catch {
            XCTAssertEqual((error as NSError).domain, NSPOSIXErrorDomain)
            XCTAssertEqual((error as NSError).code, Int(EACCES))
        }
    }

    func testOldHostRendererBuildCannotSatisfyNewExtension() async throws {
        let request = try exchange.prepareRequest(fileURL: source, rendererBuild: "2.0.42")
        XCTAssertEqual(try exchange.pendingRequests().first?.rendererBuild, "2.0.42")
        try writeReply(ProjectPreviewReply(id: request.id, sourceSHA: request.sourceSHA,
                                           rendererBuild: "2.0.41", html: "old host HTML"), named: request.id)
        do { _ = try await exchange.waitForReply(to: request); XCTFail("Expected renderer build mismatch") }
        catch { XCTAssertEqual(error as? ProjectPreviewExchangeError, .invalidReply) }
        try FileManager.default.removeItem(at: exchange.replyURL(id: request.id))
        try exchange.respond(to: request, html: "current host HTML")
        XCTAssertEqual(try exchange.readReply(to: request).rendererBuild, request.rendererBuild)
        let html = try await exchange.waitForReply(to: request)
        XCTAssertEqual(html, "current host HTML")
    }

    func testMissingAndInvalidRendererBuildsRejected() throws {
        for build in ["", " ", "1\n2", String(repeating: "x", count: 129)] {
            assertError(.invalidRequest) { _ = try exchange.prepareRequest(fileURL: source, rendererBuild: build) }
        }
        let request = try post()
        let oldReply = """
        {"id":"\(request.id)","sourceSHA":"\(request.sourceSHA)","version":1,"html":"old host HTML"}
        """
        try Data(oldReply.utf8).write(to: exchange.replyURL(id: request.id))
        XCTAssertThrowsError(try exchange.readReply(to: request)) { XCTAssertTrue($0 is DecodingError) }
        let oldRequest = """
        {"id":"\(request.id)","path":"\(source.path)","sourceSHA":"\(request.sourceSHA)","version":1}
        """
        try Data(oldRequest.utf8).write(to: exchange.requestURL(id: request.id))
        XCTAssertThrowsError(try exchange.pendingRequests()) { XCTAssertTrue($0 is DecodingError) }
        try exchange.cleanupExpired()
        XCTAssertEqual(try exchange.pendingRequests(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: exchange.replyURL(id: request.id).path))
    }
}

private final class LockedFailures: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Error] = []
    var errors: [Error] { lock.lock(); defer { lock.unlock() }; return values }
    func append(_ error: Error) { lock.lock(); defer { lock.unlock() }; values.append(error) }
}

final class ProjectPreviewServiceTests: XCTestCase {
    private let sourceHash = "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"

    func testBoundedSecureCodingInterfaceConstructs() {
        XCTAssertNotNil(ProjectPreviewServiceTransport.interface())
        XCTAssertNotNil(ProjectPreviewServiceTransport.sessionInterface())
    }

    func testPeerRequirementAllowsOnlyExactIdentifiersAndRejectsInjection() throws {
        let requirement = try ProjectPreviewServiceTransport.codeSigningRequirement(
            identifiers: ["com.example.preview", "com.example.preview.Preview"], teamIdentifier: "ABCDEFGHIJ")
        XCTAssertTrue(requirement.contains("anchor apple generic"))
        XCTAssertTrue(requirement.contains("certificate leaf[subject.OU] = \"ABCDEFGHIJ\""))
        XCTAssertTrue(requirement.contains("(identifier \"com.example.preview\" or identifier \"com.example.preview.Preview\")"))
        XCTAssertThrowsError(try ProjectPreviewServiceTransport.codeSigningRequirement(
            identifiers: ["com.example\" or true"], teamIdentifier: "ABCDEFGHIJ"))
        XCTAssertThrowsError(try ProjectPreviewServiceTransport.codeSigningRequirement(
            identifiers: ["com.example"], teamIdentifier: ""))
    }

    func testPreviewPeerCannotAuthorizeOrRevokePreviouslyGrantedRoots() {
        let endpoint = ProjectPreviewServiceEndpoint(rendererBuild: "42",
            store: { XCTFail("Preview peer must not mutate authorization"); throw ProjectAccessError.denied },
            render: { _ in XCTFail("No rendering requested"); return "" }).previewOnlyEndpoint()
        endpoint.authorizeProject(URL(fileURLWithPath: "/project") as NSURL, bookmarkData: Data() as NSData) { root, error in
            XCTAssertNil(root)
            XCTAssertNotNil(error)
        }
        endpoint.revoke { error in XCTAssertNotNil(error) }
    }

    func testPreviewValidationRequiresExactNonceHashAndBuild() throws {
        let url = URL(fileURLWithPath: "/project/Project/Sources/Forms/Test/form.4DForm")
        let id = UUID().uuidString
        try ProjectPreviewServiceTransport.validatePreview(fileURL: url, nonce: id, sourceSHA: sourceHash,
                                                           rendererBuild: "42", expectedRendererBuild: "42")
        try ProjectPreviewServiceTransport.validatePreview(
            fileURL: URL(fileURLWithPath: "/project/Project/Sources/catalog.4DCatalog"),
            nonce: id, sourceSHA: sourceHash, rendererBuild: "42", expectedRendererBuild: "42")
        try ProjectPreviewServiceTransport.validatePreview(
            fileURL: URL(fileURLWithPath: "/project/Resources/address.4LBP"),
            nonce: id, sourceSHA: sourceHash, rendererBuild: "42", expectedRendererBuild: "42")
        for nonce in ["../outside", id.lowercased(), ""] {
            XCTAssertThrowsError(try ProjectPreviewServiceTransport.validatePreview(fileURL: url, nonce: nonce,
                sourceSHA: sourceHash, rendererBuild: "42", expectedRendererBuild: "42"))
        }
        for badHash in ["", String(repeating: "A", count: 64), String(repeating: "0", count: 65)] {
            XCTAssertThrowsError(try ProjectPreviewServiceTransport.validatePreview(fileURL: url, nonce: id,
                sourceSHA: badHash, rendererBuild: "42", expectedRendererBuild: "42"))
        }
        XCTAssertThrowsError(try ProjectPreviewServiceTransport.validatePreview(fileURL: url, nonce: id,
            sourceSHA: sourceHash, rendererBuild: "41", expectedRendererBuild: "42"))
        XCTAssertThrowsError(try ProjectPreviewServiceTransport.validatePreview(fileURL: URL(string: "https://example.invalid/form.4DForm")!,
            nonce: id, sourceSHA: sourceHash, rendererBuild: "42", expectedRendererBuild: "42"))
        XCTAssertThrowsError(try ProjectPreviewServiceTransport.validatePreview(fileURL: URL(fileURLWithPath: "/project/method.4dm"),
            nonce: id, sourceSHA: sourceHash, rendererBuild: "42", expectedRendererBuild: "42"))
    }

    func testServiceNeverRendersWithoutRootAuthorization() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".project-service-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer {
            do { try FileManager.default.removeItem(at: root) }
            catch { XCTFail("Test cleanup failed: \(error)") }
        }
        let endpoint = ProjectPreviewServiceEndpoint(rendererBuild: "42",
            store: { ProjectAccessStore(containerURL: root) },
            render: { _ in XCTFail("Unapproved source must not be analyzed"); return "unsafe" })
        let replied = expectation(description: "explicit authorization error")
        let nonce = UUID().uuidString
        endpoint.preview(root.appendingPathComponent("form.4DForm") as NSURL, nonce: nonce as NSString,
                         sourceSHA: sourceHash as NSString, rendererBuild: "42") { html, error, replyNonce, replyHash, replyBuild in
            XCTAssertNil(html)
            XCTAssertNotNil(error)
            XCTAssertEqual(replyNonce as String, nonce)
            XCTAssertEqual(replyHash as String, self.sourceHash)
            XCTAssertEqual(replyBuild as String, "42")
            replied.fulfill()
        }
        wait(for: [replied], timeout: 2)
    }

    func testServiceRejectsInvalidBookmarkAndBuildBeforeStorageAccess() {
        let endpoint = ProjectPreviewServiceEndpoint(rendererBuild: "42",
            store: { XCTFail("Invalid inputs must not access shared storage"); throw ProjectAccessError.denied },
            render: { _ in XCTFail("Invalid input must not render"); return "" })
        endpoint.authorizeProject(URL(fileURLWithPath: "/project") as NSURL,
                                  bookmarkData: Data(repeating: 0, count: 65_537) as NSData) { root, error in
            XCTAssertNil(root)
            XCTAssertNotNil(error)
        }
        endpoint.preview(URL(fileURLWithPath: "/project/form.4DForm") as NSURL, nonce: UUID().uuidString as NSString,
                         sourceSHA: sourceHash as NSString, rendererBuild: "41") { html, error, _, _, _ in
            XCTAssertNil(html)
            XCTAssertNotNil(error)
        }
    }

    func testServiceVerifiesSourceBeforeAndAfterRenderer() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".project-service-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer {
            do { try FileManager.default.removeItem(at: root) }
            catch { XCTFail("Test cleanup failed: \(error)") }
        }
        let source = root.appendingPathComponent("form.4DForm")
        try Data("{}".utf8).write(to: source)
        XCTAssertEqual(try ProjectPreviewServiceTransport.renderVerified(fileURL: source, expectedHash: sourceHash,
                                                                         render: { _ in "fresh" }), "fresh")
        XCTAssertThrowsError(try ProjectPreviewServiceTransport.renderVerified(fileURL: source, expectedHash: sourceHash,
            render: { _ in try Data("{\"changed\":true}".utf8).write(to: source); return "stale" })) {
                XCTAssertEqual($0 as? ProjectPreviewExchangeError, .sourceChanged)
            }
        XCTAssertThrowsError(try ProjectPreviewServiceTransport.renderVerified(fileURL: source, expectedHash: sourceHash,
            render: { _ in XCTFail("Changed source must not render"); return "" })) {
                XCTAssertEqual($0 as? ProjectPreviewExchangeError, .sourceChanged)
            }
    }

    func testServiceQueueAdmissionIsBoundedAndRecovers() {
        let queue = ProjectPreviewServiceWorkQueue()
        let gate = DispatchSemaphore(value: 0)
        let finished = expectation(description: "bounded operations")
        finished.expectedFulfillmentCount = 32
        XCTAssertTrue(queue.submit { gate.wait(); finished.fulfill() })
        for _ in 1..<32 { XCTAssertTrue(queue.submit { finished.fulfill() }) }
        XCTAssertFalse(queue.submit { XCTFail("Over-limit operation must not execute") })
        gate.signal()
        wait(for: [finished], timeout: 2)
        let recovered = expectation(description: "queue recovers")
        XCTAssertTrue(queue.submit { recovered.fulfill() })
        wait(for: [recovered], timeout: 2)
    }
}
#endif
