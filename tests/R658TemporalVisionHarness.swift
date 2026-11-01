import Foundation
import CoreGraphics
import ImageIO

@main struct R658TemporalVisionHarness {
    static var checks = 0
    static func assertTrue(_ ok:Bool,_ name:String) {
        guard ok else {fatalError("R658_VISION_"+name)}
        checks += 1
    }
    static func png(_ shift:Int) -> Data {
        let w=512,h=256
        let cs=CGColorSpaceCreateDeviceRGB()
        let ctx=CGContext(data:nil,width:w,height:h,
            bitsPerComponent:8,bytesPerRow:w*4,space:cs,
            bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red:0.11,green:0.17,blue:0.24,alpha:1))
        ctx.fill(CGRect(x:0,y:0,width:w,height:h))
        for i in 0..<20 {
            ctx.setFillColor(CGColor(red:Double(i%5)/5+0.12,
                 green:Double(i%7)/8+0.1,blue:0.33,alpha:1))
            ctx.fill(CGRect(x:20+i*22+shift,y:50+i%3*32,
                            width:11,height:80))
        }
        let buf=NSMutableData()
        let dest=CGImageDestinationCreateWithData(
            buf,"public.png" as CFString,1,nil)!
        CGImageDestinationAddImage(dest,ctx.makeImage()!,nil)
        assertTrue(CGImageDestinationFinalize(dest),"png_encode")
        return buf as Data
    }
    static func main() throws {
        let frames=(0..<4).map{png($0*3)}
        let positions=[(0,1),(2,3),(0,2),(1,3)]
        var reports=[[String:Any]]()
        for (before,after) in positions {
            reports.append(try R656MegaVisionPair.compare(
                before:frames[before],after:frames[after],
                proposedMegaID:"gyarados-mega",manuallyReviewed:true))
        }
        assertTrue(reports.count==4,"four_pair_measurements")
        let result=R658MegaTemporalGate.audit(reports)
        assertTrue(result["schema"] as? String == R658MegaTemporalGate.schema,"schema")
        assertTrue(result["owner_certified"] as? Bool == false,"owner_hold")
        assertTrue(result["mega_event_certified"] as? Bool == false,"mega_hold")
        assertTrue(result["battle_advice_authorized"] as? Bool == false,"advice_hold")
        assertTrue((result["regions"] as? [[String:Any]])?.count == 4,"region_counts")
        assertTrue(result["original_images_exported"] as? Bool == false,"no_png_export")
        print("R658_REAL_VISION_TEMPORAL_PASS",checks)
    }
}
