import Foundation
import Compression

/// Minimal ZIP reader (stored + deflate entries) that works on macOS and iOS without shelling out.
// ponytail: no ZIP64, encryption or CRC checks — enough for Notion/HTML exports; add ZIP64 if >4 GB exports show up.
public struct ZipReader {
    public struct Entry: Sendable {
        public var path: String
        var method: UInt16
        var compressedSize: Int
        var size: Int
        var localOffset: Int
    }

    public enum ZipError: Error, LocalizedError {
        case notAZip, encrypted, unsupportedMethod(Int), corrupt
        public var errorDescription: String? {
            switch self {
            case .notAZip: String(localized: "The file isn't a ZIP archive.", bundle: .module)
            case .encrypted: String(localized: "Encrypted ZIP archives aren't supported.", bundle: .module)
            case .unsupportedMethod(let m): String(localized: "This ZIP archive uses an unsupported compression method (\(m)).", bundle: .module)
            case .corrupt: String(localized: "The ZIP archive is damaged.", bundle: .module)
            }
        }
    }

    public let data: Data
    public private(set) var entries: [Entry] = []

    public init(data: Data) throws {
        self.data = data
        let bytes = [UInt8](data)
        func u16(_ o: Int) -> Int { o + 1 < bytes.count ? Int(bytes[o]) | Int(bytes[o + 1]) << 8 : 0 }
        func u32(_ o: Int) -> Int { o + 3 < bytes.count ? u16(o) | u16(o + 2) << 16 : 0 }

        // End of central directory: last occurrence of PK\5\6 (comment may follow, up to 64 KB).
        guard bytes.count >= 22 else { throw ZipError.notAZip }
        var eocd = -1
        var i = bytes.count - 22
        let floor = max(0, bytes.count - 22 - 65_535)
        while i >= floor {
            if bytes[i] == 0x50, bytes[i + 1] == 0x4b, bytes[i + 2] == 5, bytes[i + 3] == 6 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAZip }
        let count = u16(eocd + 10)
        var p = u32(eocd + 16)
        for _ in 0..<count {
            guard u32(p) == 0x02014b50 else { throw ZipError.corrupt }
            let flags = u16(p + 8)
            let method = UInt16(u16(p + 10))
            let csize = u32(p + 20), size = u32(p + 24)
            let nameLen = u16(p + 28), extraLen = u16(p + 30), commentLen = u16(p + 32)
            let local = u32(p + 42)
            guard p + 46 + nameLen <= bytes.count else { throw ZipError.corrupt }
            let nameBytes = Array(bytes[(p + 46)..<(p + 46 + nameLen)])
            // Bit 11 = UTF-8 names; otherwise CP437, which is ASCII-compatible for the common case.
            let name = String(decoding: nameBytes, as: UTF8.self)
            if flags & 1 != 0 { throw ZipError.encrypted }
            if !name.hasSuffix("/") && !name.hasPrefix("__MACOSX/") && !(name as NSString).lastPathComponent.hasPrefix("._") {
                entries.append(Entry(path: name, method: method, compressedSize: csize, size: size, localOffset: local))
            }
            p += 46 + nameLen + extraLen + commentLen
        }
    }

    public func read(_ e: Entry) throws -> Data {
        let bytes = data
        func u16(_ o: Int) -> Int { Int(bytes[bytes.startIndex + o]) | Int(bytes[bytes.startIndex + o + 1]) << 8 }
        guard e.localOffset + 30 <= bytes.count else { throw ZipError.corrupt }
        let start = e.localOffset + 30 + u16(e.localOffset + 26) + u16(e.localOffset + 28)
        guard start + e.compressedSize <= bytes.count else { throw ZipError.corrupt }
        let raw = bytes.subdata(in: (bytes.startIndex + start)..<(bytes.startIndex + start + e.compressedSize))
        switch e.method {
        case 0: return raw
        case 8: return try Self.inflate(raw, expected: e.size)
        default: throw ZipError.unsupportedMethod(Int(e.method))
        }
    }

    /// Raw DEFLATE (Apple's COMPRESSION_ZLIB is headerless deflate).
    static func inflate(_ input: Data, expected: Int) throws -> Data {
        if expected == 0 { return Data() }
        var out = Data(count: expected)
        let n = out.withUnsafeMutableBytes { dst in
            input.withUnsafeBytes { src in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, expected,
                                          src.bindMemory(to: UInt8.self).baseAddress!, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard n == expected else { throw ZipError.corrupt }
        return out
    }

    /// All files as (path, data), expanding ZIPs nested inside (Notion exports wrap parts in inner zips).
    public func files() throws -> [(path: String, data: Data)] {
        var out: [(String, Data)] = []
        for e in entries {
            let d = try read(e)
            if e.path.lowercased().hasSuffix(".zip"), let inner = try? ZipReader(data: d) {
                out += try inner.files()
            } else {
                out.append((e.path, d))
            }
        }
        return out
    }
}
