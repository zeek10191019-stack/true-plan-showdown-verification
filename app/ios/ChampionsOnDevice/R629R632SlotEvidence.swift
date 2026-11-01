import Foundation

// R629-R632: derive *unverified* UI-slot hypotheses from authentic pixel/OCR
// evidence within the same archived frame. No battle-state promotion is allowed.
// This is intentionally observational and does not classify any Pokemon identity.
enum R629R632SlotEvidence {
    static let key = "r629_r632_hud_slot_tracking"
    static let schema = "trueplan.r629-r632.hud-slot-hypotheses.v1"
    private static let certifiedFlags = ["certified_for_battle", "owner_verified",
                                         "roi_verified", "mega_verified",
                                         "display_orientation_verified"]
    private static func rect(_ value:Any?) -> (Double,Double,Double,Double)? {
        guard let r=value as? [String:Any],
              let x=r["x"] as? Double, let y=r["y"] as? Double,
              let w=r["width"] as? Double,let h=r["height"] as? Double,
              [x,y,w,h].allSatisfy({$0.isFinite}),x>=0,y>=0,w>0,h>0,
              x+w<=1.000001,y+h<=1.000001 else {return nil}
        return (x,y,w,h)
    }
    private static func candidateKind(_ value:String)->String? {
        switch value {
        case "FRACTION_HP_OR_PP_UNASSIGNED":return "FRACTION_CANDIDATE_ROLE_UNPROVEN"
        case "PERCENT_HP_OR_OTHER_UNASSIGNED":return "PERCENT_CANDIDATE_ROLE_UNPROVEN"
        default:return nil
        }
    }
    private static func allFalse(_ record:[String:Any]) ->Bool {
        certifiedFlags.allSatisfy{record[$0] as? Bool == false}
    }
    static func analyze(_ parent:[String:Any])->[String:Any] {
        let defaults:[String:Any] = [
            "schema":schema,"status":"HOLD_UNVERIFIED_INPUT",
            "image_frame_count":0,"slots":[[String:Any]](),
            "temporal_pixel_tracks":[[String:Any]](),
            "recognized_own_hp":NSNull(),"recognized_opponent_hp":NSNull(),
            "recognized_mega":NSNull(),"certified_for_battle":false,
            "owner_verified":false,"roi_verified":false,"mega_verified":false,
            "display_orientation_verified":false]
        guard parent["schema"] as? String == "trueplan.r617-r620.rotation_readout.v1",
              allFalse(parent),
              let prior=parent["r625_r628_embedded_pixel_probe_report"] as? [String:Any],
              prior["schema"] as? String == "trueplan.r625-r628.pixel_hud_sprite_probes.v1",
              prior["status"] as? String == "HOLD_PIXEL_LOCATIONS_NOT_GROUND_TRUTH",
              allFalse(prior),
              let rows=prior["frames"] as? [[String:Any]], rows.count<=2,
              let older=parent["r621_r624_embedded_candidate_report"] as? [String:Any],
              older["schema"] as? String == "trueplan.r621-r624.visual_candidate_slots.v1",
              allFalse(older),
              let linked=older["r622_ui_slot_hypotheses"] as? [[String:Any]] else {
            return defaults
        }
        var slots=[[String:Any]](), unique=Set<String>()
        for row in rows {
            guard let ep=row["epoch"] as? Int64,ep>0,
                  let fid=row["frame_id"] as? Int64,fid>0,
                  let hash=row["original_png_sha256"] as? String,hash.count==64,
                  let pixel=row["pixel_probe"] as? [String:Any],
                  pixel["status"] as? String == "HOLD_PIXELS_DECODED_NOT_CALIBRATED",
                  let runs=pixel["colored_runs"] as? [[String:Any]],runs.count<=20,
                  let source=linked.first(where:{($0["epoch"] as? Int64)==ep &&
                                               ($0["frame_id"] as? Int64)==fid &&
                                               ($0["original_png_sha256"] as? String)==hash}),
                  let words=source["observations"] as? [[String:Any]],words.count<=48,
                  unique.insert("\(ep):\(fid)").inserted else {return defaults}
            for (i,word) in words.enumerated() {
                guard let label=word["kind"] as? String,
                      let kind=candidateKind(label),
                      word["orientation_hypothesis"] as? String == "UP",
                      let text=rect(word["normalized_rect_in_hypothesis"]) else {continue}
                // Vision OCR coordinates are bottom-origin in the UP hypothesis.
                let top=1-text.1-text.3
                var linkedBars=[Int]()
                for (j,bar) in runs.enumerated() {
                    guard let box=rect(bar["rect_top_left_norm"]),
                          bar["confirmed_hud"] as? Bool == false,
                          bar["owner"] as? String == "UNKNOWN" else {continue}
                    let xOverlap=max(0,min(text.0+text.2,box.0+box.2)-max(text.0,box.0))
                    let vDistance=abs((top+text.3/2)-(box.1+box.3/2))
                    if xOverlap >= 0.1*min(text.2,box.2) && vDistance<=0.135 {
                        linkedBars.append(j)
                    }
                }
                if linkedBars.count==1 {
                    slots.append(["epoch":ep,"frame_id":fid,
                        "original_png_sha256":hash,"observation_index":i,
                        "pixel_run_index":linkedBars[0],"slot_kind":kind,
                        "screen_half_hypothesis":top+text.3/2 < 0.5 ? "TOP" : "BOTTOM",
                        "role_hint":label == "FRACTION_HP_OR_PP_UNASSIGNED" ?
                            "POSSIBLY_OWN_OR_PP" : "POSSIBLY_OPPONENT_OR_OTHER",
                        "orientation_hypothesis":"UP_ONLY_UNVERIFIED",
                        "actor":"UNKNOWN","hp_value":NSNull(),
                        "mega_form":"UNKNOWN","certified":false])
                }
                if slots.count>=32 {break}
            }
        }
        // Correlate positions of a candidate bar across at most two timepoints.
        var tracks=[[String:Any]]()
        if rows.count==2,let x=rows[0]["pixel_probe"] as? [String:Any],
           let y=rows[1]["pixel_probe"] as? [String:Any],
           let a=x["colored_runs"] as? [[String:Any]],
           let b=y["colored_runs"] as? [[String:Any]] {
            for (i,p) in a.enumerated() {
                guard let r=rect(p["rect_top_left_norm"]),
                      let color=p["color_class"] as? String else {continue}
                let matching=b.enumerated().filter{_,q in
                    guard let s=rect(q["rect_top_left_norm"]),
                          q["color_class"] as? String == color else{return false}
                    return abs((r.0+r.2/2)-(s.0+s.2/2))<=0.025 &&
                           abs((r.1+r.3/2)-(s.1+s.3/2))<=0.025
                }
                if matching.count==1,let m=matching.first {
                    tracks.append(["first_run_index":i,"second_run_index":m.offset,
                        "color_class":color,"same_visual_slot_hypothesis":true,
                        "pokemon_identity":"UNKNOWN","owner":"UNKNOWN",
                        "hp_change_certified":false])
                }
                if tracks.count>=12 {break}
            }
        }
        var report=defaults
        report["status"] = slots.isEmpty ? "HOLD_NO_UNAMBIGUOUS_SPATIAL_SLOT" :
                          "HOLD_SLOTS_LOCATED_BUT_OWNER_HP_MEGA_UNVERIFIED"
        report["image_frame_count"]=rows.count
        report["slots"]=slots
        report["temporal_pixel_tracks"]=tracks
        return report
    }
    // Exactly one existing JSON changes. No extra ZIP member or network call.
    static func enrich(_ parent:inout[String:Any]) {
        guard parent[key]==nil else{return}
        parent[key]=analyze(parent)
    }
}
