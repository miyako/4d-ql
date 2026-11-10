import AppKit
import WebKit

// Capture the page exactly as emitted by fourdql; JavaScript only waits for assets.
final class CLISnapshot: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    let window: NSWindow
    let output: URL
    let width: Int
    let height: Int
    var done = false
    var failure: String?

    init(output: URL, width: Int, height: Int) {
        self.output = output
        self.width = width
        self.height = height
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        window = NSWindow(contentRect: webView.frame, styleMask: [.borderless],
                          backing: .buffered, defer: false)
        super.init()
        window.appearance = NSAppearance(named: .aqua)
        webView.appearance = NSAppearance(named: .aqua)
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
        webView.callAsyncJavaScript("""
            await document.fonts.ready;
            await Promise.all(Array.from(document.images).map(i => i.decode()));
            const urls = Array.from(document.querySelectorAll('svg image'))
                .map(i => i.getAttribute('href')).filter(u => u && u.startsWith('data:'));
            await Promise.all(urls.map(async url => {
                const image = new Image(); image.src = url; await image.decode();
            }));
            await new Promise(resolve => setTimeout(resolve, 300));
            const text = document.body.innerText;
            if (/No preview available|Problem report/i.test(text))
                throw new Error('Failure report instead of a preview');
            if (matchMedia('(prefers-color-scheme: dark)').matches)
                throw new Error('Expected light appearance');
            return {title:document.title, textLength:text.length,
                    images:document.images.length, svgImages:urls.length,
                    pageWidth:innerWidth, pageHeight:innerHeight,
                    documentHeight:document.documentElement.scrollHeight};
            """, arguments: [:], in: nil, in: .page) { result in
            switch result {
            case .failure(let error): self.fail(error.localizedDescription)
            case .success(let metadata):
                let config = WKSnapshotConfiguration()
                config.rect = NSRect(x: 0, y: 0, width: self.width, height: self.height)
                config.snapshotWidth = NSNumber(value: self.width)
                self.webView.takeSnapshot(with: config) { image, error in
                    if let error { self.fail(error.localizedDescription); return }
                    guard let image,
                          let bitmap = NSBitmapImageRep(
                            bitmapDataPlanes: nil, pixelsWide: self.width, pixelsHigh: self.height,
                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
                        self.fail("No decodable snapshot"); return
                    }
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = context
                    image.draw(in: NSRect(x: 0, y: 0, width: self.width, height: self.height))
                    NSGraphicsContext.restoreGraphicsState()
                    guard let png = bitmap.representation(using: .png, properties: [:]) else {
                        self.fail("PNG encoding failed"); return
                    }
                    do {
                        try png.write(to: self.output)
                        let json = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])
                        print(String(decoding: json, as: UTF8.self))
                        self.done = true
                    } catch { self.fail(error.localizedDescription) }
                }
            }
        }
    }
}

guard CommandLine.arguments.count == 5,
      let width = Int(CommandLine.arguments[3]), width > 0,
      let height = Int(CommandLine.arguments[4]), height > 0 else {
    fputs("usage: cli-snapshot HTML OUTPUT.png WIDTH HEIGHT\n", stderr)
    exit(2)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.appearance = NSAppearance(named: .aqua)
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let capture = CLISnapshot(output: URL(fileURLWithPath: CommandLine.arguments[2]), width: width, height: height)
capture.webView.loadFileURL(input, allowingReadAccessTo: input.deletingLastPathComponent())
let deadline = Date().addingTimeInterval(35)
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
