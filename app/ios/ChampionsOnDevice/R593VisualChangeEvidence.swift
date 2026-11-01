import Foundation

/// Bounded *actual pixel* evidence from historical frames. It records localized
/// image changes, NOT a certified species, Mega evolution, side or turn.
enum R593VisualChangeEvidence {
    static let schema = "trueplan.r593.historical-visual-change.v1"
    private static let cellsX = 8, cellsY = 6
    private static let windows: [(String,Double,Double,Double,Double)] = [
        ("MEMORY_LEFT_ACTOR_REGION_HYPOTHESIS", 0.06,0.60,0.30,0.80),
        ("MEMORY_RIGHT_ACTOR_REGION_HYPOTHESIS",0.60,0.78,0.35,0.82),
        ("MEMORY_UPPER_BACKGROUND_REFERENCE",0.36,0.68,0.04,0.23)
    ]
    private static func hashOK(_ s:String)->Bool {
        s.utf8.count == 64 && s.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
    static func unavailable(epoch:Int64,frame:Int64,observedMs:Int64,imageSHA:String,
                            reason:String)->[String:Any] {
        ["schema":schema,"status":"HOLD_PIXEL_BUFFER_UNAVAILABLE",
         "hold_reason":reason,"epoch":epoch,"frame_id":frame,
         "observed_ms_monotonic":observedMs,"image_sha256":imageSHA,
         "regions":[[String:Any]](),"current_state_eligible":false,
         "mega_visual_form_certified":false,"owner_certified":false,
         "automatic_upload":false]
    }
    /// Sampling on fixed 8x6 tiles with four pixels/tile. RGBA memory raster row
    /// order is unknown; windows refer to MEMORY coordinates, not displayed role.
    static func capture(pixels:[UInt8],width:Int,height:Int,rowBytes:Int,
                        epoch:Int64,frame:Int64,observedMs:Int64,imageSHA:String)->[String:Any] {
        guard width>=256,height>=192,width<=4096,height<=4096,
              rowBytes>=width*4,rowBytes<=width*4+4096,
              rowBytes<=64*1024*1024/height,
              pixels.count==rowBytes*height,epoch>0,frame>0,observedMs>0,
              hashOK(imageSHA) else {
            return unavailable(epoch:epoch,frame:frame,observedMs:observedMs,
                imageSHA:imageSHA,reason:"INVALID_GEOMETRY_OR_PROVENANCE")
        }
        var regions=[[String:Any]]()
        for (name,x0,x1,y0,y1) in windows {
            var samples=[Int]()
            for cy in 0..<cellsY {for cx in 0..<cellsX {
                var sums=[0,0,0],used=0
                for dy in [0.28,0.72] {for dx in [0.28,0.72] {
                    let u=x0+(x1-x0)*(Double(cx)+(dx))/Double(cellsX)
                    let v=y0+(y1-y0)*(Double(cy)+(dy))/Double(cellsY)
                    let px=min(width-1,max(0,Int(Double(width)*u)))
                    let py=min(height-1,max(0,Int(Double(height)*v)))
                    let i=py*rowBytes+px*4
                    guard pixels[i+3]>160 else {continue}
                    for k in 0..<3 {sums[k]+=Int(pixels[i+k])}
                    used+=1
                }}
                // -1 means transparent/incomplete, never a black pixel.
                for k in 0..<3 {samples.append(used>0 ? sums[k]/used : -1)}
            }}
            regions.append(["name":name,"samples_rgb":samples,
                            "tile_count":cellsX*cellsY,"coordinate_space":"RGBA_MEMORY_ROW_ORDER_UNVERIFIED"])
        }
        return ["schema":schema,"status":"HISTORICAL_PIXEL_SAMPLES_ONLY",
                "epoch":epoch,"frame_id":frame,"observed_ms_monotonic":observedMs,
                "image_sha256":imageSHA,"image_width":width,"image_height":height,
                "regions":regions,"color_space":"UNVERIFIED_RENDERED_RGBA",
                "owner_certified":false,"mega_visual_form_certified":false,
                "current_state_eligible":false,"automatic_upload":false]
    }
    private static func reject(_ reason:String)->[String:Any] {
        ["schema":schema,"status":"HOLD_INVALID_FRAME_SEQUENCE",
         "hold_reason":reason,"frame_count":0,"pairs":[[String:Any]](),
         "owner_certified":false,"mega_visual_form_certified":false,
         "current_state_eligible":false,"automatic_upload":false]
    }
    private static func sampleMap(_ frame:[String:Any])->[String:[Int]]? {
        guard let rows=frame["regions"] as? [[String:Any]],rows.count==windows.count else {return nil}
        var result=[String:[Int]]()
        for row in rows {
            guard let name=row["name"] as? String,
                  windows.contains(where:{$0.0==name}),
                  let vals=row["samples_rgb"] as? [Int],vals.count==cellsX*cellsY*3,
                  vals.allSatisfy({$0 >= -1 && $0<=255}),
                  result[name]==nil else{return nil}
            result[name]=vals
        }
        return result.count==windows.count ? result : nil
    }
    private static func changedTiles(_ a:[Int],_ b:[Int])->(Int,Int) {
        var eligible=0,changed=0
        for index in 0..<(cellsX*cellsY) {
            let offset=index*3
            let aa=Array(a[offset..<(offset+3)]),bb=Array(b[offset..<(offset+3)])
            if aa.contains(-1) || bb.contains(-1) {continue}
            eligible+=1
            if zip(aa,bb).map({abs($0-$1)}).reduce(0,+) >= 75 {changed+=1}
        }
        return (changed,eligible)
    }
    /// Between-frame change is evidence of motion/visual appearance only.
    /// Any significant background change blocks localization (camera/effects/UI).
    static func timeline(_ frames:[[String:Any]])->[String:Any] {
        guard frames.count<=8 else {return reject("FRAME_LIMIT")}
        var rows=[[String:Any]](),seen=Set<String>()
        var prior:[String:Any]?=nil,priorSamples:[String:[Int]]?=nil
        for f in frames {
            guard f["schema"] as? String==schema,
                  let ep=f["epoch"] as? Int64,let id=f["frame_id"] as? Int64,
                  let ms=f["observed_ms_monotonic"] as? Int64,
                  let sha=f["image_sha256"] as? String,
                  ep>0,id>0,ms>0,hashOK(sha),
                  f["owner_certified"] as? Bool == false,
                  f["current_state_eligible"] as? Bool == false,
                  f["mega_visual_form_certified"] as? Bool == false,
                  seen.insert("\(ep):\(id)").inserted,
                  let status=f["status"] as? String,
                  ["HISTORICAL_PIXEL_SAMPLES_ONLY","HOLD_PIXEL_BUFFER_UNAVAILABLE"].contains(status)
            else {return reject("SOURCE_SCHEMA_OR_FRAME_PROVENANCE")}
            let currentSamples=status=="HISTORICAL_PIXEL_SAMPLES_ONLY" ? sampleMap(f) : nil
            if status=="HISTORICAL_PIXEL_SAMPLES_ONLY" && currentSamples==nil {
                return reject("MALFORMED_PIXEL_SAMPLES")
            }
            if let old=prior {
                guard let oldEpoch=old["epoch"] as? Int64,
                      let oldFrame=old["frame_id"] as? Int64,
                      let oldMs=old["observed_ms_monotonic"] as? Int64,
                      ep>=oldEpoch,ep != oldEpoch || id>oldFrame,
                      ep != oldEpoch || ms>oldMs else {
                    return reject("NON_MONOTONIC_CAPTURE_ORDER")
                }
                var result="HOLD_CROSS_EPOCH_OR_MISSING_PIXELS"
                var regionChanges=[[String:Any]]()
                if ep==oldEpoch,let p=priorSamples,let c=currentSamples,
                   f["image_width"] as? Int==old["image_width"] as? Int,
                   f["image_height"] as? Int==old["image_height"] as? Int {
                    var all=[String:(Int,Int)]()
                    for (name,_,_,_,_) in windows {
                        guard let before=p[name],let after=c[name] else{return reject("INCOMPLETE_REGION_SET")}
                        all[name]=changedTiles(before,after)
                    }
                    let reference=all["MEMORY_UPPER_BACKGROUND_REFERENCE"]!
                    let bgMotion=reference.1<24 || reference.0*4>reference.1
                    result=bgMotion ? "HOLD_GLOBAL_BACKGROUND_OR_CAMERA_CHANGE" :
                        "LOCALIZED_VISUAL_CHANGE_CANDIDATES_ONLY"
                    for (name,_,_,_,_) in windows {
                        let metric=all[name]!
                        regionChanges.append(["region":name,"changed_tiles":metric.0,
                                              "eligible_tiles":metric.1,
                                              "motion_fraction":metric.1>0 ? Double(metric.0)/Double(metric.1):NSNull() as Any,
                                              "change_is_certified_event":false])
                    }
                }
                rows.append(["epoch":ep,"from_frame_id":oldFrame,"to_frame_id":id,
                             "from_sha256":old["image_sha256"]!,"to_sha256":sha,
                             "status":result,"regions":regionChanges,
                             "mega_evolution_confirmed":false,"switch_confirmed":false,
                             "owner":"UNKNOWN"])
            }
            prior=f;priorSamples=currentSamples
        }
        return ["schema":schema,"status":"HISTORICAL_VISUAL_CHANGE_AUDIT_ONLY",
                "frame_count":frames.count,"pair_count":rows.count,"pairs":rows,
                "owner_certified":false,"mega_visual_form_certified":false,
                "current_state_eligible":false,"automatic_upload":false,
                "limits":"PIXEL_DIFFERENCE_NOT_SPECIES_OR_MEGA_PROOF; MEMORY_ROW_ORDER_UNVERIFIED"]
    }
}
