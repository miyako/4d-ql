import AppKit
import CoreGraphics
import Foundation
import IOKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard CommandLine.arguments.count == 3 else {
    fail("usage: finder-form-preview <form.4DForm> <screenshot.png>")
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
    key code 53
end tell
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
    keystroke "y" using command down
end tell
delay 4
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
    let before = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    let existingNumbers = Set(before.compactMap { $0[kCGWindowNumber as String] as? Int })
    try run("/usr/bin/osascript", ["-e", script])
    guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
        fail("Finder is not running.")
    }
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    guard let preview = windows.first(where: {
        guard ($0[kCGWindowOwnerPID as String] as? Int) == Int(finder.processIdentifier),
              ($0[kCGWindowAlpha as String] as? Double) == 1 else { return false }
        if ($0[kCGWindowLayer as String] as? Int) == 3 { return true }
        // Some macOS versions expose the newly opened preview as a normal, unnamed window.
        return ($0[kCGWindowLayer as String] as? Int) == 0
            && ($0[kCGWindowName as String] as? String ?? "").isEmpty
            && ($0[kCGWindowNumber as String] as? Int).map { !existingNumbers.contains($0) } == true
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
    print("Finder window \(number): \(bitmap.pixelsWide) x \(bitmap.pixelsHigh), \(output.path)")
} catch {
    fail(String(describing: error))
}
