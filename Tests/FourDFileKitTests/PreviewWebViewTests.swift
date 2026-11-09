#if os(macOS)
import XCTest
import WebKit
@testable import FourDQuickLookUI
@testable import FourDRender

@MainActor
final class PreviewWebViewTests: XCTestCase {
    private func html() -> String {
        let nodes = [
            DiagramNode(id: "A", title: "First", fields: [], position: DiagramPosition(x: 0, y: 0)),
            DiagramNode(id: "B", title: "Last", fields: [], position: DiagramPosition(x: 2000, y: 2000))
        ]
        let diagram = StructureDiagram(nodes: nodes, edges: [])
        var report = Report(title: "Structure")
        report.sections = [
            Section("First", [.structureDiagram(diagram)]),
            Section("Second", [.structureDiagram(diagram)]),
            Section("Metadata", [.text("Unchanged metadata")])
        ]
        return HTMLRenderer().render(report)
    }

    private func load(_ html: String? = nil) -> PreviewWebView {
        let webView = PreviewWebView(frame: NSRect(x: 0, y: 0, width: 860, height: 1000))
        let loaded = expectation(description: "Owned preview loaded")
        webView.loadPreview(html: html ?? self.html()) { error in
            XCTAssertNil(error)
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 15)
        return webView
    }

    private func evaluate(_ body: String, in webView: WKWebView,
                          world: WKContentWorld? = nil) throws -> Any {
        let evaluated = expectation(description: "Viewer script evaluated")
        var output: Result<Any, Error>?
        webView.callAsyncJavaScript(body, arguments: [:], in: nil, in: world ?? .defaultClient) { result in
            output = result
            evaluated.fulfill()
        }
        wait(for: [evaluated], timeout: 10)
        return try XCTUnwrap(output).get()
    }

    func testOwnedViewerEnablesContinuousControlsWithoutPageScripts() throws {
        let webView = load()
        XCTAssertFalse(webView.configuration.defaultWebpagePreferences.allowsContentJavaScript)
        XCTAssertFalse(webView.configuration.websiteDataStore.isPersistent)
        XCTAssertFalse(webView.allowsMagnification)
        XCTAssertTrue(webView.gestureRecognizers.contains { $0 is NSMagnificationGestureRecognizer })
        let values = try XCTUnwrap(evaluate("""
        return {
            presets:document.querySelectorAll('.diagram-zoom-choice').length,
            sliders:document.querySelectorAll('.diagram-zoom-controls input[type=range]').length,
            outputs:[...document.querySelectorAll('.diagram-zoom-controls output')].map(e => e.value),
            bridge:typeof globalThis.webkit?.messageHandlers?.fourdDiagramZoom,
            pageScale:window.devicePixelRatio
        };
        """, in: webView) as? [String: Any])
        XCTAssertEqual(values["presets"] as? Int, 0)
        XCTAssertEqual(values["sliders"] as? Int, 2)
        XCTAssertEqual(values["outputs"] as? [String], ["100%", "100%"])
        XCTAssertEqual(values["bridge"] as? String, "undefined")
        XCTAssertEqual(try evaluate("return typeof globalThis.fourdDiagramZoom;", in: webView, world: .page) as? String, "undefined")
    }

