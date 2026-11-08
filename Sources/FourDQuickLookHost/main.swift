import AppKit
import Darwin
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
        let dropView = DropView(frame: .zero, textContainer: nil)
        self.dropView = dropView
        dropView.onDrop = { [weak self] url in self?.show(url) }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "4D Quick Look"
        window.nextResponder = self
        let authorize = NSButton(title: "Choose another folder...", target: self, action: #selector(authorizeProject))
        let remove = NSButton(title: "Remove folder authorizations...", target: self, action: #selector(removeAuthorizations))
        let projectAccessEnabled = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 13
            && !(Bundle.main.object(forInfoDictionaryKey: "FourDProjectGroupIdentifier") as? String ?? "").isEmpty
        let folders = ["Desktop", "Documents", "Downloads"].enumerated().map { index, name in
            let button = NSButton(title: "Choose \(name)...", target: self, action: #selector(authorizeStandardFolder(_:)))
            button.tag = index
            return button
        }
        for button in folders + [authorize, remove] {
            button.isEnabled = projectAccessEnabled
            if !projectAccessEnabled {
                button.toolTip = "Project-resource access requires macOS 13 or later and a team-signed build with its own app group."
            }
        }
        let image = NSImageView()
        image.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "Authorize folders for project previews")
        image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 72, weight: .regular)
        image.contentTintColor = .controlAccentColor
        image.setAccessibilityElement(true)
        let title = NSTextField(labelWithString: "4D Quick Look is installed")
        title.font = .systemFont(ofSize: 26, weight: .semibold)
        let description = welcomeLabel("""
        Select a supported 4D file in Finder and press Space to preview it.

        Choose folders containing your projects to include their CSS, referenced JSON, pictures and static form resources. One folder authorization covers all projects beneath it and is saved after this app closes. Access is read-only; no 4D or project methods are run.
        """)
        let shortcuts = NSStackView(views: folders)
        shortcuts.orientation = .horizontal
        shortcuts.spacing = 12
        let buttons = NSStackView(views: [authorize, remove])
        buttons.orientation = .horizontal
        buttons.spacing = 12
        let note = welcomeLabel("""
        To add more paths later, launch 4D Quick Look again. Folder authorization is not available from the Quick Look preview window.
        """)
        note.textColor = .secondaryLabelColor
        let availability = welcomeLabel("Folder authorization requires macOS 13 or later and a team-signed build. Selected-file previews remain available.")
        availability.isHidden = projectAccessEnabled
        let content = NSStackView(views: [image, title, description, shortcuts, buttons, note, availability, dropView])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 20
        content.edgeInsets = NSEdgeInsets(top: 32, left: 32, bottom: 32, right: 32)
        dropView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = content
        for view in [description, note, availability, dropView] {
            view.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -64).isActive = true
        }
        dropView.heightAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true
        window.contentMinSize = NSSize(width: 740, height: 720)
        window.center()
        window.makeKeyAndOrderFront(nil)
        dropView.string = "Drop a 4D file here to open its Quick Look preview.\n\nIf Finder still shows the old preview, run qlmanage -r in Terminal."
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
        selectFolder(startingAt: nil)
    }

    @objc func authorizeStandardFolder(_ sender: NSButton) {
        let folders = ["Desktop", "Documents", "Downloads"]
        guard folders.indices.contains(sender.tag) else { return }
        // NSHomeDirectory points inside the container in a sandboxed app.
        guard let home = getpwuid(getuid())?.pointee.pw_dir else {
            showError(NSError(domain: "FourDQuickLookHost", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "The user's home folder could not be located. Use Choose another folder instead."]))
            return
        }
        let url = URL(fileURLWithPath: String(cString: home), isDirectory: true)
            .appendingPathComponent(folders[sender.tag], isDirectory: true)
        selectFolder(startingAt: url)
    }

    func selectFolder(startingAt url: URL?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Authorize"
        panel.directoryURL = url
        panel.message = "Authorize this folder, or choose another folder containing your projects. All projects beneath the selected folder gain read-only resource access. No project code is executed."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let root = try await ProjectServiceClient().authorize(url)
                let alert = NSAlert()
                alert.messageText = "Folder authorized"
                alert.informativeText = "\(root.path)\n\nProjects beneath this folder can now use CSS, referenced JSON, pictures and static form resources. Close and reopen their Finder previews to apply this access. You can close this app; the read-only authorization is saved."
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
            alert.messageText = "Remove all folder authorizations?"
            alert.informativeText = entries.isEmpty ? "No folders are authorized." : entries.map(\.path).joined(separator: "\n")
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

    private func welcomeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 14)
        label.isSelectable = true
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
