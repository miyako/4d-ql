import Foundation
import QuickLookUI
import UniformTypeIdentifiers
import FourDRender
import FourDProjectAccess
import FourDQuickLookUI
import AppKit

@objc(FourDPreviewProvider)
final class PreviewProvider: NSViewController, QLPreviewingController {
    private var preparation: Task<Void, Never>?
    private var webView: PreviewWebView!

    override func loadView() {
        webView = PreviewWebView(frame: NSRect(x: 0, y: 0, width: 860, height: 1000))
        // Keep an unflipped AppKit root at the remote-view boundary.
        view = NSView(frame: webView.frame)
        webView.autoresizingMask = [.width, .height]
        view.addSubview(webView)
        preferredContentSize = NSSize(width: 860, height: 1000)
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        preparation?.cancel()
        preparation = Task { @MainActor in
            let html = await Self.html(for: url)
            guard !Task.isCancelled else {
                handler(CancellationError())
                return
            }
            _ = view
            webView.loadPreview(html: html, completion: handler)
        }
    }

    nonisolated static func html(for url: URL) async -> String {
        let contentType = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.identifier

        let pipeline = PreviewPipeline()
        let html: String
        if ["4dform", "4dcatalog", "4lbp"].contains(url.pathExtension.lowercased()) {
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
