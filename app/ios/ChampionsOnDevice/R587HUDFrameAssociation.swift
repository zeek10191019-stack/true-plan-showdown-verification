import Foundation
import CoreFoundation

/// R587: binds numeric OCR-layout hypotheses to the exact retained PNGs.
/// Inference remains historical-only. NO confirmed battle side, turn, or Mega form.
enum R587HUDFrameAssociation {
    static let schema = "trueplan.r587.frame-hud-association.v1"
    private static let maxFrames = 8
    private static let maxAnchors = 256
    private static let kinds = Set(["HYPOTHESIS_OWN_HP_FRACTION", "HYPOTHESIS_MOVE_PP_FRACTION", "HYPOTHESIS_OPPONENT_HP_PERCENT"])

    private static func number(_ raw: Any?) -> Int64? {
        guard let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let value = n.int64Value
        return n.doubleValue.isFinite && Double(value) == n.doubleValue ? value : nil
    }
    private static func shaOK(_ s: String) -> Bool {
        s.utf8.count == 64 && s.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func rectOK(_ raw: Any?) -> Bool {
        guard let r=raw as? [String:Any],let x=r["x"] as? Double,let y=r["y"] as? Double,
              let w=r["width"] as? Double,let h=r["height"] as? Double,
              [x,y,w,h].allSatisfy({$0.isFinite}),x>=0,y>=0,w>0,h>0,
              x+w<=1.000001,y+h<=1.000001 else { return false }
        return true
    }
    private static func held(_ reason: String)->[String:Any] {
        ["schema":schema,"status":"HOLD_INVALID_FRAME_OR_ASSOCIATION", "hold_reason":reason,
         "frame_count":0,"frames":[[String:Any]](),"association_count":0,
         "owner_certified":false,"orientation_certified":false,"battle_advice_authorized":false,
         "visual_mega_form_certified":false,"current_state_eligible":false,"automatic_upload":false]
    }
    private static func parseNumerics(_ h:[String:Any],kind:String)->String? {
        guard let v=h["numeric_text_candidate"] as? [String:Any] else{return nil}
        if kind=="HYPOTHESIS_OPPONENT_HP_PERCENT" {
            guard v.count==1,let q=number(v["percent"]),q>=0,q<=100 else{return nil}
            return String(q)+"%"
        }
        guard v.count==2,let n=number(v["numerator"]),let d=number(v["denominator"]),
              n>=0,d>0,n<=d,d<=9999 else {return nil}
        return String(n)+"/"+String(d)
    }
    static func make(hud:[String:Any], snapshots:[[String:Any]])->[String:Any] {
        guard hud["schema"] as? String == R586HUDSpatialCandidates.schema,
              hud["status"] as? String == "HISTORICAL_LAYOUT_HYPOTHESES_ONLY",
              hud["owner_certified"] as? Bool == false,
              hud["source_orientation_certified"] as? Bool == false,
              hud["current_state_eligible"] as? Bool == false,
              hud["battle_advice_authorized"] as? Bool == false,
              hud["automatic_upload"] as? Bool == false,
              let anchors=hud["hypotheses"] as? [[String:Any]],
              let count=number(hud["matched_candidates"]),count==anchors.count,
              anchors.count<=maxAnchors,snapshots.count<=maxFrames
        else {return held("BAD_OR_INCOMPLETE_R586_HUD_SOURCE")}
        var orderedKeys=[String](), verified=[String:[String:Any]](), lastEpoch:Int64?,lastFrame:Int64?,lastTime:Int64?
        for s in snapshots {
            guard let epoch=number(s["epoch"]), epoch>0,let frame=number(s["frame_id"]),frame>0,
                  let time=number(s["observed_ms_monotonic"]),time>0,
                  let hash=s["png_sha256"] as? String,shaOK(hash),
                  let filename=s["file"] as? String,filename=="frames/frame_\(epoch)_\(frame).png",
                  let w=number(s["width"]),let h=number(s["height"]),
                  (128...8192).contains(w),(128...8192).contains(h),
                  let bytes=number(s["png_bytes"]),bytes>0,bytes<=20_000_000,
                  s["own_opponent_certified"] as? Bool == false,
                  s["mega_form_visual_certified"] as? Bool == false else {
                return held("INVALID_RETAINED_PNG_PROVENANCE")
            }
            if let e=lastEpoch,let f=lastFrame,let t=lastTime,
               (epoch != e || frame<=f || time<t) {return held("SNAPSHOT_SEQUENCE_OR_EPOCH_CONFLICT")}
            lastEpoch=epoch;lastFrame=frame;lastTime=time
            let key="\(epoch):\(frame)"
            guard verified[key]==nil else{return held("DUPLICATE_FRAME_KEY")}
            verified[key]=["epoch":epoch,"frame_id":frame,"observed_ms_monotonic":time,
                           "image_sha256":hash,"width":w,"height":h,"file":filename]
            orderedKeys.append(key)
        }
        var grouped=[String:[[String:Any]]]()
        for a in anchors {
            guard a["status"] as? String == "UNVERIFIED_TEXT_AND_HUD_LAYOUT_MATCH",
                  a["orientation_certified"] as? Bool == false,
                  a["current_state_eligible"] as? Bool == false,
                  a["owner"] as? String == "UNKNOWN",
                  a["pokemon_identity"] as? String == "UNKNOWN",
                  a["game_turn"] is NSNull,
                  let epoch=number(a["epoch"]),let frame=number(a["frame_id"]),
                  let time=number(a["observed_ms_monotonic"]),
                  let hash=a["image_sha256"] as? String,
                  let reference=a["evidence_ref"] as? String,!reference.isEmpty,reference.utf8.count<=128,
                  let angle=number(a["rotation_degrees"]),[0,90,180,270].contains(angle),
                  reference.hasPrefix("rotation_\(angle).observations["),
                  let kind=a["hypothesis"] as? String,kinds.contains(kind),
                  let region=a["region_hypothesis"] as? String,
                  region == (kind=="HYPOTHESIS_OWN_HP_FRACTION" ? "BOTTOM_LEFT_HUD" : kind=="HYPOTHESIS_MOVE_PP_FRACTION" ? "RIGHT_MOVE_MENU" : "TOP_RIGHT_HUD"),
                  rectOK(a["source_bottom_left_roi"]),
                  let value=parseNumerics(a,kind:kind),
                  let s=verified["\(epoch):\(frame)"],
                  s["observed_ms_monotonic"] as? Int64 == time,
                  s["image_sha256"] as? String == hash else {
                return held("UNBOUND_OR_FORGED_ANCHOR")
            }
            var row=a
            row["normalized_value"] = value
            grouped["\(epoch):\(frame)",default:[]].append(row)
        }
        var results=[[String:Any]]()
        for key in orderedKeys {
            guard let s=verified[key],let w=s["width"] as? Int64,let h=s["height"] as? Int64 else {
                return held("MISSING_FRAME")
            }
            let anchors=grouped[key] ?? []
            let hp=Set(anchors.filter{$0["hypothesis"] as? String=="HYPOTHESIS_OWN_HP_FRACTION"}.compactMap{$0["normalized_value"] as? String})
            let opponent=Set(anchors.filter{$0["hypothesis"] as? String=="HYPOTHESIS_OPPONENT_HP_PERCENT"}.compactMap{$0["normalized_value"] as? String})
            let pp=Set(anchors.filter{$0["hypothesis"] as? String=="HYPOTHESIS_MOVE_PP_FRACTION"}.compactMap{$0["normalized_value"] as? String})
            let ambiguous=hp.count>1 || opponent.count>1 || pp.count>4
            let distinctKinds=(hp.isEmpty ? 0 : 1) + (opponent.isEmpty ? 0 : 1) + (pp.isEmpty ? 0 : 1)
            let geometry=w*10>=h*13 ? "SOURCE_PIXEL_LANDSCAPE" : h*10>=w*13 ? "SOURCE_PIXEL_PORTRAIT" : "SOURCE_PIXEL_NEAR_SQUARE"
            let level=ambiguous ? "AMBIGUOUS_NUMERIC_ANCHORS" : distinctKinds>=2 ? "MULTI_ANCHOR_LAYOUT_HYPOTHESIS" : distinctKinds==1 ? "SINGLE_ANCHOR_LAYOUT_HYPOTHESIS" : "NO_HUD_ANCHORS"
            let anchorsOut=anchors.map { a -> [String:Any] in
                ["hypothesis":a["hypothesis"]!,"value":a["normalized_value"]!,
                 "evidence_ref":a["evidence_ref"]!,"rotation_degrees":a["rotation_degrees"]!,
                 "roi":a["source_bottom_left_roi"]!]
            }
            results.append(["epoch":s["epoch"]!,"frame_id":s["frame_id"]!,
                            "observed_ms_monotonic":s["observed_ms_monotonic"]!,
                            "image_sha256":s["image_sha256"]!,"file":s["file"]!,
                            "source_pixel_width":w,"source_pixel_height":h,
                            "pixel_geometry_hypothesis":geometry,
                            "layout_evidence_level":level,
                            "unique_numeric_domains":distinctKinds,
                            "anchor_count":anchors.count,
                            "numeric_conflict_detected":ambiguous,"anchors":anchorsOut,
                            "display_rotation_degrees":NSNull(),"owner":"UNKNOWN",
                            "opponent":"UNKNOWN","pokemon_identity":"UNKNOWN",
                            "mega_visual_form":"UNKNOWN","turn":NSNull(),
                            "current_state_eligible":false])
        }
        return ["schema":schema,"status":"HISTORICAL_FRAME_HUD_ASSOCIATIONS_ONLY",
                "hold_reason":NSNull(),"frame_count":results.count,"frames":results,
                "association_count":anchors.count,"owner_certified":false,
                "orientation_certified":false,"battle_advice_authorized":false,
                "visual_mega_form_certified":false,"current_state_eligible":false,
                "actual_game_accuracy_certified":false,"automatic_upload":false]
    }
}
