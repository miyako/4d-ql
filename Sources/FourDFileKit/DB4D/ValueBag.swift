import Foundation

/// Decoder for 4D's serialised value bag ("VBAG"), used for the database extra
/// properties block (xDAT). Reverse-engineered from sample files, so it is
/// deliberately forgiving: it returns whatever it could decode before hitting
/// anything unexpected.
///
///     "VBAG" (as integer), u32 version, then a bag:
///     bag      := u8 flags, u32 nKeys, u32 keyBytes, nKeys × pascal string,
///                 u8 hasHash, [u32 n, n × i32], u32 (unknown),
///                 nKeys × value,
///                 u32 nElementNames, u32 nameBytes, names, u8 hasHash, [u32 n, n × i32],
///                 per name: u32 count, count × bag
///     value    := u16 kind, payload (kind 10: u32 length + UTF-16)
enum ValueBag {
    static func decode(_ data: Data, littleEndian: Bool) -> [ExtraProperty] {
        var r = BinaryReader(data, littleEndian: littleEndian)
        var out: [ExtraProperty] = []
        guard let sig = try? r.bytes(4) else { return out }
        let tag = String(decoding: littleEndian ? sig.reversed() : [UInt8](sig), as: UTF8.self)
        guard tag == "VBAG", (try? r.u32()) != nil else { return out }
        try? bag(&r, prefix: "", into: &out, depth: 0)
        return out
    }

    private static func pascalStrings(_ r: inout BinaryReader, count: Int) throws -> [String] {
        _ = try r.u32() // total bytes
        var keys: [String] = []
        for _ in 0..<count {
            let n = Int(try r.u8())
            keys.append(String(decoding: try r.bytes(n), as: UTF8.self))
        }
        if try r.u8() == 1 {
            let n = Int(try r.u32())
            guard n < 10_000 else { throw BinaryReaderError.truncated(offset: r.offset, wanted: n, available: 0) }
            try r.skip(n * 4)
        }
        return keys
    }

    private static func bag(_ r: inout BinaryReader, prefix: String, into out: inout [ExtraProperty], depth: Int) throws {
        guard depth < 8 else { return }
        _ = try r.u8()
        let nKeys = Int(try r.u32())
        guard nKeys < 10_000 else { return }
        let keys = try pascalStrings(&r, count: nKeys)
        if nKeys > 0 { _ = try r.u32() }
        for key in keys {
            guard let v = try value(&r) else { return }
            out.append(ExtraProperty(key: prefix + key, value: v))
        }
        let nNames = Int(try r.u32())
        guard nNames > 0, nNames < 10_000 else { return }
        let names = try pascalStrings(&r, count: nNames)
        for name in names {
            let count = Int(try r.u32())
            guard count < 10_000 else { return }
            for i in 0..<count {
                let p = prefix + name + (count > 1 ? "[\(i)]" : "") + "."
                try bag(&r, prefix: p, into: &out, depth: depth + 1)
            }
        }
    }

    /// nil = unknown kind; decoding stops there.
    private static func value(_ r: inout BinaryReader) throws -> String? {
        let kind = try r.u16()
        switch kind {
        case 1: return try r.u8() != 0 ? "true" : "false"
        case 2: return String(try r.u8())
        case 3: return String(try r.i16())
        case 4: return String(try r.i32())
        case 5: return String(try r.i64())
        case 6: return String(try r.f64())
        case 10:
            let n = Int(try r.u32())
            guard n < 1 << 20 else { return nil }
            return try r.utf16(count: n)
        default: return nil
        }
    }
}
