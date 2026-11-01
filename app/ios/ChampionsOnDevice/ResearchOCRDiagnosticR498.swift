import Foundation
import CoreFoundation

/// Research-only telemetry. Does not produce legal moves or certify OCR values.
struct TP498OCRDiagnostic {
    enum Verdict: String {
        case withheld = "WITHHELD_NOT_ADMITTED"
        case invalid = "MALFORMED_READINGS"
        case inspected = "INSPECTED_RESEARCH_ONLY"
    }
    struct Snapshot {
        let verdict: Verdict
        let total: Int
        let unassigned: Int
        let uncertainOwner: Int
        let lowConfidence: Int
        let unsafePromotions: Int
        var concise: String {
            guard verdict == .inspected else { return verdict.rawValue }
            return "OCR診断\(total)件／帰属不明\(unassigned)／ROI未確認\(uncertainOwner)" +
                   "／低信頼\(lowConfidence)／危険な帰属\(unsafePromotions)／研究のみ"
        }
    }
    static let withheld = Snapshot(verdict:.withheld,total:0,unassigned:0,
                                   uncertainOwner:0,lowConfidence:0,unsafePromotions:0)
    static let invalid = Snapshot(verdict:.invalid,total:0,unassigned:0,
                                  uncertainOwner:0,lowConfidence:0,unsafePromotions:0)
    /// Never stores raw_text, image, battles IDs, or OCR text.
    static func inspect(_ wire: String?, admitted: Bool) -> Snapshot {
        guard admitted else { return withheld }
        guard let wire, wire.utf8.count <= 1_000_000,
              let data = wire.data(using:.utf8),
              let envelope = try? JSONSerialization.jsonObject(with:data) as? [String:Any]
        else { return invalid }
        var body = envelope
        if let payload = envelope["payload_json"] {
            guard let encoded = payload as? String, encoded.utf8.count <= 1_000_000,
                  let nested = encoded.data(using:.utf8),
                  let parsed = try? JSONSerialization.jsonObject(with:nested) as? [String:Any]
            else { return invalid }
            body = parsed
        }
        guard let readings = body["readings"] as? [Any], readings.count <= 128 else { return invalid }
        var unassigned=0, uncertain=0, low=0, unsafe=0
        for item in readings {
            guard let r = item as? [String:Any] else { return invalid }
            let key = r["key"] as? String
            let unknownKey = key == nil || key!.isEmpty
            let reason = r["reason"] as? String ?? ""
            let ownerUnverified = reason.hasPrefix("UNVERIFIED_ROI_OWNER")
            if unknownKey { unassigned += 1 }
            if ownerUnverified { uncertain += 1 }
            if ownerUnverified && !unknownKey { unsafe += 1 }
            if let number = r["confidence"] as? NSNumber {
                if CFGetTypeID(number) == CFBooleanGetTypeID() ||
                   !number.doubleValue.isFinite || number.doubleValue < 0 || number.doubleValue > 1 {
                    return invalid
                }
                if number.doubleValue < 0.5 { low += 1 }
            } else if r["confidence"] != nil && !(r["confidence"] is NSNull) {
                return invalid
            }
        }
        return Snapshot(verdict:.inspected,total:readings.count,unassigned:unassigned,
                        uncertainOwner:uncertain,lowConfidence:low,unsafePromotions:unsafe)
    }
}
