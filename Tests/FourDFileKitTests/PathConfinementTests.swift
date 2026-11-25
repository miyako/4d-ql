import Foundation
import XCTest
import FourDFileKit

/// Lexical rules run on every host (they are pure functions of a `Style`).
/// Tests that touch the Windows file system (junctions, symbolic links, 8.3
/// names, long paths) skip with a stated reason elsewhere.
final class PathConfinementTests: XCTestCase {
    private func requireWindows() throws {
        #if !os(Windows)
        throw XCTSkip("exercises Windows file-system behavior (reparse points, long paths, 8.3 names)")
        #endif
    }

    // MARK: POSIX

    func testPOSIXContainmentIsStrictAndComponentWise() {
        XCTAssertTrue(PathConfinement.contains("/p/Sources/a.css", in: "/p", style: .posix))
        XCTAssertFalse(PathConfinement.contains("/p", in: "/p", style: .posix), "the root itself is not inside")
        XCTAssertFalse(PathConfinement.contains("/p-evil/a", in: "/p", style: .posix), "sibling sharing a prefix")
        XCTAssertFalse(PathConfinement.contains("/P/a", in: "/p", style: .posix), "POSIX is case-sensitive")
        XCTAssertFalse(PathConfinement.contains("/p/../q/a", in: "/p", style: .posix))
        XCTAssertTrue(PathConfinement.contains("/p/x/../a", in: "/p", style: .posix))
        XCTAssertNil(PathConfinement.normalize("relative/path", style: .posix))
        XCTAssertNil(PathConfinement.normalize("/../x", style: .posix))
    }

    func testRelativePathKeepsOriginalSpelling() {
        XCTAssertEqual(PathConfinement.relativePath(of: "/p/Sources/Style.CSS", in: "/p", style: .posix), "Sources/Style.CSS")
        XCTAssertEqual(PathConfinement.relativePath(of: "C:\\Proj\\Sources\\Style.CSS", in: "c:/proj", style: .windows),
                       "Sources/Style.CSS")
    }

    // MARK: Windows spellings (lexical)

    func testWindowsSeparatorsDrivePrefixAndCase() {
        let root = "C:\\Users\\me\\Proj"
        for spelling in ["C:\\Users\\me\\Proj\\Sources\\a.css", "C:/Users/me/Proj/Sources/a.css",
                         "/C:/Users/me/Proj/Sources/a.css", "c:\\users\\ME\\proj\\SOURCES\\A.CSS",
                         "\\\\?\\C:\\Users\\me\\Proj\\Sources\\a.css", "\\\\.\\C:\\Users\\me\\Proj\\Sources\\a.css"] {
            XCTAssertTrue(PathConfinement.contains(spelling, in: root, style: .windows), spelling)
        }
        XCTAssertTrue(PathConfinement.contains("C:/x/Proj/a", in: "/C:/x/Proj", style: .windows))
        XCTAssertFalse(PathConfinement.contains("D:\\Users\\me\\Proj\\a", in: root, style: .windows), "other drive")
        XCTAssertFalse(PathConfinement.contains("C:\\Users\\me\\Proj2\\a", in: root, style: .windows), "shared prefix")
        XCTAssertFalse(PathConfinement.contains("C:\\Users\\me\\Proj", in: root, style: .windows))
        XCTAssertFalse(PathConfinement.contains("C:\\Users\\me\\Proj\\..\\Other\\a", in: root, style: .windows))
        XCTAssertNil(PathConfinement.normalize("Proj\\a", style: .windows), "relative paths are rejected")
        XCTAssertNil(PathConfinement.normalize("C:Proj\\a", style: .windows), "drive-relative paths are rejected")
        XCTAssertNil(PathConfinement.normalize("C:\\..\\a", style: .windows))
    }

    func testWindowsUNCAndExtendedUNC() {
        let root = "\\\\server\\share\\Proj"
        XCTAssertTrue(PathConfinement.contains("\\\\server\\share\\Proj\\Sources\\a.css", in: root, style: .windows))
        XCTAssertTrue(PathConfinement.contains("\\\\?\\UNC\\SERVER\\Share\\proj\\Sources\\a.css", in: root, style: .windows))
        XCTAssertTrue(PathConfinement.contains("//server/share/Proj/a", in: root, style: .windows))
        XCTAssertFalse(PathConfinement.contains("\\\\server\\share2\\Proj\\a", in: root, style: .windows))
        XCTAssertFalse(PathConfinement.contains("\\\\other\\share\\Proj\\a", in: root, style: .windows))
        XCTAssertNil(PathConfinement.normalize("\\\\server", style: .windows))
        XCTAssertNil(PathConfinement.normalize("\\\\server\\share\\..\\..\\x", style: .windows),
                     "cannot climb out of the share")
        XCTAssertFalse(PathConfinement.contains("\\\\?\\UNC\\server\\share\\Proj\\..\\x", in: root, style: .windows))
        XCTAssertNil(PathConfinement.normalize("\\\\?\\Volume{01234567-89ab-cdef-0123-456789abcdef}\\a", style: .windows))
        XCTAssertNil(PathConfinement.normalize("\\\\?\\GLOBALROOT\\Device\\x", style: .windows))
    }

