import Foundation
#if os(Windows)
import WinSDK
#endif

public enum ByteSourceError: Error, CustomStringConvertible {
    case cannotOpen(String, Int32)
    case outOfBounds(offset: Int64, length: Int, fileSize: Int64)
    case shortRead(offset: Int64, wanted: Int, got: Int)

    public var description: String {
        switch self {
        case .cannotOpen(let path, let err): return "cannot open \(path): \(Self.message(err))"
        case .outOfBounds(let o, let l, let s): return "read of \(l) bytes at \(o) is outside the file (\(s) bytes)"
        case .shortRead(let o, let w, let g): return "short read at \(o): wanted \(w), got \(g)"
        }
    }

    private static func message(_ code: Int32) -> String {
        #if os(Windows)
        var buffer = [WCHAR](repeating: 0, count: 512)
        let count = FormatMessageW(DWORD(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS), nil,
                                   DWORD(bitPattern: code), 0, &buffer, DWORD(buffer.count), nil)
        let text = String(decoding: buffer.prefix(Int(count)), as: UTF16.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Windows error \(code)" : text
        #else
        return String(cString: strerror(code))
        #endif
    }
}

/// Random access to a file without loading it into memory.
///
/// Data files can be many gigabytes, and a preview only needs a few blocks,
/// so every read is a bounded positional read (`pread`, or `ReadFile` with an
/// explicit offset on Windows). Reads are thread safe.
public final class ByteSource {
    public let url: URL
    public let size: Int64
    #if os(Windows)
    private let handle: HANDLE
    #else
    private let fd: Int32
    #endif

    public init(url: URL) throws {
        self.url = url
        #if os(Windows)
        let opened = url.path.withCString(encodedAs: UTF16.self) { path in
            CreateFileW(path, GENERIC_READ, DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE), nil,
                        DWORD(OPEN_EXISTING), DWORD(FILE_ATTRIBUTE_NORMAL), nil)
        }
        guard let opened, opened != INVALID_HANDLE_VALUE else {
            throw ByteSourceError.cannotOpen(url.path, Int32(bitPattern: GetLastError()))
        }
        var fileSize = LARGE_INTEGER()
        guard GetFileSizeEx(opened, &fileSize) else {
            let e = GetLastError()
            CloseHandle(opened)
            throw ByteSourceError.cannotOpen(url.path, Int32(bitPattern: e))
        }
        self.handle = opened
        self.size = fileSize.QuadPart
        #else
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { throw ByteSourceError.cannotOpen(url.path, errno) }
        var st = stat()
        guard fstat(fd, &st) == 0 else {
            let e = errno
            close(fd)
            throw ByteSourceError.cannotOpen(url.path, e)
        }
        self.fd = fd
        self.size = Int64(st.st_size)
        #endif
    }

    #if os(Windows)
    deinit { CloseHandle(handle) }
    #else
    deinit { close(fd) }
    #endif

    /// Reads exactly `length` bytes at `offset`, or throws.
    public func read(at offset: Int64, length: Int) throws -> Data {
        guard length >= 0, offset >= 0, offset + Int64(length) <= size else {
            throw ByteSourceError.outOfBounds(offset: offset, length: length, fileSize: size)
        }
        var data = Data(count: length)
        let got = data.withUnsafeMutableBytes { buf -> Int in
            #if os(Windows)
            // ReadFile transfers at most 4 GiB - 1 per call; loop with explicit offsets.
            var total = 0
            while total < length {
                var overlapped = OVERLAPPED()
                let position = UInt64(offset) + UInt64(total)
                overlapped.Offset = DWORD(truncatingIfNeeded: position)
                overlapped.OffsetHigh = DWORD(truncatingIfNeeded: position >> 32)
                let chunk = DWORD(min(length - total, 1 << 30))
                var read: DWORD = 0
                guard ReadFile(handle, buf.baseAddress! + total, chunk, &read, &overlapped), read > 0 else { break }
                total += Int(read)
            }
            return total
            #else
            return pread(fd, buf.baseAddress, length, off_t(offset))
            #endif
        }
        guard got == length else { throw ByteSourceError.shortRead(offset: offset, wanted: length, got: got) }
        return data
    }

    /// Reads up to `length` bytes at `offset`, truncated at end of file.
    public func readAvailable(at offset: Int64, length: Int) throws -> Data {
        guard offset >= 0, offset < size else { return Data() }
        return try read(at: offset, length: Int(min(Int64(length), size - offset)))
    }
}
