import Foundation

/// R586: strict text+geometry intersection for the landscape battle HUD.
/// A role label is ONLY a layout hypothesis, never authenticated owner/HP/PP.
/// No Vision request is added; this consumes R585's historical OCR geometry.
enum R586HUDSpatialCandidates {
    static let schema = "trueplan.r586.historical-hud-text-region-hypotheses.v1"
    static let maxCandidates = 256
    private static let rotations: Set<Int> = [0,90,180,270]

    private static func validSHA(_ value:String)->Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
    private static func rect(_ raw:Any?) -> (Double,Double,Double,Double)? {
        guard let value=raw as? [String:Any],
              let x=value["x"] as? Double,let y=value["y"] as? Double,
              let w=value["width"] as? Double,let h=value["height"] as? Double,
              [x,y,w,h].allSatisfy({$0.isFinite}),
              x>=0,y>=0,w>0,h>0,x+w<=1.000001,y+h<=1.000001 else{return nil}
        return (x,y,w,h)
    }
    private static func whollyInside(_ r:(Double,Double,Double,Double),
                _ region:(Double,Double,Double,Double))->Bool {
        let (x,y,w,h)=r, (left,bottom,right,top)=region
        return x>=left && y>=bottom && x+w<=right && y+h<=top
    }
    private static func asciiNumber(_ text:Substring)->Int? {
        guard !text.isEmpty,text.count<=4,
              text.utf8.allSatisfy({(48...57).contains($0)}) else{return nil}
        return Int(text)
    }
    private static func fraction(_ text:String)->(Int,Int)? {
        let components=text.split(separator:"/",omittingEmptySubsequences:false)
        guard components.count==2,let a=asciiNumber(components[0]),
              let b=asciiNumber(components[1]),b>0,b<=9999,a<=b else{return nil}
        return (a,b)
    }
    private static func percent(_ text:String)->Int? {
        guard text.hasSuffix("%"),let n=asciiNumber(text.dropLast()),n<=100 else{return nil}
        return n
    }
    private static func fields(_ text:String,_ r:(Double,Double,Double,Double))
        -> (String,String,[String:Any])? {
        let value=text.trimmingCharacters(in:.whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .folding(options:[.widthInsensitive],locale:Locale(identifier:"ja_JP"))
        if let (n,d)=fraction(value) {
            // Strict containment in empirically observed LANDSCAPE-HUD regions.
            // Does not mean the captured image orientation or player side is proven.
            if whollyInside(r,(0.04,0.0,0.50,0.30)) {
                return ("HYPOTHESIS_OWN_HP_FRACTION","BOTTOM_LEFT_HUD",
                        ["numerator":n,"denominator":d])
            }
            if whollyInside(r,(0.69,0.12,1.00,0.72)) {
                return ("HYPOTHESIS_MOVE_PP_FRACTION","RIGHT_MOVE_MENU",
                        ["numerator":n,"denominator":d])
            }
            return nil
        }
        if let n=percent(value),whollyInside(r,(0.68,0.72,1.00,1.00)) {
            return ("HYPOTHESIS_OPPONENT_HP_PERCENT","TOP_RIGHT_HUD",["percent":n])
        }
        return nil
    }
    static func make(spatial:[String:Any])->[String:Any] {
        var reason:String?=nil
        let rows=spatial["candidates"] as? [[String:Any]] ?? []
        guard spatial["schema"] as? String == R585SpatialOCRProjection.schema,
              spatial["status"] as? String == "HISTORICAL_GEOMETRY_CANDIDATES_ONLY",
              spatial["source_coordinate_space"] as? String == "VISION_ORIENTED_NORMALIZED_BOTTOM_LEFT",
              spatial["projected_coordinate_space"] as? String == "NOMINAL_SOURCE_NORMALIZED_BOTTOM_LEFT_UNVERIFIED",
              spatial["display_orientation_certified"] as? Bool == false,
              spatial["roi_owner_certified"] as? Bool == false,
              spatial["visual_mega_form_certified"] as? Bool == false,
              spatial["game_turn_certified"] as? Bool == false,
              spatial["current_state_eligible"] as? Bool == false,
              spatial["battle_advice_authorized"] as? Bool == false,
              spatial["automatic_upload"] as? Bool == false,
              spatial["truncated_by_limit"] as? Bool == false,
              let count=spatial["candidate_count"] as? Int,count==rows.count,
              count<=maxCandidates,
              let frames=spatial["frames_examined"] as? Int,(0...8).contains(frames)
        else {return held("INVALID_R585_SOURCE_OR_INCOMPLETE_DATA")}
        var derived=[[String:Any]](),checked=0,unmatched=0
        var lastEpoch:Int64?=nil,lastFrame:Int64?=nil,lastTime:Int64?=nil
        for row in rows {
            guard row["status"] as? String == "UNVERIFIED_ORIENTATION_SPATIAL_OCR_CANDIDATE",
                  row["display_orientation_certified"] as? Bool == false,
                  row["current_state_eligible"] as? Bool == false,
                  row["owner"] as? String == "UNKNOWN",
                  row["pokemon_identity"] as? String == "UNKNOWN",
                  row["turn"] is NSNull,
                  let hash=row["image_sha256"] as? String,validSHA(hash),
                  let frame=row["frame_id"] as? Int64,frame>0,
                  let epoch=row["epoch"] as? Int64,epoch>0,
                  let time=row["observed_ms_monotonic"] as? Int64,time>0,
                  let text=row["text"] as? String,!text.isEmpty,text.utf8.count<=256,
                  let angle=row["rotation_degrees"] as? Int,rotations.contains(angle),
                  let ref=row["evidence_ref"] as? String,!ref.isEmpty,ref.utf8.count<=128,
                  ref.hasPrefix("rotation_\(angle).observations["),
                  let original=rect(row["vision_oriented_bottom_left_roi"]),
                  let source=rect(row["nominal_source_bottom_left_roi"]),
                  let expected=R585SpatialOCRProjection.projected(
                     row["vision_oriented_bottom_left_roi"] as! [String:Any],angle:angle),
                  let ex=expected["x"],let ey=expected["y"],
                  let ew=expected["width"],let eh=expected["height"],
                  abs(source.0-ex)<0.000001,abs(source.1-ey)<0.000001,
                  abs(source.2-ew)<0.000001,abs(source.3-eh)<0.000001,
                  original.2>0
            else {reason="MALFORMED_OR_INCONSISTENT_SPATIAL_EVIDENCE";break}
            if let p=lastFrame,let e=lastEpoch,let t=lastTime {
                if epoch != e || frame<p || time<t || (frame==p && time != t) ||
                        (frame>p && time<t) {
                    reason="NONMONOTONIC_OR_MIXED_FRAME_PROVENANCE";break
                }
            }
            lastEpoch=epoch;lastFrame=frame;lastTime=time
            checked+=1
            guard let (kind,region,parsed)=fields(text,source) else {unmatched+=1;continue}
            derived.append([
                "hypothesis":kind,"region_hypothesis":region,
                "numeric_text_candidate":parsed,
                "text":text,"frame_id":frame,"epoch":epoch,
                "observed_ms_monotonic":time,"image_sha256":hash,
                "evidence_ref":ref,"rotation_degrees":angle,
                "source_bottom_left_roi":row["nominal_source_bottom_left_roi"]!,
                "status":"UNVERIFIED_TEXT_AND_HUD_LAYOUT_MATCH",
                "orientation_certified":false,"owner":"UNKNOWN",
                "pokemon_identity":"UNKNOWN","game_turn":NSNull(),
                "current_state_eligible":false
            ])
        }
        if let reason {return held(reason)}
        return ["schema":schema,"status":"HISTORICAL_LAYOUT_HYPOTHESES_ONLY",
                "hold_reason":NSNull(),"source_schema":R585SpatialOCRProjection.schema,
                "source_candidate_count":count,"checked_candidates":checked,
                "unmatched_candidates":unmatched,"matched_candidates":derived.count,
                "hypotheses":derived,"profile":"OBSERVED_LANDSCAPE_BATTLE_HUD_UNCALIBRATED",
                "source_orientation_certified":false,"owner_certified":false,
                "hp_vs_pp_certified":false,"visual_mega_form_certified":false,
                "game_turn_certified":false,"current_state_eligible":false,
                "actual_game_accuracy_certified":false,"battle_advice_authorized":false,
                "automatic_upload":false]
    }
    private static func held(_ reason:String)->[String:Any] {
        ["schema":schema,"status":"HOLD_INVALID_SOURCE","hold_reason":reason,
         "source_schema":R585SpatialOCRProjection.schema,
         "source_candidate_count":0,"checked_candidates":0,"unmatched_candidates":0,
         "matched_candidates":0,"hypotheses":[[String:Any]](),
         "profile":"OBSERVED_LANDSCAPE_BATTLE_HUD_UNCALIBRATED",
         "source_orientation_certified":false,"owner_certified":false,
         "hp_vs_pp_certified":false,"visual_mega_form_certified":false,
         "game_turn_certified":false,"current_state_eligible":false,
         "actual_game_accuracy_certified":false,"battle_advice_authorized":false,
         "automatic_upload":false]
    }
}
