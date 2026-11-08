import Foundation
import FourDFileKit
import FourDProjectAccess
import FourDRender
import Security

final class ProjectPreviewRoleListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let endpoint: ProjectPreviewServiceProtocol

    init(endpoint: ProjectPreviewServiceProtocol) { self.endpoint = endpoint }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier == geteuid() else { return false }
        // The anonymous listener verifies the signing requirement before invoking this delegate.
        connection.exportedInterface = ProjectPreviewServiceTransport.interface()
        connection.exportedObject = endpoint
        connection.resume()
        return true
    }
}

final class ProjectPreviewSessionBroker: NSObject, ProjectPreviewServiceSessionProtocol {
    private let authorizationListener: NSXPCListener
    private let previewListener: NSXPCListener
    private let authorizationDelegate: ProjectPreviewRoleListenerDelegate
    private let previewDelegate: ProjectPreviewRoleListenerDelegate

    @available(macOS 13.0, *)
    init(endpoint: ProjectPreviewServiceEndpoint, hostRequirement: String, previewRequirement: String) {
        authorizationDelegate = ProjectPreviewRoleListenerDelegate(endpoint: endpoint)
        previewDelegate = ProjectPreviewRoleListenerDelegate(endpoint: endpoint.previewOnlyEndpoint())
        authorizationListener = NSXPCListener.anonymous()
        previewListener = NSXPCListener.anonymous()
        super.init()
        authorizationListener.delegate = authorizationDelegate
        previewListener.delegate = previewDelegate
        authorizationListener.setConnectionCodeSigningRequirement(hostRequirement)
        previewListener.setConnectionCodeSigningRequirement(previewRequirement)
        authorizationListener.resume()
        previewListener.resume()
    }

    func openSession(authorizing: Bool, withReply reply: @escaping (NSXPCListenerEndpoint?, NSString?) -> Void) {
        reply(authorizing ? authorizationListener.endpoint : previewListener.endpoint, nil)
    }
}

final class ProjectPreviewListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let broker: ProjectPreviewSessionBroker?
    private let peerRequirement: String?

    override init() {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let endpoint = ProjectPreviewServiceEndpoint(rendererBuild: build,
            store: { try ProjectAccessStore.configured() },
            render: { url in
                let pipeline = PreviewPipeline()
                let model = try pipeline.analyzers.analyze(url: url)
                return pipeline.renderer.render(pipeline.presenters.report(for: model))
            })
        do {
            guard #available(macOS 13.0, *), let serviceIdentifier = Bundle.main.bundleIdentifier,
                  serviceIdentifier.hasSuffix(".ProjectPreviewService") else { throw ProjectAccessError.denied }
            let hostIdentifier = String(serviceIdentifier.dropLast(".ProjectPreviewService".count))
            var code: SecCode?
            var staticCode: SecStaticCode?
            var information: CFDictionary?
            guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
                  SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
                  SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation),
                                               &information) == errSecSuccess,
                  let information = information as? [String: Any],
                  let team = information[kSecCodeInfoTeamIdentifier as String] as? String else {
                throw ProjectAccessError.denied
            }
            let peers = try ProjectPreviewServiceTransport.codeSigningRequirement(
                identifiers: [hostIdentifier, hostIdentifier + ".Preview"], teamIdentifier: team)
            let host = try ProjectPreviewServiceTransport.codeSigningRequirement(
                identifiers: [hostIdentifier], teamIdentifier: team)
            peerRequirement = peers
            broker = ProjectPreviewSessionBroker(endpoint: endpoint, hostRequirement: host, previewRequirement: peers)
        } catch {
            peerRequirement = nil
            broker = nil
            NSLog("Project preview service peer verification is unavailable: %@", String(describing: error))
        }
        super.init()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier == geteuid(), let peerRequirement, let broker,
              #available(macOS 13.0, *) else { return false }
        // Foundation verifies every broker message without sandbox-denied PID inspection.
        connection.setCodeSigningRequirement(peerRequirement)
        connection.exportedInterface = ProjectPreviewServiceTransport.sessionInterface()
        connection.exportedObject = broker
        connection.resume()
        return true
    }
}

let delegate = ProjectPreviewListenerDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