    func testNativeMagnificationAnchorsCursorAndLeavesOtherContentUnscaled() throws {
        let webView = load()
        let before = try XCTUnwrap(evaluate("""
        const viewport = document.querySelector('.diagram-viewport');
        viewport.scrollLeft = 800;
        viewport.scrollTop = 700;
        const rect = viewport.getBoundingClientRect();
        return {
            x:rect.left + viewport.clientLeft + 150,
            y:rect.top + viewport.clientTop + 120,
            width:viewport.querySelector('svg').getBoundingClientRect().width,
            height:viewport.querySelector('svg').getBoundingClientRect().height,
            heading:document.querySelector('h1').getBoundingClientRect().height,
            metadata:document.querySelectorAll('section')[2].getBoundingClientRect().height,
            other:document.querySelectorAll('.diagram-svg')[1].getBoundingClientRect().width
        };
        """, in: webView) as? [String: Double])
        let x = try XCTUnwrap(before["x"])
        let y = try XCTUnwrap(before["y"])
        let magnified = expectation(description: "Native magnification completed")
        webView.magnifyDiagram(at: NSPoint(x: x, y: webView.isFlipped ? y : webView.bounds.height - y),
                               delta: log(1.37)) { result in
            switch result {
            case .success(let value): XCTAssertEqual(value as? Bool, true)
            case .failure(let error): XCTFail("Magnification failed: \(error)")
            }
            magnified.fulfill()
        }
        wait(for: [magnified], timeout: 10)
        let after = try XCTUnwrap(evaluate("""
        const viewport = document.querySelector('.diagram-viewport');
        return {
            width:viewport.querySelector('svg').getBoundingClientRect().width,
            height:viewport.querySelector('svg').getBoundingClientRect().height,
            contentX:(viewport.scrollLeft + 150) / 1.37,
            contentY:(viewport.scrollTop + 120) / 1.37,
            heading:document.querySelector('h1').getBoundingClientRect().height,
            metadata:document.querySelectorAll('section')[2].getBoundingClientRect().height,
            other:document.querySelectorAll('.diagram-svg')[1].getBoundingClientRect().width
        };
        """, in: webView) as? [String: Double])
        XCTAssertEqual(try XCTUnwrap(after["width"]), try XCTUnwrap(before["width"]) * 1.37, accuracy: 0.1)
        XCTAssertEqual(try XCTUnwrap(after["height"]), try XCTUnwrap(before["height"]) * 1.37, accuracy: 0.1)
        XCTAssertEqual(try XCTUnwrap(after["contentX"]), 950, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(after["contentY"]), 820, accuracy: 1)
        for key in ["heading", "metadata", "other"] { XCTAssertEqual(after[key], before[key]) }
        XCTAssertEqual(try evaluate("""
        return globalThis.fourdDiagramZoom.magnify(10, 10, 0.5);
        """, in: webView) as? Bool, false)
    }

    func testSliderButtonsKeyboardResetAndBoundsKeepScrollExtentCorrect() throws {
        let webView = load()
        let values = try XCTUnwrap(evaluate("""
        const root = document.querySelector('.structure-diagram');
        const viewport = root.querySelector('.diagram-viewport');
        const svg = root.querySelector('svg');
        const original = svg.getBoundingClientRect().width;
        const slider = root.querySelector('input[type=range]');
        const output = root.querySelector('output');
        const results = [];
        for (const scale of [0.01, 0.1347, 0.8765, 2.345, 8]) {
            slider.value = Math.log(scale);
            slider.dispatchEvent(new Event('input', {bubbles:true}));
            results.push({scale, width:svg.getBoundingClientRect().width,
                scroll:viewport.scrollWidth, viewport:viewport.clientWidth, output:output.value});
        }
        root.querySelector('button[aria-label="Zoom diagram in"]').click();
        const maximum = svg.getBoundingClientRect().width / original;
        root.querySelector('button[aria-label="Reset diagram zoom"]').click();
        const reset = svg.getBoundingClientRect().width / original;
        root.querySelector('button[aria-label="Zoom diagram out"]').click();
        const out = svg.getBoundingClientRect().width / original;
        slider.dispatchEvent(new KeyboardEvent('keydown', {key:'ArrowRight', bubbles:true, cancelable:true}));
        const keyboard = svg.getBoundingClientRect().width / original;
        slider.dispatchEvent(new KeyboardEvent('keydown', {key:'Home', bubbles:true, cancelable:true}));
        root.querySelector('button[aria-label="Zoom diagram out"]').click();
        const minimum = svg.getBoundingClientRect().width / original;
        return {original, results, maximum, reset, out, keyboard, minimum};
        """, in: webView) as? [String: Any])
        let original = try XCTUnwrap(values["original"] as? Double)
        let results = try XCTUnwrap(values["results"] as? [[String: Any]])
        XCTAssertEqual(results.count, 5)
        for result in results {
            let scale = try XCTUnwrap(result["scale"] as? Double)
            let width = try XCTUnwrap(result["width"] as? Double)
            let viewport = try XCTUnwrap(result["viewport"] as? Double)
            XCTAssertEqual(width, original * scale, accuracy: 0.1)
            XCTAssertEqual(try XCTUnwrap(result["scroll"] as? Double), max(viewport, width), accuracy: 1)
            XCTAssertEqual(result["output"] as? String, "\(Int((scale * 100).rounded()))%")
        }
        for (key, expected) in [("maximum", 8.0), ("reset", 1.0), ("out", 1 / 1.2),
                                ("keyboard", 1.05 / 1.2), ("minimum", 0.01)] {
            XCTAssertEqual(try XCTUnwrap(values[key] as? Double), expected, accuracy: 0.001)
        }
    }

