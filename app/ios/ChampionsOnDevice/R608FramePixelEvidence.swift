import Foundation
#if canImport(ImageIO) && canImport(CoreGraphics)
import ImageIO
import CoreGraphics
#endif

// R608: visually inspect the ORIGINAL PNG bytes listed by R607.
// Pixel aspect and color runs are not the device orientation, actor, HP,
// species, Mega form or a certified screen ROI. No auto-promotion.
enum R608FramePixelEvidence {
    static let memberName = "r608_original_pixel_evidence.json"
    static let maximumImagePixels = 24_000_000
    static let maximumScannedFrames = 8
    private static let pngSignature: [UInt8] = [137,80,78,71,13,10,26,10]

    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        (UInt32(b[i]) << 24) | (UInt32(b[i+1]) << 16) |
        (UInt32(b[i+2]) << 8) | UInt32(b[i+3])
    }
    private static func crc32(_ b: ArraySlice<UInt8>) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for c in b {
            crc ^= UInt32(c)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1
            }
        }
        return ~crc
    }
    private static func pngSize(_ data: Data) -> (Int,Int)? {
        guard data.count >= 33, data.count <= 16*1024*1024 else {return nil}
        let b = [UInt8](data.prefix(33))
        guard Array(b[0..<8]) == pngSignature,
              u32(b,8) == 13, Array(b[12..<16]) == [73,72,68,82],
              crc32(b[12..<29]) == u32(b,29),
              b[26] == 0, b[27] == 0, b[28] <= 1 else {return nil}
        let w = Int(u32(b,16)), h = Int(u32(b,20))
        guard w >= 1, h >= 1, w <= 8192, h <= 8192,
              w <= maximumImagePixels/h else {return nil}
        return (w,h)
    }
    private static func candidateRuns(_ data: Data, width: Int,
                                      height: Int) -> [[String:Any]]? {
        #if canImport(ImageIO) && canImport(CoreGraphics)
        guard let source = CGImageSourceCreateWithData(data as CFData,nil),
              CGImageSourceGetCount(source) == 1,
              let image = CGImageSourceCreateImageAtIndex(source,0,nil),
              image.width == width, image.height == height else {return nil}
        // Limit the scan to 768 pixels across, keeping the ORIGINAL bytes in the ZIP.
        let sw = min(width,768), sh = max(1,Int((Double(sw)*Double(height)/Double(width)).rounded()))
        guard sh <= 8192 else {return nil}
        var pixels = [UInt8](repeating:0,count:sw*sh*4)
        let rendered = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data:raw.baseAddress,width:sw,height:sh,
                bitsPerComponent:8,bytesPerRow:sw*4,
                space:CGColorSpaceCreateDeviceRGB(),
                bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue |
                    CGBitmapInfo.byteOrder32Big.rawValue) else {return false}
            ctx.interpolationQuality = .high
            ctx.draw(image,in:CGRect(x:0,y:0,width:sw,height:sh))
            return true
        }
        guard rendered else {return nil}
        var results=[[String:Any]]()
        let minRun=max(12,sw/20)
        let yStride=max(1,sh/160)
        for y in stride(from:0,to:sh,by:yStride) {
            var start: Int? = nil
            for x in 0...sw {
                var bar=false
                if x < sw {
                    let idx=(y*sw+x)*4
                    let r=Int(pixels[idx]),g=Int(pixels[idx+1]),b=Int(pixels[idx+2])
                    let green=g>110 && g*10>r*13 && g*10>b*12
                    let yellow=r>150 && g>115 && b*4<g*3 && abs(r-g)<105
                    bar=green || yellow
                }
                if bar && start == nil {start=x}
                if !bar, let left=start {
                    if x-left>=minRun && results.count<12 {
                        // These are raw pixel region HYPOTHESES, not battle-HUD ROIs.
                        results.append([
                            "x_norm":Double(left)/Double(sw),
                            "y_norm":Double(y)/Double(sh),
                            "width_norm":Double(x-left)/Double(sw),
                            "height_norm":Double(yStride)/Double(sh),
                            "label":"SATURATED_HORIZONTAL_COLOR_RUN_UNVERIFIED"
                        ])
                    }
                    start=nil
                }
            }
            if results.count>=12 {break}
        }
        return results
        #else
        return nil // Cannot certify decoded pixels without ImageIO.
        #endif
    }
    static func inspect(_ bytes: Data) -> [String:Any] {
        guard let (w,h)=pngSize(bytes) else {
            return ["status":"HOLD_PNG_HEADER_OR_IHDR_INVALID"]
        }
        let aspect = w>h ? "WIDER_THAN_TALL" : (w<h ? "TALLER_THAN_WIDE" : "SQUARE")
        var row:[String:Any] = [
            "raw_width":w,"raw_height":h,"raw_pixel_aspect":aspect,
            "png_ihdr_crc_verified":true,
            "display_orientation_verified":false,
            "owner_verified":false,"roi_verified":false,"mega_verified":false
        ]
        if let runs=candidateRuns(bytes,width:w,height:h) {
            row["status"]="HOLD_PIXEL_CANDIDATES_NEED_VISUAL_CALIBRATION"
            row["decoded_pixels_verified"]=true
            row["unverified_region_candidates"]=runs
        } else {
            row["status"]="HOLD_IMAGE_DECODING_UNAVAILABLE_OR_FAILED"
            row["decoded_pixels_verified"]=false
            row["unverified_region_candidates"]=[[String:Any]]()
        }
        return row
    }
    private static func validName(_ s:String) -> Bool {
        !s.isEmpty && s.utf8.count<=160 && !s.hasPrefix("/") &&
        !s.contains("..") && !s.contains("\\") && !s.contains("//") &&
        s.utf8.allSatisfy{$0>=32 && $0 != 127}
    }
    static func beforeZip(_ entries:[R548ResearchArchive.Entry]) -> [R548ResearchArchive.Entry] {
        let names=entries.map(\.name)
        guard entries.count<R548ResearchArchive.maximumMembers,
              names.count==Set(names).count,
              names.allSatisfy({validName($0)}),
              !names.contains(memberName) else {return entries}
        var rows=[[String:Any]]()
        var status="HOLD_R607_AUDIT_MISSING_OR_INVALID"
        if let evidence=entries.first(where:{$0.name=="r607_frame_provenance_audit.json"}),
           evidence.bytes.count<=96*1024,
           let doc=(try? JSONSerialization.jsonObject(with:evidence.bytes)) as? [String:Any],
           doc["schema"] as? String == "trueplan.r607.byte_provenance_audit.v1",
           doc["certified_for_battle"] as? Bool == false,
           doc["owner_verified"] as? Bool == false,
           let bindings=doc["bindings"] as? [[String:Any]],
           bindings.count<=maximumScannedFrames {
            status="HOLD_VISUAL_OWNER_ROI_AND_ORIENTATION_UNCERTIFIED"
            var seen=Set<String>()
            for row in bindings {
                guard let frame=row["frame_id"] as? Int64,frame>0,
                      let epoch=row["epoch"] as? Int64,epoch>0,
                      let hash=row["source_png_sha256"] as? String,
                      hash.utf8.count==64 else {
                    status="HOLD_R607_BINDING_CONTRACT_INVALID";rows=[];break
                }
                let key="\(epoch):\(frame)"
                guard seen.insert(key).inserted else {
                    status="HOLD_DUPLICATE_FRAME_BINDING";rows=[];break
                }
                var value:[String:Any] = ["epoch":epoch,"frame_id":frame,
                    "original_png_sha256":hash,
                    "frame_identity_verified":false,"owner_verified":false,
                    "display_orientation_verified":false,"roi_verified":false,
                    "species_verified":false,"mega_verified":false]
                if let name=row["archive_png"] as? String,validName(name),
                   row["status"] as? String == "CONTENT_HASH_MATCH_ONLY_NEEDS_FRAME_AND_OWNER_PROOF",
                   let match=entries.first(where:{$0.name==name && $0.name.hasSuffix(".png")}),
                   R598OneButtonFormAttachment.testDigest(match.bytes)==hash {
                    value.merge(inspect(match.bytes)) {_,new in new}
                    value["archive_png"]=name
                } else {
                    value["status"]="HOLD_ARCHIVE_OR_FRAME_HASH_NOT_VERIFIED"
                }
                rows.append(value)
            }
        }
        let report:[String:Any] = [
            "schema":"trueplan.r608.raw_png_visual_evidence.v1",
            "status":status,"certified_for_battle":false,
            "frame_identity_verified":false,"owner_verified":false,
            "display_orientation_verified":false,"roi_verified":false,
            "species_verified":false,"mega_verified":false,
            "bindings":rows,
            "limitations":"Image pixel geometry and uncalibrated color runs do not establish HUD, ownership, device orientation or Mega form"
        ]
        guard let json=try? JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]) else {return entries}
        return entries+[.init(name:memberName,bytes:json)]
    }
}
