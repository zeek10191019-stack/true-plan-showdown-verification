import Foundation

/// R585: bounded geometric evidence for the R583 OCR candidates. It expresses
/// what was visible *where*, not which side, Pokemon, move, status, or turn.
/// The orientation is not certified; every back-projection is a proposal only.
enum R585SpatialOCRProjection {
    static let schema = "trueplan.r585.historical-spatial-ocr-candidates.v1"
    static let maximumFrames = 8
    static let maximumCandidates = 256
    private static let allowedAngles:Set<Int> = [0,90,180,270]

    private static func shaOK(_ v:String)->Bool {
        v.utf8.count == 64 && v.utf8.allSatisfy{ (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func rect(_ value:Any?) -> (Double,Double,Double,Double)? {
        guard let v=value as? [String:Any],
              let x=v["x"] as? Double,let y=v["y"] as? Double,
              let w=v["width"] as? Double,let h=v["height"] as? Double,
              [x,y,w,h].allSatisfy({$0.isFinite}),
              x>=0,y>=0,w>0,h>0,x+w<=1.000001,y+h<=1.000001 else{return nil}
        return (x,y,w,h)
    }
    private static func pack(_ x:Double,_ y:Double,_ w:Double,_ h:Double)->[String:Double] {
        ["x":x,"y":y,"width":w,"height":h]
    }
    /// Inverse of a nominal 0/90/180/270 degree clockwise display transform,
    /// using bottom-left normalized rectangles. No claim that this is the
    /// correct display rotation for the actual captured game frame.
    static func projected(_ input:[String:Any],angle:Int)->[String:Double]? {
        guard allowedAngles.contains(angle),let (x,y,w,h)=rect(input) else {return nil}
        switch angle {
        case 0: return pack(x,y,w,h)
        case 90: return pack(1-y-h,x,h,w)
        case 180: return pack(1-x-w,1-y-h,w,h)
        default: return pack(y,1-x-w,h,w)
        }
    }
    private static func location(_ x:Double,_ y:Double,_ w:Double,_ h:Double)->String {
        let col=(x+w/2)<0.333333 ? "LEFT" : (x+w/2)>0.666667 ? "RIGHT" : "CENTER"
        let row=(y+h/2)<0.333333 ? "BOTTOM" : (y+h/2)>0.666667 ? "TOP" : "MIDDLE"
        return row+"_"+col
    }
    static func make(indexes:[[String:Any]]) -> [String:Any] {
        var rows=[[String:Any]](), reason:String?=nil, skipped=0, inspected=0
        var lastFrame:Int64?=nil,lastEpoch:Int64?=nil,lastTime:Int64?=nil
        if indexes.count>maximumFrames {reason="TOO_MANY_FRAMES"}
        if reason == nil {
            for index in indexes {
                guard index["schema"] as? String == R583FrameReadabilityIndex.schema,
                    index["status"] as? String == "HISTORICAL_OCR_INDEX_ONLY",
                    index["source_binding_valid"] as? Bool == true,
                    index["owner_certified"] as? Bool == false,
                    index["turn_certified"] as? Bool == false,
                    index["mega_visual_form_certified"] as? Bool == false,
                    index["current_state_eligible"] as? Bool == false,
                    let frame=index["frame_id"] as? Int64,frame>0,
                    let epoch=index["epoch"] as? Int64,epoch>0,
                    let time=index["observed_ms_monotonic"] as? Int64,time>0,
                    let sha=index["image_sha256"] as? String,shaOK(sha),
                    let observations=index["observations"] as? [[String:Any]],observations.count<=128 else {
                    reason="INVALID_OR_UNBOUND_SOURCE_FRAME";break
                }
                if let p=lastFrame,let e=lastEpoch,let t=lastTime,
                   (epoch != e || frame<=p || time<t) {
                    reason="MIXED_EPOCH_OR_NONMONOTONIC_FRAMES";break
                }
                lastFrame=frame;lastEpoch=epoch;lastTime=time
                for ob in observations {
                    inspected+=1
                    guard ob["status"] as? String == "UNBOUND_TEXT_CANDIDATE",
                        ob["source_image_sha256"] as? String == sha,
                        ob["owner"] as? String == "UNKNOWN",
                        ob["visual_mega_certified"] as? Bool == false,
                        let ref=ob["ref"] as? String,ref.utf8.count<=128,
                        let text=ob["primary_text"] as? String,!text.isEmpty,text.utf8.count<=256,
                        let labels=ob["provisional_domains"] as? [String],labels.count<=16,
                        let angle=ob["rotation_degrees"] as? Int,allowedAngles.contains(angle),
                        ref.hasPrefix("rotation_\(angle).observations["),
                        let (x,y,w,h)=rect(ob["roi"]),
                        let transformed=projected(ob["roi"] as! [String:Any],angle:angle),
                        let px=transformed["x"],let py=transformed["y"],
                        let pw=transformed["width"],let ph=transformed["height"],
                        px >= -0.000001,py >= -0.000001,px+pw<=1.000001,py+ph<=1.000001 else {
                        skipped+=1;continue
                    }
                    guard rows.count<maximumCandidates else {skipped+=1;continue}
                    rows.append([
                        "frame_id":frame,"epoch":epoch,"observed_ms_monotonic":time,
                        "image_sha256":sha,"text":text,"evidence_ref":ref,
                        "rotation_degrees":angle,
                        "vision_oriented_bottom_left_roi":pack(x,y,w,h),
                        "nominal_source_bottom_left_roi":transformed,
                        "oriented_cell":location(x,y,w,h),
                        "nominal_source_cell":location(px,py,pw,ph),
                        "provisional_domains":labels,
                        "status":"UNVERIFIED_ORIENTATION_SPATIAL_OCR_CANDIDATE",
                        "display_orientation_certified":false,
                        "owner":"UNKNOWN","pokemon_identity":"UNKNOWN",
                        "turn":NSNull(),"current_state_eligible":false
                    ])
                }
            }
        }
        // Do not emit any partial dataset if a later frame violates provenance.
        if reason != nil {rows.removeAll()}
        return ["schema":schema,
                "status":reason == nil ? "HISTORICAL_GEOMETRY_CANDIDATES_ONLY" : "HOLD_INVALID_SOURCE",
                "hold_reason":reason as Any? ?? NSNull(),
                "frames_examined":reason == nil ? indexes.count : 0,
                "observations_examined":inspected,"candidate_count":rows.count,
                "skipped_or_truncated":skipped,"truncated_by_limit":skipped>0 && rows.count==maximumCandidates,
                "candidates":rows,
                "source_coordinate_space":"VISION_ORIENTED_NORMALIZED_BOTTOM_LEFT",
                "projected_coordinate_space":"NOMINAL_SOURCE_NORMALIZED_BOTTOM_LEFT_UNVERIFIED",
                "display_orientation_certified":false,"roi_owner_certified":false,
                "visual_mega_form_certified":false,"game_turn_certified":false,
                "actual_game_accuracy_certified":false,"current_state_eligible":false,
                "automatic_upload":false,"battle_advice_authorized":false]
    }
}
