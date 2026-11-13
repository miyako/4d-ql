import AppKit
import ApplicationServices

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func run(_ script: String) throws {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.arguments = ["-e", script]
    task.standardOutput = FileHandle.nullDevice
    try task.run()
    task.waitUntilExit()
    guard task.terminationStatus == 0 else {
        throw NSError(domain: "FinderFocusCheck", code: Int(task.terminationStatus),
                      userInfo: [NSLocalizedDescriptionKey: "Finder automation failed. Check Automation and Accessibility permissions."])
    }
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return value
}

func descendants(_ element: AXUIElement) -> [AXUIElement] {
    let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    return children.flatMap { [$0] + descendants($0) }
}

func screenRect(_ element: AXUIElement) throws -> CGRect {
    guard let position = attribute(element, kAXPositionAttribute),
          let size = attribute(element, kAXSizeAttribute),
          CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else {
        throw NSError(domain: "FinderFocusCheck", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "The preview control has no accessible screen geometry."])
    }
    var point = CGPoint.zero
    var dimensions = CGSize.zero
    guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
          AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else {
        throw NSError(domain: "FinderFocusCheck", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "The preview control's screen geometry could not be decoded."])
    }
    return CGRect(origin: point, size: dimensions)
}

func center(_ element: AXUIElement) throws -> CGPoint {
    guard let window = previewWindow() else { fail("The Quick Look window disappeared.") }
    let visible = try screenRect(element).intersection(screenRect(window))
    guard !visible.isNull, !visible.isEmpty else { fail("The preview control is outside the visible Quick Look window.") }
    return CGPoint(x: visible.midX, y: visible.midY)
}

func click(_ element: AXUIElement) throws {
    requireFinderActive()
    let point = try center(element)
    for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: .left) else {
            fail("Could not create a native mouse event.")
        }
        event.flags = []
        event.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.1)
    }
}

func quoted(_ path: String) -> String {
    "\"" + path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
}

guard CommandLine.arguments.count == 2 else {
    fail("usage: finder-preview-focus <catalog.4DCatalog>")
}
guard AXIsProcessTrusted() else { fail("Accessibility permission is required for native Finder input checks.") }
let catalog = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
guard FileManager.default.fileExists(atPath: catalog.path), catalog.pathExtension.lowercased() == "4dcatalog" else {
    fail("Supply an existing .4DCatalog with a structure diagram.")
}
guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
    fail("Finder is not running.")
}
let app = AXUIElementCreateApplication(finder.processIdentifier)

func previewWindow() -> AXUIElement? {
    (attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []).first {
        attribute($0, kAXSubroleAttribute) as? String == "Quick Look"
    }
}

func elements() -> [AXUIElement] {
    previewWindow().map(descendants) ?? []
}

func named(_ name: String) -> AXUIElement? {
    elements().first {
        attribute($0, kAXTitleAttribute) as? String == name
            || attribute($0, kAXDescriptionAttribute) as? String == name
    }
}

func waitFor(_ description: String, _ condition: () -> Bool) {
    for _ in 0..<50 {
        if condition() { return }
        Thread.sleep(forTimeInterval: 0.2)
    }
    fail("Timed out: \(description). Keep the desktop unlocked and verify the elected extension and permissions.")
}

func requireFinderActive() {
    guard attribute(app, kAXFrontmostAttribute) as? Bool == true else {
        fail("Finder lost foreground focus. Do not use other apps while this native-input check runs.")
    }
}

func zoom() -> String? {
    elements().compactMap { attribute($0, kAXValueAttribute) as? String }.first { $0.hasSuffix("%") }
}

func select(_ url: URL) throws {
    try run("""
    set targetItem to POSIX file \(quoted(url.path)) as alias
    tell application "Finder"
        reveal targetItem
    end tell
    repeat 30 times
        tell application "Finder"
            set selection to {targetItem}
            set picked to selection
        end tell
        if (count of picked) is 1 then
            if (item 1 of picked as alias) is targetItem then return
        end if
        delay 0.1
    end repeat
    error "Finder did not select the requested item."
    """)
}

func check(_ phase: String) throws {
    waitFor("catalog controls after \(phase)") {
        named("Zoom diagram in") != nil
            && elements().contains { attribute($0, kAXValueAttribute) as? String == catalog.lastPathComponent }
    }
    guard let canvas = named("Scrollable structure diagram"), let before = zoom() else {
        fail("No visible diagram or zoom output after \(phase).")
    }
    let point = try center(canvas)
    requireFinderActive()
    guard let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                             mouseCursorPosition: point, mouseButton: .left),
          let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                              wheelCount: 1, wheel1: 20, wheel2: 0, wheel3: 0) else {
        fail("Could not create native wheel input.")
    }
    move.flags = []
    move.post(tap: .cghidEventTap)
    wheel.location = point
    wheel.flags = .maskControl
    wheel.post(tap: .cghidEventTap)
    waitFor("Control-wheel zoom after \(phase)") { zoom().map { $0 != before } ?? false }
    guard let reset = named("Reset diagram zoom") else { fail("The reset control disappeared.") }
    try click(reset)
    waitFor("first-click reset after \(phase)") { zoom() == "100%" }
    guard let increase = named("Zoom diagram in") else { fail("The zoom-in control disappeared.") }
    try click(increase)
    waitFor("first-click zoom after \(phase)") { zoom() == "120%" }
    print("Verified \(phase): native Control-wheel, reset, zoom-in (120%).")
}

do {
    if let window = previewWindow(), let close = attribute(window, kAXCloseButtonAttribute) {
        guard CFGetTypeID(close) == AXUIElementGetTypeID(),
              AXUIElementPerformAction(close as! AXUIElement, kAXPressAction as CFString) == .success else {
            fail("Could not close the previous Quick Look window.")
        }
        waitFor("previous Quick Look window to close") { previewWindow() == nil }
    }
    try select(catalog)
    try run("""
    tell application "Finder" to activate
    delay 1
    tell application "System Events" to tell process "Finder"
        set frontmost to true
        key code 49
    end tell
    """)
    try check("initial presentation")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("fourdql-focus-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer {
        do { try FileManager.default.removeItem(at: directory) }
        catch { FileHandle.standardError.write(Data("Temporary probe cleanup failed: \(error)\n".utf8)) }
    }
    let otherFile = directory.appendingPathComponent("other.txt")
    try Data("Quick Look focus round trip\n".utf8).write(to: otherFile)
    for other in [otherFile, directory] {
        try select(other)
        let expected = other == directory ? directory.lastPathComponent : "Quick Look focus round trip"
        waitFor("the alternate item to replace the catalog") {
            named("Zoom diagram in") == nil
                && elements().contains { (attribute($0, kAXValueAttribute) as? String)?.contains(expected) == true }
        }
        try select(catalog)
        try check("return from \(other == directory ? "folder" : "file")")
    }
} catch {
    fail(error.localizedDescription)
}
