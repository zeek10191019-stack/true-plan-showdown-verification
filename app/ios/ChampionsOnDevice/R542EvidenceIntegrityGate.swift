import Foundation
import CoreFoundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// R542: on-device, research-only structural and byte-level integrity gate.
/// A PASS proves only that exported observations agree with their embedded
/// image bytes and source receipts. It does NOT validate Pokemon mechanics,
/// screen ownership, OCR correctness, battle turns or Files destination save.
enum R542EvidenceIntegrityGate {
    enum Result: Equatable {
        case pass
        case fail(String)
    }
    private enum PNGCheckError: Error, CustomStringConvertible {
        case bytesOrSHA, dimensions
        var description: String {
            switch self {
            case .bytesOrSHA: return "PNG_BYTES_OR_SHA_INVALID"
            case .dimensions: return "PNG_DIMENSIONS_DISAGREE"
            }
        }
    }

    static func verify(_ bytes: Data, frame: Int64, epoch: Int64) -> Result {
        #if canImport(CryptoKit)
        return verify(bytes, frame:frame, epoch:epoch, digest: { data in
            SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
        })
        #else
        // Prevent an accidental certification in a host without CryptoKit.
        return .fail("CRYPTO_SHA256_UNAVAILABLE")
        #endif
    }

    // Injectable digest allows Foundation-only unit tests on non-Apple hosts.
    static func verify(_ bytes: Data, frame: Int64, epoch: Int64,
                       digest: (Data) -> String) -> Result {
        guard bytes.count > 0, bytes.count <= 20_000_000,
              frame > 0, epoch > 0,
              let root = (try? JSONSerialization.jsonObject(with:bytes)) as? [String:Any],
              root["schema"] as? String == "R537_UNIFIED_FRAME_EVIDENCE_V1",
              number(root["frame_id"]) == frame,
              number(root["epoch"]) == epoch,
              (root["verified_game_screen"] as? Bool) == false,
              (root["battle_advice_authorized"] as? Bool) == false,
              (root["production_enabled"] as? Bool) == false,
              (root["recognition_certified"] as? Bool) == false,
              (root["owner_certified"] as? Bool) == false,
              let observed = number(root["observed_ms_monotonic"]), observed > 0,
              let inventory = root["r537_inventory"] as? [String:Any],
              number(inventory["selected_frame_id"]) == frame,
              number(inventory["selected_epoch"]) == epoch,
              (inventory["raw_image_included"] as? Bool) == true,
              (inventory["save_to_files_confirmed"] as? Bool) == false,
              (inventory["no_battle_advice"] as? Bool) == true
        else { return .fail("SOURCE_OR_UNSAFE_CLAIM") }

        let original: (Data, String, Int, Int)
        switch extractPNG(root, imageKey:"image_png_base64", digestKey:"png_sha256",
                          bytesKey:"png_bytes", widthKey:"image_width", heightKey:"image_height",
                          digest:digest) {
        case .failure(let reason): return .fail("RAW_"+reason.description)
        case .success(let value): original=value
        }

        let analysis = root["analysis_image"] as? [String:Any]
        let candidate = root["research_candidate_envelope"] as? String
        guard (inventory["analysis_image_included"] as? Bool) == (analysis != nil),
              (inventory["same_frame_research_candidate_included"] as? Bool) == (candidate != nil),
              (inventory["diagnostics_included"] as? Bool) == (root["metrics"] is [String:Any]),
              (inventory["diagnostics_match_selected_frame_certified"] as? Bool) == false,
              (inventory["share_activity_completed"] as? Bool) == false
        else { return .fail("INVENTORY_DISAGREES_WITH_CONTENT") }
        var analysisDigest: String?
        var analysisCount=0
        if let analysis {
            switch extractPNG(analysis, imageKey:"image_png_base64", digestKey:"png_sha256",
                              bytesKey:"png_bytes", widthKey:"width", heightKey:"height",
                              digest:digest) {
            case .failure(let reason): return .fail("ANALYSIS_"+reason.description)
            case .success(let value):
                analysisDigest=value.1
                analysisCount=value.0.count
            }
        }
        guard original.0.count + analysisCount <= 14_000_000 else {
            return .fail("EMBEDDED_IMAGES_TOO_LARGE")
        }
        if candidate != nil && analysisDigest == nil { return .fail("CANDIDATE_MISSING_ANALYSIS_IMAGE") }
        if let candidate {
            guard let wrapped=try? JSONSerialization.jsonObject(with:Data(candidate.utf8)) as? [String:Any],
                  wrapped["schema"] as? String == "trueplan.mobile-envelope.v1",
                  let payload=wrapped["payload_json"] as? String,
                  let checksum=wrapped["payload_sha256"] as? String,
                  checksum == digest(Data(payload.utf8)),
                  let object=try? JSONSerialization.jsonObject(with:Data(payload.utf8)) as? [String:Any],
                  number(object["frame_id"]) == frame,
                  number(object["epoch"]) == epoch,
                  number(object["observed_at_ms"]) == observed,
                  (object["turn"] is NSNull),
                  object["image_sha256"] as? String == analysisDigest,
                  object["source_ref"] as? String == "device-local:selected-frame:\(frame)",
                  let readings=object["readings"] as? [[String:Any]],
                  readings.count <= 256,
                  readings.allSatisfy({ reading in
                      (reading["key"] == nil || reading["key"] is NSNull) &&
                      (reading["roi_owner_certified"] as? Bool != true) &&
                      (reading["source_image_sha256"] == nil ||
                       reading["source_image_sha256"] as? String == analysisDigest) &&
                      (reading["source_frame_id"] == nil || number(reading["source_frame_id"]) == frame) &&
                      (reading["source_epoch"] == nil || number(reading["source_epoch"]) == epoch)
                  }) else { return .fail("CANDIDATE_PROVENANCE_OR_PAYLOAD_MISMATCH") }
        }
        if let metrics=root["metrics"] as? [String:Any] {
            guard let sources=metrics["sources"] as? [String:Any],
                  Set(sources.keys) == Set(["r519_vision","r520_roi_session","r521_roi_collision","r532_first_pass"]),
                  (metrics["all_sources_same_frame_certified"] as? Bool) == false,
                  (metrics["battle_advice_authorized"] as? Bool) == false,
                  (metrics["recognition_certified"] as? Bool) == false,
                  (root["metrics_match_selected_frame_certified"] as? Bool) == false,
                  root["metrics_scope"] as? String == "MULTI_WINDOW_COUNTERS_NOT_SELECTED_FRAME"
            else { return .fail("METRICS_INVALID_OR_CERTIFICATION_CLAIM") }
        } else {
            guard ["DIAGNOSTICS_UNAVAILABLE","DIAGNOSTIC_MERGE_REJECTED"]
                    .contains(root["metrics_omission_reason"] as? String ?? "") else {
                return .fail("METRICS_OMISSION_NOT_EXPLAINED")
            }
        }
        return .pass
    }

