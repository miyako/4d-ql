import Foundation
import QuickLookUI
import UniformTypeIdentifiers
import FourDRender
import FourDProjectAccess

/// Data-based Quick Look preview (macOS 12+): we hand Quick Look an HTML page
/// and it renders it, so the extension contains no UI code at all.
///
/// The class name is fixed with @objc so Info.plist can name it without a
/// module prefix (NSExtensionPrincipalClass = FourDPreviewProvider).
@objc(FourDPreviewProvider)
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let url = request.fileURL
        let html = await Self.html(for: url)
        let reply = QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 860, height: 1000)) { _ in
            Data(html.utf8)
        }
        reply.stringEncoding = .utf8
        reply.title = url.lastPathComponent
        return reply
    }

    static func html(for url: URL) async -> String {
        let contentType = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.identifier

        let pipeline = PreviewPipeline()
        let html: String
        if ["4dform", "4dcatalog"].contains(url.pathExtension.lowercased()) {
            do {
                let group = Bundle.main.object(forInfoDictionaryKey: "FourDProjectGroupIdentifier") as? String ?? ""
                if group.isEmpty {
                    html = pipeline.html(for: url, contentType: contentType)
                } else {
                    let store = try ProjectAccessStore.configured()
                    if try store.hasAuthorization(for: url) {
                        html = try await ProjectServiceClient().preview(url)
                    } else {
                        html = pipeline.html(for: url, contentType: contentType)
                    }
                }
            } catch {
                var report = pipeline.report(for: url, contentType: contentType)
                report.sections.insert(Section("Project authorization", [
                    .note(error.localizedDescription, .warning)
                ]), at: 0)
                html = pipeline.renderer.render(report)
            }
        } else {
            html = pipeline.html(for: url, contentType: contentType)
        }

        return html
    }
}
