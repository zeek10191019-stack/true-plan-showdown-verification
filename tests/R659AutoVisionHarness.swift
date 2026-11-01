import Foundation
import CoreGraphics
import Vision

@main struct R659AutoVisionHarness {
    static func makeImage(_ shift:Int)->CGImage {
        let w=512,h=256
        let ctx=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,
                          bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red:0.16,green:0.19,blue:0.30,alpha:1))
        ctx.fill(CGRect(x:0,y:0,width:w,height:h))
        for i in 0..<16 {
            let x=Int((i*27+shift)%480)
            ctx.setFillColor(CGColor(red:Double(i%6)/7.0+0.1,
                green:Double(i%7)/9.0+0.1,
                blue:Double(i%8)/10.0+0.1,alpha:1))
            ctx.fill(CGRect(x:x,y:45+(i%3)*25,width:15,height:92))
        }
        return ctx.makeImage()!
    }
    static func main() throws {
        let ids=(0..<4).map{Int64($0+1)}
        let hashes=(0..<4).map{String(repeating:String($0+1),count:64)}
        let frames=(0..<4).map{i in
            R659AutoVisionTimeline.Frame(epoch:1,frameID:ids[i],
                observedMs:Int64((i+1)*200),image:makeImage(i*9),
                sha256:hashes[i])
        }
        let actual=R659AutoVisionTimeline.audit(frames:frames,budgetMs:30000)
        guard actual["status"] as? String ==
            "HISTORICAL_UNLABELED_VISUAL_MOTION_ONLY",
            let rows=actual["regions"] as? [[String:Any]],rows.count==9,
            rows.allSatisfy({($0["feature_distance_unscaled"] as? Double ?? -1)>=0}),
            actual["owner_certified"] as? Bool == false,
            actual["mega_event_certified"] as? Bool == false,
            actual["battle_advice_authorized"] as? Bool == false,
            actual["original_images_exported"] as? Bool == false else {
            fatalError("R659_ACTUAL_VISION_TEST_FAILED: \(actual)")
        }
        let empty=R659AutoVisionTimeline.audit(frames:[],budgetMs:30000)
        guard empty["status"] as? String=="HOLD_NEED_FOUR_RETAINED_FRAMES" else {
            fatalError("R659_NO_FRAMES_GATE")
        }
        let invalid=R659AutoVisionTimeline.audit(frames:frames,budgetMs:10)
        guard invalid["status"] as? String=="HOLD_INVALID_BUDGET" else {
            fatalError("R659_INVALID_BUDGET_GATE")
        }
        print("R659_APPLE_VISION_REAL_FEATURE_PRINT_PASS 9 DISTANCES 3 GATES")
    }
}
