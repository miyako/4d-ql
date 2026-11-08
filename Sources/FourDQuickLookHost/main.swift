import AppKit
import WebKit

// Host app for the Quick Look extension. macOS discovers app extensions through
// the app that contains them, so this only needs to exist and be launched once.
// As a convenience, dropping a file on its window opens the Quick Look panel.

final class DropView: WKWebView {
    var onDrop: ((URL) -> Void)?

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = NSURL(from: sender.draggingPasteboard) as URL? else { return false }
        onDrop?(url)
        return true
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var web: DropView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        web = DropView(frame: .zero, configuration: WKWebViewConfiguration())
        web.onDrop = { [weak self] url in self?.show(url) }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "4D Quick Look"
        window.contentView = web
        window.center()
        window.makeKeyAndOrderFront(nil)
        web.loadHTMLString(Self.welcome, baseURL: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        show(URL(fileURLWithPath: filename))
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Opens the Quick Look panel for the file, exactly as pressing Space in Finder
    /// would, so what you see is what the installed extension produces.
    func show(_ url: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        p.arguments = ["-p", url.path]
        try? p.run()
    }

    static let welcome = """
    <html><head><meta name="color-scheme" content="light dark"><style>
    body{font:14px -apple-system;margin:40px;color:CanvasText;background:Canvas}
    code{background:rgba(127,127,127,.15);padding:1px 5px;border-radius:4px}
    </style></head><body>
    <h2>4D Quick Look is installed</h2>
    <p>Select a <code>.4DD</code>, <code>.4DB</code>, or <code>.4dm</code> file in Finder and press Space.</p>
    <p>You can also drop a file on this window to open its Quick Look preview.</p>
    <p>If Finder still shows the old preview, run <code>qlmanage -r</code> in Terminal.</p>
    </body></html>
    """
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
