import Foundation
import CoreFoundation

/// Research-only join of two *independent* historical diagnostics.
/// This rejects evidence mismatches; it does NOT classify actors or Mega.
enum R661CrossModalEvidenceGate {
    static let schema = "trueplan.r661.cross-modal-evidence.v1"
    private static let featureOK =
        "HISTORICAL_UNLABELED_VISUAL_MOTION_ONLY"
    private static let motionOK =
        "HISTORICAL_CAMERA_TRANSLATION_MEASURE_ONLY"
    private static let regionNames = ["LEFT_ACTOR_HYPOTHESIS",
                               "RIGHT_ACTOR_HYPOTHESIS",
                               "BACKGROUND_CONTROL"]
    private static let noProof = ["owner_certified",
                                 "species_certified",
                                 "mega_event_certified",
                                 "mega_form_certified",
                                 "battle_advice_authorized",
                                 "current_state_eligible"]
    private static func hold(_ reason: String) -> [String:Any] {
        ["schema":schema,"status":reason,"pairs_checked":0,
         "source_join_verified":false,"region_calibrated":false,
         "owner_certified":false,"species_certified":false,
         "mega_event_certified":false,"mega_form_certified":false,
         "battle_advice_authorized":false,
         "current_state_eligible":false,
         "held_out_accuracy":"NOT_MEASURED"]
    }
    private static func i64(_ v: Any?) -> Int64? {
        guard let n=v as? NSNumber,
              CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let x=n.doubleValue
        guard x.isFinite, x.rounded() == x,
              x > -9.22e18, x < 9.22e18 else { return nil }
        return n.int64Value
    }
    private static func numeric(_ v: Any?) -> Double? {
        guard let n=v as? NSNumber,
              CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let x=n.doubleValue
        return x.isFinite ? x : nil
    }
    private static func verifiedNoProof(_ v:[String:Any]) -> Bool {
        noProof.allSatisfy { v[$0] as? Bool == false } &&
        v["region_calibrated"] as? Bool == false
    }
    static func audit(feature:[String:Any],
                      registration:[String:Any]) -> [String:Any] {
        guard feature["status"] as? String == featureOK,
              registration["status"] as? String == motionOK else {
            return hold("HOLD_UPSTREAM_UNAVAILABLE")
        }
        guard verifiedNoProof(feature),
              verifiedNoProof(registration),
              feature["retained_frame_count"] as? Int == 4,
              registration["frame_count"] as? Int == 4,
              registration["image_registration_is_mega_proof"]
                as? Bool == false,
              registration["scene_translation_may_include_actor_motion"]
                as? Bool == true else {
            return hold("HOLD_PROOF_BOUNDARY_MISMATCH")
        }
        guard let ids=feature["frame_ids"] as? [Any],
              let hashes=feature["image_sha256"] as? [String],
              let epochs=feature["epochs"] as? [Any],
              let times=feature["observed_ms_monotonic"] as? [Any],
              let motions=registration["pairs"] as? [[String:Any]],
              let regions=feature["regions"] as? [[String:Any]],
              ids.count == 4,hashes.count == 4,epochs.count == 4,
              times.count == 4,motions.count == 3,
              regions.count == 9 else {
            return hold("HOLD_EVIDENCE_CARDINALITY")
        }
        let fid=ids.compactMap{i64($0)}
        let epoch=epochs.compactMap{i64($0)}
        let tm=times.compactMap{i64($0)}
        guard fid.count == 4,epoch.count == 4,tm.count == 4,
              epoch[0]>0,epoch.allSatisfy({$0==epoch[0]}),
              fid[0]>0,tm[0]>0,
              zip(fid,fid.dropFirst()).allSatisfy({$0 < $1}),
              zip(tm,tm.dropFirst()).allSatisfy({$0 < $1}),
              Set(hashes).count == 4,
              hashes.allSatisfy({ hash in
                  hash.count == 64 && hash.utf8.allSatisfy({ byte in
                    (48...57).contains(byte) || (97...102).contains(byte)
                  })
              }) else {
            return hold("HOLD_FRAME_PROVENANCE")
        }
        var grouped=[[String:[String:Any]]](repeating:[:],count:3)
        for r in regions {
            guard let name=r["region"] as? String,
                  regionNames.contains(name),
                  let a=i64(r["from_frame_id"]),
                  let b=i64(r["to_frame_id"]),
                  let sa=r["from_sha256"] as? String,
                  let sb=r["to_sha256"] as? String,
                  let ta=i64(r["from_observed_ms"]),
                  let tb=i64(r["to_observed_ms"]),
                  let dist=numeric(r["feature_distance_unscaled"]),
                  dist>=0,let revision=i64(r["vision_revision"]),
                  revision>0,
                  r["region_calibrated"] as? Bool == false,
                  r["mega_event_confirmed"] as? Bool == false,
                  r["owner"] as? String == "UNKNOWN",
                  let idx=(0..<3).first(where:{fid[$0]==a &&
                         fid[$0+1]==b}) else {
                return hold("HOLD_REGION_EVIDENCE_INVALID")
            }
            guard sa==hashes[idx],sb==hashes[idx+1],
                  ta==tm[idx],tb==tm[idx+1],
                  grouped[idx][name] == nil else {
                return hold("HOLD_REGION_SOURCE_MISMATCH")
            }
            grouped[idx][name]=r
        }
        guard grouped.allSatisfy({$0.count==3}) else {
            return hold("HOLD_REGION_COVERAGE")
        }
        var output=[[String:Any]]()
        for idx in 0..<3 {
            let m=motions[idx]
            guard i64(m["pair_index"]) == Int64(idx),
                  i64(m["from_frame_id"]) == fid[idx],
                  i64(m["to_frame_id"]) == fid[idx+1],
                  i64(m["from_observed_ms"]) == tm[idx],
                  i64(m["to_observed_ms"]) == tm[idx+1],
                  m["from_sha256"] as? String == hashes[idx],
                  m["to_sha256"] as? String == hashes[idx+1],
                  let dx=numeric(m["translation_x_fraction"]),
                  let dy=numeric(m["translation_y_fraction"]),
                  let mag=numeric(m["translation_magnitude_fraction"]),
                  abs(mag-hypot(dx,dy)) <= 1e-8,
                  mag>=0,mag<=2,
                  m["alignment_is_actor_or_mega_proof"]
                      as? Bool == false else {
                return hold("HOLD_MOTION_SOURCE_MISMATCH")
            }
            var distances=[String:Double]()
            for name in regionNames {
                guard let d=numeric(grouped[idx][name]?[
                    "feature_distance_unscaled"]) else {
                    return hold("HOLD_REGION_DISTANCE")
                }
                distances[name]=d
            }
            output.append([
                "from_frame_id":fid[idx],
                "to_frame_id":fid[idx+1],
                "source_sha256_from":hashes[idx],
                "source_sha256_to":hashes[idx+1],
                "translation_magnitude_fraction":mag,
                "translation_x_fraction":dx,
                "translation_y_fraction":dy,
                "feature_distance_by_region_unscaled":distances,
                "diagnostic_only":true,
                "camera_or_actor_motion_distinguished":false,
                "mega_event_confirmed":false
            ])
        }
        return ["schema":schema,
                "status":"HISTORICAL_CROSS_MODAL_EVIDENCE_ONLY",
                "pairs_checked":3,"source_join_verified":true,
                "pairs":output,
                "source_kind":"RETAINED_CAPTURE_ONE_TAP_HISTORY",
                "region_calibrated":false,"owner_certified":false,
                "species_certified":false,
                "mega_event_certified":false,
                "mega_form_certified":false,
                "battle_advice_authorized":false,
                "current_state_eligible":false,
                "held_out_accuracy":"NOT_MEASURED",
                "limitations":"Aligned historical evidence provenance only. " +
                "Unknown actor ROIs and camera-vs-actor ambiguity; " +
                "no Mega form or event classification."]
    }
}