    func testControlWheelZoomStaysInsideDiagramAndOrdinaryWheelIsNotIntercepted() throws {
        let webView = load()
        let values = try XCTUnwrap(evaluate("""
        const viewport = document.querySelector('.diagram-viewport');
        const rect = viewport.getBoundingClientRect();
        const original = viewport.querySelector('svg').getBoundingClientRect().width;
        const wheel = new WheelEvent('wheel', {deltaY:10, bubbles:true, cancelable:true});
        viewport.dispatchEvent(wheel);
        const normalWidth = viewport.querySelector('svg').getBoundingClientRect().width;
        const pinch = new WheelEvent('wheel', {
            deltaY:-20, ctrlKey:true, clientX:rect.left + 100, clientY:rect.top + 100,
            bubbles:true, cancelable:true
        });
        viewport.dispatchEvent(pinch);
        return {ordinaryPrevented:wheel.defaultPrevented, zoomPrevented:pinch.defaultPrevented,
            original, normalWidth, zoomed:viewport.querySelector('svg').getBoundingClientRect().width};
        """, in: webView) as? [String: Any])
        XCTAssertEqual(values["ordinaryPrevented"] as? Bool, false)
        XCTAssertEqual(values["zoomPrevented"] as? Bool, true)
        let original = try XCTUnwrap(values["original"] as? Double)
        XCTAssertEqual(try XCTUnwrap(values["normalWidth"] as? Double), original)
        XCTAssertEqual(try XCTUnwrap(values["zoomed"] as? Double), original * exp(0.2), accuracy: 0.1)
    }

    func testUntrustedScriptsAndExternalResourcesStayBlocked() throws {
        let webView = load(html().replacingOccurrences(of: "</body>", with: """
        <script>globalThis.untrustedScriptRan = true;</script>
        <iframe srcdoc="<script>parent.untrustedScriptRan=true;</script>"></iframe>
        <img src="https://example.invalid/blocked.png" onerror="globalThis.untrustedScriptRan=true">
        <a href="file:///etc/passwd">File link</a>
        </body>
        """))
        XCTAssertEqual(try evaluate("return typeof globalThis.untrustedScriptRan;", in: webView, world: .page) as? String, "undefined")
        let values = try XCTUnwrap(evaluate("""
        return {
            policies:[...document.querySelectorAll('meta[http-equiv="Content-Security-Policy"]')].map(e => e.content),
            base:document.baseURI,
            scripts:typeof globalThis.fourdDiagramZoom.magnify,
            frames:window.frames.length
        };
        """, in: webView) as? [String: Any])
        let policies = try XCTUnwrap(values["policies"] as? [String])
        XCTAssertTrue(policies.contains { $0.contains("default-src 'none'; script-src 'none'") })
        XCTAssertEqual(values["base"] as? String, "about:blank")
        XCTAssertEqual(values["scripts"] as? String, "function")
    }

