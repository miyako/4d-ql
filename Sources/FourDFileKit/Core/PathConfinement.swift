import Foundation
#if os(Windows)
import WinSDK
#endif

/// Path canonicalization and containment checks shared by every analyzer that
/// confines dependency reads to a project or form folder.
///
/// Containment compares normalized path *components*, never string prefixes of
/// `URL.path`. On Windows the same file has many spellings, and a textual
/// `hasPrefix(root + "/")` test is wrong for all of them:
///
/// - separators: `C:\p\f`, `C:/p/f` and `/C:/p/f`;
/// - extended and device prefixes: `\\?\C:\p\f`, `\\?\UNC\server\share\f`,
///   `\\.\C:\p\f`;
/// - case: NTFS is case-insensitive (`C:\Project` == `c:\project`);
/// - trailing dots and spaces, which Win32 discards (`Sources.` == `Sources`);
/// - alternate data streams (`file.css::$DATA`) and reserved DOS device names
///   (`CON`, `NUL`, `COM1`), which never denote project files;
/// - reparse points: symbolic links *and* junctions, resolved by the file
///   system through `GetFinalPathNameByHandleW`, which also expands 8.3 short
///   names.
///
/// The lexical rules are pure functions of a `Style`, so they are exercised on
/// every host. Only `canonicalURL` consults the file system.
public enum PathConfinement {
    public enum Style: Sendable {
        case posix
        case windows

        /// The style of the host operating system.
        public static var host: Style {
            #if os(Windows)
            return .windows
            #else
            return .posix
            #endif
        }
    }

    /// A normalized path: `keys` are used for comparison, `names` keep the
    /// original spelling for display.
    public struct Normalized: Equatable, Sendable {
        public let keys: [String]
        public let names: [String]
    }

    // MARK: Lexical rules

    /// Normalizes an absolute path, or returns nil when it is not absolute,
    /// climbs above its root, or contains a component Windows would treat as
    /// something other than a plain file or folder name.
    public static func normalize(_ path: String, style: Style = .host) -> Normalized? {
        switch style {
        case .posix: return normalizePOSIX(path)
        case .windows: return normalizeWindows(path)
        }
    }

    /// True when `path` is strictly inside `root` (the root itself is not).
    public static func contains(_ path: String, in root: String, style: Style = .host) -> Bool {
        relativeComponents(of: path, in: root, style: style) != nil
    }

    public static func contains(_ url: URL, in root: URL, style: Style = .host) -> Bool {
        contains(url.path, in: root.path, style: style)
    }

    /// The `/`-joined path of `path` below `root` in its original spelling, or
    /// nil when it is not strictly inside.
    public static func relativePath(of path: String, in root: String, style: Style = .host) -> String? {
        relativeComponents(of: path, in: root, style: style)?.joined(separator: "/")
    }

    public static func relativePath(of url: URL, in root: URL, style: Style = .host) -> String? {
        relativePath(of: url.path, in: root.path, style: style)
    }

    /// True when both paths name the same location after normalization.
    public static func isSameLocation(_ a: String, _ b: String, style: Style = .host) -> Bool {
        guard let a = normalize(a, style: style), let b = normalize(b, style: style) else { return false }
        return a.keys == b.keys
    }

    public static func isSameLocation(_ a: URL, _ b: URL, style: Style = .host) -> Bool {
        isSameLocation(a.path, b.path, style: style)
    }

    private static func relativeComponents(of path: String, in root: String, style: Style) -> [String]? {
        guard let path = normalize(path, style: style), let root = normalize(root, style: style),
              path.keys.count > root.keys.count, !root.keys.isEmpty,
              Array(path.keys.prefix(root.keys.count)) == root.keys else { return nil }
        return Array(path.names.dropFirst(root.keys.count))
    }

