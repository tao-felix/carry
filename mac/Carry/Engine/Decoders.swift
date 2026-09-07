import Compression
import Foundation

/// The two binary decoders of util.py: Messages typedstream and Apple Notes' gzip+protobuf body.
enum Decoders {
    /// `decode_attributed_body`: the plain string inside a Messages `attributedBody` typedstream blob.
    /// Find `NSString`, skip 8 bytes (the name plus 5 class-info bytes ending in '+'), then a length byte:
    /// 0x81 → 2-byte little-endian length, 0x82 → 4-byte, else the byte itself.
    static func attributedBody(_ blob: Data?) -> String? {
        guard let blob, !blob.isEmpty else { return nil }
        let bytes = [UInt8](blob)
        let marker = Array("NSString".utf8)
        guard var i = find(marker, in: bytes) else { return nil }
        i += marker.count + 5
        guard i < bytes.count else { return nil }
        let b = bytes[i]
        var n: Int
        if b == 0x81 {
            n = Int(bytes.count > i + 2 ? UInt16(bytes[i + 1]) | (UInt16(bytes[i + 2]) << 8) : 0)
            i += 3
        } else if b == 0x82 {
            n = 0
            if bytes.count > i + 4 {
                n = Int(UInt32(bytes[i + 1]) | (UInt32(bytes[i + 2]) << 8) | (UInt32(bytes[i + 3]) << 16) | (UInt32(bytes[i + 4]) << 24))
            }
            i += 5
        } else {
            n = Int(b)
            i += 1
        }
        guard i <= bytes.count else { return nil }
        let end = min(bytes.count, i + n)
        let text = String(decoding: bytes[i ..< end], as: UTF8.self)
        return text.isEmpty ? nil : text
    }

    private static func find(_ needle: [UInt8], in hay: [UInt8]) -> Int? {
        guard needle.count <= hay.count else { return nil }
        var i = 0
        while i + needle.count <= hay.count {
            if hay[i] == needle[0], Array(hay[i ..< i + needle.count]) == needle { return i }
            i += 1
        }
        return nil
    }

    /// `decode_note_body`: gunzip, then protobuf Document(2) → Note(3) → note_text(2), UTF-8, stripped.
    static func noteBody(_ zdata: Data?) -> String? {
        guard let zdata, !zdata.isEmpty, let raw = gunzip(zdata) else { return nil }
        for (fn, wt, v) in pbFields(raw) where fn == 2 && wt == 2 {
            for (fn2, wt2, v2) in pbFields(v) where fn2 == 3 && wt2 == 2 {
                for (fn3, wt3, v3) in pbFields(v2) where fn3 == 2 && wt3 == 2 {
                    let text = Py.strip(String(decoding: v3, as: UTF8.self))
                    return text.isEmpty ? nil : text
                }
            }
        }
        return nil
    }

    // MARK: protobuf walker

    private static func varint(_ buf: [UInt8], _ start: Int) -> (UInt64, Int) {
        var i = start
        var shift: UInt64 = 0
        var out: UInt64 = 0
        while i < buf.count {
            let b = buf[i]
            i += 1
            if shift < 64 { out |= UInt64(b & 0x7F) << shift }
            if b & 0x80 == 0 { break }
            shift += 7
        }
        return (out, i)
    }

    /// `pb_fields(buf)`: (field number, wire type, value bytes) triples; stops at an unknown wire type.
    static func pbFields(_ buf: [UInt8]) -> [(Int, Int, [UInt8])] {
        var i = 0
        var out: [(Int, Int, [UInt8])] = []
        while i < buf.count {
            let (key, next) = varint(buf, i)
            i = next
            let fn = Int(key >> 3), wt = Int(key & 7)
            var v: [UInt8]
            switch wt {
            case 0:
                let (_, n2) = varint(buf, i)
                v = Array(buf[i ..< min(n2, buf.count)])
                i = n2
            case 1:
                v = Array(buf[i ..< min(i + 8, buf.count)])
                i += 8
            case 2:
                let (n, n2) = varint(buf, i)
                i = n2
                let end = min(i + Int(clamping: n), buf.count)
                v = i <= end ? Array(buf[i ..< end]) : []
                i += Int(clamping: n)
            case 5:
                v = Array(buf[i ..< min(i + 4, buf.count)])
                i += 4
            default:
                return out
            }
            out.append((fn, wt, v))
        }
        return out
    }

    // MARK: gzip

    /// gzip → bytes: skip the RFC 1952 header, inflate the raw deflate stream with Compression.
    static func gunzip(_ data: Data) -> [UInt8]? {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 8 else { return nil }
        let flags = bytes[3]
        var i = 10
        if flags & 0x04 != 0 { // FEXTRA
            guard i + 2 <= bytes.count else { return nil }
            let xlen = Int(bytes[i]) | (Int(bytes[i + 1]) << 8)
            i += 2 + xlen
        }
        if flags & 0x08 != 0 { // FNAME
            while i < bytes.count, bytes[i] != 0 { i += 1 }
            i += 1
        }
        if flags & 0x10 != 0 { // FCOMMENT
            while i < bytes.count, bytes[i] != 0 { i += 1 }
            i += 1
        }
        if flags & 0x02 != 0 { i += 2 } // FHCRC
        guard i < bytes.count - 8 else { return nil }
        let deflated = Array(bytes[i ..< bytes.count - 8])
        let expected = Int(UInt32(bytes[bytes.count - 4]) | (UInt32(bytes[bytes.count - 3]) << 8)
            | (UInt32(bytes[bytes.count - 2]) << 16) | (UInt32(bytes[bytes.count - 1]) << 24))
        return inflate(deflated, sizeHint: expected)
    }

    private static func inflate(_ input: [UInt8], sizeHint: Int) -> [UInt8]? {
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else { return nil }
        defer { compression_stream_destroy(stream) }
        var output: [UInt8] = []
        output.reserveCapacity(max(sizeHint, 1024))
        let chunk = 64 * 1024
        var buffer = [UInt8](repeating: 0, count: chunk)
        var status = COMPRESSION_STATUS_OK
        input.withUnsafeBufferPointer { inPtr in
            stream.pointee.src_ptr = inPtr.baseAddress!
            stream.pointee.src_size = inPtr.count
            repeat {
                buffer.withUnsafeMutableBufferPointer { outPtr in
                    stream.pointee.dst_ptr = outPtr.baseAddress!
                    stream.pointee.dst_size = chunk
                    status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                    let produced = chunk - stream.pointee.dst_size
                    if produced > 0 { output.append(contentsOf: outPtr[0 ..< produced]) }
                }
            } while status == COMPRESSION_STATUS_OK
        }
        return status == COMPRESSION_STATUS_END || !output.isEmpty ? output : nil
    }
}
