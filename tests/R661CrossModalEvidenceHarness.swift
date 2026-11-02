import Foundation
@main struct R661CrossModalEvidenceHarness {
    static func main() {
        let names=["LEFT_ACTOR_HYPOTHESIS",
                   "RIGHT_ACTOR_HYPOTHESIS","BACKGROUND_CONTROL"]
        let ids:[Int64]=[10,11,12,13]
        let ts:[Int64]=[100,200,300,400]
        let sha=["a","b","c","d"].map{String(repeating:$0,count:64)}
        let safety:[String:Any]=[
            "owner_certified":false,"species_certified":false,
            "mega_event_certified":false,"mega_form_certified":false,
            "battle_advice_authorized":false,
            "current_state_eligible":false,"region_calibrated":false]
        var regions=[[String:Any]]()
        for area in names {
            for i in 0..<3 {
                regions.append([
                    "region":area,"from_frame_id":ids[i],
                    "to_frame_id":ids[i+1],"from_sha256":sha[i],
                    "to_sha256":sha[i+1],
                    "from_observed_ms":ts[i],
                    "to_observed_ms":ts[i+1],
                    "feature_distance_unscaled":Double(i+1)*0.1,
                    "vision_revision":1,"region_calibrated":false,
                    "owner":"UNKNOWN","mega_event_confirmed":false])
            }
        }
        var feature=safety
        feature.merge([
            "status":"HISTORICAL_UNLABELED_VISUAL_MOTION_ONLY",
            "retained_frame_count":4,"frame_ids":ids,
            "epochs":[1,1,1,1],"image_sha256":sha,
            "observed_ms_monotonic":ts,"regions":regions]){_,b in b}
        var motions=[[String:Any]]()
        for i in 0..<3 {
            motions.append([
                "pair_index":i,"from_frame_id":ids[i],
                "to_frame_id":ids[i+1],
                "from_observed_ms":ts[i],
                "to_observed_ms":ts[i+1],
                "from_sha256":sha[i],"to_sha256":sha[i+1],
                "translation_x_fraction":0.02,
                "translation_y_fraction":0.00,
                "translation_magnitude_fraction":0.02,
                "alignment_is_actor_or_mega_proof":false])
        }
        var scene=safety
        scene.merge([
            "status":"HISTORICAL_CAMERA_TRANSLATION_MEASURE_ONLY",
            "frame_count":4,"pairs":motions,
            "scene_translation_may_include_actor_motion":true,
            "image_registration_is_mega_proof":false]){_,b in b}
        var passed=0
        func check(_ b:Bool,_ tag:String) {
            precondition(b,"R661_TEST_FAIL_"+tag);passed += 1
        }
        func verdict(_ f:[String:Any],_ s:[String:Any])->String {
            R661CrossModalEvidenceGate.audit(feature:f,
                     registration:s)["status"] as? String ?? ""
        }
        let ok="HISTORICAL_CROSS_MODAL_EVIDENCE_ONLY"
        let original=R661CrossModalEvidenceGate.audit(
            feature:feature,registration:scene)
        check(original["schema"] as? String ==
              R661CrossModalEvidenceGate.schema,"schema")
        check(original["status"] as? String == ok,"valid")
        check(original["pairs_checked"] as? Int == 3,"three")
        check(original["source_join_verified"] as? Bool == true,"joined")
        check(original["mega_event_certified"] as? Bool == false,"mega")
        check(original["owner_certified"] as? Bool == false,"owner")
        check(original["battle_advice_authorized"] as? Bool == false,"advice")
        check(original["held_out_accuracy"] as? String ==
              "NOT_MEASURED","accuracy")
        var f=feature,s=scene
        f["status"]="HOLD_NO_FEATURE"
        check(verdict(f,s)=="HOLD_UPSTREAM_UNAVAILABLE","upstream")
        f=feature;f["owner_certified"]=true
        check(verdict(f,s)=="HOLD_PROOF_BOUNDARY_MISMATCH","promotion")
        f=feature;f["frame_ids"]=[10,11,12]
        check(verdict(f,s)=="HOLD_EVIDENCE_CARDINALITY","short")
        f=feature;f["frame_ids"]=[10,11,11,13]
        check(verdict(f,s)=="HOLD_FRAME_PROVENANCE","duplicateid")
        f=feature;f["image_sha256"]=[sha[0],sha[1],sha[1],sha[3]]
        check(verdict(f,s)=="HOLD_FRAME_PROVENANCE","duplicatesha")
        f=feature;f["observed_ms_monotonic"]=[100,200,100,400]
        check(verdict(f,s)=="HOLD_FRAME_PROVENANCE","clock")
        f=feature;f["epochs"]=[1,1,2,1]
        check(verdict(f,s)=="HOLD_FRAME_PROVENANCE","epoch")
        f=feature;var rr=regions
        rr[0]["feature_distance_unscaled"] = Double.nan
        f["regions"]=rr
        check(verdict(f,s)=="HOLD_REGION_EVIDENCE_INVALID","nan")
        f=feature;rr=regions
        rr[0]["to_sha256"]=sha[0]
        f["regions"]=rr
        check(verdict(f,s)=="HOLD_REGION_SOURCE_MISMATCH","region_sha")
        f=feature;rr=regions
        rr[0]=rr[1]
        f["regions"]=rr
        check(verdict(f,s)=="HOLD_REGION_SOURCE_MISMATCH","duplicate_region")
        f=feature;rr=regions
        rr[0]["mega_event_confirmed"]=true
        f["regions"]=rr
        check(verdict(f,s)=="HOLD_REGION_EVIDENCE_INVALID","fake_mega")
        s=scene;var mm=motions
        mm[0]["to_sha256"]=sha[0]
        s["pairs"]=mm
        check(verdict(feature,s)=="HOLD_MOTION_SOURCE_MISMATCH","motion_sha")
        s=scene;mm=motions
        mm[0]["translation_magnitude_fraction"]=0.3
        s["pairs"]=mm
        check(verdict(feature,s)=="HOLD_MOTION_SOURCE_MISMATCH","norm")
        s=scene;mm=motions
        mm[0]["translation_y_fraction"]=Double.infinity
        s["pairs"]=mm
        check(verdict(feature,s)=="HOLD_MOTION_SOURCE_MISMATCH","infinity")
        s=scene;s["image_registration_is_mega_proof"]=true
        check(verdict(feature,s)=="HOLD_PROOF_BOUNDARY_MISMATCH","scene_proof")
        check(R661CrossModalEvidenceGate.audit(feature:feature,
              registration:scene)["pairs"] as? [[String:Any]] != nil,
              "pair_output")
        print("R661_CROSS_MODAL_GUARD_PASS",passed)
    }
}
