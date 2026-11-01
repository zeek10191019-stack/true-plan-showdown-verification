import Foundation

@main struct R586HUDSpatialCandidatesHarness {
    static var passed=0
    static let sha=String(repeating:"a",count:64)
    static func check(_ ok:Bool,_ label:String) {
        guard ok else {fatalError("R586_FAIL_"+label)}
        passed+=1
    }
    static func makeRecord(_ text:String,_ x:Double,_ y:Double,_ w:Double=0.07,_ h:Double=0.035,
                           _ frame:Int64=1,_ time:Int64=1000,_ rotation:Int=0)->[String:Any] {
        let roi:[String:Any]=["x":x,"y":y,"width":w,"height":h]
        let projected=R585SpatialOCRProjection.projected(roi,angle:rotation)!
        return ["status":"UNVERIFIED_ORIENTATION_SPATIAL_OCR_CANDIDATE",
                "display_orientation_certified":false,"owner":"UNKNOWN",
                "pokemon_identity":"UNKNOWN","turn":NSNull(),"current_state_eligible":false,
                "image_sha256":sha,"frame_id":frame,"epoch":Int64(1),
                "observed_ms_monotonic":time,"text":text,
                "evidence_ref":"rotation_\(rotation).observations[0]",
                "rotation_degrees":rotation,"vision_oriented_bottom_left_roi":roi,
                "nominal_source_bottom_left_roi":projected]
    }
    static func spatial(_ records:[[String:Any]])->[String:Any] {
        ["schema":R585SpatialOCRProjection.schema,
         "status":"HISTORICAL_GEOMETRY_CANDIDATES_ONLY",
         "source_coordinate_space":"VISION_ORIENTED_NORMALIZED_BOTTOM_LEFT",
         "projected_coordinate_space":"NOMINAL_SOURCE_NORMALIZED_BOTTOM_LEFT_UNVERIFIED",
         "display_orientation_certified":false,"roi_owner_certified":false,
         "visual_mega_form_certified":false,"game_turn_certified":false,
         "current_state_eligible":false,"battle_advice_authorized":false,
         "automatic_upload":false,"truncated_by_limit":false,
         "candidate_count":records.count,"frames_examined":records.isEmpty ? 0 : 1,
         "candidates":records]
    }
    static func result(_ text:String,_ x:Double,_ y:Double)->[String:Any] {
        R586HUDSpatialCandidates.make(spatial:spatial([makeRecord(text,x,y)]))
    }
    static func main() {
        let own=result("180/192",0.14,0.045)
        check(own["status"] as? String=="HISTORICAL_LAYOUT_HYPOTHESES_ONLY","SUCCESS_STATUS")
        check(own["matched_candidates"] as? Int==1,"OWN_COUNT")
        let ownH=(own["hypotheses"] as! [[String:Any]])[0]
        check(ownH["hypothesis"] as? String=="HYPOTHESIS_OWN_HP_FRACTION","OWN_HP")
        check(ownH["region_hypothesis"] as? String=="BOTTOM_LEFT_HUD","OWN_REGION")
        check(ownH["numeric_text_candidate"] as? [String:Int]==["numerator":180,"denominator":192],"OWN_NUMS")
        check(ownH["owner"] as? String=="UNKNOWN","UNVERIFIED_OWNER")
        check(ownH["game_turn"] is NSNull,"UNKNOWN_TURN")
        check(ownH["current_state_eligible"] as? Bool==false,"NO_ADMISSION")
        check(ownH["image_sha256"] as? String==sha,"SHA")
        check(ownH["evidence_ref"] as? String=="rotation_0.observations[0]","REF")
        check(own["owner_certified"] as? Bool==false,"ROOT_OWNER")
        check(own["hp_vs_pp_certified"] as? Bool==false,"ROOT_HP_PP")
        check(own["actual_game_accuracy_certified"] as? Bool==false,"NO_REAL_GAME")
        check(own["automatic_upload"] as? Bool==false,"NO_UPLOAD")
        check(own["battle_advice_authorized"] as? Bool==false,"NO_COACH")
        let pp=result("16/16",0.86,0.46)
        let ppH=(pp["hypotheses"] as! [[String:Any]])[0]
        check(ppH["hypothesis"] as? String=="HYPOTHESIS_MOVE_PP_FRACTION","MOVE_PP")
        check(ppH["numeric_text_candidate"] as? [String:Int]==["numerator":16,"denominator":16],"PP_NUMS")
        let opponent=result("55%",0.86,0.85)
        let oppH=(opponent["hypotheses"] as! [[String:Any]])[0]
        check(oppH["hypothesis"] as? String=="HYPOTHESIS_OPPONENT_HP_PERCENT","OPP_PERCENT")
        check(oppH["numeric_text_candidate"] as? [String:Int]==["percent":55],"OPP_NUM")
        check(result("101%",0.86,0.85)["matched_candidates"] as? Int==0,"OVER_PERCENT")
        check(result("0%",0.86,0.85)["matched_candidates"] as? Int==1,"ZERO_PERCENT")
        check(result("100%",0.86,0.85)["matched_candidates"] as? Int==1,"MAX_PERCENT")
        check(result("101/100",0.14,0.045)["matched_candidates"] as? Int==0,"OVER_FRACTION")
        check(result("0/10",0.14,0.045)["matched_candidates"] as? Int==1,"ZERO_FRACTION")
        check(result("0/0",0.14,0.045)["matched_candidates"] as? Int==0,"ZERO_MAX")
        check(result("16/16",0.53,0.43)["matched_candidates"] as? Int==0,"CENTER_AMBIGUOUS")
        check(result("16/16",0.85,0.87)["matched_candidates"] as? Int==0,"TOP_RIGHT_NOT_PP")
        check(result("55%",0.13,0.05)["matched_candidates"] as? Int==0,"BOTTOM_LEFT_NOT_OPP")
        check(result("メガシンカ",0.86,0.85)["matched_candidates"] as? Int==0,"MEGA_NOT_FORM")
        check(result("まひ",0.13,0.05)["matched_candidates"] as? Int==0,"STATUS_NOT_NUMERIC")
        check(result("16/16",0.66,0.46)["matched_candidates"] as? Int==0,"RIGHT_EDGE_FENCE")
        let wide=R586HUDSpatialCandidates.make(spatial:spatial([makeRecord("55%",0.65,0.85,0.35,0.04)]))
        check(wide["matched_candidates"] as? Int==0,"WIDE_NOT_IN_TOP_RIGHT")
        var forged=spatial([makeRecord("55%",0.86,0.85)]);forged["roi_owner_certified"]=true
        check(R586HUDSpatialCandidates.make(spatial:forged)["status"] as? String=="HOLD_INVALID_SOURCE","FORGED_OWNER")
        forged=spatial([makeRecord("55%",0.86,0.85)]);forged["truncated_by_limit"]=true
        check(R586HUDSpatialCandidates.make(spatial:forged)["status"] as? String=="HOLD_INVALID_SOURCE","TRUNCATED")
        forged=spatial([makeRecord("55%",0.86,0.85)]);forged["candidate_count"]=0
        check(R586HUDSpatialCandidates.make(spatial:forged)["status"] as? String=="HOLD_INVALID_SOURCE","COUNT_MISMATCH")
        forged=spatial([makeRecord("55%",0.86,0.85)])
        var row=makeRecord("55%",0.86,0.85);row["image_sha256"]=String(repeating:"x",count:64);forged["candidates"]=[row]
        check(R586HUDSpatialCandidates.make(spatial:forged)["status"] as? String=="HOLD_INVALID_SOURCE","FORGED_SHA")
        forged=spatial([makeRecord("55%",0.86,0.85)]);row=makeRecord("55%",0.86,0.85)
        row["nominal_source_bottom_left_roi"]=["x":0.76,"y":0.85,"width":0.07,"height":0.035]
        forged["candidates"]=[row]
        check(R586HUDSpatialCandidates.make(spatial:forged)["status"] as? String=="HOLD_INVALID_SOURCE","FORGED_TRANSFORM")
        forged=spatial([makeRecord("55%",0.86,0.85)]);row=makeRecord("55%",0.86,0.85);row["current_state_eligible"]=true;forged["candidates"]=[row]
        check(R586HUDSpatialCandidates.make(spatial:forged)["status"] as? String=="HOLD_INVALID_SOURCE","FORGED_LIVE")
        let two=spatial([makeRecord("180/192",0.14,0.045),makeRecord("16/16",0.86,0.46,0.07,0.035,2,1100)])
        let many=R586HUDSpatialCandidates.make(spatial:two)
        check(many["matched_candidates"] as? Int==2,"TWO_FRAMES")
        check((many["hypotheses"] as? [[String:Any]])?.count==2,"TWO_OUTPUTS")
        let wrong=spatial([makeRecord("180/192",0.14,0.045,0.07,0.035,2,1200),makeRecord("16/16",0.86,0.46,0.07,0.035,1,1100)])
        check(R586HUDSpatialCandidates.make(spatial:wrong)["status"] as? String=="HOLD_INVALID_SOURCE","REVERSED")
        let mixed=spatial([makeRecord("180/192",0.14,0.045),makeRecord("16/16",0.86,0.46)])
        var mixedRows=mixed["candidates"] as! [[String:Any]]
        mixedRows[1]["epoch"]=Int64(2)
        forged=mixed;forged["candidates"]=mixedRows
        check(R586HUDSpatialCandidates.make(spatial:forged)["status"] as? String=="HOLD_INVALID_SOURCE","MIXED_EPOCH")
        let angle90=R586HUDSpatialCandidates.make(spatial:spatial([makeRecord("180/192",0.045,0.79,0.035,0.07,1,1000,90)]))
        check(angle90["status"] as? String=="HISTORICAL_LAYOUT_HYPOTHESES_ONLY","ROT90_VALID")
        check(angle90["source_orientation_certified"] as? Bool==false,"ROT90_NOT_CERT")
        let empty=R586HUDSpatialCandidates.make(spatial:spatial([]))
        check(empty["matched_candidates"] as? Int==0,"EMPTY")
        check(JSONSerialization.isValidJSONObject(own),"SERIALIZABLE")
        check(JSONSerialization.isValidJSONObject(empty),"EMPTY_SERIALIZABLE")
        check(passed>=40,"MINIMUM")
        print("PASS_R586_\(passed)_HUD_GEOMETRY_TEXT_UNCERTIFIED_AND_FAIL_CLOSED")
    }
}
