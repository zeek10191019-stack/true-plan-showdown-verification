import Foundation
import CryptoKit
import Compression

/// A small, dependency-free ZIP (STORE) writer. No upload, no network, no source guessing.
/// Every member is bounded, names are fixed ASCII paths, and CRC32 is written explicitly.
enum R548ResearchArchive {
    struct Entry { let name: String; let bytes: Data }
    enum Error: Swift.Error { case invalidEntry, tooLarge, duplicate, invalidArchive }
    static let maximumMembers = 32
    static let maximumBytes = 100_000_000

    private static let crcTable: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 { value = (value >> 1) ^ ((value & 1) == 1 ? 0xedb88320 : 0) }
        return value
    }
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data { crc = (crc >> 8) ^ crcTable[Int((crc ^ UInt32(byte)) & 0xff)] }
        return crc ^ 0xffffffff
    }
    private static func u16(_ value: UInt16) -> Data {
        Data([UInt8(truncatingIfNeeded:value), UInt8(truncatingIfNeeded:value >> 8)])
    }
    private static func u32(_ value: UInt32) -> Data {
        Data([UInt8(truncatingIfNeeded:value),UInt8(truncatingIfNeeded:value >> 8),
              UInt8(truncatingIfNeeded:value >> 16),UInt8(truncatingIfNeeded:value >> 24)])
    }
    private static func validName(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count<=120 && !name.hasPrefix("/") &&
        !name.contains("..") && !name.contains("\\") &&
        !name.split(separator:"/",omittingEmptySubsequences:false).contains {$0.isEmpty || $0=="."} &&
        name.utf8.allSatisfy { value in
            (65...90).contains(value) || (97...122).contains(value) ||
            (48...57).contains(value) || [45,46,47,95].contains(value)
        }
    }
    static func write(_ entries: [Entry], to destination: URL,work: R551EvidenceWork?=nil,
                      onChunkWritten: ((Int)->Void)?=nil) throws -> Int {
        try work?.check()
        guard !entries.isEmpty, entries.count<=maximumMembers else { throw Error.invalidEntry }
        var seen = Set<String>()
        var inputBytes = 0
        for entry in entries {
            guard validName(entry.name),seen.insert(entry.name.lowercased()).inserted else { throw Error.duplicate }
            guard entry.bytes.count <= maximumBytes,
                  inputBytes <= maximumBytes-entry.bytes.count else {throw Error.tooLarge}
            inputBytes += entry.bytes.count
        }
        let handle = try R551ExclusiveFile.create(at:destination)
        var successful = false
        defer {
            if !successful {R555StoredZIPReadback.removeIfOwned(destination,descriptor:handle.fileDescriptor)}
            try? handle.close()
        }
        func append(_ bytes: Data) throws {
            var position=0
            while position<bytes.count {
                try work?.check()
                let end=min(bytes.count,position+R555StoredZIPReadback.chunkBytes)
                try autoreleasepool {try handle.write(contentsOf:bytes.subdata(in:(bytes.startIndex+position)..<(bytes.startIndex+end)))}
                onChunkWritten?(end-position);position=end
                try work?.check()
            }
        }
        var offset: UInt32 = 0
        var central = Data()
        for entry in entries {
            try work?.check()
            guard entry.bytes.count <= Int(UInt32.max) else {throw Error.tooLarge}
            let encodedName = Data(entry.name.utf8)
            let count = UInt32(entry.bytes.count)
            let checksum = try R555StoredZIPReadback.checksum(entry.bytes,work:work)
            var local = Data()
            local.append(u32(0x04034b50));local.append(u16(20))
            local.append(u16(0));local.append(u16(0)) // no data descriptors; STORE
            local.append(u16(0));local.append(u16(0)) // no clock claims
            local.append(u32(checksum));local.append(u32(count));local.append(u32(count))
            local.append(u16(UInt16(encodedName.count)));local.append(u16(0))
            local.append(encodedName)
            try append(local)
            try append(entry.bytes)
            var header = Data()
            header.append(u32(0x02014b50));header.append(u16(20));header.append(u16(20))
            header.append(u16(0));header.append(u16(0));header.append(u16(0));header.append(u16(0))
            header.append(u32(checksum));header.append(u32(count));header.append(u32(count))
            header.append(u16(UInt16(encodedName.count)));header.append(u16(0));header.append(u16(0))
            header.append(u16(0));header.append(u16(0));header.append(u32(0));header.append(u32(offset))
            header.append(encodedName)
            central.append(header)
            let increment = UInt64(local.count)+UInt64(entry.bytes.count)
            guard UInt64(offset)+increment < UInt64(UInt32.max) else { throw Error.tooLarge }
            offset += UInt32(increment)
        }
        guard UInt64(offset)+UInt64(central.count)+22 < UInt64(UInt32.max) else {throw Error.tooLarge}
        try append(central)
        var end=Data()
        end.append(u32(0x06054b50));end.append(u16(0));end.append(u16(0))
        end.append(u16(UInt16(entries.count)));end.append(u16(UInt16(entries.count)))
        end.append(u32(UInt32(central.count)));end.append(u32(offset));end.append(u16(0))
        try append(end)
        try work?.check()
        try handle.synchronize()
        let expected = Int(offset)+central.count+end.count
        let actual = (try FileManager.default.attributesOfItem(atPath:destination.path)[.size] as? NSNumber)?.intValue
        guard actual == expected else {throw Error.invalidArchive}
        // Reopen the writer-owned file and verify persisted CRC32 + SHA256 in
        // bounded chunks. Generic imported ZIPs retain the R549 validator.
        // Cancellation or failure removes only a path that still has our inode.
        let originals = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0.bytes) })
        let receipt = try R555StoredZIPReadback.verify(archiveURL:destination,expectedFiles:originals,
            expectedDescriptor:handle.fileDescriptor,work:work)
        guard receipt.entryCount == entries.count,
              receipt.entrySHA256.count == entries.count else { throw Error.invalidArchive }
        try work?.check()
        successful=true
        return expected
    }
}