    func testWindowsIgnoredAndForbiddenComponents() {
        let root = "C:\\Proj"
        XCTAssertTrue(PathConfinement.contains("C:\\Proj.\\Sources \\a", in: root, style: .windows),
                      "Win32 discards trailing dots and spaces")
        XCTAssertFalse(PathConfinement.contains("C:\\Proj\\... \\a", in: root, style: .windows))
        XCTAssertFalse(PathConfinement.contains("C:\\Proj\\a.css::$DATA", in: root, style: .windows), "alternate data stream")
        XCTAssertFalse(PathConfinement.contains("C:\\Proj\\a.css:stream", in: root, style: .windows))
        for device in ["CON", "nul", "COM1", "LPT9.txt", "aux.css", "CONIN$"] {
            XCTAssertFalse(PathConfinement.contains("C:\\Proj\\\(device)", in: root, style: .windows), device)
        }
        XCTAssertTrue(PathConfinement.contains("C:\\Proj\\console.css", in: root, style: .windows), "not a device name")
        XCTAssertTrue(PathConfinement.contains("C:\\Proj\\com10.css", in: root, style: .windows))
        for bad in ["a?b", "a*b", "a<b", "a>b", "a|b", "a\"b", "a\u{1}b"] {
            XCTAssertFalse(PathConfinement.contains("C:\\Proj\\\(bad)", in: root, style: .windows), bad)
        }
        XCTAssertNil(PathConfinement.normalize("C:\\Proj\\a\0b", style: .windows))
    }

    func testSameLocation() {
        XCTAssertTrue(PathConfinement.isSameLocation("C:\\A\\b", "/c:/a/B/", style: .windows))
        XCTAssertFalse(PathConfinement.isSameLocation("C:\\A\\b", "C:\\A\\c", style: .windows))
        XCTAssertFalse(PathConfinement.isSameLocation("/a/b", "/a/B", style: .posix))
    }

    // MARK: Win32 spelling

    func testWin32PathUsesBackslashesAndExtendsLongPaths() {
        XCTAssertEqual(PathConfinement.win32Path("C:/Proj/a.css"), "C:\\Proj\\a.css")
        XCTAssertEqual(PathConfinement.win32Path("/C:/Proj/a.css"), "C:\\Proj\\a.css")
        XCTAssertEqual(PathConfinement.win32Path("\\\\?\\C:\\Proj\\a.css"), "\\\\?\\C:\\Proj\\a.css")
        let long = "C:/" + String(repeating: "d/", count: 130) + "a.css"
        XCTAssertTrue(PathConfinement.win32Path(long).hasPrefix("\\\\?\\C:\\d\\"))
        let uncLong = "\\\\srv\\share\\" + String(repeating: "d\\", count: 130) + "a.css"
        XCTAssertTrue(PathConfinement.win32Path(uncLong).hasPrefix("\\\\?\\UNC\\srv\\share\\"))
        XCTAssertEqual(PathConfinement.win32Path("relative/a.css"), "relative\\a.css", "relative paths are left alone")
    }

