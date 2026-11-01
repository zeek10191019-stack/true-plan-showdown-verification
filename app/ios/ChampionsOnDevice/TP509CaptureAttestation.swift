import Foundation
import CoreFoundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Research-only, frame-bound verification of the real PNG bytes given to OCR.
/// A hash match certifies the PNG-to-Wire byte identity, NOT the visible Pokémon,
/// text correctness, ownership of a ROI, or battle-action legality.
enum TP509CaptureAttestation {
    enum Verdict: String {
        case verified = "PIXEL_BYTES_MATCH_WIRE"
        case unavailable = "REAL_CAPTURE_DIGEST_UNAVAILABLE"
        case malformed = "WIRE_MALFORMED"
        case contextMismatch = "FRAME_OR_SESSION_MISMATCH"
        case digestMismatch = "CAPTURE_WIRE_SHA_MISMATCH"
    }
    static func sha256Hex(_ png: Data) -> String? {
        guard !png.isEmpty, png.count <= 32_000_000 else { return nil }
        #if canImport(CryptoKit)
        return SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        #else
        // Linux local tests validate the wire gate. Real hashing is exercised by
        // the iPhoneOS build using Apple's CryptoKit, not claimed as Linux PASS.
        return nil
        #endif
    }
    private static func digest(_ v: Any?) -> String? {
        guard let s = v as? String, s.utf8.count == 64,
              s.utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) })
        else { return nil }
        return s
    }
    private static func uint(_ v: Any?) -> UInt64? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return UInt64(n.stringValue)
    }
    static func verify(_ wire: String?, actualPNGHash: String?,
                       battleID: String, epoch: Int, frameID: Int64) -> Verdict {
        guard let realHash = digest(actualPNGHash) else { return .unavailable }
        guard let wire, wire.utf8.count <= 1_000_000,
              let data = wire.data(using: .utf8),
              let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return .malformed }
        var body = top
        if let wrapped = top["payload_json"] {
            guard let json = wrapped as? String, json.utf8.count <= 1_000_000,
                  let nested = json.data(using: .utf8),
                  let object = (try? JSONSerialization.jsonObject(with: nested)) as? [String: Any]
            else { return .malformed }
            body = object
        }
        guard let id = body["battle_id"] as? String, !id.isEmpty,
              let ep = uint(body["epoch"]), let fr = uint(body["frame_id"]),
              let claimedHash = digest(body["image_sha256"])
        else { return .malformed }
        guard epoch >= 0, frameID > 0, id == battleID,
              ep == UInt64(epoch), fr == UInt64(frameID)
        else { return .contextMismatch }
        return claimedHash == realHash ? .verified : .digestMismatch
    }
}
