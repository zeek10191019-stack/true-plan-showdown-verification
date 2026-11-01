import Foundation
#if canImport(ImageIO) && canImport(CoreGraphics)
import ImageIO
import CoreGraphics
#endif

// R625: decode ORIGINAL archive PNG; R626: locate long, colored pixel runs;
// R627: match unverified OCR fractions/percent to visible color runs and track
// stable image locations; R628: collect unlabelled sprite-window fingerprints.
// No such geometric signal certifies own/opponent, HP, status, Mega, or form.
enum R625R628PixelHUDAndSprite {
    static let embeddedKey = "r625_r628_embedded_pixel_probe_report"
    static let memberName = R617R620RotationReadout.memberName
    static let maxFrames = 2
    static let maxPNGBytes = 8_000_000
    static let maxJSONBytes = 110_000
    private static let flags = ["certified_for_battle", "owner_verified", "roi_verified",
                                "mega_verified", "display_orientation_verified"]

    static func validRect(_ rect:[String:Any]) -> (Double,Double,Double,Double)? {
        guard let x=rect["x"] as? Double,let y=rect["y"] as? Double,
              let w=rect["width"] as? Double,let h=rect["height"] as? Double,
              [x,y,w,h].allSatisfy({$0.isFinite}),x>=0,y>=0,w>0,h>0,
              x+w<=1.000001,y+h<=1.000001 else {return nil}
        return (x,y,w,h)
    }
    private static func hold(_ obj:[String:Any]) -> Bool {
        flags.allSatisfy({obj[$0] as? Bool == false})
    }
    private static func sha(_ s:String) -> Bool {
        s.utf8.count==64 && s.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)})
    }
    private static func safePNG(_ s:String) -> Bool {
        !s.isEmpty && s.utf8.count<=160 && s.hasSuffix(".png") &&
        !s.hasPrefix("/") && !s.contains("..") && !s.contains("\\") &&
        !s.contains("//") && s.utf8.allSatisfy({$0>=32 && $0 != 127})
    }
    private static func document(_ entries:[R548ResearchArchive.Entry],_ name:String)->[String:Any]? {
        guard let data=entries.first(where:{$0.name==name})?.bytes,data.count<=160_000,
              let value=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else {return nil}
        return value
    }
    private static func role(_ r:[String:Any])->(Int64,Int64,String,String)? {
        guard let e=r["epoch"] as? Int64,e>0,
              let f=r["frame_id"] as? Int64,f>0,
              let name=r["archive_png"] as? String,safePNG(name),
              let hash=r["original_png_sha256"] as? String,sha(hash) else {return nil}
        return (e,f,name,hash)
    }

    // Pure pixel entry point. The Linux fixture invokes this directly;
    // iPhoneOS calls it only on verified, decoded real PNG bytes.
    static func probeRGBA(_ pixels:[UInt8],width:Int,height:Int)->[[String:Any]] {
        guard width>=64,height>=32,width<=512,height<=512,
              pixels.count==width*height*4 else{return []}
        struct Run {var x:Int;var y:Int;var width:Int;var color:String}
        var runs=[Run]()
        let minLen=max(12,Int(Double(width)*0.035))
        for y in 0..<height {
            var x=0
            while x<width {
                let i=(y*width+x)*4
                let r=Int(pixels[i]),g=Int(pixels[i+1]),b=Int(pixels[i+2])
                func kind(_ r:Int,_ g:Int,_ b:Int)->String? {
                    if g>=85 && g-r>=26 && g-b>=18 {return "GREEN_LIKE"}
                    if r>=132 && g>=103 && b<=117 && r-b>=34 {return "YELLOW_LIKE"}
                    if r>=103 && r-g>=42 && r-b>=35 {return "RED_LIKE"}
                    return nil
                }
                guard let c=kind(r,g,b) else {x+=1;continue}
                let start=x
                while x<width {
                    let j=(y*width+x)*4
                    if kind(Int(pixels[j]),Int(pixels[j+1]),Int(pixels[j+2])) != c {break}
                    x+=1
                }
                let len=x-start
                if len>=minLen && len <= Int(Double(width)*0.94) {
                    runs.append(Run(x:start,y:y,width:len,color:c))
                }
            }
        }
        // Merge identical horizontal bands across consecutive bitmap scan-lines.
        struct Band {var minX:Int;var maxX:Int;var minY:Int;var maxY:Int;var color:String}
        var bands=[Band]()
        for line in runs {
            let left=line.x,right=line.x+line.width
            var found:Int?=nil
            for i in bands.indices.reversed() {
                let q=bands[i]
                if q.color != line.color || q.maxY != line.y-1 {continue}
                let overlap=max(0,min(right,q.maxX)-max(left,q.minX))
                if overlap >= Int(Double(min(right-left,q.maxX-q.minX))*0.72) {
                    found=i;break
                }
            }
            if let i=found {
                bands[i].minX=min(bands[i].minX,left)
                bands[i].maxX=max(bands[i].maxX,right)
                bands[i].maxY=line.y
            } else {
                bands.append(Band(minX:left,maxX:right,minY:line.y,maxY:line.y,color:line.color))
            }
        }
        var output=[[String:Any]]()
        for b in bands where b.maxY-b.minY+1>=2 && b.maxY-b.minY+1<=height/9 {
            let w=b.maxX-b.minX,h=b.maxY-b.minY+1
            if Double(w)/Double(max(1,h)) < 3.0 {continue}
            output.append(["rect_top_left_norm":[
                 "x":Double(b.minX)/Double(width),"y":Double(b.minY)/Double(height),
                 "width":Double(w)/Double(width),"height":Double(h)/Double(height)],
                 "color_class":b.color,"confirmed_hud":false,
                 "owner":"UNKNOWN","source":"ORIGINAL_PNG_PIXELS_NOT_GAME_ROLE"])
        }
        return Array(output.sorted { a,b in
            let ra=a["rect_top_left_norm"] as! [String:Double]
            let rb=b["rect_top_left_norm"] as! [String:Double]
            return (ra["y"] ?? 0)<(rb["y"] ?? 0)
        }.prefix(20))
    }
    private static func fingerprints(_ pixels:[UInt8],width:Int,height:Int)->[[String:Any]] {
        // These are generic image windows, NOT certified Pokémon sprite ROIs.
        let windows:[(String,Double,Double,Double,Double)] = [
            ("RAW_LOWER_LEFT_PROPOSAL",0.05,0.40,0.42,0.53),
            ("RAW_UPPER_RIGHT_PROPOSAL",0.53,0.04,0.42,0.52)]
        return windows.map {name,x,y,w,h in
            var values=[Int]()
            for row in 0..<8 {
                for col in 0..<9 {
                    let px=min(width-1,max(0,Int((x+w*(Double(col)+0.5)/9)*Double(width))))
                    let py=min(height-1,max(0,Int((y+h*(Double(row)+0.5)/8)*Double(height))))
                    let i=(py*width+px)*4
                    let red = Int(pixels[i])
                    let green = Int(pixels[i + 1])
                    let blue = Int(pixels[i + 2])
                    values.append((red*299 + green*587 + blue*114)/1000)
                }
            }
            var bits:UInt64=0
            for row in 0..<8 {
                for col in 0..<8 {
                    bits=(bits<<1) | (values[row*9+col]>values[row*9+col+1] ? 1 : 0)
                }
            }
            return ["window_proposal":name,"dhash64":String(format:"%016llx",bits),
                    "pixel_origin":"TOP_LEFT_UNCALIBRATED",
                    "species":"UNKNOWN","mega_form":"UNKNOWN",
                    "reference_catalog_matched":false]
        }
    }
    static func scanPixels(_ pixels:[UInt8],width:Int,height:Int)->[String:Any] {
        guard width>=64,height>=32,width<=512,height<=512,
              pixels.count==width*height*4 else {
            return ["status":"HOLD_PIXEL_BUFFER_INVALID","colored_runs":[[String:Any]](),
                    "sprite_window_fingerprints":[[String:Any]]()]
        }
        return ["status":"HOLD_PIXELS_DECODED_NOT_CALIBRATED",
                "bitmap_width":width,"bitmap_height":height,
                "colored_runs":probeRGBA(pixels,width:width,height:height),
                "sprite_window_fingerprints":fingerprints(pixels,width:width,height:height)]
    }
    static func decodePNG(_ data:Data)->[String:Any] {
        #if canImport(ImageIO) && canImport(CoreGraphics)
        guard data.count<=maxPNGBytes,
              let source=CGImageSourceCreateWithData(data as CFData,nil),
              CGImageSourceGetCount(source)==1,
              let image=CGImageSourceCreateImageAtIndex(source,0,nil),
              image.width>=64,image.height>=32,
              image.width*image.height<=24_000_000 else {
            return ["status":"HOLD_IMAGE_DECODE_FAILED"]
        }
        let scale=min(1.0,min(384.0/Double(image.width),256.0/Double(image.height)))
        let width=max(64,Int(Double(image.width)*scale))
        let height=max(32,Int(Double(image.height)*scale))
        guard width<=512,height<=512,
              let colors=CGColorSpace(name:CGColorSpace.sRGB),
              let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,
                 bytesPerRow:width*4,space:colors,
                 bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue)
                            .union(.byteOrder32Big)),
              let buffer=context.data else {
            return ["status":"HOLD_RGBA_CONVERSION_FAILED"]
        }
        context.interpolationQuality = .high
        context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
        let rgba=Array(UnsafeBufferPointer(start:buffer.assumingMemoryBound(to:UInt8.self),
                                            count:width*height*4))
        var result=scanPixels(rgba,width:width,height:height)
        result["source_width"]=image.width
        result["source_height"]=image.height
        return result
        #else
        return ["status":"HOLD_IMAGEIO_UNAVAILABLE"]
        #endif
    }
    static func visualMatches(_ observations:[[String:Any]],_ runs:[[String:Any]])->[[String:Any]] {
        var matches=[[String:Any]]()
        for (oi,tok) in observations.enumerated() {
            guard let orientation=tok["orientation_hypothesis"] as? String,
                  orientation=="UP", // no unverified 90-degree transformation promoted
                  let kind=tok["kind"] as? String,
                  ["FRACTION_HP_OR_PP_UNASSIGNED","PERCENT_HP_OR_OTHER_UNASSIGNED"].contains(kind),
                  let r=tok["normalized_rect_in_hypothesis"] as? [String:Any],
                  let box=validRect(r) else {continue}
            for (pi,p) in runs.enumerated() {
                guard let raw=p["rect_top_left_norm"] as? [String:Any],
                      let b=validRect(raw) else {continue}
                let overlap=max(0,min(box.0+box.2,b.0+b.2)-max(box.0,b.0))
                guard overlap>=0.12*min(box.2,b.2) else {continue}
                let vision=box.1+box.3/2
                let rawTop=b.1+b.3/2
                for (hyp,cy) in [("UNVERIFIED_UP_Y_SAME",rawTop),
                                 ("UNVERIFIED_UP_Y_INVERTED",1-rawTop)] {
                    if abs(vision-cy)<=0.13 {
                        matches.append(["ocr_index":oi,"pixel_run_index":pi,
                           "coordinate_hypothesis":hyp,
                           "hypothesis_only":"COLOR_BAR_NEAR_HP_OR_PP_LIKE_TEXT",
                           "owner":"UNKNOWN","exact_hp_certified":false])
                    }
                    if matches.count>=24{return matches}
                }
            }
        }
        return matches
    }
    static func beforeZip(_ entries:[R548ResearchArchive.Entry])->[R548ResearchArchive.Entry] {
        let names=entries.map(\.name)
        guard entries.count<=R548ResearchArchive.maximumMembers,
              names.count==Set(names).count,
              names.contains(memberName) else{return entries}
        var status="HOLD_SOURCE_MISSING_OR_CONTRADICTORY"
        var frames=[[String:Any]]()
        if let prior=document(entries,memberName),
           prior["schema"] as? String == "trueplan.r617-r620.rotation_readout.v1",
           prior[embeddedKey] == nil,
           let doc=prior["r621_r624_embedded_candidate_report"] as? [String:Any],
           let raw=document(entries,"r608_original_pixel_evidence.json"),
           doc["schema"] as? String == "trueplan.r621-r624.visual_candidate_slots.v1",
           raw["schema"] as? String == "trueplan.r608.raw_png_visual_evidence.v1",
           hold(doc),hold(raw),
           doc["status"] as? String == "HOLD_UI_SLOTS_REQUIRE_LABELED_GAME_FRAMES",
           let rows=doc["r622_ui_slot_hypotheses"] as? [[String:Any]],
           let bindings=raw["bindings"] as? [[String:Any]],
           rows.count<=maxFrames {
            status="HOLD_PIXEL_LOCATIONS_NOT_GROUND_TRUTH"
            var ids=Set<String>(),names=Set<String>(),hashes=Set<String>()
            for row in rows {
                guard let f=role(row),ids.insert("\(f.0):\(f.1)").inserted,
                      names.insert(f.2).inserted,hashes.insert(f.3).inserted,
                      let original=bindings.first(where:{role($0)?.0==f.0 && role($0)?.1==f.1}),
                      let b=role(original),b.2==f.2,b.3==f.3,
                      original["decoded_pixels_verified"] as? Bool==true,
                      original["png_ihdr_crc_verified"] as? Bool==true,
                      let image=entries.first(where:{$0.name==f.2}),
                      image.bytes.count<=maxPNGBytes,
                      R598OneButtonFormAttachment.testDigest(image.bytes)==f.3,
                      let observations=row["observations"] as? [[String:Any]],
                      observations.count<=48 else {
                    status="HOLD_ORIGINAL_PIXEL_FRAME_OR_OCR_CONTRADICTION"
                    frames=[];break
                }
                let decoded=decodePNG(image.bytes)
                let runs=decoded["colored_runs"] as? [[String:Any]] ?? []
                let neighbors=visualMatches(observations,runs)
                frames.append(["epoch":f.0,"frame_id":f.1,"archive_png":f.2,
                     "original_png_sha256":f.3,"pixel_probe":decoded,
                     "ocr_color_proximity_hypotheses":neighbors,
                     "owner":"UNKNOWN","opponent":"UNKNOWN","mega_form":"UNKNOWN"])
            }
        }
        // A compact temporal comparison of the same unlabelled proposed image windows.
        var temporal=[[String:Any]]()
        if frames.count==2,
           let a=frames[0]["pixel_probe"] as? [String:Any],
           let b=frames[1]["pixel_probe"] as? [String:Any],
           let first=a["sprite_window_fingerprints"] as? [[String:Any]],
           let second=b["sprite_window_fingerprints"] as? [[String:Any]] {
            for x in first {
                guard let name=x["window_proposal"] as? String,
                      let before=x["dhash64"] as? String,
                      let next=second.first(where:{$0["window_proposal"] as? String==name}),
                      let after=next["dhash64"] as? String,
                      let old=UInt64(before,radix:16),let new=UInt64(after,radix:16) else{continue}
                temporal.append(["window_proposal":name,"dhash_hamming_distance":
                                 (old ^ new).nonzeroBitCount,
                                 "interpretation":"UNVERIFIED_VISUAL_CHANGE_NOT_MEGA_EVOLUTION"])
            }
        }
        let report:[String:Any]=[
            "schema":"trueplan.r625-r628.pixel_hud_sprite_probes.v1",
            "status":status,"frames":frames,"r628_temporary_sprite_dhash":temporal,
            "r625_source":"ARCHIVED_ORIGINAL_PNG_PIXELS",
            "r626_paint_detection":"PIXEL_COLOR_RUNS_ARE_NOT_CERTIFIED_HP_BARS",
            "r627_spatial_association":"OCR_TEXT_NEAR_COLOR_RUNS_NOT_OWN_OPP_HUD",
            "r628_form_reference":"NOT_SUPPLIED; NO_SPECIES_OR_MEGA_INFERENCE",
            "required_for_certification":["orientation_ground_truth","labelled_own_and_opponent_rois",
              "reference_sprite_catalogue","real_game_frame_truth_labels"],
            "certified_for_battle":false,"owner_verified":false,"roi_verified":false,
            "mega_verified":false,"display_orientation_verified":false,
            "coverage":["target_fields":79,"certified_fields":0],
            "limitations":"Color bars and sprite window hashes are real pixel probes, not actor/HP/status/Mega labels."
        ]
        guard var prior=document(entries,memberName),prior[embeddedKey] == nil else {return entries}
        prior[embeddedKey]=report
        guard let data=try? JSONSerialization.data(withJSONObject:prior,options:[.sortedKeys]),
              data.count<=maxJSONBytes else{return entries}
        return entries.map { item in
            item.name == memberName ? .init(name:item.name,bytes:data) : item
        }
    }
    static func containsReport(_ entries:[R548ResearchArchive.Entry])->Bool {
        guard let r=document(entries,memberName),
              let p=r[embeddedKey] as? [String:Any] else{return false}
        return p["schema"] as? String=="trueplan.r625-r628.pixel_hud_sprite_probes.v1" &&
               p["certified_for_battle"] as? Bool == false &&
               p["owner_verified"] as? Bool == false &&
               p["mega_verified"] as? Bool == false
    }
}
