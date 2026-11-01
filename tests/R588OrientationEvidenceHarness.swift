import Foundation
@main struct R588OrientationEvidenceHarness {
    static var tests=0
    static func expect(_ yes:Bool,_ why:String){guard yes else{fatalError("R588_"+why)};tests+=1}
    static let hash=String(repeating:"a",count:64)
    static func anchor(_ kind:String,_ rotation:Int64=0,_ value:String="180/192")->[String:Any] {
        ["hypothesis":kind,"value":value,"rotation_degrees":rotation,
         "evidence_ref":"rotation_\(rotation).observations[0]",
         "roi":["x":0.1,"y":0.1,"width":0.05,"height":0.04]]
    }
    static let own="HYPOTHESIS_OWN_HP_FRACTION"
    static let opp="HYPOTHESIS_OPPONENT_HP_PERCENT"
    static let pp="HYPOTHESIS_MOVE_PP_FRACTION"
    static func source(_ anchors:[[String:Any]],_ conflict:Bool=false)->[String:Any] {
        let frame:[String:Any]=[
            "epoch":Int64(1),"frame_id":Int64(1),"observed_ms_monotonic":Int64(1000),
            "image_sha256":hash,"file":"frames/frame_1_1.png",
            "pixel_geometry_hypothesis":"SOURCE_PIXEL_LANDSCAPE",
            "display_rotation_degrees":NSNull(),"owner":"UNKNOWN","opponent":"UNKNOWN",
            "mega_visual_form":"UNKNOWN","current_state_eligible":false,
            "anchor_count":anchors.count,"anchors":anchors,"numeric_conflict_detected":conflict,
            "layout_evidence_level":conflict ? "AMBIGUOUS_NUMERIC_ANCHORS" : "MULTI_ANCHOR_LAYOUT_HYPOTHESIS"]
        return ["schema":R587HUDFrameAssociation.schema,
            "status":"HISTORICAL_FRAME_HUD_ASSOCIATIONS_ONLY",
            "owner_certified":false,"orientation_certified":false,
            "visual_mega_form_certified":false,"current_state_eligible":false,
            "battle_advice_authorized":false,"automatic_upload":false,
            "frame_count":1,"frames":[frame],"association_count":anchors.count]
    }
    static func one(_ r:[String:Any])->[String:Any] {(r["frames"] as! [[String:Any]])[0]}
    static func main(){
        let hp=anchor(own),enemy=anchor(opp,0,"55%"),move=anchor(pp,0,"16/16")
        let r=R588OrientationEvidence.make(associations:source([hp,enemy,move]))
        expect(r["status"] as? String == "HISTORICAL_OCR_ROTATION_HYPOTHESES_ONLY","VALID")
        expect(r["frame_count"] as? Int==1,"ONE_FRAME")
        expect(r["candidate_count"] as? Int==1,"ONE_CANDIDATE")
        expect(one(r)["status"] as? String == "SINGLE_OCR_ROTATION_HYPOTHESIS_ONLY","SINGLE")
        expect((one(r)["ocr_rotation_hypothesis_degrees"] as? Int64)==0,"ROTATION_ZERO")
        expect(one(r)["source_display_rotation_degrees"] is NSNull,"DISPLAY_UNCERTIFIED")
        expect(r["orientation_certified"] as? Bool == false,"NOT_CERT")
        expect(r["owner_certified"] as? Bool == false,"NO_OWNER")
        expect(r["mega_form_visual_certified"] as? Bool == false,"NO_MEGA")
        expect(r["current_state_eligible"] as? Bool == false,"NOT_LIVE")
        expect(r["automatic_upload"] as? Bool == false,"NO_UPLOAD")
        expect(r["battle_advice_authorized"] as? Bool == false,"NO_ADVICE")
        expect(JSONSerialization.isValidJSONObject(r),"VALID_JSON")
        let no=R588OrientationEvidence.make(associations:source([]))
        expect(one(no)["status"] as? String=="INSUFFICIENT_INDEPENDENT_HUD_DOMAINS","EMPTY")
        let oneDomain=R588OrientationEvidence.make(associations:source([hp,hp]))
        expect(one(oneDomain)["ocr_rotation_hypothesis_degrees"] is NSNull,"DUPLICATE_NOT_INDEPENDENT")
        let withPP=R588OrientationEvidence.make(associations:source([hp,move]))
        expect(one(withPP)["status"] as? String == "SINGLE_OCR_ROTATION_HYPOTHESIS_ONLY","PP_SECOND_DOMAIN")
        let angled=R588OrientationEvidence.make(associations:source([anchor(own,90),anchor(opp,90,"75%")] ))
        expect((one(angled)["ocr_rotation_hypothesis_degrees"] as? Int64)==90,"ANGLE_NINETY")
        let ambiguous=R588OrientationEvidence.make(associations:source([hp,enemy,anchor(own,180),anchor(opp,180,"55%")] ))
        expect(one(ambiguous)["status"] as? String=="HOLD_MULTIPLE_ORIENTATION_CANDIDATES","MULTIPLE_CANDIDATES")
        expect(one(ambiguous)["ocr_rotation_hypothesis_degrees"] is NSNull,"MULTIPLE_HELD")
        let conflict=R588OrientationEvidence.make(associations:source([hp,enemy],true))
        expect(one(conflict)["status"] as? String=="HOLD_NUMERIC_HUD_CONFLICT","CONFLICT")
        expect(one(conflict)["ocr_rotation_hypothesis_degrees"] is NSNull,"CONFLICT_HELD")
        var bad=source([hp]);bad["owner_certified"]=true
        expect(R588OrientationEvidence.make(associations:bad)["status"] as? String=="HOLD_INVALID_R587_EVIDENCE","BAD_ROOT_OWNER")
        bad=source([hp]);bad["status"]="CERTIFIED"
        expect(R588OrientationEvidence.make(associations:bad)["status"] as? String=="HOLD_INVALID_R587_EVIDENCE","BAD_ROOT_STATUS")
        bad=source([hp]);bad["association_count"]=2
        expect(R588OrientationEvidence.make(associations:bad)["status"] as? String=="HOLD_INVALID_R587_EVIDENCE","BAD_COUNTS")
        bad=source([hp]);bad["frame_count"]=9
        expect(R588OrientationEvidence.make(associations:bad)["status"] as? String=="HOLD_INVALID_R587_EVIDENCE","BAD_FRAME_COUNT")
        bad=source([hp]);var frames=bad["frames"] as! [[String:Any]];frames[0]["owner"]="OWN";bad["frames"]=frames
        expect(R588OrientationEvidence.make(associations:bad)["status"] as? String=="HOLD_INVALID_R587_EVIDENCE","FORGED_FRAME_OWNER")
        bad=source([hp]);frames=bad["frames"] as! [[String:Any]];frames[0]["image_sha256"]="bad";bad["frames"]=frames
        expect(R588OrientationEvidence.make(associations:bad)["status"] as? String=="HOLD_INVALID_R587_EVIDENCE","BAD_SHA")
        bad=source([hp]);frames=bad["frames"] as! [[String:Any]];frames[0]["file"]="frames/../../wrong.png";bad["frames"]=frames
        expect(R588OrientationEvidence.make(associations:bad)["status"] as? String=="HOLD_INVALID_R587_EVIDENCE","BAD_PATH")
        bad=source([hp]);frames=bad["frames"] as! [[String:Any]];var anchors=frames[0]["anchors"] as! [[String:Any]];anchors[0]["rotation_degrees"]=45;frames[0]["anchors"]=anchors;bad["frames"]=frames
        expect(R588OrientationEvidence.make(associations:bad)["status"] as? String=="HOLD_INVALID_R587_EVIDENCE","BAD_ANGLE")
        bad=source([hp]);frames=bad["frames"] as! [[String:Any]];anchors=frames[0]["anchors"] as! [[String:Any]];anchors[0]["evidence_ref"]="fake";frames[0]["anchors"]=anchors;bad["frames"]=frames
        expect(R588OrientationEvidence.make(associations:bad)["status"] as? String=="HOLD_INVALID_R587_EVIDENCE","BAD_REF")
        bad=source([hp]);frames=bad["frames"] as! [[String:Any]];anchors=frames[0]["anchors"] as! [[String:Any]];anchors[0]["roi"]=["x":1.3,"y":0.0,"width":0.1,"height":0.1];frames[0]["anchors"]=anchors;bad["frames"]=frames
        expect(R588OrientationEvidence.make(associations:bad)["status"] as? String=="HOLD_INVALID_R587_EVIDENCE","BAD_ROI")
        bad=source([hp]);frames=bad["frames"] as! [[String:Any]];frames[0]["display_rotation_degrees"]=90;bad["frames"]=frames
        expect(R588OrientationEvidence.make(associations:bad)["status"] as? String=="HOLD_INVALID_R587_EVIDENCE","FALSE_DISPLAY_ANGLE")
        bad=source([hp]);frames=bad["frames"] as! [[String:Any]];frames[0]["current_state_eligible"]=true;bad["frames"]=frames
        expect(R588OrientationEvidence.make(associations:bad)["status"] as? String=="HOLD_INVALID_R587_EVIDENCE","FALSE_LIVE")
        expect(R588OrientationEvidence.make(associations:source([]))["frame_count"] as? Int==1,"EMPTY_FRAME_PRESERVED")
        expect(tests>=30,"MIN_TESTS")
        print("R588_PASS_\(tests)_ORIENTATION_CONSENSUS_WITHOUT_OWNER_OR_DISPLAY_CERTIFICATION")
    }
}
