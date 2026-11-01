import Foundation
@main struct R658TemporalHarness {
    static var count=0
    static func check(_ p:Bool,_ label:String) {
        guard p else {fatalError("R658_"+label)};count+=1
    }
    static let names=R658MegaTemporalGate.regions
    static let hashes=(1...4).map{String(repeating:String($0),count:64)}
    static func report(_ b:String,_ a:String,
                       _ scores:[Double], form:String="gyarados-mega") -> [String:Any] {
        ["schema":R656MegaVisionPair.schema,
         "status":"OFFLINE_VISION_DISTANCE_ONLY",
         "owner_certified":false,"mega_event_certified":false,
         "battle_advice_authorized":false,
         "proposed_mega_form_id":form,
         "before_sha256":b,"after_sha256":a,
         "human_pair_claim_reviewed":true,
         "distances":zip(names,scores).map {name,val in
            ["region":name,"feature_distance_unscaled":val,
             "mega_event_confirmed":false,"owner":"UNKNOWN"] as [String:Any]
         }]
    }
    static func main() {
        let h=hashes
        // WHOLE, LEFT, RIGHT, BACKGROUND
        let good=[report(h[0],h[1],[0.1,0.1,0.1,0.1]),
                  report(h[2],h[3],[0.1,0.1,0.1,0.1]),
                  report(h[0],h[2],[0.7,0.8,0.1,0.2]),
                  report(h[1],h[3],[0.7,0.9,0.1,0.2])]
        let result=R658MegaTemporalGate.audit(good)
        check(result["status"] as? String == "UNVERIFIED_LOCALIZED_APPEARANCE_CHANGE","single_actor")
        check(result["mega_event_certified"] as? Bool == false,"no_mega")
        check(result["owner_certified"] as? Bool == false,"no_owner")
        check(result["battle_advice_authorized"] as? Bool == false,"no_advice")
        check(result["held_out_accuracy"] as? String == "NOT_MEASURED","unmeasured")
        check((result["regions"] as? [[String:Any]])?.count == 4,"four_regions")
        check(R658MegaTemporalGate.audit(Array(good.dropLast()))["status"] as? String == "HOLD_WRONG_REPORT_COUNT","count_gate")
        var wrong=good
        wrong[3]["before_sha256"] = h[0]
        check(R658MegaTemporalGate.audit(wrong)["status"] as? String == "HOLD_FRAME_PAIR_BINDING","binding")
        wrong=good
        wrong[0]["human_pair_claim_reviewed"] = false
        check(R658MegaTemporalGate.audit(wrong)["status"] as? String == "HOLD_PAIR_PROVENANCE_OR_SCHEMA","review")
        wrong=good
        wrong[2]["proposed_mega_form_id"] = "charizard-mega-x"
        check(R658MegaTemporalGate.audit(wrong)["status"] as? String == "HOLD_PAIR_PROVENANCE_OR_SCHEMA","form_binding")
        wrong=good
        wrong[2]["mega_event_certified"] = true
        check(R658MegaTemporalGate.audit(wrong)["status"] as? String == "HOLD_PAIR_PROVENANCE_OR_SCHEMA","cert_gate")
        wrong=good
        var rows=wrong[0]["distances"] as! [[String:Any]]
        rows[1]["feature_distance_unscaled"] = Double.infinity
        wrong[0]["distances"] = rows
        check(R658MegaTemporalGate.audit(wrong)["status"] as? String == "HOLD_DISTANCE_OR_REGION","infinite")
        wrong=good
        rows=wrong[0]["distances"] as! [[String:Any]]
        rows[1]["region"] = "WHOLE_FRAME"
        wrong[0]["distances"] = rows
        check(R658MegaTemporalGate.audit(wrong)["status"] as? String == "HOLD_DISTANCE_OR_REGION","duplicate_region")
        wrong=good
        wrong[1]["after_sha256"] = h[0]
        check(R658MegaTemporalGate.audit(wrong)["status"] as? String == "HOLD_FRAME_PAIR_BINDING","all_distinct")
        wrong=good
        wrong[2]["distances"] = zip(names,[0.7,0.8,0.8,0.2]).map {n,v in
            ["region":n,"feature_distance_unscaled":v,
             "mega_event_confirmed":false,"owner":"UNKNOWN"] as [String:Any]
        }
        wrong[3]["distances"] = wrong[2]["distances"]
        check(R658MegaTemporalGate.audit(wrong)["status"] as? String == "HOLD_BOTH_ACTOR_REGIONS_CHANGED","both_changed")
        wrong=good
        wrong[2]["distances"] = zip(names,[0.1,0.1,0.1,0.7]).map {n,v in
            ["region":n,"feature_distance_unscaled":v,
             "mega_event_confirmed":false,"owner":"UNKNOWN"] as [String:Any]
        }
        wrong[3]["distances"] = wrong[2]["distances"]
        check(R658MegaTemporalGate.audit(wrong)["status"] as? String == "HOLD_NO_LOCALIZED_CHANGE","background_motion")
        wrong=good
        wrong[0]["schema"]="bad"
        check(R658MegaTemporalGate.audit(wrong)["status"] as? String == "HOLD_PAIR_PROVENANCE_OR_SCHEMA","foreign_schema")
        check(result["original_images_exported"] as? Bool == false,"privacy")
        print("R658_TEMPORAL_GATE_PASS",count)
    }
}
