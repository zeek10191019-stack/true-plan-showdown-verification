import Foundation

@main struct R592HUDSpatialPixelAlignmentHarness {
    static func main() {
        var passed = 0
        func check(_ yes:Bool,_ key:String) {
            guard yes else { fatalError("R592_\(key)_FAIL") }
            passed += 1
        }
        let hash=String(repeating:"a",count:64)
        let w=480,h=240
        var pixels=[UInt8](repeating:0,count:w*h*4)
        for y in 207..<212 {for x in 64..<130 {
            let i=(y*w+x)*4
            pixels[i]=38;pixels[i+1]=202;pixels[i+2]=48;pixels[i+3]=255
        }}
        for y in 26..<30 {for x in 384..<435 {
            let i=(y*w+x)*4
            pixels[i]=230;pixels[i+1]=188;pixels[i+2]=20;pixels[i+3]=255
        }}
        func getPixels(_ frame:Int64=1,_ ep:Int64=1,_ sha:String=hash) -> [String:Any] {
            R590ColorHUDCorroboration.inspect(pixels:pixels,width:w,height:h,
              rowBytes:w*4,epoch:ep,frame:frame,observedMs:100,imageSHA:sha)
        }
        // OCR Vision bottom-left coordinates. Own text close to lower-left bar;
        // opponent percentage close to upper-right bar. Still not owner certified.
        func anchor(_ role:String,_ v:String,_ x:Double,_ y:Double)->[String:Any] {
            ["hypothesis":role,"value":v,"owner":"UNKNOWN",
             "status":"UNVERIFIED_TEXT_AND_HUD_LAYOUT_MATCH",
             "rotation_degrees":0,"evidence_ref":"rotation_0.observations[0]",
             "source_bottom_left_roi":["x":x,"y":y,"width":0.09,"height":0.045]]
        }
        let own=anchor("HYPOTHESIS_OWN_HP_FRACTION","170/185",0.145,0.09)
        let opp=anchor("HYPOTHESIS_OPPONENT_HP_PERCENT","64%",0.8,0.835)
        func getAssociations(_ p:[String:Any],anchors:[[String:Any]]?=nil)->[String:Any] {
            ["schema":"trueplan.r587.frame-hud-association.v1",
             "status":"HISTORICAL_FRAME_HUD_ASSOCIATIONS_ONLY",
             "owner_certified":false,"orientation_certified":false,
             "current_state_eligible":false,"frame_count":1,
             "frames":[["epoch":p["epoch"]!,"frame_id":p["frame_id"]!,
               "observed_ms_monotonic":p["observed_ms_monotonic"]!,
               "image_sha256":p["image_sha256"]!,
               "anchors":anchors ?? [own,opp]]]]
        }
        func audit(_ p:[String:Any],_ a:[String:Any])->[String:Any] {
            R592HUDSpatialPixelAlignment.make(pixelFrames:[p],associations:a)
        }
        func regions(_ d:[String:Any])->[[String:Any]] {
            let f=d["frames"] as? [[String:Any]] ?? []
            return f.first?["regions"] as? [[String:Any]] ?? []
        }
        let p=getPixels()
        check(p["candidate_count"] as? Int==2,"pixel_fixture")
        let a=getAssociations(p)
        let happy=audit(p,a)
        check(happy["status"] as? String=="HISTORICAL_SPATIAL_PIXEL_OCR_AUDIT_ONLY","good_source")
        check(happy["frame_count"] as? Int==1,"count")
        check(regions(happy).count==2,"two_roles")
        check(regions(happy).allSatisfy{$0["status"] as? String=="NEARBY_PIXEL_OCR_SPATIAL_HYPOTHESIS_ONLY"},"proximity")
        check(happy["owner_certified"] as? Bool==false,"owner_hold")
        check(happy["hp_certified"] as? Bool==false,"hp_hold")
        check(happy["orientation_certified"] as? Bool==false,"rotation_hold")
        check(happy["current_state_eligible"] as? Bool==false,"no_live_state")
        check(happy["automatic_upload"] as? Bool==false,"no_upload")
        check(regions(happy).allSatisfy{$0["hp_value"] is NSNull},"no_hps")
        check(regions(happy).allSatisfy{$0["spatial_threshold_is_calibrated"] as? Bool==false},"not_calibrated")
        // Incorrect OCR text location must NOT get a match, even same frame.
        let far=anchor("HYPOTHESIS_OWN_HP_FRACTION","170/185",0.6,0.5)
        let dist=audit(p,getAssociations(p,anchors:[far,opp]))
        check(regions(dist)[0]["status"] as? String=="HOLD_INSUFFICIENT_OR_DISTANT_EVIDENCE","distance_hold")
        check(regions(dist)[1]["status"] as? String=="NEARBY_PIXEL_OCR_SPATIAL_HYPOTHESIS_ONLY","independent_opp")
        let duplicate=audit(p,getAssociations(p,anchors:[own,own,opp]))
        check(regions(duplicate)[0]["status"] as? String=="HOLD_AMBIGUOUS_SHAPE_OR_OCR","duplicate_hold")
        let absent=audit(p,getAssociations(p,anchors:[own]))
        check(regions(absent)[1]["status"] as? String=="HOLD_INSUFFICIENT_OR_DISTANT_EVIDENCE","missing_ocr_hold")
        // Multiple separated shapes are valid but MUST never be promoted.
        var ambiguousPixel=p
        var ambiguousCandidates=ambiguousPixel["color_run_candidates"] as! [[String:Any]]
        ambiguousCandidates[0]["shape_ambiguous"]=true
        ambiguousCandidates[0]["disjoint_shape_count"]=2
        ambiguousPixel["color_run_candidates"]=ambiguousCandidates
        let ambiguousReport=audit(ambiguousPixel,a)
        check(ambiguousReport["status"] as? String == "HISTORICAL_SPATIAL_PIXEL_OCR_AUDIT_ONLY","ambiguous_record_valid")
        check(regions(ambiguousReport)[0]["status"] as? String=="HOLD_AMBIGUOUS_SHAPE_OR_OCR","ambiguous_record_held")
        check(regions(ambiguousReport)[1]["status"] as? String=="NEARBY_PIXEL_OCR_SPATIAL_HYPOTHESIS_ONLY","ambiguous_other_role")
        let noOCR=audit(p,getAssociations(p,anchors:[]))
        check(regions(noOCR).allSatisfy{$0["status"] as? String=="HOLD_INSUFFICIENT_OR_DISTANT_EVIDENCE"},"no_ocr")
        let p0=R590ColorHUDCorroboration.inspect(pixels:[UInt8](repeating:0,count:w*h*4),width:w,height:h,rowBytes:w*4,epoch:1,frame:1,observedMs:100,imageSHA:hash)
        check(regions(audit(p0,getAssociations(p0,anchors:[]))).allSatisfy{$0["status"] as? String=="NO_EVIDENCE"},"empty_both")
        check(regions(audit(p0,getAssociations(p0))).allSatisfy{$0["status"] as? String=="HOLD_INSUFFICIENT_OR_DISTANT_EVIDENCE"},"no_pixels")
        func reject(_ pixels:[[String:Any]],_ assoc:[String:Any])->Bool {
            R592HUDSpatialPixelAlignment.make(pixelFrames:pixels,associations:assoc)["status"] as? String=="HOLD_INVALID_SOURCE_OR_PROVENANCE"
        }
        var modified=a
        modified["owner_certified"]=true
        check(reject([p],modified),"owner_root_reject")
        modified=a;modified["frame_count"]=2
        check(reject([p],modified),"count_reject")
        modified=a;modified["schema"]="wrong"
        check(reject([p],modified),"schema_reject")
        modified=a;var rows=modified["frames"] as! [[String:Any]]
        rows[0]["image_sha256"]=String(repeating:"b",count:64);modified["frames"]=rows
        check(reject([p],modified),"sha_mismatch")
        modified=a;rows=modified["frames"] as! [[String:Any]]
        rows[0]["frame_id"]=Int64(2);modified["frames"]=rows
        check(reject([p],modified),"frame_mismatch")
        modified=a;rows=modified["frames"] as! [[String:Any]]
        rows[0]["observed_ms_monotonic"]=Int64(102);modified["frames"]=rows
        check(reject([p],modified),"time_mismatch")
        var px=p;px["candidate_count"]=999
        check(reject([px],a),"pixel_count_reject")
        px=p;px["owner_certified"]=true
        check(reject([px],a),"pixel_cert_reject")
        px=p;px["image_sha256"]=String(repeating:"B",count:64)
        check(reject([px],a),"nonhex_hash")
        px=p;var candidates=px["color_run_candidates"] as! [[String:Any]]
        candidates[0]["bounds_right_normalized"]=Double.nan
        px["color_run_candidates"]=candidates
        check(reject([px],a),"nan_geometry_reject")
        px=p;candidates=px["color_run_candidates"] as! [[String:Any]]
        candidates[0]["shape_provenance"]="UNKNOWN"
        px["color_run_candidates"]=candidates
        check(reject([px],a),"forged_shape_reject")
        px=p;candidates=px["color_run_candidates"] as! [[String:Any]]
        candidates[0]["color_hypothesis"]="BLUE"
        px["color_run_candidates"]=candidates
        check(reject([px],a),"wrong_color_reject")
        modified=getAssociations(p,anchors:[own,opp]);rows=modified["frames"] as! [[String:Any]]
        var broken=own
        broken["source_bottom_left_roi"]=["x":0.1,"y":0.1,"width":-0.05,"height":0.1]
        rows[0]["anchors"]=[broken,opp];modified["frames"]=rows
        check(reject([p],modified),"bad_ocr_rect")
        modified=getAssociations(p,anchors:[own,opp]);rows=modified["frames"] as! [[String:Any]]
        broken=own;broken["status"]="CERTIFIED"
        rows[0]["anchors"]=[broken,opp];modified["frames"]=rows
        check(reject([p],modified),"forged_ocr_cert")
        check(reject([p,p],a),"frame_count_extra")
        check(reject(Array(repeating:p,count:9),a),"max_frame_cap")
        modified=a;rows=modified["frames"] as! [[String:Any]]
        rows.append(rows[0]);modified["frames"]=rows;modified["frame_count"]=2
        check(reject([p,p],modified),"duplicate_frame_reject")
        check(R592HUDSpatialPixelAlignment.make(pixelFrames:[],associations:[
              "schema":"trueplan.r587.frame-hud-association.v1",
              "status":"HISTORICAL_FRAME_HUD_ASSOCIATIONS_ONLY",
              "owner_certified":false,"orientation_certified":false,
              "current_state_eligible":false,"frame_count":0,
              "frames":[[String:Any]]()])["frame_count"] as? Int == 0,"zero_frames")
        print("R592_SPATIAL_PIXEL_OCR_AUDIT_PASS \(passed)/\(passed)")
    }
}