    func testPointerDragPansWithoutZoomAndCancellationStopsDragging() throws {
        let webView = load()
        let values = try XCTUnwrap(evaluate("""
        const viewport = document.querySelector('.diagram-viewport');
        const svg = viewport.querySelector('svg');
        const width = svg.getBoundingClientRect().width;
        const captured = [];
        // Synthetic pointer events have no active hardware pointer to capture.
        viewport.setPointerCapture = id => captured.push(id);
        viewport.scrollLeft = 500;
        viewport.scrollTop = 500;
        svg.dispatchEvent(new PointerEvent('pointerdown', {
            pointerId:1, button:0, clientX:200, clientY:200, bubbles:true, cancelable:true
        }));
        viewport.dispatchEvent(new PointerEvent('pointermove', {
            pointerId:1, clientX:140, clientY:170, bubbles:true
        }));
        const dragged = [viewport.scrollLeft, viewport.scrollTop];
        const grabbing = viewport.style.cursor;
        viewport.dispatchEvent(new PointerEvent('pointercancel', {pointerId:1, bubbles:true}));
        viewport.dispatchEvent(new PointerEvent('pointermove', {
            pointerId:1, clientX:0, clientY:0, bubbles:true
        }));
        const cancelled = [viewport.scrollLeft, viewport.scrollTop];
        svg.dispatchEvent(new PointerEvent('pointerdown', {
            pointerId:2, button:2, clientX:200, clientY:200, bubbles:true, cancelable:true
        }));
        viewport.dispatchEvent(new PointerEvent('pointermove', {pointerId:2, clientX:0, clientY:0, bubbles:true}));
        return {captured, dragged, cancelled, grabbing, cursor:viewport.style.cursor,
            rightDrag:[viewport.scrollLeft, viewport.scrollTop], width, afterWidth:svg.getBoundingClientRect().width};
        """, in: webView) as? [String: Any])
        XCTAssertEqual(values["captured"] as? [Int], [1])
        XCTAssertEqual(values["dragged"] as? [Int], [560, 530])
        XCTAssertEqual(values["cancelled"] as? [Int], [560, 530])
        XCTAssertEqual(values["rightDrag"] as? [Int], [560, 530])
        XCTAssertEqual(values["grabbing"] as? String, "grabbing")
        XCTAssertEqual(values["cursor"] as? String, "grab")
        XCTAssertEqual(values["width"] as? Double, values["afterWidth"] as? Double)
    }

    func testExternalAndFileLinkNavigationsAreRejected() throws {
        for destination in ["https://example.invalid/blocked", "file:///etc/passwd"] {
            let webView = load()
            let rejected = expectation(description: "Untrusted navigation rejected")
            let observer = PreviewNavigationObserver(viewer: webView, rejected: rejected)
            webView.navigationDelegate = observer
            webView.load(URLRequest(url: try XCTUnwrap(URL(string: destination))))
            wait(for: [rejected], timeout: 10)
            XCTAssertEqual(webView.url?.absoluteString, "about:blank")
        }
    }

    func testReloadCancelsPreviousCompletionAndReinitializesControls() throws {
        let webView = PreviewWebView(frame: NSRect(x: 0, y: 0, width: 860, height: 1000))
        let cancelled = expectation(description: "Previous load cancelled")
        let loaded = expectation(description: "Replacement load completed")
        webView.loadPreview(html: html()) { error in
            XCTAssertTrue(error is CancellationError)
            cancelled.fulfill()
        }
        webView.loadPreview(html: html()) { error in
            XCTAssertNil(error)
            loaded.fulfill()
        }
        wait(for: [cancelled, loaded], timeout: 15)
        XCTAssertEqual(try evaluate("return document.querySelectorAll('input[type=range]').length;", in: webView) as? Int, 2)
    }

    func testOtherPreviewFamiliesRemainUsable() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "form", withExtension: "4DForm",
            subdirectory: "Fixtures/FormProject/Project/Sources/Forms/Controls"))
        let webView = load(PreviewPipeline().html(for: fixture))
        let values = try XCTUnwrap(evaluate("""
        return {
            forms:document.querySelectorAll('.form-preview').length,
            sliders:document.querySelectorAll('.diagram-zoom-controls').length,
            formInputs:document.querySelectorAll('.theme-choice').length,
            zoomOutside:globalThis.fourdDiagramZoom.magnify(10, 10, 0.5)
        };
        """, in: webView) as? [String: Any])
        XCTAssertGreaterThan(try XCTUnwrap(values["forms"] as? Int), 0)
        XCTAssertGreaterThan(try XCTUnwrap(values["formInputs"] as? Int), 0)
        XCTAssertEqual(values["sliders"] as? Int, 0)
        XCTAssertEqual(values["zoomOutside"] as? Bool, false)
    }
}

@MainActor
private final class PreviewNavigationObserver: NSObject, WKNavigationDelegate {
    let viewer: PreviewWebView
    let rejected: XCTestExpectation

    init(viewer: PreviewWebView, rejected: XCTestExpectation) {
        self.viewer = viewer
        self.rejected = rejected
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        viewer.webView(webView, decidePolicyFor: navigationAction) { policy in
            XCTAssertEqual(policy, .cancel)
            decisionHandler(policy)
            self.rejected.fulfill()
        }
    }
}
#endif
