import Foundation
import CoreFoundation

/// Research-only metadata gate; checks provenance fields, NOT OCR correctness.
struct TP496WireProvenance {
    enum Result: String {
        case matched = "METADATA_MATCH_RESEARCH_ONLY"
        case absent = "NO_WIRE"
        case malformed = "BAD_JSON_OR_SCHEMA"
        case mismatch = "WRONG_FRAME_OR_SESSION"
        case invalidHash = "INVALID_HASH_FORMAT"
    }
    private static func int64(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let n = number.int64Value
        return number.doubleValue == Double(n) ? n : nil
    }
    static func check(_ wire: String?, battle: String,
                      epoch: Int, frame: Int64, observedMs: Int64) -> Result {
        guard let wire, !wire.isEmpty else { return .absent }
        guard !battle.isEmpty, epoch >= 0, frame > 0, observedMs >= 0,
              wire.utf8.count <= 1_000_000,
              let data = wire.data(using: .utf8),
              let outer = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .malformed }
        var body = outer
        if let raw = outer["payload_json"] {
            guard let nested = raw as? String,
                  let nestedData = nested.data(using: .utf8),
                  let decoded = try? JSONSerialization.jsonObject(with: nestedData) as? [String: Any]
            else { return .malformed }
            body = decoded
        }
        guard let id = body["battle_id"] as? String,
              let en = int64(body["epoch"]),
              let fr = int64(body["frame_id"]),
              let at = int64(body["observed_at_ms"]),
              body["readings"] is [Any] else { return .malformed }
        guard id == battle, en == Int64(epoch), fr == frame,
              at == observedMs else { return .mismatch }
        guard let sha = body["image_sha256"] as? String,
              sha.utf8.count == 64,
              sha.utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) ||
                                    ($0 >= 65 && $0 <= 70) ||
                                    ($0 >= 97 && $0 <= 102) }) else { return .invalidHash }
        return .matched
    }
}
