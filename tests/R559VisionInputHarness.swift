import Foundation
import CoreGraphics
import CoreVideo
import CryptoKit

/// Literal pixel vectors and injected NSError; no claim that Vision succeeded.
@main struct R559VisionInputHarness {
    enum ProbeFailure: Error {case failed(String)}
    static func main() throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let reportURL=URL(fileURLWithPath:CommandLine.arguments[2])
        var checks=0
        func check(_ value:@autoclosure ()->Bool,_ reason:String)throws {
            guard value() else {throw ProbeFailure.failed(reason)};checks+=1
        }
        func json(_ value:Any)throws->Data {try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys,.withoutEscapingSlashes])}
        func image(_ bytes:[UInt8],_ w:Int,_ h:Int)throws->CGImage {
            guard let space=CGColorSpace(name:CGColorSpace.sRGB),let provider=CGDataProvider(data:Data(bytes) as CFData),
                  let result=CGImage(width:w,height:h,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:w*4,
                    space:space,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                    provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else {throw ProbeFailure.failed("image")}
            return result
        }
        let reds:[UInt8]=[0,1,2,3,4,5,6,10,11,12,13,14,15,16,20,21,22,23,24,25,26,30,31,32,33,34,35,36,40,41,42,43,44,45,46]
        let rgba=reds.flatMap {[$0,UInt8(100),UInt8(200),UInt8(255)]}
        let prepared=try R559VisionInput.prepare(image(rgba,7,5))
        let buffer=prepared.buffer
        try check(CVPixelBufferLockBaseAddress(buffer,.readOnly)==kCVReturnSuccess,"lock prepared pixels")
        guard let base=CVPixelBufferGetBaseAddress(buffer) else {throw ProbeFailure.failed("base")}
        let row=CVPixelBufferGetBytesPerRow(buffer)
        var visible=Data()
        for y in 0..<5 {
            let bytes=base.advanced(by:y*row).assumingMemoryBound(to:UInt8.self)
            for x in 0..<7 {
                let offset=x*4
                try check(Array(UnsafeBufferPointer(start:bytes+offset,count:4)) == [200,100,reds[y*7+x],255],"literal top-to-bottom BGRA grid")
            }
            visible.append(Data(bytes:bytes,count:28))
            if row>28 {try check((28..<row).allSatisfy {bytes[$0]==0},"padding has no allocator bytes")}
        }
        try check(CVPixelBufferUnlockBaseAddress(buffer,.readOnly)==kCVReturnSuccess,"unlock prepared pixels")
        let hash=SHA256.hash(data:visible).map {String(format:"%02x",$0)}.joined()
        try check(prepared.audit.visible_pixel_sha256==hash && prepared.audit.visible_pixel_bytes==140,"visible-only incremental hash")
        try check(prepared.audit.width==7 && prepared.audit.height==5 && !prepared.audit.source_pixel_equality_certified,"same dimensions, no general pixel equality certification")
        let alpha=try R559VisionInput.prepare(image([100,50,0,128],1,1))
        try check(CVPixelBufferLockBaseAddress(alpha.buffer,.readOnly)==kCVReturnSuccess,"lock alpha vector")
        let a=CVPixelBufferGetBaseAddress(alpha.buffer)!.assumingMemoryBound(to:UInt8.self)
        try check(abs(Int(a[0])-127)<=1 && abs(Int(a[1])-177)<=1 && abs(Int(a[2])-227)<=1 && a[3]==255,"premultiplied half-alpha over white, literal vector")
        try check(CVPixelBufferUnlockBaseAddress(alpha.buffer,.readOnly)==kCVReturnSuccess,"unlock alpha vector")
        let work=R551EvidenceWork();work.cancel()
        do {_=try R559VisionInput.prepare(image(rgba,7,5),work:work);throw ProbeFailure.failed("cancelled accepted")}
        catch R551EvidenceWork.Failure.cancelled {checks+=1}
        let underlying=NSError(domain:"TextRecognition.CRImageReaderError",code:0,userInfo:[NSLocalizedDescriptionKey:"PRIVATE_SENTINEL_秘密"])
        let injected=NSError(domain:"Vision/with private path",code:-7,userInfo:[NSUnderlyingErrorKey:underlying,NSLocalizedDescriptionKey:"PRIVATE_SENTINEL_秘密"])
        let sourcePNG=try Data(contentsOf:root.appendingPathComponent("frames/frame_17.png"))
        let failure=R559OCRFailure.report(injected,session:"capture-test",frame:17,epoch:3,observedMs:1200,png:sourcePNG,width:2,height:2)
        let data=try json(failure),text=String(data:data,encoding:.utf8)!
        try check(!text.contains("PRIVATE_SENTINEL") && !text.contains("秘密") && !text.contains("Vision/"),"no raw error descriptions, paths or userInfo")
        try check((failure["error_codes"] as? [[String:Any]])?.count==2 && failure["current_state_eligible"] as? Bool==false,"bounded underlying error codes, no current values")
        var selected=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("selected_evidence.json"))) as! [String:Any]
        selected["research_candidate_envelope"]=NSNull();selected["screen_read_state"]=NSNull();selected["r559_ocr_failure"]=failure
        var entries=[R548ResearchArchive.Entry(name:"selected_evidence.json",bytes:try json(selected))]
        for name in ["capture_manifest.json","frames/frame_17.png"] {entries.append(.init(name:name,bytes:try Data(contentsOf:root.appendingPathComponent(name))))}
        entries=try R551EvidenceIntegrity.appendingIndex(entries,captureSessionID:"capture-test",frame:17,epoch:3,appVersion:"0.5.59",appBuild:"559")
        _=try R548ResearchArchive.write(entries,to:root.appendingPathComponent("r559_failure.zip"))
        let input=try JSONSerialization.jsonObject(with:JSONEncoder().encode(prepared.audit))
        try json(["checks":checks,"scope":"SYNTHETIC_PIXEL_AND_INJECTED_ERROR_ONLY","vision_input":input,"failure":failure,
            "Vision_request_executed":false,"device_certified":false,"game_accuracy_certified":false]).write(to:reportURL)
        print("R559_NATIVE_VISION_INPUT_CHECKS_PASS=\(checks); VISION_EXECUTION_NOT_CERTIFIED")
    }
}
