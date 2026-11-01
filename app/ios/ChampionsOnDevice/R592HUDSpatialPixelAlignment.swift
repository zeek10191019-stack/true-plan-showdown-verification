import Foundation

/// R592: independently check that retained-color HUD candidates and retained
/// OCR HUD numerics occupy NEARBY image regions, not merely the same frame.
/// Screen orientation, side ownership, HP and move PP are NEVER certified.
/// Bounded historical audit; consumes existing R590/R587 results with no OCR work.
enum R592HUDSpatialPixelAlignment {
    static let schema = "trueplan.r592.historical-hud-spatial-pixel-alignment.v1"
    private static let pixelSchema = R590ColorHUDCorroboration.schema
    private static let ocrSchema = "trueplan.r587.frame-hud-association.v1"
    private static let roles:[(String,String)] = [
        ("LOWER_LEFT_HUD_REGION", "HYPOTHESIS_OWN_HP_FRACTION"),
        ("UPPER_RIGHT_HUD_REGION", "HYPOTHESIS_OPPONENT_HP_PERCENT")
    ]
    private static func shaOK(_ s:String) -> Bool {
        s.utf8.count == 64 && s.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
    private static func hold(_ reason:String)->[String:Any] {
        ["schema":schema,"status":"HOLD_INVALID_SOURCE_OR_PROVENANCE",
         "hold_reason":reason,"frame_count":0,"frames":[[String:Any]](),
         "owner_certified":false,"hp_certified":false,
         "orientation_certified":false,"mega_visual_form_certified":false,
         "current_state_eligible":false,"automatic_upload":false]
    }
    private struct Rect {
        var x:Double;var y:Double;var w:Double;var h:Double
        var left:Double{x};var right:Double{x+w}
        var top:Double{1-y-h};var bottom:Double{1-y}
        var centerX:Double{x+w/2};var centerY:Double{top+h/2}
    }
    private static func rect(_ source:Any?) -> Rect? {
        guard let d=source as? [String:Any],let x=d["x"] as? Double,
              let y=d["y"] as? Double,let w=d["width"] as? Double,
              let h=d["height"] as? Double,
              [x,y,w,h].allSatisfy({$0.isFinite}),x>=0,y>=0,w>0,h>0,
              x+w<=1.000001,y+h<=1.000001 else{return nil}
        return Rect(x:x,y:y,w:w,h:h)
    }
    private static func gap(_ a0:Double,_ a1:Double,_ b0:Double,_ b1:Double)->Double {
        max(0,max(b0-a1,a0-b1))
    }
    private static func near(_ rect:Rect,_ candidate:[String:Any])->Bool {
        guard let x0=candidate["bounds_left_normalized"] as? Double,
              let x1=candidate["bounds_right_normalized"] as? Double,
              let y0=candidate["bounds_top_normalized"] as? Double,
              let y1=candidate["bounds_bottom_normalized"] as? Double,
              [x0,x1,y0,y1].allSatisfy({$0.isFinite}),
              x0>=0,x0<x1,x1<=1,y0>=0,y0<y1,y1<=1,
              let aspect=candidate["horizontal_aspect_min"] as? Double,
              aspect.isFinite,aspect>=4,
              candidate["shape_provenance"] as? String ==
                    "R591_CONNECTED_SCANLINE_GEOMETRY_HYPOTHESIS",
              candidate["shape_ambiguous"] as? Bool == false,
              candidate["disjoint_shape_count"] as? Int == 1
        else{return false}
        // Pixel coordinates are top-left; Vision OCR source boxes are bottom-left.
        // Separation threshold is an uncalibrated search envelope, NOT ownership.
        return gap(x0,x1,rect.left,rect.right)<=0.18 &&
               gap(y0,y1,rect.top,rect.bottom)<=0.12
    }
    private static func validPixel(_ a:[String:Any])->Bool {
        guard let color=a["color_hypothesis"] as? String,
              ["GREEN","YELLOW","RED"].contains(color),
              let region=a["region_hypothesis"] as? String,
              roles.contains(where:{$0.0==region}),
              let raster=a["raster_row_order_hypothesis"] as? String,
              ["MEMORY_FIRST_ROW_TOP_HYPOTHESIS","MEMORY_LAST_ROW_TOP_HYPOTHESIS"].contains(raster),
              a["owner"] as? String == "UNKNOWN",
              a["status"] as? String == "UNCALIBRATED_COLOR_RUN_CANDIDATE_ONLY"
        else{return false}
        // A legitimate ambiguous shape must remain a valid piece of evidence;
        // its REGION status becomes HOLD rather than rejecting the whole archive.
        guard let x0=a["bounds_left_normalized"] as? Double,
              let x1=a["bounds_right_normalized"] as? Double,
              let y0=a["bounds_top_normalized"] as? Double,
              let y1=a["bounds_bottom_normalized"] as? Double,
              [x0,x1,y0,y1].allSatisfy({$0.isFinite}),
              x0>=0,x0<x1,x1<=1,y0>=0,y0<y1,y1<=1,
              let aspect=a["horizontal_aspect_min"] as? Double,
              aspect.isFinite,aspect>=4,
              a["shape_provenance"] as? String ==
                   "R591_CONNECTED_SCANLINE_GEOMETRY_HYPOTHESIS",
              let ambiguous=a["shape_ambiguous"] as? Bool,
              let count=a["disjoint_shape_count"] as? Int,
              count>=1,count<=512,ambiguous == (count>1)
        else{return false}
        return true
    }
    private static func validAnchor(_ a:[String:Any])->Bool {
        guard let kind=a["hypothesis"] as? String,
              roles.contains(where:{$0.1==kind}),
              a["owner"] as? String == "UNKNOWN",
              a["status"] as? String == "UNVERIFIED_TEXT_AND_HUD_LAYOUT_MATCH",
              let value=a["value"] as? String,!value.isEmpty,value.utf8.count<=20,
              let angle=a["rotation_degrees"] as? Int,[0,90,180,270].contains(angle),
              let evidence=a["evidence_ref"] as? String,
              evidence.hasPrefix("rotation_\(angle).observations["),
              rect(a["source_bottom_left_roi"]) != nil
        else{return false}
        return true
    }
    static func make(pixelFrames:[[String:Any]], associations:[String:Any])->[String:Any] {
        guard pixelFrames.count<=8,
              associations["schema"] as? String == ocrSchema,
              associations["status"] as? String == "HISTORICAL_FRAME_HUD_ASSOCIATIONS_ONLY",
              associations["owner_certified"] as? Bool == false,
              associations["orientation_certified"] as? Bool == false,
              associations["current_state_eligible"] as? Bool == false,
              let frames=associations["frames"] as? [[String:Any]],
              associations["frame_count"] as? Int == frames.count,
              frames.count==pixelFrames.count else {return hold("SOURCE_ROOT_OR_COUNT_MISMATCH")}
        var result=[[String:Any]](),seen=Set<String>()
        for (index,p) in pixelFrames.enumerated() {
            let o=frames[index]
            guard p["schema"] as? String == pixelSchema,
                  let epoch=p["epoch"] as? Int64,epoch>0,
                  let frame=p["frame_id"] as? Int64,frame>0,
                  let ms=p["observed_ms_monotonic"] as? Int64,ms>0,
                  let sha=p["image_sha256"] as? String,shaOK(sha),
                  o["epoch"] as? Int64 == epoch,
                  o["frame_id"] as? Int64 == frame,
                  o["observed_ms_monotonic"] as? Int64 == ms,
                  o["image_sha256"] as? String == sha,
                  seen.insert("\(epoch):\(frame)").inserted,
                  let status=p["status"] as? String,
                  ["UNCALIBRATED_COLOR_RUN_CANDIDATES","NO_COLOR_RUN_CANDIDATES",
                   "HOLD_PIXEL_BUFFER_NOT_AVAILABLE"].contains(status),
                  p["owner_certified"] as? Bool == false,
                  p["current_state_eligible"] as? Bool == false,
                  let pixels=p["color_run_candidates"] as? [[String:Any]],
                  pixels.count<=12,p["candidate_count"] as? Int == pixels.count,
                  pixels.allSatisfy({validPixel($0)}),
                  let anchors=o["anchors"] as? [[String:Any]],anchors.count<=256,
                  anchors.allSatisfy({validAnchor($0)})
            else{return hold("FRAME_OR_PIXEL_OR_SPATIAL_OCR_PROVENANCE_REJECTED")}
            var matched=[[String:Any]]()
            for (role,kind) in roles {
                let regionPixels=pixels.filter{$0["region_hypothesis"] as? String == role}
                let regionAnchors=anchors.filter{$0["hypothesis"] as? String == kind}
                let nearby=regionPixels.count==1 ? regionAnchors.filter {
                    guard let r=rect($0["source_bottom_left_roi"]) else{return false}
                    return near(r,regionPixels[0])
                } : []
                let state:String
                if regionPixels.count>1 || regionAnchors.count>1 ||
                   regionPixels.contains(where:{$0["shape_ambiguous"] as? Bool == true}) {
                    state="HOLD_AMBIGUOUS_SHAPE_OR_OCR"
                } else if regionPixels.count==1 && regionAnchors.count==1 && nearby.count==1 {
                    state="NEARBY_PIXEL_OCR_SPATIAL_HYPOTHESIS_ONLY"
                } else if regionPixels.isEmpty && regionAnchors.isEmpty {
                    state="NO_EVIDENCE"
                } else {
                    state="HOLD_INSUFFICIENT_OR_DISTANT_EVIDENCE"
                }
                matched.append(["region_hypothesis":role,"status":state,
                    "pixel_candidate_count":regionPixels.count,
                    "ocr_candidate_count":regionAnchors.count,
                    "nearby_pair_count":nearby.count,
                    "candidate_texts":regionAnchors.compactMap{$0["value"] as? String},
                    "hp_value":NSNull(),"owner":"UNKNOWN",
                    "spatial_threshold_is_calibrated":false])
            }
            result.append(["epoch":epoch,"frame_id":frame,
                "observed_ms_monotonic":ms,"image_sha256":sha,
                "regions":matched,"current_state_eligible":false])
        }
        return ["schema":schema,"status":"HISTORICAL_SPATIAL_PIXEL_OCR_AUDIT_ONLY",
                "hold_reason":NSNull(),"frame_count":result.count,"frames":result,
                "owner_certified":false,"hp_certified":false,
                "orientation_certified":false,"mega_visual_form_certified":false,
                "actual_game_accuracy_certified":false,
                "current_state_eligible":false,"automatic_upload":false]
    }
}
