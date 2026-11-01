import Foundation

// R599: enforce an actual staged PNG byte-to-frame association before attaching
// the R597/R598 *research-only* form candidate to a one-button export.
// Important: this code is a callable pre-ZIP seam, not a patched UI callsite.
struct R599BoundExportReceipt {
    let emitted: Bool
    let reason: String
    let sidecarPath: String?
}

enum R599BoundOneButton {
    private static let maxPNGBytes = 12 * 1024 * 1024
    private static let minSide = 8
    private static let maxSide = 8192
    private static let pngSignature: [UInt8] = [137,80,78,71,13,10,26,10]

    private static func fail(_ reason: String) -> R599BoundExportReceipt {
        R599BoundExportReceipt(emitted: false, reason: reason, sidecarPath: nil)
    }
    private static func u32(_ bytes: [UInt8], at i: Int) -> UInt32 {
        (UInt32(bytes[i]) << 24) | (UInt32(bytes[i+1]) << 16) |
        (UInt32(bytes[i+2]) << 8) | UInt32(bytes[i+3])
    }
    private static func crc32(_ slice: ArraySlice<UInt8>) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in slice {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1 }
        }
        return crc ^ 0xffffffff
    }
    // Reject truncated / CRC-invalid PNGs and unrealistic dimensions. Never decode.
    // Real game screenshot capture is upstream and must be explicitly authorized.
    static func validPNG(_ data: Data) -> Bool {
        if data.count < 57 || data.count > maxPNGBytes { return false }
        let b = Array(data)
        if Array(b[0..<8]) != pngSignature { return false }
        var i = 8
        var seenIHDR = false, seenIDAT = false, seenIEND = false
        var chunks = 0
        while i <= b.count - 12 && chunks < 10000 {
            let n = Int(u32(b, at: i)); i += 4
            if n < 0 || n > maxPNGBytes || n > b.count - i - 8 { return false }
            let typeStart = i
            let name = String(bytes: b[i..<i+4], encoding: .ascii) ?? ""
            i += 4
            if name.count != 4 || !name.utf8.allSatisfy({ $0 >= 65 && $0 <= 90 || $0 >= 97 && $0 <= 122 }) { return false }
            let payloadStart = i
            i += n
            let stored = u32(b, at: i); i += 4
            if crc32(b[typeStart..<(payloadStart+n)]) != stored { return false }
            if chunks == 0 {
                if name != "IHDR" || n != 13 { return false }
                let w = Int(u32(b, at: payloadStart)); let h = Int(u32(b, at: payloadStart+4))
                if w < minSide || w > maxSide || h < minSide || h > maxSide { return false }
                if b[payloadStart+8] != 8 || ![2,6].contains(b[payloadStart+9]) ||
                   b[payloadStart+10] != 0 || b[payloadStart+11] != 0 || b[payloadStart+12] != 0 { return false }
                seenIHDR = true
            } else if name == "IHDR" { return false }
            if name == "IDAT" { seenIDAT = true }
            if name == "IEND" {
                if n != 0 || !seenIHDR || !seenIDAT || i != b.count { return false }
                seenIEND = true
                break
            }
            chunks += 1
        }
        return seenIEND
    }

    // Critical: cropRelativePath must identify the *actual crop PNG* that was
    // used for R595 observation. A full-frame image is NOT an equivalent hash.
    // If no crop is exported, evidence stays HOLD and no fabricated association.
    static func attachBeforeZip(bundleRoot: URL, cropRelativePath: String,
                                observation: R597FrameObservation, catalogData: Data,
                                manifestName: String = "manifest.json") -> R599BoundExportReceipt {
        let fm = FileManager.default
        let parts = cropRelativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 10, cropRelativePath.count <= 240,
              cropRelativePath.hasSuffix(".png"), !cropRelativePath.hasPrefix("/"),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." &&
                  $0.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) ||
                                            (97...122).contains($0) || $0 == 95 || $0 == 45 || $0 == 46 } }) else {
            return fail("CROP_PATH_UNSAFE")
        }
        guard observation.hasVerifiedActorBinding && observation.hasVerifiedOrientation &&
              ["own", "opponent"].contains(observation.captureSide),
              !observation.actorToken.isEmpty, !observation.battleID.isEmpty,
              observation.epoch >= 0, observation.frameID >= 0 else {
            return fail("SOURCE_FRAME_OWNER_OR_ORIENTATION_HOLD")
        }
        guard observation.cropSHA256.count == 64 &&
              observation.cropSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            return fail("CROP_HASH_MALFORMED")
        }
        let root = bundleRoot.standardizedFileURL
        guard let rootType = try? fm.attributesOfItem(atPath: root.path)[.type] as? FileAttributeType,
              rootType == .typeDirectory else { return fail("BUNDLE_ROOT_UNAVAILABLE") }
        var current = root
        for part in parts.dropLast() {
            current.appendPathComponent(String(part), isDirectory: true)
            guard let t = try? fm.attributesOfItem(atPath: current.path)[.type] as? FileAttributeType,
                  t == .typeDirectory else { return fail("CROP_PARENT_MISSING_OR_SYMLINK") }
        }
        let cropURL = current.appendingPathComponent(String(parts.last!))
        guard let t = try? fm.attributesOfItem(atPath: cropURL.path)[.type] as? FileAttributeType,
              t == .typeRegular, let bytes = try? Data(contentsOf: cropURL), validPNG(bytes) else {
            return fail("CROP_PNG_MISSING_OR_INVALID")
        }
        guard R598OneButtonFormAttachment.testDigest(bytes) == observation.cropSHA256 else {
            return fail("CROP_SHA256_NOT_BOUND_TO_FRAME")
        }
        let receipt = R598OneButtonFormAttachment.attach(bundleRoot: root,
                            manifestName: manifestName, observation: observation, catalogData: catalogData)
        if !receipt.attached { return fail("R598_" + receipt.reason) }
        return R599BoundExportReceipt(emitted: true,
                    reason: "BYTE_BOUND_RESEARCH_ONLY_NOT_LIVE_CERTIFIED", sidecarPath: receipt.relativePath)
    }
}
