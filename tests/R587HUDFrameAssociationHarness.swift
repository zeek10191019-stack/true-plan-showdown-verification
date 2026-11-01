import Foundation

@main struct R587HUDFrameAssociationHarness {
    static var passed=0
    static let sha=String(repeating:"a",count:64)
    static func check(_ yes:Bool,_ label:String) {
        guard yes else{fatalError("R587_FAIL_"+label)};passed+=1
    }
    static func snapshot(_ frame:Int64=1,_ time:Int64=1000,_ w:Int64=1920,_ h:Int64=1080)->[String:Any] {
        ["epoch":Int64(1),"frame_id":frame,"observed_ms_monotonic":time,
         "png_sha256":sha,"file":"frames/frame_1_\(frame).png","width":w,"height":h,
         "png_bytes":Int64(1000),"own_opponent_certified":false,"mega_form_visual_certified":false]
    }
    static func anchor(_ kind:String,_ value:[String:Int],_ frame:Int64=1,_ time:Int64=1000,
                       _ ref:String="rotation_0.observations[0]")->[String:Any] {
        let region=kind=="HYPOTHESIS_OWN_HP_FRACTION" ? "BOTTOM_LEFT_HUD" :
                   kind=="HYPOTHESIS_OPPONENT_HP_PERCENT" ? "TOP_RIGHT_HUD" : "RIGHT_MOVE_MENU"
        return ["hypothesis":kind,"region_hypothesis":region,"numeric_text_candidate":value,
                "text":"label","frame_id":frame,"epoch":Int64(1),"observed_ms_monotonic":time,
                "image_sha256":sha,"evidence_ref":ref,"rotation_degrees":0,
                "source_bottom_left_roi":["x":0.84,"y":0.43,"width":0.08,"height":0.04],
                "status":"UNVERIFIED_TEXT_AND_HUD_LAYOUT_MATCH","orientation_certified":false,
                "owner":"UNKNOWN","pokemon_identity":"UNKNOWN","game_turn":NSNull(),
                "current_state_eligible":false]
    }
    static func hud(_ a:[[String:Any]])->[String:Any] {
        ["schema":R586HUDSpatialCandidates.schema,"status":"HISTORICAL_LAYOUT_HYPOTHESES_ONLY",
         "owner_certified":false,"source_orientation_certified":false,
         "current_state_eligible":false,"battle_advice_authorized":false,
         "automatic_upload":false,"matched_candidates":a.count,"hypotheses":a]
    }
    static let own="HYPOTHESIS_OWN_HP_FRACTION"
    static let opp="HYPOTHESIS_OPPONENT_HP_PERCENT"
    static let pp="HYPOTHESIS_MOVE_PP_FRACTION"
    static func inspect(_ a:[[String:Any]],_ images:[[String:Any]]=[snapshot()])->[String:Any] {
        R587HUDFrameAssociation.make(hud:hud(a),snapshots:images)
    }
    static func first(_ r:[String:Any])->[String:Any] {
        (r["frames"] as! [[String:Any]])[0]
    }
    static func main() {
        let hp=anchor(own,["numerator":180,"denominator":192])
        let opponent=anchor(opp,["percent":55])
        let move=anchor(pp,["numerator":16,"denominator":16])
        let r=inspect([hp,opponent,move])
        check(r["status"] as? String == "HISTORICAL_FRAME_HUD_ASSOCIATIONS_ONLY","OK")
        check(r["frame_count"] as? Int==1,"FRAME_COUNT")
        check(r["association_count"] as? Int==3,"ANCHOR_COUNT")
        let f=first(r)
        check(f["unique_numeric_domains"] as? Int==3,"THREE_DOMAINS")
        check(f["layout_evidence_level"] as? String=="MULTI_ANCHOR_LAYOUT_HYPOTHESIS","MULTI")
        check(f["pixel_geometry_hypothesis"] as? String=="SOURCE_PIXEL_LANDSCAPE","PIXEL_LANDSCAPE")
        check(f["display_rotation_degrees"] is NSNull,"ROTATION_HOLD")
        check(f["owner"] as? String=="UNKNOWN","OWNER_HOLD")
        check(f["pokemon_identity"] as? String=="UNKNOWN","POKEMON_HOLD")
        check(f["mega_visual_form"] as? String=="UNKNOWN","MEGA_HOLD")
        check(f["turn"] is NSNull,"TURN_HOLD")
        check(f["current_state_eligible"] as? Bool==false,"NO_LIVE")
        check(r["orientation_certified"] as? Bool==false,"ROTATION_NOT_CERTIFIED")
        check(r["owner_certified"] as? Bool==false,"OWNER_NOT_CERTIFIED")
        check(r["battle_advice_authorized"] as? Bool==false,"NO_BATTLE_ADVICE")
        check(r["automatic_upload"] as? Bool==false,"NO_UPLOAD")
        check(JSONSerialization.isValidJSONObject(r),"JSON")
        let one=inspect([hp]);check(first(one)["layout_evidence_level"] as? String=="SINGLE_ANCHOR_LAYOUT_HYPOTHESIS","SINGLE")
        let zero=inspect([]);check(first(zero)["layout_evidence_level"] as? String=="NO_HUD_ANCHORS","ZERO")
        let portrait=inspect([hp],[snapshot(1,1000,720,1280)])
        check(first(portrait)["pixel_geometry_hypothesis"] as? String=="SOURCE_PIXEL_PORTRAIT","PORTRAIT")
        check(first(portrait)["display_rotation_degrees"] is NSNull,"PORTRAIT_NOT_ROTATION")
        let square=inspect([hp],[snapshot(1,1000,1100,1000)])
        check(first(square)["pixel_geometry_hypothesis"] as? String=="SOURCE_PIXEL_NEAR_SQUARE","NEAR_SQUARE")
        let conflict=inspect([hp,anchor(own,["numerator":170,"denominator":192])])
        check(first(conflict)["numeric_conflict_detected"] as? Bool==true,"CONFLICT")
        check(first(conflict)["layout_evidence_level"] as? String=="AMBIGUOUS_NUMERIC_ANCHORS","CONFLICT_LABEL")
        let repeated=inspect([hp,hp]);check(first(repeated)["numeric_conflict_detected"] as? Bool==false,"DUPLICATE_VALUES_NO_CONFLICT")
        let two=inspect([hp,anchor(pp,["numerator":15,"denominator":16],2,2000)],
                        [snapshot(),snapshot(2,2000)])
        check(two["frame_count"] as? Int==2,"TWO_FRAMES")
        check((two["frames"] as? [[String:Any]])?[1]["anchor_count"] as? Int==1,"SECOND_FRAME")
        var bad=snapshot();bad["file"]="frames/../escape.png"
        check(inspect([hp],[bad])["status"] as? String == "HOLD_INVALID_FRAME_OR_ASSOCIATION","PATH_FORGED")
        bad=snapshot();bad["png_sha256"]="BAD"
        check(inspect([hp],[bad])["status"] as? String == "HOLD_INVALID_FRAME_OR_ASSOCIATION","SHA_FORGED")
        bad=snapshot();bad["width"]=Int64(0)
        check(inspect([hp],[bad])["status"] as? String == "HOLD_INVALID_FRAME_OR_ASSOCIATION","WIDTH_INVALID")
        bad=snapshot();bad["epoch"]=Int64(2)
        check(inspect([hp],[bad])["status"] as? String == "HOLD_INVALID_FRAME_OR_ASSOCIATION","EPOCH_INVALID")
        bad=snapshot();bad["own_opponent_certified"]=true
        check(inspect([hp],[bad])["status"] as? String == "HOLD_INVALID_FRAME_OR_ASSOCIATION","FALSE_OWNER_CERT")
        bad=snapshot();bad["png_bytes"]=Int64(30_000_000)
        check(inspect([hp],[bad])["status"] as? String == "HOLD_INVALID_FRAME_OR_ASSOCIATION","OVER_BYTES")
        var altered=hp;altered["image_sha256"]=String(repeating:"b",count:64)
        check(inspect([altered])["status"] as? String == "HOLD_INVALID_FRAME_OR_ASSOCIATION","UNBOUND_SHA")
        altered=hp;altered["owner"]="OWN"
        check(inspect([altered])["status"] as? String == "HOLD_INVALID_FRAME_OR_ASSOCIATION","FORGED_OWNER")
        altered=hp;altered["orientation_certified"]=true
        check(inspect([altered])["status"] as? String == "HOLD_INVALID_FRAME_OR_ASSOCIATION","FORGED_ANGLE")
        altered=hp;altered["game_turn"]=7
        check(inspect([altered])["status"] as? String == "HOLD_INVALID_FRAME_OR_ASSOCIATION","FORGED_TURN")
        altered=hp;altered["numeric_text_candidate"]=["numerator":400,"denominator":100]
        check(inspect([altered])["status"] as? String == "HOLD_INVALID_FRAME_OR_ASSOCIATION","HP_OVER_MAX")
        altered=opponent;altered["numeric_text_candidate"]=["percent":101]
        check(inspect([altered])["status"] as? String == "HOLD_INVALID_FRAME_OR_ASSOCIATION","PERCENT_OVER_MAX")
        altered=move;altered["region_hypothesis"]="BOTTOM_LEFT_HUD"
        check(inspect([altered])["status"] as? String == "HOLD_INVALID_FRAME_OR_ASSOCIATION","REGION_FORGED")
        altered=hp;altered["evidence_ref"]="fake.ref"
        check(inspect([altered])["status"] as? String == "HOLD_INVALID_FRAME_OR_ASSOCIATION","REF_FORGED")
        altered=hp;altered["source_bottom_left_roi"]=["x":1.2,"y":0.2,"width":0.1,"height":0.1]
        check(inspect([altered])["status"] as? String == "HOLD_INVALID_FRAME_OR_ASSOCIATION","ROI_FORGED")
        altered=hp;altered["frame_id"]=Int64(9)
        check(inspect([altered])["status"] as? String == "HOLD_INVALID_FRAME_OR_ASSOCIATION","ORPHAN_FRAME")
        var corrupted=hud([hp]);corrupted["owner_certified"]=true
        check(R587HUDFrameAssociation.make(hud:corrupted,snapshots:[snapshot()])["status"] as? String == "HOLD_INVALID_FRAME_OR_ASSOCIATION","ROOT_OWNER_FORGED")
        corrupted=hud([hp]);corrupted["matched_candidates"]=2
        check(R587HUDFrameAssociation.make(hud:corrupted,snapshots:[snapshot()])["status"] as? String == "HOLD_INVALID_FRAME_OR_ASSOCIATION","COUNT_FORGED")
        check(inspect([hp],[snapshot(),snapshot()])["status"] as? String == "HOLD_INVALID_FRAME_OR_ASSOCIATION","DUPLICATE_FRAME")
        check(inspect([hp],[snapshot(2,2000),snapshot()])["status"] as? String == "HOLD_INVALID_FRAME_OR_ASSOCIATION","REVERSED_FRAMES")
        check(inspect([],[snapshot(1,1000),snapshot(2,900)])["status"] as? String == "HOLD_INVALID_FRAME_OR_ASSOCIATION","TIME_REVERSED")
        check(inspect([],Array(repeating:snapshot(),count:9))["status"] as? String == "HOLD_INVALID_FRAME_OR_ASSOCIATION","FRAME_LIMIT")
        check(inspect([] ,[])["frame_count"] as? Int==0,"EMPTY")
        check(JSONSerialization.isValidJSONObject(inspect([],[])),"EMPTY_JSON")
        check(passed>=40,"MINIMUM_TESTS")
        print("R587_PASS_\(passed)_FRAME_HUD_ANCHOR_BINDING_FAIL_CLOSED")
    }
}
