#if os(macOS)
import XCTest
import WebKit
import FourDFileKit
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

    private func formHTML(large: Bool = true) throws -> String {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "form", withExtension: "4DForm",
            subdirectory: "Fixtures/FormProject/Project/Sources/Forms/Controls"))
        var form = try FormFileAnalyzer(platforms: [.macOS, .windows]).analyzeForm(ByteSource(url: fixture))
        if large {
            form.properties["width"] = .integer(2400)
            form.properties["height"] = .integer(1800)
        }
        return HTMLRenderer().render(FormPresenter().formReport(form, initialTheme: .classicLight))
    }

    func testConsecutiveNativeClicksWorkWithoutAKeyWindow() throws {
        let webView = load(try formHTML(large: false))
        let window = NSWindow(contentRect: webView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.orderFront(nil)
        defer { window.close() }
        var eventNumber = 0
        func click(_ selector: String) throws {
            let point = try XCTUnwrap(evaluate("""
            const control = document.querySelector('\(selector)');
            control.scrollIntoView({block:'center'});
            const rect = control.getBoundingClientRect();
            return {x:rect.left + rect.width / 2, y:rect.top + rect.height / 2};
            """, in: webView) as? [String: Double])
            let x = try XCTUnwrap(point["x"])
            let y = try XCTUnwrap(point["y"])
            let location = webView.convert(NSPoint(x: x, y: webView.isFlipped ? y : webView.bounds.height - y), to: nil)
            eventNumber += 1
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: eventNumber, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
                window.sendEvent(event)
                _ = try evaluate("await new Promise(resolve => setTimeout(resolve, 100)); return true;", in: webView)
            }
            XCTAssertFalse(window.isKeyWindow)
        }
        for id in ["platform-windows", "platform-macOS", "theme-glassDark", "theme-classicLight",
                   "page-classicLight-2", "page-classicLight-1"] {
            try click("label[for=\"\(id)\"]")
            XCTAssertEqual(try evaluate("return document.getElementById('\(id)').checked;", in: webView) as? Bool, true, id)
        }
        try click("button[aria-label=\"Zoom form in\"]")
        XCTAssertEqual(try evaluate("return document.querySelector('.form-zoom-controls output').value;", in: webView) as? String, "120%")
        try click("button[aria-label=\"Reset form zoom\"]")
        XCTAssertEqual(try evaluate("return document.querySelector('.form-zoom-controls output').value;", in: webView) as? String, "100%")
    }

    func testFormZoomControlsBoundsAndScrollExtents() throws {
        let webView = load(try formHTML())
        let values = try XCTUnwrap(evaluate("""
        const root = document.querySelector('.form-zoom');
        const viewport = [...root.querySelectorAll('.form-scroll')].find(e => e.getClientRects().length);
        const svg = viewport.querySelector('svg');
        const slider = root.querySelector('input[type=range]');
        const output = root.querySelector('output');
        const results = [];
        for (const scale of [0.01, 0.1347, 0.8765, 2.345, 8]) {
            slider.value = Math.log(scale);
            slider.dispatchEvent(new Event('input', {bubbles:true}));
            results.push({scale, width:svg.getBoundingClientRect().width, height:svg.getBoundingClientRect().height,
                scrollWidth:viewport.scrollWidth, scrollHeight:viewport.scrollHeight,
                viewportWidth:viewport.clientWidth, viewportHeight:viewport.clientHeight, output:output.value});
        }
        root.querySelector('button[aria-label="Zoom form in"]').click();
        const maximum = svg.getBoundingClientRect().width / 2400;
        root.querySelector('button[aria-label="Reset form zoom"]').click();
        const reset = svg.getBoundingClientRect().width / 2400;
        root.querySelector('button[aria-label="Zoom form out"]').click();
        const out = svg.getBoundingClientRect().width / 2400;
        slider.dispatchEvent(new KeyboardEvent('keydown', {key:'ArrowRight', bubbles:true, cancelable:true}));
        const keyboard = svg.getBoundingClientRect().width / 2400;
        slider.dispatchEvent(new KeyboardEvent('keydown', {key:'End', bubbles:true, cancelable:true}));
        const end = svg.getBoundingClientRect().width / 2400;
        slider.dispatchEvent(new KeyboardEvent('keydown', {key:'Home', bubbles:true, cancelable:true}));
        root.querySelector('button[aria-label="Zoom form out"]').click();
        return {results, maximum, reset, out, keyboard, end, minimum:svg.getBoundingClientRect().width / 2400,
            presets:root.querySelectorAll('.form-zoom-choice').length,
            sliders:root.querySelectorAll('input[type=range]').length,
            accessible:slider.getAttribute('aria-valuetext')};
        """, in: webView) as? [String: Any])
        let results = try XCTUnwrap(values["results"] as? [[String: Any]])
        XCTAssertEqual(results.count, 5)
        for result in results {
            let scale = try XCTUnwrap(result["scale"] as? Double)
            for (dimension, original) in [("Width", 2400.0), ("Height", 1800.0)] {
                let size = try XCTUnwrap(result[dimension.lowercased()] as? Double)
                let extent = try XCTUnwrap(result["scroll\(dimension)"] as? Double)
                let viewport = try XCTUnwrap(result["viewport\(dimension)"] as? Double)
                XCTAssertEqual(size, original * scale, accuracy: 0.1)
                XCTAssertEqual(extent, max(viewport, size), accuracy: 1)
            }
            XCTAssertEqual(result["output"] as? String, "\(Int((scale * 100).rounded()))%")
        }
        for (key, expected) in [("maximum", 8.0), ("reset", 1.0), ("out", 1 / 1.2),
                                ("keyboard", 1.05 / 1.2), ("end", 8.0), ("minimum", 0.01)] {
            XCTAssertEqual(try XCTUnwrap(values[key] as? Double), expected, accuracy: 0.001)
        }
        XCTAssertEqual(values["presets"] as? Int, 0)
        XCTAssertEqual(values["sliders"] as? Int, 1)
        XCTAssertEqual(values["accessible"] as? String, "1%")
    }

    func testNativeFormMagnificationAnchorsCursorWithoutScalingControlsOrMetadata() throws {
        let webView = load(try formHTML())
        let before = try XCTUnwrap(evaluate("""
        const viewport = [...document.querySelectorAll('.form-scroll')].find(e => e.getClientRects().length);
        viewport.scrollIntoView({block:'start'});
        viewport.scrollLeft = 600;
        viewport.scrollTop = 400;
        const rect = viewport.getBoundingClientRect();
        return {x:rect.left + viewport.clientLeft + 150, y:rect.top + viewport.clientTop + 120,
            heading:document.querySelector('h1').getBoundingClientRect().height,
            controls:document.querySelector('.form-zoom-controls').getBoundingClientRect().height,
            themes:document.querySelector('.form-themes').getBoundingClientRect().height,
            caption:document.querySelector('.form-caption').textContent};
        """, in: webView) as? [String: Any])
        let x = try XCTUnwrap(before["x"] as? Double)
        let y = try XCTUnwrap(before["y"] as? Double)
        let magnified = expectation(description: "Native form magnification completed")
        webView.magnifyCanvas(at: NSPoint(x: x, y: webView.isFlipped ? y : webView.bounds.height - y),
                             delta: log(1.37)) { result in
            switch result {
            case .success(let value): XCTAssertEqual(value as? Bool, true)
            case .failure(let error): XCTFail("Magnification failed: \(error)")
            }
            magnified.fulfill()
        }
        wait(for: [magnified], timeout: 10)
        let after = try XCTUnwrap(evaluate("""
        const viewport = [...document.querySelectorAll('.form-scroll')].find(e => e.getClientRects().length);
        const svg = viewport.querySelector('svg');
        return {width:svg.getBoundingClientRect().width, height:svg.getBoundingClientRect().height,
            contentX:(viewport.scrollLeft + 150) / 1.37, contentY:(viewport.scrollTop + 120) / 1.37,
            heading:document.querySelector('h1').getBoundingClientRect().height,
            controls:document.querySelector('.form-zoom-controls').getBoundingClientRect().height,
            themes:document.querySelector('.form-themes').getBoundingClientRect().height,
            caption:document.querySelector('.form-caption').textContent,
            output:document.querySelector('.form-zoom-controls output').value};
        """, in: webView) as? [String: Any])
        for (key, expected) in [("width", 2400 * 1.37), ("height", 1800 * 1.37),
                                ("contentX", 750), ("contentY", 520)] {
            XCTAssertEqual(try XCTUnwrap(after[key] as? Double), expected, accuracy: 1)
        }
        for key in ["heading", "controls", "themes"] {
            XCTAssertEqual(after[key] as? Double, before[key] as? Double)
        }
        XCTAssertEqual(after["caption"] as? String, before["caption"] as? String)
        XCTAssertEqual(after["output"] as? String, "137%")
    }

    func testFormZoomPersistsAcrossPlatformAppearanceAndPageSwitches() throws {
        let webView = load(try formHTML(large: false))
        let results = try XCTUnwrap(evaluate("""
        const root = document.querySelector('.form-zoom');
        const slider = root.querySelector('input[type=range]');
        slider.value = Math.log(1.75);
        slider.dispatchEvent(new Event('input', {bubbles:true}));
        const results = [];
        for (const platform of root.querySelectorAll('.platform-choice')) {
            root.querySelector(`label[for="${platform.id}"]`).click();
            const panel = root.querySelector(`.form-platform[data-platform="${platform.id.replace('platform-', '')}"]`);
            for (const theme of panel.querySelectorAll('.theme-choice')) {
                panel.querySelector(`label[for="${theme.id}"]`).click();
                const appearance = panel.querySelector(`.form-appearance[data-theme="${theme.id.replace('theme-', '')}"]`);
                for (const page of appearance.querySelectorAll('.page-choice')) {
                    const label = appearance.querySelector(`label[for="${page.id}"]`);
                    if (label) label.click();
                    const svg = [...appearance.querySelectorAll('.form-scroll')]
                        .find(e => e.getClientRects().length).querySelector('svg');
                    results.push({id:page.id, checked:page.checked, width:svg.getBoundingClientRect().width,
                        output:root.querySelector('output').value});
                }
            }
        }
        root.querySelector('button[aria-label="Zoom form in"]').click();
        const svg = [...root.querySelectorAll('.form-scroll')].find(e => e.getClientRects().length).querySelector('svg');
        results.push({id:'after-switch', checked:true, width:svg.getBoundingClientRect().width,
            output:root.querySelector('output').value});
        return results;
        """, in: webView) as? [[String: Any]])
        XCTAssertEqual(results.count, 22)
        for result in results {
            let afterSwitch = result["id"] as? String == "after-switch"
            XCTAssertEqual(result["checked"] as? Bool, true, "\(result)")
            XCTAssertEqual(try XCTUnwrap(result["width"] as? Double), afterSwitch ? 1260 : 1050, accuracy: 0.1)
            XCTAssertEqual(result["output"] as? String, afterSwitch ? "210%" : "175%")
        }
    }

    func testFormWheelAndDragStayInsideCanvas() throws {
        let webView = load(try formHTML())
        let values = try XCTUnwrap(evaluate("""
        const viewport = [...document.querySelectorAll('.form-scroll')].find(e => e.getClientRects().length);
        const svg = viewport.querySelector('svg');
        viewport.scrollLeft = 600;
        viewport.scrollTop = 400;
        viewport.setPointerCapture = () => {};
        svg.dispatchEvent(new PointerEvent('pointerdown', {
            pointerId:1, button:0, clientX:200, clientY:200, bubbles:true, cancelable:true
        }));
        viewport.dispatchEvent(new PointerEvent('pointermove', {
            pointerId:1, clientX:140, clientY:170, bubbles:true
        }));
        const dragged = [viewport.scrollLeft, viewport.scrollTop];
        viewport.dispatchEvent(new PointerEvent('pointercancel', {pointerId:1, bubbles:true}));
        viewport.dispatchEvent(new PointerEvent('pointermove', {pointerId:1, clientX:0, clientY:0, bubbles:true}));
        const cancelled = [viewport.scrollLeft, viewport.scrollTop];
        const wheel = new WheelEvent('wheel', {deltaY:10, bubbles:true, cancelable:true});
        viewport.dispatchEvent(wheel);
        const normalWidth = svg.getBoundingClientRect().width;
        const rect = viewport.getBoundingClientRect();
        const pinch = new WheelEvent('wheel', {deltaY:-20, ctrlKey:true,
            clientX:rect.left + 100, clientY:rect.top + 100, bubbles:true, cancelable:true});
        viewport.dispatchEvent(pinch);
        const outside = new WheelEvent('wheel', {deltaY:-20, ctrlKey:true, bubbles:true, cancelable:true});
        document.querySelector('.form-themes').dispatchEvent(outside);
        return {dragged, cancelled, cursor:viewport.style.cursor, ordinaryPrevented:wheel.defaultPrevented,
            zoomPrevented:pinch.defaultPrevented, outsidePrevented:outside.defaultPrevented,
            normalWidth, zoomed:svg.getBoundingClientRect().width};
        """, in: webView) as? [String: Any])
        XCTAssertEqual(values["dragged"] as? [Int], [660, 430])
        XCTAssertEqual(values["cancelled"] as? [Int], [660, 430])
        XCTAssertEqual(values["cursor"] as? String, "grab")
        XCTAssertEqual(values["ordinaryPrevented"] as? Bool, false)
        XCTAssertEqual(values["zoomPrevented"] as? Bool, true)
        XCTAssertEqual(values["outsidePrevented"] as? Bool, false)
        XCTAssertEqual(try XCTUnwrap(values["normalWidth"] as? Double), 2400, accuracy: 0.1)
        XCTAssertEqual(try XCTUnwrap(values["zoomed"] as? Double), 2400 * exp(0.2), accuracy: 0.1)
    }

    func testFormZoomPresetsWorkWithoutViewerScripts() throws {
        let html = try formHTML()
        XCTAssertFalse(html.contains("<script"))
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 860, height: 1000), configuration: configuration)
        let loaded = expectation(description: "Script-free form loaded")
        let observer = PreviewHTMLLoadObserver(loaded: loaded)
        webView.navigationDelegate = observer
        webView.loadHTMLString(html, baseURL: nil)
        wait(for: [loaded], timeout: 15)
        let values = try XCTUnwrap(evaluate("""
        const root = document.querySelector('.form-zoom');
        const viewport = [...root.querySelectorAll('.form-scroll')].find(e => e.getClientRects().length);
        const svg = viewport.querySelector('svg');
        const results = [];
        for (const percent of [10, 25, 50, 75, 100, 150, 200, 100]) {
            root.querySelector(`.form-zoom-controls label[for$="-${percent}"]`).click();
            results.push({percent, width:svg.getBoundingClientRect().width, height:svg.getBoundingClientRect().height,
                scrollWidth:viewport.scrollWidth, viewportWidth:viewport.clientWidth});
        }
        return {results, presets:root.querySelectorAll('.form-zoom-choice').length,
            script:typeof globalThis.fourdCanvasZoom};
        """, in: webView) as? [String: Any])
        XCTAssertEqual(values["presets"] as? Int, 7)
        XCTAssertEqual(values["script"] as? String, "undefined")
        let results = try XCTUnwrap(values["results"] as? [[String: Double]])
        XCTAssertEqual(results.count, 8)
        for result in results {
            let scale = try XCTUnwrap(result["percent"]) / 100
            XCTAssertEqual(try XCTUnwrap(result["width"]), 2400 * scale, accuracy: 0.1)
            XCTAssertEqual(try XCTUnwrap(result["height"]), 1800 * scale, accuracy: 0.1)
            XCTAssertEqual(try XCTUnwrap(result["scrollWidth"]),
                           max(try XCTUnwrap(result["viewportWidth"]), 2400 * scale), accuracy: 1)
        }
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
            bridge:typeof globalThis.webkit?.messageHandlers?.fourdCanvasZoom,
            pageScale:window.devicePixelRatio
        };
        """, in: webView) as? [String: Any])
        XCTAssertEqual(values["presets"] as? Int, 0)
        XCTAssertEqual(values["sliders"] as? Int, 2)
        XCTAssertEqual(values["outputs"] as? [String], ["100%", "100%"])
        XCTAssertEqual(values["bridge"] as? String, "undefined")
        XCTAssertEqual(try evaluate("return typeof globalThis.fourdCanvasZoom;", in: webView, world: .page) as? String, "undefined")
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
        webView.magnifyCanvas(at: NSPoint(x: x, y: webView.isFlipped ? y : webView.bounds.height - y),
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
        return globalThis.fourdCanvasZoom.magnify(10, 10, 0.5);
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
            scripts:typeof globalThis.fourdCanvasZoom.magnify,
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
            zoomOutside:globalThis.fourdCanvasZoom.magnify(10, 10, 0.5)
        };
        """, in: webView) as? [String: Any])
        XCTAssertGreaterThan(try XCTUnwrap(values["forms"] as? Int), 0)
        XCTAssertGreaterThan(try XCTUnwrap(values["formInputs"] as? Int), 0)
        XCTAssertEqual(values["sliders"] as? Int, 0)
        XCTAssertEqual(values["zoomOutside"] as? Bool, false)
    }
}

@MainActor
private final class PreviewHTMLLoadObserver: NSObject, WKNavigationDelegate {
    let loaded: XCTestExpectation

    init(loaded: XCTestExpectation) { self.loaded = loaded }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded.fulfill()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        XCTFail("Preview navigation failed: \(error)")
        loaded.fulfill()
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