/// Standalone inventory: owner and Mega remain unknown until an independent detector is certified.
enum R548CaptureManifest {
    static func make(selectedFrame:Int64,selectedEpoch:Int64,
                     frames:[[String:Any]],omissions:[String]) -> [String:Any] {
        ["schema":"trueplan.r548.single-share-capture-package.v1",
         "selected_frame_id":selectedFrame,"selected_epoch":selectedEpoch,
         "captured_frame_count":frames.count,"frames":frames,"omissions":omissions,
         "animation_sampling_guaranteed":false,"capture_sample_spacing_ms":4000,
         "mega_visual_classifier_certified":false,"own_opponent_auto_certified":false,
         "mega_name_change_required":false,"mega_animation_required":false,
         "battle_advice_authorized":false,
         "notes":"Stored captured frames only. An unrecorded Mega animation cannot be reconstructed."]
    }
}

/// Text-only candidates for a captured Mega scene, never proof of activation.
enum R548MegaTextRules {
    static let phrases = ["メガシンカ", "メガ進化", "メガギャラドス", "メガグソクムシャ", "メガバンギラス"]
    static func hints(_ texts:[String]) -> [String] {
        Array(Set(texts.flatMap { text in
            let compact = text.replacingOccurrences(of:" ",with:"")
                .replacingOccurrences(of:"　",with:"")
            return phrases.filter { compact.contains($0) }
        })).sorted()
    }
}



// R549: STRICT post-write ZIP readback. Fail closed: never report an exported archive
// as verified unless every expected entry is actually inflated and CRC32 + SHA256
// are recomputed from the persisted archive bytes.
enum R549ZipReadback {
    enum VerificationError: Error, CustomStringConvertible {
        case invalid(String)
        var description: String {
            switch self { case .invalid(let why): return "R549_ZIP_READBACK_" + why }
        }
    }

    struct Receipt {
        let entryCount: Int
        let archiveSHA256: String
        let entrySHA256: [String: String]
    }

