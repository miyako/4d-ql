import AppKit
import WebKit

// JavaScript belongs only to this test harness, never to fourdql's generated HTML.
final class Snapshot: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    let window: NSWindow
    let html: URL
    let output: URL
    let theme: String
    let page: Int
    let width: Int
    let height: Int
    var done = false
    var failure: String?

    init(arguments: [String]) {
        html = URL(fileURLWithPath: arguments[1])
        output = URL(fileURLWithPath: arguments[2])
        theme = arguments[3]
        page = Int(arguments[4])!
        width = Int(arguments[5])!
        height = Int(arguments[6])!
        let configuration = WKWebViewConfiguration()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: width + 100, height: height + 400),
                            configuration: configuration)
        window = NSWindow(contentRect: webView.frame, styleMask: [.borderless],
                          backing: .buffered, defer: false)
        super.init()
        window.contentView = webView
        window.orderFront(nil)
        webView.navigationDelegate = self
    }

    func fail(_ message: String) {
        failure = message
        done = true
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail(error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail(error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        fputs("Navigation finished; selecting exact canvas\n", stderr)
        let script = """
        (() => {
          const theme = '\(theme)', page = '\(page)';
          const t = document.getElementById('theme-' + theme);
          const p = document.getElementById('page-' + theme + '-' + page);
          if (!t || !p) throw new Error('Missing exact theme/page selector');
          t.checked = true; p.checked = true;
          t.dispatchEvent(new Event('change')); p.dispatchEvent(new Event('change'));
          const selected = document.querySelector('.form-appearance[data-theme="' + theme + '"] .form-page[data-page="' + page + '"]');
          const svg = selected.querySelector('svg[role="img"]');
          if (!svg || getComputedStyle(selected).display === 'none' ||
              getComputedStyle(selected.parentElement).display === 'none')
            throw new Error('Selected canvas is not visible');
          // Preserve checked-input sibling CSS, inherited colors and shared SVG definitions.
          const style = document.createElement('style');
          style.textContent = '.form-themes,.form-pages,.form-caption{display:none!important} .form-scroll{overflow:visible!important;border:0!important;border-radius:0!important}';
          document.head.appendChild(style);
          svg.scrollIntoView({block:'start',inline:'start'});
          window.__benchmarkSVG = svg;
          return true;
        })()
        """
        webView.evaluateJavaScript(script) { _, error in
            if let error { self.fail(error.localizedDescription); return }
            self.waitForAssets()
        }
    }

    func waitForAssets() {
        fputs("Waiting for fonts and images\n", stderr)
        webView.callAsyncJavaScript("""
            await document.fonts.ready;
            await Promise.all(Array.from(document.images).map(i => i.decode()));
            const assetURLs = Array.from(document.querySelectorAll('svg image'))
              .map(i => i.getAttribute('href')).filter(u => u && u.startsWith('data:'));
            await Promise.all(assetURLs.map(async url => {
              const image = new Image(); image.src = url; await image.decode();
            }));
            await new Promise(resolve => setTimeout(resolve, 200));
            const svg = window.__benchmarkSVG;
            const r = svg.getBoundingClientRect();
            return {x:r.x,y:r.y,width:r.width,height:r.height,
                    viewBox:svg.getAttribute('viewBox'),
                    theme:svg.closest('.form-appearance').dataset.theme,
                    page:Number(svg.closest('.form-page').dataset.page),
                    checkedTheme:document.querySelector('.theme-choice:checked').id,
                    checkedPage:svg.closest('.form-appearance').querySelector('.page-choice:checked').id,
                    visibleThemes:Array.from(document.querySelectorAll('.form-appearance'))
                      .filter(e => getComputedStyle(e).display!=='none').map(e => e.dataset.theme),
                    visiblePages:Array.from(svg.closest('.form-appearance').querySelectorAll('.form-page'))
                      .filter(e => getComputedStyle(e).display!=='none').map(e => Number(e.dataset.page)),
                    decodedImageAssets:assetURLs.length,
                    objects:Array.from(svg.children).filter(g => g.tagName.toLowerCase()==='g')
                      .map(g => { const b=g.getBBox(); return {title:g.querySelector('title')?.textContent,
                                 x:b.x,y:b.y,width:b.width,height:b.height,transform:g.getAttribute('transform')}; })};
            """, arguments: [:], in: nil, in: .page) { result in
            switch result {
            case .failure(let error): self.fail(error.localizedDescription)
            case .success(let value):
                guard let metadata = value as? [String: Any],
                      let w = metadata["width"] as? Double, let h = metadata["height"] as? Double,
                      let x = metadata["x"] as? Double, let y = metadata["y"] as? Double,
                      abs(w - Double(self.width)) < 0.01, abs(h - Double(self.height)) < 0.01,
                      metadata["theme"] as? String == self.theme,
                      metadata["page"] as? Int == self.page,
                      metadata["checkedTheme"] as? String == "theme-\(self.theme)",
                      metadata["checkedPage"] as? String == "page-\(self.theme)-\(self.page)",
                      metadata["visibleThemes"] as? [String] == [self.theme],
                      metadata["visiblePages"] as? [Int] == [self.page],
                      metadata["viewBox"] as? String == "0 0 \(self.width) \(self.height)",
                      x >= 0, y >= 0, x + w <= self.webView.frame.width,
                      y + h <= self.webView.frame.height else {
                    self.fail("Unexpected canvas dimensions, visibility, theme or page: \(value)")
                    return
                }
                let config = WKSnapshotConfiguration()
                fputs("Canvas verified; taking WebKit snapshot\n", stderr)
                config.rect = NSRect(x: x, y: y, width: w, height: h)
                config.snapshotWidth = NSNumber(value: self.width)
                self.webView.takeSnapshot(with: config) { image, error in
                    if let error { self.fail(error.localizedDescription); return }
                    guard let image, let tiff = image.tiffRepresentation,
                          let bitmap = NSBitmapImageRep(data: tiff),
                          let png = bitmap.representation(using: .png, properties: [:]) else {
                        self.fail("WebKit returned no decodable bitmap"); return
                    }
                    do {
                        try png.write(to: self.output)
                        var saved = metadata
                        saved["pixelWidth"] = bitmap.pixelsWide
                        saved["pixelHeight"] = bitmap.pixelsHigh
                        saved["windowBackingScale"] = self.window.backingScaleFactor
                        try JSONSerialization.data(withJSONObject: saved, options: [.prettyPrinted, .sortedKeys])
                            .write(to: self.output.appendingPathExtension("json"))
                        self.done = true
                    } catch { self.fail(error.localizedDescription) }
                }
            }
        }
    }
}

guard CommandLine.arguments.count == 7,
      ["classicLight", "classicDark", "glassLight", "glassDark"].contains(CommandLine.arguments[3]),
      let page = Int(CommandLine.arguments[4]), page > 0,
      let width = Int(CommandLine.arguments[5]), width > 0,
      let height = Int(CommandLine.arguments[6]), height > 0 else {
    fputs("usage: snapshot HTML OUTPUT.png THEME PAGE WIDTH HEIGHT\n", stderr)
    exit(2)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let capture = Snapshot(arguments: CommandLine.arguments)
capture.webView.loadFileURL(capture.html, allowingReadAccessTo: capture.html.deletingLastPathComponent())
let deadline = Date().addingTimeInterval(25)
while !capture.done && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
capture.window.orderOut(nil)
if let failure = capture.failure {
    fputs("snapshot failed: \(failure)\n", stderr)
    exit(1)
}
if !capture.done {
    fputs("snapshot timed out\n", stderr)
    exit(1)
}
