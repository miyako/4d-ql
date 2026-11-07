import Foundation

public enum ByteSourceError: Error, CustomStringConvertible {
    case cannotOpen(String, Int32)
    case outOfBounds(offset: Int64, length: Int, fileSize: Int64)
    case shortRead(offset: Int64, wanted: Int, got: Int)

    public var description: String {
        switch self {
        case .cannotOpen(let path, let err): return "cannot open \(path): \(String(cString: strerror(err)))"
        case .outOfBounds(let o, let l, let s): return "read of \(l) bytes at \(o) is outside the file (\(s) bytes)"
        case .shortRead(let o, let w, let g): return "short read at \(o): wanted \(w), got \(g)"
        }
    }
}

/// Random access to a file without loading it into memory.
///
/// Data files can be many gigabytes, and a preview only needs a few blocks,
/// so every read is a bounded `pread`. Reads are thread safe.
public final class ByteSource {
    public let url: URL
    public let size: Int64
    private let fd: Int32

    public init(url: URL) throws {
        self.url = url
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
    }

    deinit { close(fd) }

    /// Reads exactly `length` bytes at `offset`, or throws.
    public func read(at offset: Int64, length: Int) throws -> Data {
        guard length >= 0, offset >= 0, offset + Int64(length) <= size else {
            throw ByteSourceError.outOfBounds(offset: offset, length: length, fileSize: size)
        }
        var data = Data(count: length)
        let got = data.withUnsafeMutableBytes { buf -> Int in
            pread(fd, buf.baseAddress, length, off_t(offset))
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
