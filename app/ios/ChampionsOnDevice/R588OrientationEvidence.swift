import Foundation
import CoreFoundation

/// R588: bounded orientation CONSENSUS HYPOTHESIS from independently typed
/// HUD anchors already bound to immutable historical PNG evidence by R587.
/// No player ownership, display rotation, Mega form or live state certification.
enum R588OrientationEvidence {
    static let schema = "trueplan.r588.historical-ocr-rotation-consensus.v1"
    private static let allowed:[Int64] = [0,90,180,270]
    private static let allowedKinds=Set(["HYPOTHESIS_OWN_HP_FRACTION",
                                        "HYPOTHESIS_OPPONENT_HP_PERCENT",
                                        "HYPOTHESIS_MOVE_PP_FRACTION"])
    private static func integer(_ any:Any?) -> Int64? {
        guard let n=any as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else {return nil}
        let i=n.int64Value
        return n.doubleValue.isFinite && Double(i)==n.doubleValue ? i : nil
    }
    private static func shaOK(_ s:String)->Bool {
        s.utf8.count==64 && s.utf8.allSatisfy{(48...57).contains($0)||(97...102).contains($0)}
    }
    private static func rectOK(_ a:Any?)->Bool {
        guard let r=a as? [String:Any],let x=r["x"] as? Double,let y=r["y"] as? Double,
              let w=r["width"] as? Double,let h=r["height"] as? Double,
              [x,y,w,h].allSatisfy({$0.isFinite}),x>=0,y>=0,w>0,h>0,
              x+w<=1.000001,y+h<=1.000001 else{return false}
        return true
    }
    private static func held(_ why:String)->[String:Any] {
        ["schema":schema,"status":"HOLD_INVALID_R587_EVIDENCE", "hold_reason":why,
         "frame_count":0,"frames":[[String:Any]](),"candidate_count":0,
         "orientation_certified":false,"owner_certified":false,
         "mega_form_visual_certified":false,"current_state_eligible":false,
         "battle_advice_authorized":false,"automatic_upload":false]
    }
    static func make(associations:[String:Any])->[String:Any] {
        guard associations["schema"] as? String == R587HUDFrameAssociation.schema,
              associations["status"] as? String == "HISTORICAL_FRAME_HUD_ASSOCIATIONS_ONLY",
              associations["owner_certified"] as? Bool == false,
              associations["orientation_certified"] as? Bool == false,
              associations["visual_mega_form_certified"] as? Bool == false,
              associations["current_state_eligible"] as? Bool == false,
              associations["battle_advice_authorized"] as? Bool == false,
              associations["automatic_upload"] as? Bool == false,
              let sourceFrames=associations["frames"] as? [[String:Any]],
              let frameCount=integer(associations["frame_count"]),frameCount==sourceFrames.count,
              sourceFrames.count<=8,
              let anchorCount=integer(associations["association_count"]),anchorCount>=0,anchorCount<=256
        else {return held("R587_ROOT_MISMATCH")}
        var results=[[String:Any]](),seen=Set<String>(),total=0
        for s in sourceFrames {
            guard let epoch=integer(s["epoch"]),epoch>0,
                  let frame=integer(s["frame_id"]),frame>0,
                  let time=integer(s["observed_ms_monotonic"]),time>0,
                  let hash=s["image_sha256"] as? String,shaOK(hash),
                  let path=s["file"] as? String,path=="frames/frame_\(epoch)_\(frame).png",
                  let geometry=s["pixel_geometry_hypothesis"] as? String,
                  ["SOURCE_PIXEL_LANDSCAPE","SOURCE_PIXEL_PORTRAIT","SOURCE_PIXEL_NEAR_SQUARE"].contains(geometry),
                  s["display_rotation_degrees"] is NSNull,
                  s["owner"] as? String == "UNKNOWN",
                  s["opponent"] as? String == "UNKNOWN",
                  s["mega_visual_form"] as? String == "UNKNOWN",
                  s["current_state_eligible"] as? Bool == false,
                  let rawAnchors=s["anchors"] as? [[String:Any]], rawAnchors.count<=256,
                  let count=integer(s["anchor_count"]),count==rawAnchors.count,
                  let conflict=s["numeric_conflict_detected"] as? Bool,
                  let level=s["layout_evidence_level"] as? String,
                  ["NO_HUD_ANCHORS","SINGLE_ANCHOR_LAYOUT_HYPOTHESIS",
                   "MULTI_ANCHOR_LAYOUT_HYPOTHESIS","AMBIGUOUS_NUMERIC_ANCHORS"].contains(level)
            else{return held("INVALID_FRAME_METADATA")}
            let key="\(epoch):\(frame)"
            guard seen.insert(key).inserted else{return held("DUPLICATE_FRAME")}
            var domainByAngle:[Int64:Set<String>]=[:]
            var dedupByAngle:[Int64:Set<String>]=[:]
            for a in rawAnchors {
                guard let rotation=integer(a["rotation_degrees"]),allowed.contains(rotation),
                      let kind=a["hypothesis"] as? String,allowedKinds.contains(kind),
                      let ref=a["evidence_ref"] as? String,ref.hasPrefix("rotation_\(rotation).observations["),
                      let value=a["value"] as? String,!value.isEmpty,value.utf8.count<=16,
                      rectOK(a["roi"]) else{return held("INVALID_ROTATION_ANCHOR")}
                domainByAngle[rotation,default:[]].insert(kind)
                dedupByAngle[rotation,default:[]].insert(kind+":"+value)
            }
            total+=rawAnchors.count
            var angleEvidence=[[String:Any]](),qualifying=[Int64]()
            for a in allowed {
                let types=domainByAngle[a] ?? []
                let names=types.sorted()
                let diverse=types.count>=2
                if diverse {qualifying.append(a)}
                angleEvidence.append(["ocr_rotation_degrees":a,
                                      "distinct_hud_domains":types.count,
                                      "independent_text_values":dedupByAngle[a]?.count ?? 0,
                                      "hud_domain_hypotheses":names,
                                      "two_domain_requirement_met":diverse])
            }
            let status:String
            let candidate:Any
            if conflict {status="HOLD_NUMERIC_HUD_CONFLICT";candidate=NSNull()}
            else if qualifying.count>1 {status="HOLD_MULTIPLE_ORIENTATION_CANDIDATES";candidate=NSNull()}
            else if let unique=qualifying.first {status="SINGLE_OCR_ROTATION_HYPOTHESIS_ONLY";candidate=unique}
            else {status="INSUFFICIENT_INDEPENDENT_HUD_DOMAINS";candidate=NSNull()}
            results.append(["epoch":epoch,"frame_id":frame,"observed_ms_monotonic":time,
                            "image_sha256":hash,"file":path,
                            "source_pixel_geometry":geometry,
                            "status":status,"ocr_rotation_hypothesis_degrees":candidate,
                            "source_display_rotation_degrees":NSNull(),
                            "orientation_evidence":angleEvidence,
                            "qualifying_rotation_count":qualifying.count,
                            "anchor_count":rawAnchors.count,"owner":"UNKNOWN",
                            "opponent":"UNKNOWN","pokemon_identity":"UNKNOWN",
                            "mega_visual_form":"UNKNOWN","game_turn":NSNull(),
                            "orientation_certified":false,"owner_certified":false,
                            "current_state_eligible":false])
        }
        guard total==anchorCount else{return held("ROOT_ANCHOR_COUNT_MISMATCH")}
        return ["schema":schema,"status":"HISTORICAL_OCR_ROTATION_HYPOTHESES_ONLY",
                "hold_reason":NSNull(),"frame_count":results.count,"frames":results,
                "candidate_count":results.filter{$0["status"] as? String == "SINGLE_OCR_ROTATION_HYPOTHESIS_ONLY"}.count,
                "orientation_certified":false,"owner_certified":false,
                "mega_form_visual_certified":false,"current_state_eligible":false,
                "actual_game_accuracy_certified":false,"battle_advice_authorized":false,
                "automatic_upload":false]
    }
}