    // MARK: Windows file system

    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fourdql-path-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return PathConfinement.canonicalURL(url)
    }

    func testCanonicalURLResolvesCaseAndMissingTail() throws {
        try requireWindows()
        let root = try scratch()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        let odd = URL(fileURLWithPath: root.path.uppercased()).appendingPathComponent("sources/missing/a.css")
        let resolved = PathConfinement.canonicalURL(odd)
        XCTAssertTrue(PathConfinement.contains(resolved, in: root))
        XCTAssertEqual(PathConfinement.relativePath(of: resolved, in: root)?.lowercased(), "sources/missing/a.css")
        XCTAssertEqual(resolved.pathComponents[resolved.pathComponents.count - 3], "Sources",
                       "the stored case replaces the requested case")
    }

    func testJunctionEscapeIsResolvedAndRejected() throws {
        try requireWindows()
        let root = try scratch()
        let project = root.appendingPathComponent("Proj"), outside = root.appendingPathComponent("Outside")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: outside.appendingPathComponent("a.css"))
        let junction = project.appendingPathComponent("link")
        // mklink /J needs neither Developer Mode nor elevation.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "C:\\Windows\\System32\\cmd.exe")
        process.arguments = ["/c", "mklink", "/J", junction.path.replacingOccurrences(of: "/", with: "\\"),
                             outside.path.replacingOccurrences(of: "/", with: "\\")]
        process.standardOutput = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw XCTSkip("mklink /J failed (status \(process.terminationStatus))") }

        let target = PathConfinement.canonicalURL(junction.appendingPathComponent("a.css"))
        XCTAssertTrue(PathConfinement.isSameLocation(target, outside.appendingPathComponent("a.css")),
                      "a junction resolves to its destination")
        XCTAssertFalse(PathConfinement.contains(target, in: project), "so the escape is detected")
    }

    func testSymbolicLinkEscapeIsRejected() throws {
        try requireWindows()
        let root = try scratch()
        let project = root.appendingPathComponent("Proj"), outside = root.appendingPathComponent("Outside")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: outside.appendingPathComponent("a.css"))
        try createSymbolicLink(at: project.appendingPathComponent("link"), to: outside)
        let target = PathConfinement.canonicalURL(project.appendingPathComponent("link/a.css"))
        XCTAssertFalse(PathConfinement.contains(target, in: project))
    }

    func testShortNameCannotHideAnEscape() throws {
        try requireWindows()
        let root = try scratch()
        let long = root.appendingPathComponent("A Long Folder Name")
        try FileManager.default.createDirectory(at: long, withIntermediateDirectories: true)
        // 8.3 names exist only when the volume generates them; skip if not.
        let short = root.appendingPathComponent("ALONGF~1")
        guard FileManager.default.fileExists(atPath: short.path) else { throw XCTSkip("8.3 names are disabled on this volume") }
        XCTAssertTrue(PathConfinement.isSameLocation(PathConfinement.canonicalURL(short), long))
        XCTAssertTrue(PathConfinement.contains(PathConfinement.canonicalURL(short.appendingPathComponent("a")), in: long))
    }

    func testLongPathIsReadableThroughByteSource() throws {
        try requireWindows()
        var folder = try scratch()
        while folder.path.count < 300 {
            folder.appendPathComponent(String(repeating: "d", count: 40))
        }
        let created = URL(fileURLWithPath: PathConfinement.win32Path(folder.path))
        try FileManager.default.createDirectory(at: created, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("a.bin")
        try Data([1, 2, 3]).write(to: URL(fileURLWithPath: PathConfinement.win32Path(file.path)))
        let source = try ByteSource(url: file)
        XCTAssertEqual(source.size, 3)
        XCTAssertEqual(try source.read(at: 0, length: 3), Data([1, 2, 3]))
    }

    func testCanonicalURLKeepsLongPathsComparable() throws {
        try requireWindows()
        var folder = try scratch()
        while folder.path.count < 300 {
            folder.appendPathComponent(String(repeating: "d", count: 40))
        }
        let created = URL(fileURLWithPath: PathConfinement.win32Path(folder.path))
        try FileManager.default.createDirectory(at: created, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("a.bin")
        try Data([1]).write(to: URL(fileURLWithPath: PathConfinement.win32Path(file.path)))

        let canonicalRoot = PathConfinement.canonicalURL(folder)
        let canonicalFile = PathConfinement.canonicalURL(file)
        XCTAssertTrue(PathConfinement.contains(canonicalFile, in: canonicalRoot))
    }

    func testUNCPathReadsThroughAdministrativeShare() throws {
        try requireWindows()
        let root = try scratch()
        let file = root.appendingPathComponent("a.css")
        try Data("a{}".utf8).write(to: file)
        // \\localhost\C$\... reaches the local volume as a UNC path when the
        // administrative share is enabled.
        let path = file.path.replacingOccurrences(of: "/", with: "\\")
        guard path.count > 3, path.dropFirst().first == ":" else { throw XCTSkip("scratch folder is not on a drive letter") }
        let drive = String(path.prefix(1))
        let unc = URL(fileURLWithPath: "\\\\localhost\\\(drive)$" + path.dropFirst(2))
        guard FileManager.default.fileExists(atPath: unc.path) else { throw XCTSkip("administrative share is unavailable") }
        XCTAssertEqual(try ByteSource(url: unc).size, 3)
        XCTAssertTrue(PathConfinement.contains(unc.deletingLastPathComponent().appendingPathComponent("x"),
                                               in: unc.deletingLastPathComponent()))
    }
}