    private static func number(_ value: Any?) -> Int64? {
        // Bool is an NSNumber in JSONSerialization; never allow it as an integer.
        guard let n=value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        guard n.doubleValue.isFinite, n.doubleValue == Double(n.int64Value) else { return nil }
        return n.int64Value
    }

    private static func extractPNG(_ dictionary: [String:Any], imageKey: String,
                                   digestKey: String, bytesKey: String,
                                   widthKey: String, heightKey: String,
                                   digest: (Data)->String) -> Swift.Result<(Data,String,Int,Int),PNGCheckError> {
        guard let encoded=dictionary[imageKey] as? String,
              let raw=Data(base64Encoded:encoded), raw.count > 0, raw.count <= 12_000_000,
              let declaredBytes=number(dictionary[bytesKey]), Int64(raw.count)==declaredBytes,
              let checksum=dictionary[digestKey] as? String, checksum.count==64,
              checksum == digest(raw),
              let declaredWidth=number(dictionary[widthKey]), let declaredHeight=number(dictionary[heightKey]),
              raw.count >= 33,
              Array(raw.prefix(8)) == [137,80,78,71,13,10,26,10],
              Array(raw[8..<12]) == [0,0,0,13],
              Array(raw[12..<16]) == [73,72,68,82]
        else { return .failure(.bytesOrSHA) }
        let width=Int(raw[16]) << 24 | Int(raw[17]) << 16 | Int(raw[18]) << 8 | Int(raw[19])
        let height=Int(raw[20]) << 24 | Int(raw[21]) << 16 | Int(raw[22]) << 8 | Int(raw[23])
        guard width > 0,height > 0,width <= 3072,height <= 3072,
              width*height <= 4_500_000,
              declaredWidth == Int64(width), declaredHeight == Int64(height)
        else { return .failure(.dimensions) }
        return .success((raw,checksum,width,height))
    }
}