    private static let archiveLimit = 128 * 1024 * 1024
    private static let singleEntryLimit = 48 * 1024 * 1024
    private static let totalOutputLimit = 96 * 1024 * 1024

    private static func failure(_ code: String) -> VerificationError { .invalid(code) }
    private static func u16(_ d: Data, _ i: Int) throws -> Int {
        guard i >= 0, i <= d.count - 2 else { throw failure("TRUNCATED_U16") }
        return Int(d[i]) | (Int(d[i + 1]) << 8)
    }
    private static func u32(_ d: Data, _ i: Int) throws -> Int {
        guard i >= 0, i <= d.count - 4 else { throw failure("TRUNCATED_U32") }
        return Int(d[i]) | (Int(d[i + 1]) << 8) | (Int(d[i + 2]) << 16) | (Int(d[i + 3]) << 24)
    }
    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private static func crc32(_ data: Data) -> Int {
        var c: UInt32 = 0xffff_ffff
        for byte in data {
            c ^= UInt32(byte)
            for _ in 0..<8 { c = (c >> 1) ^ ((c & 1) == 1 ? 0xedb8_8320 : 0) }
        }
        return Int(~c)
    }
    private static func safePath(_ path: String) -> Bool {
        if path.isEmpty || path.hasPrefix("/") || path.hasSuffix("/") || path.contains("\\") || path.contains(":") { return false }
        if path.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) { return false }
        return !path.split(separator: "/", omittingEmptySubsequences: false)
            .contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
    }
    private static func inflated(_ payload: Data, method: Int, expectedSize: Int) throws -> Data {
        guard expectedSize <= singleEntryLimit else { throw failure("ENTRY_TOO_LARGE") }
        if method == 0 {
            guard payload.count == expectedSize else { throw failure("STORED_LENGTH") }
            return payload
        }
        guard method == 8 else { throw failure("UNSUPPORTED_COMPRESSION") }
        if expectedSize == 0 {
            // A zero-byte deflate stream must still be structurally checked.
            // Disallow instead of accepting an unchecked stream.
            throw failure("EMPTY_DEFLATE_NOT_VERIFIED")
        }
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: expectedSize)
        defer { buffer.deallocate() }
        let count = payload.withUnsafeBytes { raw -> Int in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(buffer, expectedSize, base, payload.count, nil, COMPRESSION_ZLIB)
        }
        guard count == expectedSize else { throw failure("INFLATE_LENGTH_OR_CORRUPTION") }
        return Data(bytes: buffer, count: expectedSize)
    }

    // `expectedFiles` must be the original bytes captured BEFORE writing the ZIP.
    // An empty expected set is not an acceptable successful export.
    static func verify(archiveURL: URL, expectedFiles: [String: Data]) throws -> Receipt {
        guard !expectedFiles.isEmpty else { throw failure("EMPTY_EXPECTATION") }
        guard expectedFiles.keys.allSatisfy(safePath) else { throw failure("UNSAFE_EXPECTED_PATH") }
        let d = try Data(contentsOf: archiveURL, options: []) // Reopen persisted bytes.
        guard d.count >= 22 && d.count <= archiveLimit else { throw failure("ARCHIVE_SIZE") }
        let start = max(0, d.count - 65_557)
        var eocd: Int? = nil
        for i in stride(from: d.count - 22, through: start, by: -1) {
            if try u32(d, i) == 0x06054b50 && i + 22 + (try u16(d, i + 20)) == d.count {
                eocd = i; break
            }
        }
        guard let e = eocd else { throw failure("MISSING_EOCD") }
        let diskNo = try u16(d, e + 4)
        let cdDiskNo = try u16(d, e + 6)
        guard diskNo == 0, cdDiskNo == 0 else { throw failure("MULTIDISK") }
        let entries = try u16(d, e + 10)
        let diskEntries = try u16(d, e + 8)
        guard entries == expectedFiles.count, entries == diskEntries else { throw failure("ENTRY_COUNT") }
        let cdLength = try u32(d, e + 12)
        let cdStart = try u32(d, e + 16)
        guard cdLength != 0xffff_ffff, cdStart != 0xffff_ffff,
              cdStart <= e, cdLength <= e - cdStart, cdStart + cdLength == e else {
            throw failure("CENTRAL_DIRECTORY_RANGE")
        }
        var cursor = cdStart
        var names = Set<String>()
        var verified: [String: String] = [:]
        var totalOutput = 0
        for _ in 0..<entries {
            guard cursor <= e - 46, try u32(d, cursor) == 0x02014b50 else { throw failure("CENTRAL_HEADER") }
            let flags = try u16(d, cursor + 8)
            let method = try u16(d, cursor + 10)
            let declaredCRC = try u32(d, cursor + 16)
            let compressedSize = try u32(d, cursor + 20)
            let plainSize = try u32(d, cursor + 24)
            let nameLength = try u16(d, cursor + 28)
            let extraLength = try u16(d, cursor + 30)
            let commentLength = try u16(d, cursor + 32)
            let localOffset = try u32(d, cursor + 42)
            guard flags & 1 == 0, flags & 0x40 == 0,
                  compressedSize != 0xffff_ffff, plainSize != 0xffff_ffff,
                  localOffset != 0xffff_ffff else { throw failure("ENCRYPTED_OR_ZIP64") }
            let next = cursor + 46 + nameLength + extraLength + commentLength
            guard next <= e, nameLength > 0 else { throw failure("CENTRAL_TRUNCATED") }
            let nameBytes = d.subdata(in: cursor + 46..<cursor + 46 + nameLength)
            guard let name = String(data: nameBytes, encoding: .utf8), safePath(name),
                  !names.contains(name), let source = expectedFiles[name] else {
                throw failure("UNEXPECTED_DUPLICATE_OR_UNSAFE_NAME")
            }
            names.insert(name)
            guard plainSize == source.count, plainSize <= singleEntryLimit,
                  totalOutput <= totalOutputLimit - plainSize else { throw failure("OUTPUT_LIMIT_OR_EXPECTED_SIZE") }
            totalOutput += plainSize
            guard localOffset <= cdStart - 30 else { throw failure("LOCAL_HEADER") }
            let localSig = try u32(d, localOffset)
            guard localSig == 0x04034b50 else { throw failure("LOCAL_HEADER") }
            let localFlags = try u16(d, localOffset + 6)
            let localMethod = try u16(d, localOffset + 8)
            let localNameLength = try u16(d, localOffset + 26)
            let localExtraLength = try u16(d, localOffset + 28)
            let bodyStart = localOffset + 30 + localNameLength + localExtraLength
            guard localFlags == flags, localMethod == method,
                  localNameLength == nameLength,
                  bodyStart <= cdStart, compressedSize <= cdStart - bodyStart,
                  d.subdata(in: localOffset + 30..<localOffset + 30 + localNameLength) == nameBytes else {
                throw failure("LOCAL_CENTRAL_MISMATCH")
            }
            if flags & 0x8 == 0 {
                let localCRC = try u32(d, localOffset + 14)
                let localPacked = try u32(d, localOffset + 18)
                let localPlain = try u32(d, localOffset + 22)
                guard localCRC == declaredCRC, localPacked == compressedSize, localPlain == plainSize else {
                    throw failure("LOCAL_CHECKSUM_OR_LENGTH")
                }
            }
            let compressed = d.subdata(in: bodyStart..<bodyStart + compressedSize)
            let plain = try inflated(compressed, method: method, expectedSize: plainSize)
            guard crc32(plain) == declaredCRC else { throw failure("CRC32_MISMATCH") }
            let actualSHA = sha256(plain)
            guard actualSHA == sha256(source) else { throw failure("SHA256_MISMATCH") }
            verified[name] = actualSHA
            cursor = next
        }
        guard cursor == e, names.count == expectedFiles.count else { throw failure("CENTRAL_TRAILING_OR_MISSING") }
        return Receipt(entryCount: entries, archiveSHA256: sha256(d), entrySHA256: verified)
    }
}
