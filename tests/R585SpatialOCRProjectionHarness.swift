import Foundation

@main struct R585SpatialOCRProjectionHarness {
    static var ok=0
    static func check(_ value:Bool,_ name:String) {
        guard value else {fatalError("FAIL_R585_"+name)}
        ok+=1
    }
    static let sha=String(repeating:"a",count:64)
    static func index(_ frame:Int64=1,_ epoch:Int64=1,_ time:Int64=1000,
                      _ text:String="まひ",_ angle:Int=90)->[String:Any] {
        let ocr:[String:Any]=[
            "schema":"trueplan.r551.rotation-ocr-evidence.v1","image_sha256":sha,
            "own_opponent":"UNKNOWN","mega_certified":false,"visual_form_certified":false,
            "orientation_evidence":[[
                "orientation_degrees":angle,"status":"OCR_CANDIDATES_ONLY",
                "observations":[["roi":["x":0.1,"y":0.2,"width":0.3,"height":0.4],
                                 "candidates":[["text":text,"confidence":0.93]]]]]]]
        return R583FrameReadabilityIndex.make(frame:frame,epoch:epoch,
                            observedMs:time,imageSHA:sha,ocr:ocr)
    }
    static func near(_ a:Double?,_ b:Double)->Bool { a != nil && abs(a!-b)<1e-8 }
    static func main() {
        let g=R585SpatialOCRProjection.make(indexes:[index()]);let candidates=g["candidates"] as? [[String:Any]] ?? []
        check(g["status"] as? String == "HISTORICAL_GEOMETRY_CANDIDATES_ONLY","PASS")
        check(g["candidate_count"] as? Int == 1,"ONE")
        check(g["frames_examined"] as? Int == 1,"ONE_FRAME")
        check(candidates.count==1,"RECORDS")
        let c=candidates[0]
        let p=c["nominal_source_bottom_left_roi"] as? [String:Double] ?? [:]
        check(near(p["x"],0.4),"ROT90_X")
        check(near(p["y"],0.1),"ROT90_Y")
        check(near(p["width"],0.4),"ROT90_W")
        check(near(p["height"],0.3),"ROT90_H")
        check(c["text"] as? String == "まひ","TEXT")
        check(c["owner"] as? String == "UNKNOWN","OWNER_UNKNOWN")
        check(c["current_state_eligible"] as? Bool == false,"STATE_HOLD")
        check(c["turn"] is NSNull,"TURN_UNKNOWN")
        check(c["display_orientation_certified"] as? Bool == false,"ORIENTATION_HOLD")
        check(c["status"] as? String == "UNVERIFIED_ORIENTATION_SPATIAL_OCR_CANDIDATE","CANDIDATE")
        check(c["rotation_degrees"] as? Int == 90,"ANGLE")
        check(c["image_sha256"] as? String == sha,"SHA_BIND")
        check(c["evidence_ref"] as? String == "rotation_90.observations[0]","REF")
        check(c["provisional_domains"] as? [String] == ["major_status"],"DOMAIN")
        check(g["automatic_upload"] as? Bool == false,"NO_UPLOAD")
        check(g["visual_mega_form_certified"] as? Bool == false,"MEGA_HOLD")
        check(g["battle_advice_authorized"] as? Bool == false,"ADVICE_HOLD")
        check(JSONSerialization.isValidJSONObject(g),"SERIALIZE")
        let r:[String:Any] = ["x":0.1,"y":0.2,"width":0.3,"height":0.4]
        let expected:[(Int,[Double])]=[(0,[0.1,0.2,0.3,0.4]),(90,[0.4,0.1,0.4,0.3]),
            (180,[0.6,0.4,0.3,0.4]),(270,[0.2,0.6,0.4,0.3])]
        for (angle,e) in expected {
            let v=R585SpatialOCRProjection.projected(r,angle:angle)!
            for (key,index) in [("x",0),("y",1),("width",2),("height",3)] {
                check(near(v[key],e[index]),"TRANSFORM_\(angle)_\(key)")
            }
        }
        check(R585SpatialOCRProjection.projected(r,angle:45)==nil,"BAD_ANGLE")
        check(R585SpatialOCRProjection.projected(["x":Double.nan,"y":0.2,"width":0.3,"height":0.4],angle:90)==nil,"NAN")
        check(R585SpatialOCRProjection.projected(["x":0.9,"y":0.2,"width":0.3,"height":0.4],angle:90)==nil,"OUT_OF_BOUNDS")
        check(R585SpatialOCRProjection.projected(["x":0.1,"y":0.2,"width":0.0,"height":0.4],angle:90)==nil,"ZERO_WIDTH")
        check(R585SpatialOCRProjection.make(indexes:[])["candidate_count"] as? Int==0,"EMPTY")
        let two=R585SpatialOCRProjection.make(indexes:[index(),index(2,1,1050,"リフレクター")])
        check(two["frames_examined"] as? Int==2,"TWO_FRAMES")
        check(two["candidate_count"] as? Int==2,"TWO_CANDIDATES")
        check(R585SpatialOCRProjection.make(indexes:[index(2),index()])["status"] as? String=="HOLD_INVALID_SOURCE","REORDER_HOLD")
        check(R585SpatialOCRProjection.make(indexes:[index(),index()])["candidate_count"] as? Int==0,"DUP_HOLD")
        check(R585SpatialOCRProjection.make(indexes:[index(),index(2,2)])["candidate_count"] as? Int==0,"EPOCH_HOLD")
        check(R585SpatialOCRProjection.make(indexes:[index(),index(2,1,900)])["candidate_count"] as? Int==0,"CLOCK_HOLD")
        var bad=index();bad["owner_certified"]=true
        check(R585SpatialOCRProjection.make(indexes:[bad])["candidate_count"] as? Int==0,"FORGED_OWNER")
        bad=index();bad["source_binding_valid"]=false
        check(R585SpatialOCRProjection.make(indexes:[bad])["status"] as? String=="HOLD_INVALID_SOURCE","BAD_BIND")
        bad=index();bad["image_sha256"]=String(repeating:"z",count:64)
        check(R585SpatialOCRProjection.make(indexes:[bad])["candidate_count"] as? Int==0,"BAD_SHA")
        bad=index();bad["current_state_eligible"]=true
        check(R585SpatialOCRProjection.make(indexes:[bad])["candidate_count"] as? Int==0,"FALSE_STATE")
        let nine=(0..<9).map{index(Int64($0+1),1,Int64(1000+$0))}
        check(R585SpatialOCRProjection.make(indexes:nine)["candidate_count"] as? Int==0,"MAX_FRAMES")
        let ambiguity = index(3,1,1500,"80%")
        check(R585SpatialOCRProjection.make(indexes:[ambiguity])["candidate_count"] as? Int==1,"PERCENT_GEOMETRY")
        check(ok>=45,"MIN_ASSERTIONS")
        print("PASS_R585_\(ok)_SPATIAL_OCR_AND_SAFE_PROVENANCE")
    }
}
