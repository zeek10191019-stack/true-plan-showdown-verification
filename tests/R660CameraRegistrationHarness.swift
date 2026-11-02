import Foundation
import CoreGraphics
import Vision

@main struct R660CameraRegistrationHarness {
    static var count=0
    static func check(_ ok:Bool,_ name:String) {
        precondition(ok,"R660_REGISTRATION_FAIL_"+name)
        count += 1
    }
    static func picture(_ shift:Int)->CGImage {
        let w=512,h=256
        let cs=CGColorSpaceCreateDeviceRGB()
        let ctx=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,
            bytesPerRow:w*4,space:cs,
            bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red:0.09,green:0.15,blue:0.25,alpha:1))
        ctx.fill(CGRect(x:0,y:0,width:w,height:h))
        for n in 0..<70 {
            let x=(n*37)%454+shift,y=(n*83)%202
            let color=CGColor(red:Double(n%11)/12+0.08,
                green:Double(n%7)/8+0.08,
                blue:Double(n%17)/18+0.05,alpha:1)
            ctx.setFillColor(color)
            ctx.fill(CGRect(x:x,y:y,width:12+n%6,height:14+n%9))
        }
        return ctx.makeImage()!
    }
    static func main() {
        func frame(_ i:Int,epoch:Int64=1,sha:String?=nil)
            ->R659AutoVisionTimeline.Frame {
            .init(epoch:epoch,frameID:Int64(i),
                  observedMs:Int64(100*i),image:picture((i-1)*2),
                  sha256:sha ?? String(repeating:["a","b","c","d"][(i-1)%4],count:64))
        }
        // The source is actual CoreGraphics imagery, not mocked Vision.
        let frames=[frame(1),frame(2),frame(3),frame(4)]
        let missing=R660CameraMotionRegistration.audit(frames:[frame(1)])
        check(missing["status"] as? String ==
              "HOLD_NEED_FOUR_RETAINED_FRAMES","missing")
        check(missing["mega_event_certified"] as? Bool == false,
              "no_mega_missing")
        let out=R660CameraMotionRegistration.audit(frames:frames,
                                                   budgetMs:10000)
        check(out["schema"] as? String ==
              R660CameraMotionRegistration.schema,"schema")
        check(out["owner_certified"] as? Bool == false,"owner")
        check(out["mega_event_certified"] as? Bool == false,"mega")
        check(out["mega_form_certified"] as? Bool == false,"mega_form")
        check(out["battle_advice_authorized"] as? Bool == false,"advice")
        check(out["current_state_eligible"] as? Bool == false,"current")
        check(out["held_out_accuracy"] as? String ==
              "NOT_MEASURED","accuracy")
        // A registration failure is a legitimate HOLD, never a fake pass.
        let status=out["status"] as? String ?? ""
        if status == "HISTORICAL_CAMERA_TRANSLATION_MEASURE_ONLY" {
            let pairs=out["pairs"] as? [[String:Any]] ?? []
            check(pairs.count==3,"three_pairs")
            check(pairs.allSatisfy{
                $0["image_registration_is_mega_proof"] == nil &&
                ($0["translation_magnitude_fraction"] as? Double)?
                  .isFinite == true },"finite_no_mega")
            check(pairs[0]["from_frame_id"] as? Int64 == 1,
                  "from_frame")
            check(pairs[2]["to_frame_id"] as? Int64 == 4,
                  "to_frame")
        } else {
            check(status.hasPrefix("HOLD_"),"fail_closed")
        }
        let changed=[frame(1),frame(2,epoch:2),frame(3),frame(4)]
        let bad=R660CameraMotionRegistration.audit(frames:changed)
        check(bad["status"] as? String ==
              "HOLD_MIXED_SOURCE_OR_DUPLICATE","mixed_epoch")
        print("R660_REAL_VISION_REGISTRATION_GUARD_PASS",count,
              "status",status)
    }
}
