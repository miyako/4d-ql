import AppKit
import WebKit

/// Owns the viewer's interaction code without allowing scripts supplied by previewed files.
@MainActor
public final class PreviewWebView: WKWebView, WKNavigationDelegate {
    private var pending: ((Error?) -> Void)?
    private var previewNavigation: WKNavigation?
    private var failureLabel: NSTextField?

    public init(frame: NSRect) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.userContentController.addUserScript(WKUserScript(
            source: CanvasInteraction.script, injectionTime: .atDocumentEnd,
            forMainFrameOnly: true, in: .defaultClient))
        super.init(frame: frame, configuration: configuration)
        allowsMagnification = false
        navigationDelegate = self
        addGestureRecognizer(NSMagnificationGestureRecognizer(target: self, action: #selector(magnifyCanvas(_:))))
    }

    required init?(coder: NSCoder) { nil }

    // Finder hosts the preview remotely; its key window need not be key in this process.
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public func loadPreview(html: String, completion: @escaping (Error?) -> Void) {
        let previous = pending
        pending = nil
        previewNavigation = nil
        previous?(CancellationError())
        stopLoading()
        failureLabel?.removeFromSuperview()
        failureLabel = nil
        pending = completion
        // Generated previews embed their assets. Never give WebKit a project-folder base URL.
        let policy = "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; script-src 'none'; img-src data:; font-src data:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'\">"
        previewNavigation = loadHTMLString(html.replacingOccurrences(of: "<head>", with: "<head>\(policy)"), baseURL: nil)
    }

    @objc private func magnifyCanvas(_ gesture: NSMagnificationGestureRecognizer) {
        guard gesture.state == .began || gesture.state == .changed else { return }
        let delta = gesture.magnification
        gesture.magnification = 0
        magnifyCanvas(at: gesture.location(in: self), delta: delta) { result in
            if case .failure(let error) = result {
                NSLog("Canvas magnification failed: %@", error.localizedDescription)
            }
        }
    }

    func magnifyCanvas(at point: NSPoint, delta: Double,
                        completion: @escaping @MainActor @Sendable (Result<Any, Error>) -> Void) {
        let y = isFlipped ? point.y : bounds.height - point.y
        callAsyncJavaScript(
            "return globalThis.fourdCanvasZoom.magnify(x, y, delta);",
            arguments: ["x": point.x, "y": y, "delta": delta],
            in: nil, in: .defaultClient, completionHandler: completion)
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let isPreview = navigationAction.navigationType == .other
            && navigationAction.request.url?.absoluteString == "about:blank"
            && navigationAction.targetFrame?.isMainFrame == true
        decisionHandler(isPreview ? .allow : .cancel)
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        callAsyncJavaScript("return typeof globalThis.fourdCanvasZoom?.magnify === 'function';",
                            arguments: [:], in: nil, in: .defaultClient) { [weak self] result in
            switch result {
            case .success(let ready) where ready as? Bool == true:
                self?.finish(navigation, error: nil)
            case .success:
                self?.finish(navigation, error: NSError(domain: "FourDQuickLookUI", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "The preview interaction controls could not be initialized."]))
            case .failure(let error):
                self?.finish(navigation, error: error)
            }
        }
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(navigation, error: error)
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(navigation, error: error)
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        let error = NSError(domain: "FourDQuickLookUI", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "The preview web content process stopped. Reopen the preview."])
        NSLog("%@", error.localizedDescription)
        finish(previewNavigation, error: error)
        let label = NSTextField(wrappingLabelWithString: error.localizedDescription)
        label.frame = bounds.insetBy(dx: 24, dy: 24)
        label.autoresizingMask = [.width, .height]
        addSubview(label)
        failureLabel = label
    }

    private func finish(_ navigation: WKNavigation?, error: Error?) {
        guard navigation === previewNavigation else { return }
        let completion = pending
        pending = nil
        completion?(error)
    }
}
