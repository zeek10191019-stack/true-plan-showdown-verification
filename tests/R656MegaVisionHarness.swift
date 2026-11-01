import Foundation
import CoreGraphics
import ImageIO
import Vision

@main struct R656MegaVisionHarness {
    static var count = 0
    static func check(_ ok: Bool,_ label: String) {
        guard ok else {fatalError("R656_TEST_FAIL_" + label)}
        count += 1
    }
    static func png(_ shift: Int,_ width:Int=512) -> Data {
        let height = 256
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let ctx = CGContext(data:nil,width:width,height:height,
                            bitsPerComponent:8,bytesPerRow:width*4,
                            space:cs,bitmapInfo:info)!
        ctx.setFillColor(CGColor(red:0.12,green:0.2,blue:0.31,alpha:1))
        ctx.fill(CGRect(x:0,y:0,width:width,height:height))
        for i in 0..<16 {
            let x=15+i*27+shift
            ctx.setFillColor(CGColor(red:Double(i%5)/5+0.1,
                                     green:Double(i%7)/8+0.1,
                                     blue:Double(i%9)/10+0.1,alpha:1))
            ctx.fill(CGRect(x:x,y:45+i%3*27,width:15,height:90))
        }
        let bitmap=ctx.makeImage()!
        let data=NSMutableData()
        let dest=CGImageDestinationCreateWithData(data, "public.png" as CFString,1,nil)!
        CGImageDestinationAddImage(dest,bitmap,nil)
        check(CGImageDestinationFinalize(dest),"png_created")
        return data as Data
    }
    static func failure(_ reason:String,_ run:()->Void) {
        // Compiled in a separate test call: this is intentionally not used
        // for forced unwraps or software errors.
        run()
        _=reason
    }
    static func main() throws {
        let a=png(0),b=png(12),c=png(12,640)
        let good=try R656MegaVisionPair.compare(before:a,after:b,
            proposedMegaID:"gyarados-mega",manuallyReviewed:true)
        check(good["schema"] as? String==R656MegaVisionPair.schema,"schema")
        check(good["status"] as? String=="OFFLINE_VISION_DISTANCE_ONLY","status")
        let rows=good["distances"] as! [[String:Any]]
        check(rows.count==4,"four_regions")
        check(rows.allSatisfy{($0["feature_distance_unscaled"] as? Double ?? -1)>=0},"distances")
        check(rows.allSatisfy{$0["owner"] as? String=="UNKNOWN"},"unknown_owner")
        check(good["owner_certified"] as? Bool==false,"owner_gate")
        check(good["mega_event_certified"] as? Bool==false,"mega_gate")
        check(good["battle_advice_authorized"] as? Bool==false,"advice_gate")
        check(good["original_images_exported"] as? Bool==false,"no_images")
        check(good["proposed_mega_form_id"] as? String=="gyarados-mega","form")
        check(good["human_pair_claim_reviewed"] as? Bool==true,"human_review")
        check(good["label_independently_verified"] as? Bool==false,"human_not_cert")
        check(good["held_out_accuracy"] as? String=="NOT_MEASURED","no_accuracy")
        check(good["width"] as? Int==512,"pixel_geometry")
        do {
            _=try R656MegaVisionPair.compare(before:a,after:a,
                proposedMegaID:"gyarados-mega",manuallyReviewed:false)
            fatalError("IDENTICAL_SHOULD_FAIL")
        }catch let e as R656MegaVisionPair.Failure {
            check(e.description=="HOLD_IDENTICAL_IMAGE","duplicate_guard")
        }
        do {
            _=try R656MegaVisionPair.compare(before:a,after:c,
                proposedMegaID:"gyarados-mega",manuallyReviewed:false)
            fatalError("GEOMETRY_SHOULD_FAIL")
        }catch let e as R656MegaVisionPair.Failure {
            check(e.description=="HOLD_GEOMETRY_MISMATCH","geometry_guard")
        }
        do {
            _=try R656MegaVisionPair.compare(before:a,after:b,
                proposedMegaID:"mewtwo-mega-x",manuallyReviewed:false)
            fatalError("UNREGISTERED_SHOULD_FAIL")
        }catch let e as R656MegaVisionPair.Failure {
            check(e.description=="HOLD_UNKNOWN_MEGA_FORM","registry_guard")
        }
        do {
            _=try R656MegaVisionPair.compare(before:Data([1,2,3]),after:b,
                proposedMegaID:"gyarados-mega",manuallyReviewed:false)
            fatalError("PNG_SHOULD_FAIL")
        }catch let e as R656MegaVisionPair.Failure {
            check(e.description=="HOLD_INVALID_PNG","png_guard")
        }
        print("R656_REAL_VISION_FEATURE_TEST_PASS",count)
    }
}
