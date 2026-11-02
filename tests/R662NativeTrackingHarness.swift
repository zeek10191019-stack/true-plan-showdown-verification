import Foundation
import CoreGraphics
import Vision

@main struct R662NativeTrackingHarness {
    static func picture(_ offset: Int) -> CGImage {
        let w=512,h=256
        let context=CGContext(data:nil,width:w,height:h,
            bitsPerComponent:8,bytesPerRow:w*4,
            space:CGColorSpaceCreateDeviceRGB(),
            bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray:0.12,alpha:1))
        context.fill(CGRect(x:0,y:0,width:w,height:h))
        for i in 0..<100 {
            let x=20+(i*33)%470+offset
            let y=13+(i*29)%210
            context.setFillColor(CGColor(red:Double(i%13)/14,
                green:Double(i%17)/18,
                blue:Double(i%9)/10,alpha:1))
            context.fill(CGRect(x:x,y:y,width:7+i%13,
                                height:8+i%11))
        }
        return context.makeImage()!
    }
    static func main() {
        var frames=[R659AutoVisionTimeline.Frame]()
        let hs=["a","b","c","d"].map{String(repeating:$0,count:64)}
        for i in 0..<4 {
            frames.append(.init(epoch:1,frameID:Int64(i+1),
                observedMs:Int64((i+1)*100),
                image:picture(i*2),sha256:hs[i]))
        }
        var pairs=[[String:Any]]()
        for i in 0..<3 {
            pairs.append([
                "from_frame_id":i+1,"to_frame_id":i+2,
                "source_sha256_from":hs[i],
                "source_sha256_to":hs[i+1],
                "diagnostic_only":true,
                "camera_or_actor_motion_distinguished":false,
                "mega_event_confirmed":false])
        }
        var evidence:[String:Any]=[
            "status":"HISTORICAL_CROSS_MODAL_EVIDENCE_ONLY",
            "source_join_verified":true,"pairs_checked":3,
            "region_calibrated":false,"owner_certified":false,
            "species_certified":false,"mega_event_certified":false,
            "mega_form_certified":false,
            "battle_advice_authorized":false,
            "current_state_eligible":false,
            "held_out_accuracy":"NOT_MEASURED","pairs":pairs]
        let out=R662VisionRegionTracking.audit(frames:frames,
                                               evidence:evidence,
                                               budgetMs:9500)
        let state=out["status"] as? String ?? ""
        precondition(state == "HISTORICAL_UNLABELED_REGION_TRACKS_ONLY"
                     || state.hasPrefix("HOLD_"))
        for k in ["owner_certified","species_certified",
                  "mega_event_certified","mega_form_certified",
                  "battle_advice_authorized","current_state_eligible"] {
            precondition(out[k] as? Bool == false)
        }
        precondition(out["held_out_accuracy"] as? String == "NOT_MEASURED")
        if state == "HISTORICAL_UNLABELED_REGION_TRACKS_ONLY" {
            let samples=out["samples"] as? [[String:Any]] ?? []
            precondition(samples.count == 6)
            precondition(samples.allSatisfy {
                $0["source_is_pokemon"] as? Bool == false &&
                $0["mega_form_identified"] as? Bool == false
            })
        }
        evidence["source_join_verified"]=false
        let bad=R662VisionRegionTracking.audit(frames:frames,
                                               evidence:evidence)
        precondition(bad["status"] as? String ==
                     "HOLD_R661_JOIN_UNAVAILABLE")
        print("R662_NATIVE_VISION_TRACKING_BOUNDARY_PASS",state)
    }
}
