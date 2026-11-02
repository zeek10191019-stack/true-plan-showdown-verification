import Foundation
import CoreFoundation

/// Evidence-only comparison of *unverified* tracked regions and scene shift.
/// No coordinate direction, sprite identity, or Mega conclusion is inferred.
enum R663RelativeMotionAudit {
    static let schema = "trueplan.r663.relative-motion-audit.v1"
    private static let regions = ["LEFT_REGION_HYPOTHESIS",
                                  "RIGHT_REGION_HYPOTHESIS"]
    private static let noProof = ["owner_certified", "species_certified",
                                  "mega_event_certified", "mega_form_certified",
                                  "battle_advice_authorized", "current_state_eligible",
                                  "region_calibrated"]
    private static func hold(_ reason: String) -> [String:Any] {
        ["schema":schema,"status":reason,
         "source_join_verified":false,"pairs_compared":0,
         "owner_certified":false,"species_certified":false,
         "mega_event_certified":false,"mega_form_certified":false,
         "region_calibrated":false,"battle_advice_authorized":false,
         "current_state_eligible":false,
         "camera_or_actor_motion_distinguished":false,
         "held_out_accuracy":"NOT_MEASURED"]
    }
    private static func number(_ value: Any?) -> Double? {
        guard let n=value as? NSNumber,
              CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let x=n.doubleValue
        return x.isFinite ? x : nil
    }
    private static func int64(_ value: Any?) -> Int64? {
        guard let x=number(value), x.rounded()==x,
              x > -9.22e18, x < 9.22e18 else { return nil }
        return Int64(x)
    }
    private static func safe(_ dictionary: [String:Any]) -> Bool {
        noProof.allSatisfy { dictionary[$0] as? Bool == false } &&
        dictionary["held_out_accuracy"] as? String == "NOT_MEASURED"
    }
    private static func hashValid(_ s: String) -> Bool {
        s.utf8.count == 64 && s.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }
    private static func validBox(_ p: [String:Any]) -> [Double]? {
        let keys=["box_x_lower_left","box_y_lower_left",
                  "box_width","box_height"]
        let v=keys.compactMap { number(p[$0]) }
        guard v.count==4,v[0]>=0,v[1]>=0,
              v[2]>0,v[3]>0,
              v[0]+v[2] <= 1.000001,
              v[1]+v[3] <= 1.000001 else { return nil }
        return v
    }
    static func audit(feature: [String:Any],
                      joined: [String:Any],
                      tracking: [String:Any]) -> [String:Any] {
        guard feature["status"] as? String ==
                "HISTORICAL_UNLABELED_VISUAL_MOTION_ONLY",
              joined["status"] as? String ==
                "HISTORICAL_CROSS_MODAL_EVIDENCE_ONLY",
              tracking["status"] as? String ==
                "HISTORICAL_UNLABELED_REGION_TRACKS_ONLY",
              safe(feature),safe(joined),safe(tracking),
              joined["source_join_verified"] as? Bool == true,
              joined["pairs_checked"] as? Int == 3,
              tracking["frame_count"] as? Int == 4,
              tracking["seed_coordinates"] as? String ==
                "TOP_LEFT_FRACTIONS",
              tracking["vision_boxes"] as? String ==
                "BOTTOM_LEFT_FRACTIONS",
              tracking["assumed_image_orientation"] as? String ==
                "UP_UNVERIFIED",
              tracking["source_kind"] as? String ==
                "RETAINED_CAPTURE_ONE_TAP_HISTORY",
              let ids=feature["frame_ids"] as? [Any],
              let times=feature["observed_ms_monotonic"] as? [Any],
              let hashes=feature["image_sha256"] as? [String],
              let joinPairs=joined["pairs"] as? [[String:Any]],
              let samples=tracking["samples"] as? [[String:Any]],
              ids.count==4,times.count==4,hashes.count==4,
              joinPairs.count==3,samples.count==6 else {
            return hold("HOLD_UPSTREAM_OR_CARDINALITY")
        }
        let frames=ids.compactMap{int64($0)}
        let clock=times.compactMap{int64($0)}
        guard frames.count==4,clock.count==4,
              frames[0]>0,clock[0]>0,
              Set(hashes).count==4,hashes.allSatisfy(hashValid),
              zip(frames,frames.dropFirst()).allSatisfy({$0<$1}),
              zip(clock,clock.dropFirst()).allSatisfy({$0<$1 && $1-$0<=10000})
        else { return hold("HOLD_FRAME_PROVENANCE") }
        // Two distinct hypothetical trackers, each with 3 successive pairs.
        var byRegion=[[String:[Double]]](repeating:[:],count:3)
        for row in samples {
            guard let name=row["region"] as? String,
                  regions.contains(name),
                  let from=int64(row["from_frame_id"]),
                  let to=int64(row["to_frame_id"]),
                  let start=int64(row["from_observed_ms"]),
                  let end=int64(row["to_observed_ms"]),
                  let shaFrom=row["from_sha256"] as? String,
                  let shaTo=row["to_sha256"] as? String,
                  let confidence=number(row["tracker_confidence_unvalidated"]),
                  (0...1).contains(confidence),
                  row["source_is_pokemon"] as? Bool == false,
                  row["owner_verified"] as? Bool == false,
                  row["camera_vs_actor_distinguished"] as? Bool == false,
                  row["mega_form_identified"] as? Bool == false,
                  let box=validBox(row),
                  let index=(0..<3).first(where:{frames[$0]==from &&
                                                 frames[$0+1]==to}),
                  start==clock[index],end==clock[index+1],
                  shaFrom==hashes[index],shaTo==hashes[index+1],
                  byRegion[index][name] == nil else {
                return hold("HOLD_TRACKING_PROVENANCE_OR_GEOMETRY")
            }
            byRegion[index][name]=box
        }
        guard byRegion.allSatisfy({$0.count==2}) else {
            return hold("HOLD_TRACK_REGION_COVERAGE")
        }
        // R662 starts both trackers from fixed uncalibrated hypotheses.
        let seed: [String:(Double,Double)] = [
            "LEFT_REGION_HYPOTHESIS":(0.10+0.31/2, 1-0.36-0.32/2),
            "RIGHT_REGION_HYPOTHESIS":(0.60+0.22/2,1-0.40-0.30/2)]
        var previous=seed
        var output=[[String:Any]]()
        for index in 0..<3 {
            let j=joinPairs[index]
            guard int64(j["from_frame_id"])==frames[index],
                  int64(j["to_frame_id"])==frames[index+1],
                  j["source_sha256_from"] as? String==hashes[index],
                  j["source_sha256_to"] as? String==hashes[index+1],
                  j["diagnostic_only"] as? Bool==true,
                  j["camera_or_actor_motion_distinguished"] as? Bool==false,
                  j["mega_event_confirmed"] as? Bool==false,
                  let tx=number(j["translation_x_fraction"]),
                  let ty=number(j["translation_y_fraction"]),
                  let tm=number(j["translation_magnitude_fraction"]),
                  abs(tm-hypot(tx,ty)) <= 1e-8,tm>=0,tm<=2,
                  let d=j["feature_distance_by_region_unscaled"]
                        as? [String:Any],d.count==3,
                  ["LEFT_ACTOR_HYPOTHESIS","RIGHT_ACTOR_HYPOTHESIS",
                   "BACKGROUND_CONTROL"].allSatisfy({key in
                      guard let value=number(d[key]) else {return false}
                      return value>=0
                   }) else {return hold("HOLD_JOINED_CAMERA_EVIDENCE")}
            for name in regions {
                guard let b=byRegion[index][name],
                      let old=previous[name] else {
                    return hold("HOLD_MISSING_TRACK_STATE")
                }
                let now=(b[0]+b[2]/2,b[1]+b[3]/2)
                let dx=now.0-old.0,dy=now.1-old.1
                // Translation sign and image axis conventions are not proven.
                // Report BOTH signed interpretations. Never select one.
                output.append([
                    "region":name,
                    "from_frame_id":frames[index],
                    "to_frame_id":frames[index+1],
                    "from_sha256":hashes[index],
                    "to_sha256":hashes[index+1],
                    "tracker_delta_x_fraction":dx,
                    "tracker_delta_y_fraction":dy,
                    "scene_alignment_x_fraction":tx,
                    "scene_alignment_y_fraction":ty,
                    "residual_if_scene_subtracted":hypot(dx-tx,dy-ty),
                    "residual_if_scene_added":hypot(dx+tx,dy+ty),
                    "scene_alignment_sign_calibrated":false,
                    "source_is_pokemon":false,
                    "actor_motion_confirmed":false,
                    "mega_event_confirmed":false
                ])
                previous[name]=now
            }
        }
        return ["schema":schema,
            "status":"HISTORICAL_TWO_SIGN_RESIDUALS_ONLY",
            "source_kind":"RETAINED_CAPTURE_ONE_TAP_HISTORY",
            "source_join_verified":true,
            "pairs_compared":3,"rows":output,
            "scene_alignment_sign_calibrated":false,
            "image_orientation_calibrated":false,
            "object_seeds_calibrated":false,
            "camera_or_actor_motion_distinguished":false,
            "owner_certified":false,"species_certified":false,
            "mega_event_certified":false,"mega_form_certified":false,
            "region_calibrated":false,"battle_advice_authorized":false,
            "current_state_eligible":false,
            "held_out_accuracy":"NOT_MEASURED",
            "limitations":"Two sign hypotheses, no orientation or camera " +
              "direction calibration. Historical unlabelled regions only; " +
              "not object discovery, Mega or owner certification."]
    }
}