    private static func normalizePOSIX(_ path: String) -> Normalized? {
        guard path.hasPrefix("/"), !path.contains("\0") else { return nil }
        var names: [String] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch part {
            case ".": continue
            case "..": guard names.popLast() != nil else { return nil }
            default: names.append(String(part))
            }
        }
        return Normalized(keys: names, names: names)
    }

    private static let reservedDeviceNames: Set<String> = {
        var names: Set<String> = ["con", "prn", "aux", "nul", "conin$", "conout$"]
        for index in 0...9 { names.insert("com\(index)"); names.insert("lpt\(index)") }
        return names
    }()

    private static func normalizeWindows(_ input: String) -> Normalized? {
        guard !input.contains("\0") else { return nil }
        var path = input.replacingOccurrences(of: "\\", with: "/")
        var unc = false

        // \\?\UNC\server\share, \\?\C:\..., \\.\C:\... -> UNC or drive form.
        if path.hasPrefix("//?/") || path.hasPrefix("//./") {
            path = String(path.dropFirst(4))
            if path.lowercased().hasPrefix("unc/") {
                path = String(path.dropFirst(4))
                unc = true
            } else if path.lowercased().hasPrefix("volume{") || path.lowercased().hasPrefix("globalroot") {
                return nil // volume-GUID and object-manager paths are never project paths.
            }
        } else if path.hasPrefix("//") {
            unc = true
            path = String(path.dropFirst(2))
        } else if path.count >= 3, path.hasPrefix("/"), let drive = path.dropFirst().first,
                  drive.isASCII, drive.isLetter, path.dropFirst(2).first == ":" {
            path = String(path.dropFirst()) // URL.path form "/C:/dir".
        }

        var parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        var keys: [String] = []
        var names: [String] = []
        let rootDepth: Int
        if unc {
            // The server and share are the root; they can never be climbed out of.
            guard parts.count >= 2 else { return nil }
            let server = parts.removeFirst(), share = parts.removeFirst()
            guard validRootName(server), validRootName(share) else { return nil }
            keys = ["//" + server.lowercased(), share.lowercased()]
            names = ["//" + server, share]
            rootDepth = 2
        } else {
            guard let first = parts.first, first.count == 2, first.last == ":",
                  let letter = first.first, letter.isASCII, letter.isLetter else { return nil }
            parts.removeFirst()
            keys = [first.lowercased()]
            names = [first]
            rootDepth = 1
        }

        for part in parts {
            switch part {
            case ".": continue
            case "..":
                guard keys.count > rootDepth else { return nil }
                keys.removeLast(); names.removeLast()
            default:
                guard let name = windowsComponent(part) else { return nil }
                keys.append(name.lowercased()); names.append(name)
            }
        }
        return Normalized(keys: keys, names: names)
    }

    private static func validRootName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains(":") && !name.contains("?") && !name.contains("*")
    }

    /// Validates one component and strips the trailing dots and spaces Win32
    /// ignores, so `Sources.` and `Sources` compare equal.
    private static func windowsComponent(_ part: String) -> String? {
        guard !part.contains(":"), !part.contains("?"), !part.contains("*"), !part.contains("\""),
              !part.contains("<"), !part.contains(">"), !part.contains("|"),
              !part.unicodeScalars.contains(where: { $0.value < 0x20 }) else { return nil }
        var name = part
        while let last = name.last, last == "." || last == " " { name.removeLast() }
        guard !name.isEmpty else { return nil }
        let stem = name.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? name
        guard !reservedDeviceNames.contains(stem.trimmingCharacters(in: .whitespaces).lowercased()) else { return nil }
        return name
    }

    // MARK: Win32 path spelling

    /// The spelling to hand to Win32 file APIs: backslashes, and the `\\?\`
    /// (or `\\?\UNC\`) prefix once a path nears MAX_PATH, so long paths open
    /// without the process opting in to long-path awareness.
    public static func win32Path(_ path: String) -> String {
        var text = path.replacingOccurrences(of: "/", with: "\\")
        if text.hasPrefix("\\\\?\\") || text.hasPrefix("\\\\.\\") { return text }
        if text.count >= 3, text.hasPrefix("\\"), let drive = text.dropFirst().first, drive.isASCII, drive.isLetter,
           text.dropFirst(2).first == ":" {
            text.removeFirst() // "\C:\dir" from URL.path
        }
        let unc = text.hasPrefix("\\\\")
        let absolute = unc || (text.count >= 3 && text.dropFirst().first == ":" && text.dropFirst(2).first == "\\")
        guard absolute, text.count >= 240, !text.contains("\\.\\"), !text.contains("\\..\\") else { return text }
        return unc ? "\\\\?\\UNC\\" + text.dropFirst(2) : "\\\\?\\" + text
    }

    // MARK: Canonical location

    /// The location with `.`/`..` removed and every link resolved: symbolic
    /// links everywhere; on Windows also junctions and mount points, with 8.3
    /// names expanded and the case the file system stores.
    ///
    /// A path that does not exist resolves through its deepest existing
    /// ancestor, so confinement is decided before a read is attempted.
    public static func canonicalURL(_ url: URL) -> URL {
        #if os(Windows)
        if let resolved = windowsCanonical(url.standardizedFileURL) { return resolved }
        #endif
        return url.standardizedFileURL.resolvingSymlinksInPath()
    }

    #if os(Windows)
    private static func windowsCanonical(_ url: URL) -> URL? {
        var existing = url
        var tail: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path) {
            let parent = existing.deletingLastPathComponent()
            if parent.path == existing.path || parent.path.isEmpty { return nil }
            tail.insert(existing.lastPathComponent, at: 0)
            existing = parent
        }
        guard let final = finalPath(of: existing) else { return nil }
        var resolved = URL(fileURLWithPath: display(final))
        for part in tail { resolved.appendPathComponent(part) }
        return resolved
    }

    private static func finalPath(of url: URL) -> String? {
        let handle = win32Path(url.path).withCString(encodedAs: UTF16.self) { path in
            // Access 0 queries the name only; backup semantics allows folders.
            CreateFileW(path, 0, DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE), nil,
                        DWORD(OPEN_EXISTING), DWORD(FILE_FLAG_BACKUP_SEMANTICS), nil)
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else { return nil }
        defer { CloseHandle(handle) }
        // dwFlags 0 == VOLUME_NAME_DOS | FILE_NAME_NORMALIZED.
        var buffer = [WCHAR](repeating: 0, count: 1024)
        var count = GetFinalPathNameByHandleW(handle, &buffer, DWORD(buffer.count), 0)
        if count > buffer.count {
            buffer = [WCHAR](repeating: 0, count: Int(count) + 1)
            count = GetFinalPathNameByHandleW(handle, &buffer, DWORD(buffer.count), 0)
        }
        guard count > 0, Int(count) < buffer.count else { return nil }
        return String(decoding: buffer.prefix(Int(count)), as: UTF16.self)
    }

    /// Keep URLs in conventional form; Win32 file calls add the extended prefix
    /// back through `win32Path` when it is needed.
    private static func display(_ final: String) -> String {
        if final.hasPrefix("\\\\?\\UNC\\") { return "\\\\" + final.dropFirst(8) }
        if final.hasPrefix("\\\\?\\") { return String(final.dropFirst(4)) }
        return final
    }
    #endif
}
