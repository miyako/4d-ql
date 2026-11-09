import AppKit
import CoreGraphics
import Foundation
import IOKit
import Vision

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard (3...4).contains(CommandLine.arguments.count) else {
    fail("usage: finder-form-preview <preview-file> <screenshot.png> [expected-visible-text]")
}
let form = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let output = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
guard FileManager.default.fileExists(atPath: form.path) else { fail("Form does not exist: \(form.path)") }
let root = IORegistryGetRootEntry(kIOMainPortDefault)
if root != 0 {
    if let users = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [[String: Any]],
       users.contains(where: {
           ($0["kCGSSessionUserIDKey"] as? Int) == Int(getuid())
               && ($0["CGSSessionScreenIsLocked"] as? Bool) == true
       }) {
        IOObjectRelease(root)
        fail("Unlock the macOS desktop before running the Finder preview check.")
    }
    IOObjectRelease(root)
}
guard CGPreflightScreenCaptureAccess() else {
    fail("Screen Recording permission is required for the hosting app in System Settings > Privacy & Security.")
}
let quotedPath = form.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
let script = """
set targetFile to POSIX file "\(quotedPath)" as alias
tell application "Finder" to activate
delay 0.5
tell application "System Events" to tell process "Finder"
    set frontmost to true
    if exists menu item "Close Quick Look" of menu "File" of menu bar 1 then
        click menu item "Close Quick Look" of menu "File" of menu bar 1
    end if
end tell
delay 0.7
tell application "Finder"
    reveal targetFile
    activate
end tell
delay 2
tell application "Finder" to set selection to {targetFile}
set selectedTarget to false
repeat 20 times
    tell application "Finder" to set picked to selection
    if (count of picked) is 1 then
        if (item 1 of picked as alias) is targetFile then
            set selectedTarget to true
            exit repeat
        end if
    end if
    delay 0.2
end repeat
if not selectedTarget then error "Finder did not select the requested form."
tell application "Finder" to activate
tell application "System Events" to tell process "Finder"
    set frontmost to true
end tell
tell application "Finder" to set selection to {targetFile}
tell application "System Events" to tell process "Finder"
    click (first menu item of menu "File" of menu bar 1 whose name starts with "Quick Look")
end tell
delay 4
tell application "Finder" to set picked to selection
if (count of picked) is not 1 then error "Finder selection changed while opening Quick Look."
if (item 1 of picked as alias) is not targetFile then error "Finder preview target changed."
"""

func run(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        fail("\(executable) exited \(process.terminationStatus). Automation needs Finder and System Events permission; UI control also needs Accessibility.")
    }
}

do {
    try run("/usr/bin/osascript", ["-e", script])
    guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
        fail("Finder is not running.")
    }
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    guard let preview = windows.first(where: {
        guard ($0[kCGWindowOwnerPID as String] as? Int) == Int(finder.processIdentifier),
              ($0[kCGWindowAlpha as String] as? Double) == 1 else { return false }
        if ($0[kCGWindowLayer as String] as? Int) == 3 { return true }
        // Finder can reuse its normal-level, unnamed preview window between files.
        return ($0[kCGWindowLayer as String] as? Int) == 0
            && ($0[kCGWindowName as String] as? String ?? "").isEmpty
    }), let number = preview[kCGWindowNumber as String] as? Int else {
        fail("No visible Finder Quick Look window after selecting the form.")
    }
    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    try run("/usr/sbin/screencapture", ["-x", "-t", "png", "-l", String(number), output.path])
    guard let bitmap = NSBitmapImageRep(data: try Data(contentsOf: output)) else {
        fail("Finder screenshot could not be decoded.")
    }
    var visible = false
    for y in stride(from: 0, to: bitmap.pixelsHigh, by: 16) {
        for x in stride(from: 0, to: bitmap.pixelsWide, by: 16) {
            if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 { visible = true; break }
        }
        if visible { break }
    }
    guard visible else { fail("The OS screenshot is transparent, not usable preview evidence.") }
    if CommandLine.arguments.count == 4 {
        let recognition = VNRecognizeTextRequest()
        recognition.recognitionLevel = .accurate
        let handler = VNImageRequestHandler(url: output)
        try handler.perform([recognition])
        let text = (recognition.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        let expected = CommandLine.arguments[3]
        guard text.localizedCaseInsensitiveContains(expected) else {
            fail("Finder preview is missing expected visible text '\(expected)'. Recognized text:\n\(text)")
        }
        for error in ["No preview available", "could not be initialized", "web content process stopped"] {
            guard !text.localizedCaseInsensitiveContains(error) else {
                fail("Finder preview contains an error: \(error)")
            }
        }
        print("Verified visible preview content: \(expected)")
    }
    print("Finder window \(number): \(bitmap.pixelsWide) x \(bitmap.pixelsHigh), \(output.path)")
} catch {
    fail(String(describing: error))
}
