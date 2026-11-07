import Foundation
import QuickLookUI
import UniformTypeIdentifiers
import FourDRender

/// Data-based Quick Look preview (macOS 12+): we hand Quick Look an HTML page
/// and it renders it, so the extension contains no UI code at all.
///
/// The class name is fixed with @objc so Info.plist can name it without a
/// module prefix (NSExtensionPrincipalClass = FourDPreviewProvider).
@objc(FourDPreviewProvider)
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let url = request.fileURL
        let contentType = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.identifier

        let html = PreviewPipeline().html(for: url, contentType: contentType)

        let reply = QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 860, height: 1000)) { _ in
            Data(html.utf8)
        }
        reply.stringEncoding = .utf8
        reply.title = url.lastPathComponent
        return reply
    }
}
