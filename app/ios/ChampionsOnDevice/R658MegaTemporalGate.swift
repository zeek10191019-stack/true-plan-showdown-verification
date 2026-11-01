import Foundation

/// Independent research gate for four user-selected PNGs: before twice,
/// after twice. Every result is evidence, never an actor/mega assertion.
enum R658MegaTemporalGate {
    static let schema = "trueplan.r658.temporal-vision-audit.v1"
    static let labels = ["BEFORE_PAIR", "AFTER_PAIR", "CROSS_FIRST", "CROSS_SECOND"]
    static let regions = ["WHOLE_FRAME", "LEFT_ACTOR_HYPOTHESIS",
                          "RIGHT_ACTOR_HYPOTHESIS", "BACKGROUND_CONTROL"]
    static func reject(_ reason: String) -> [String: Any] {
        ["schema": schema, "status": reason, "owner_certified": false,
         "mega_event_certified": false, "mega_form_certified": false,
         "battle_advice_authorized": false, "current_state_eligible": false,
         "held_out_accuracy": "NOT_MEASURED"]
    }
    static func audit(_ documents: [[String: Any]]) -> [String: Any] {
        guard documents.count == 4 else { return reject("HOLD_WRONG_REPORT_COUNT") }
        var arrays = [[String: Double]]()
        var shas = [(String, String)]()
        var form: String?
        for item in documents {
            guard item["schema"] as? String == R656MegaVisionPair.schema,
                  item["status"] as? String == "OFFLINE_VISION_DISTANCE_ONLY",
                  item["owner_certified"] as? Bool == false,
                  item["mega_event_certified"] as? Bool == false,
                  item["battle_advice_authorized"] as? Bool == false,
                  let id = item["proposed_mega_form_id"] as? String,
                  let before = item["before_sha256"] as? String,
                  let after = item["after_sha256"] as? String,
                  before.count == 64, after.count == 64,
                  before != after,
                  let rows = item["distances"] as? [[String: Any]],
                  rows.count == regions.count,
                  let reviewed = item["human_pair_claim_reviewed"] as? Bool,
                  reviewed,
                  form == nil || form == id else {
                return reject("HOLD_PAIR_PROVENANCE_OR_SCHEMA")
            }
            form = id
            var table = [String: Double]()
            for row in rows {
                guard let name = row["region"] as? String,
                      regions.contains(name), table[name] == nil,
                      let value = row["feature_distance_unscaled"] as? Double,
                      value.isFinite, value >= 0,
                      row["mega_event_confirmed"] as? Bool == false,
                      row["owner"] as? String == "UNKNOWN" else {
                    return reject("HOLD_DISTANCE_OR_REGION")
                }
                table[name] = value
            }
            guard table.count == regions.count else {
                return reject("HOLD_MISSING_REGION")
            }
            arrays.append(table)
            shas.append((before,after))
        }
        // [B1->B2, A1->A2, B1->A1, B2->A2]. Exactly four distinct PNGs.
        let b1 = shas[0].0, b2 = shas[0].1
        let a1 = shas[1].0, a2 = shas[1].1
        guard Set([b1,b2,a1,a2]).count == 4,
              shas[2] == (b1,a1), shas[3] == (b2,a2) else {
            return reject("HOLD_FRAME_PAIR_BINDING")
        }
        let background = max(arrays[2]["BACKGROUND_CONTROL"]!,
                             arrays[3]["BACKGROUND_CONTROL"]!)
        var output = [[String:Any]]()
        for name in regions {
            let within = max(arrays[0][name]!,arrays[1][name]!)
            let cross = min(arrays[2][name]!,arrays[3][name]!)
            let delta = cross - within
            let tag: String
            if delta <= 0 {
                tag = "HOLD_WITHIN_STATE_MOTION_DOMINATES"
            } else if name != "BACKGROUND_CONTROL" &&
                        name != "WHOLE_FRAME" && cross <= background {
                tag = "HOLD_BACKGROUND_SHIFT_DOMINATES"
            } else {
                tag = "TEMPORAL_VISUAL_CHANGE_CANDIDATE_ONLY"
            }
            output.append(["region":name,"within_max":within,
                           "cross_min":cross,"separation_unscaled":delta,
                           "background_cross_max":background,"status":tag,
                           "actor_owner":"UNKNOWN", "mega_confirmed":false])
        }
        let actors = output.filter {
            ($0["region"] as? String ?? "").contains("ACTOR") &&
            $0["status"] as? String == "TEMPORAL_VISUAL_CHANGE_CANDIDATE_ONLY"
        }
        let status = actors.count == 1 ?
            "UNVERIFIED_LOCALIZED_APPEARANCE_CHANGE" :
            (actors.count > 1 ? "HOLD_BOTH_ACTOR_REGIONS_CHANGED" :
                                  "HOLD_NO_LOCALIZED_CHANGE")
        return ["schema":schema,"status":status,
                "source_kind":"FOUR_USER_SELECTED_LOCAL_PNGS",
                "proposed_mega_form_id":form ?? "UNKNOWN",
                "png_sha256":[b1,b2,a1,a2],
                "regions":output,"four_distinct_pngs":true,
                "human_labels_independently_verified":false,
                "owner_certified":false,"species_certified":false,
                "mega_event_certified":false,"mega_form_certified":false,
                "current_state_eligible":false,"battle_advice_authorized":false,
                "original_images_exported":false,
                "held_out_accuracy":"NOT_MEASURED",
                "limitations":"Uncalibrated fixed ROIs and feature distance; " +
                   "manual ordering is unverified; scene effects and " +
                   "camera motion can mimic a change"]
    }
}
