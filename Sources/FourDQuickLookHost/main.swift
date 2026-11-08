import AppKit
import FourDProjectAccess
import QuickLookUI

final class DropView: NSTextView {
    var onDrop: ((URL) -> Void)?

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        isEditable = false
        isSelectable = true
        drawsBackground = false
        textContainerInset = NSSize(width: 28, height: 24)
        font = NSFont.systemFont(ofSize: 14)
        textColor = .labelColor
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

final class AppDelegate: NSResponder, NSApplicationDelegate, QLPreviewPanelDataSource {
    var window: NSWindow!
    var dropView: DropView!
    var previewURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        makeWindow()
    }

    func makeWindow() {
        NSApp.setActivationPolicy(.regular)
        dropView = DropView(frame: .zero, textContainer: nil)
        dropView.onDrop = { [weak self] url in self?.show(url) }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "4D Quick Look"
        window.nextResponder = self
        let authorize = NSButton(title: "Authorize project...", target: self, action: #selector(authorizeProject))
        let remove = NSButton(title: "Remove project authorizations...", target: self, action: #selector(removeAuthorizations))
        let projectAccessEnabled = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 13
            && !(Bundle.main.object(forInfoDictionaryKey: "FourDProjectGroupIdentifier") as? String ?? "").isEmpty
        authorize.isEnabled = projectAccessEnabled
        remove.isEnabled = projectAccessEnabled
        if !projectAccessEnabled {
            authorize.toolTip = "Project-resource access requires macOS 13 or later and a team-signed build with its own app group."
        }
        let buttons = NSStackView(views: [authorize, remove])
        buttons.orientation = .horizontal
        buttons.spacing = 12
        let content = NSStackView(views: [buttons, dropView])
        content.orientation = .vertical
        content.alignment = .leading
        content.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        dropView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = content
        dropView.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -24).isActive = true
        window.center()
        window.makeKeyAndOrderFront(nil)
        dropView.string = Self.welcome + (projectAccessEnabled ? "" : "\n\nProject authorization requires macOS 13 or later and a team-signed build. Selected-file previews remain available.")
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        show(URL(fileURLWithPath: filename))
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { makeWindow() }
        return true
    }

    @objc func authorizeProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Authorize"
        panel.message = "Choose the folder containing Project and Resources. The preview helper gains read-only access; Finder receives self-contained previews. No project code is executed."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let root = try await ProjectServiceClient().authorize(url)
                let alert = NSAlert()
                alert.messageText = "Project authorized"
                alert.informativeText = "\(root.path)\n\nClose and reopen its Finder preview to use project CSS, JSON pointers, pictures and static form resources. The service prepares a fresh, self-contained preview for each request."
                alert.runModal()
            } catch {
                showError(error)
            }
        }
    }

    @objc func removeAuthorizations() {
        do {
            let store = try ProjectAccessStore.configured()
            let entries = try store.entries()
            let alert = NSAlert()
            alert.messageText = "Remove all project authorizations?"
            alert.informativeText = entries.isEmpty ? "No projects are authorized." : entries.map(\.path).joined(separator: "\n")
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Remove")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
            Task { @MainActor in
                do { try await ProjectServiceClient().revoke() }
                catch { showError(error) }
            }
        } catch {
            showError(error)
        }
    }

    func show(_ url: URL) {
        previewURL = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = self }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = nil }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURL == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { previewURL as NSURL? }

    func showError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Project access failed"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    static let welcome = """
    4D Quick Look is installed

    Select a .4DForm, .4DD, .4DB, .4DCatalog, .4DSettings, .4si, .4DProject, .4df or .4dm file in Finder and press Space.

    Use Authorize project... to let the sandboxed service read that project's CSS, JSON pointers, pictures and static form resources. Finder receives a fresh, self-contained preview. Access is read-only and does not run 4D or project methods.

    You can also drop a file on this window to open its Quick Look preview.

    If Finder still shows the old preview, run qlmanage -r in Terminal.
    """
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
