import Foundation

/// Historical, uncalibrated visual descriptors from the SAME raster already used
/// by the OCR/pixel audit. A silhouette change is NEVER evidence of Mega identity.
enum R594ActorAppearance {
    static let schema = "trueplan.r594.historical-actor-appearance.v1"
    private static let columns = 16, rows = 12
    private static let bounds: [(String,Double,Double,Double,Double)] = [
        ("MEMORY_LEFT_ACTOR_HYPOTHESIS", 0.06,0.60,0.30,0.80),
        ("MEMORY_RIGHT_ACTOR_HYPOTHESIS",0.60,0.78,0.35,0.82),
        ("MEMORY_BACKGROUND_REFERENCE",0.36,0.68,0.04,0.23)
    ]
    private static func validHash(_ text:String)->Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
    static func unavailable(epoch:Int64,frame:Int64,ms:Int64,sha:String,reason:String)->[String:Any] {
        ["schema":schema,"status":"HOLD_RASTER_UNAVAILABLE","reason":reason,
         "epoch":epoch,"frame_id":frame,"observed_ms_monotonic":ms,
         "image_sha256":sha,"regions":[[String:Any]](),
         "owner_certified":false,"species_certified":false,"mega_certified":false,
         "current_state_eligible":false,"automatic_upload":false]
    }
    static func capture(pixels:[UInt8],width:Int,height:Int,rowBytes:Int,
                        epoch:Int64,frame:Int64,ms:Int64,sha:String)->[String:Any] {
        guard width>=256,height>=192,width<=4096,height<=4096,
              rowBytes>=width*4,rowBytes<=width*4+4096,
              rowBytes<=64*1024*1024/height,pixels.count==rowBytes*height,
              epoch>0,frame>0,ms>0,validHash(sha) else {
            return unavailable(epoch:epoch,frame:frame,ms:ms,sha:sha,
                               reason:"INVALID_RASTER_OR_PROVENANCE")
        }
        var regionRows=[[String:Any]]()
        for (name,x0,x1,y0,y1) in bounds {
            var luma=[Int](),transparent=0
            for y in 0..<rows {for x in 0..<columns {
                let u=x0+(x1-x0)*(Double(x)+0.5)/Double(columns)
                let v=y0+(y1-y0)*(Double(y)+0.5)/Double(rows)
                let xx=min(width-1,max(0,Int(Double(width)*u)))
                let yy=min(height-1,max(0,Int(Double(height)*v)))
                let k=yy*rowBytes+xx*4
                guard pixels[k+3]>=160 else {
                    luma.append(-1);transparent+=1;continue
                }
                // Integer approximation for sRGB Y; no assertion of calibrated color.
                let yValue=(77*Int(pixels[k])+150*Int(pixels[k+1])+29*Int(pixels[k+2]))>>8
                luma.append(yValue)
            }}
            regionRows.append(["name":name,"luma_grid":luma,
                               "transparent_samples":transparent,
                               "grid_width":columns,"grid_height":rows,
                               "coordinate_space":"RGBA_MEMORY_ROW_ORDER_UNVERIFIED"])
        }
        return ["schema":schema,"status":"HISTORICAL_APPEARANCE_SAMPLES_ONLY",
                "epoch":epoch,"frame_id":frame,"observed_ms_monotonic":ms,
                "image_sha256":sha,"image_width":width,"image_height":height,
                "regions":regionRows,"owner_certified":false,"species_certified":false,
                "mega_certified":false,"current_state_eligible":false,"automatic_upload":false]
    }
    private static func reject(_ reason:String)->[String:Any] {
        ["schema":schema,"status":"HOLD_INVALID_SEQUENCE","reason":reason,
         "pairs":[[String:Any]](),"owner_certified":false,"species_certified":false,
         "mega_certified":false,"current_state_eligible":false,"automatic_upload":false]
    }
    private static func grids(_ frame:[String:Any])->[String:[Int]]? {
        guard let list=frame["regions"] as? [[String:Any]],list.count==bounds.count else {return nil}
        var output=[String:[Int]]()
        for entry in list {
            guard let name=entry["name"] as? String,
                  bounds.contains(where:{$0.0==name}),output[name]==nil,
                  entry["grid_width"] as? Int==columns,
                  entry["grid_height"] as? Int==rows,
                  let vals=entry["luma_grid"] as? [Int],vals.count==columns*rows,
                  vals.allSatisfy({(-1...255).contains($0)}),
                  let missing=entry["transparent_samples"] as? Int,
                  missing==vals.filter({$0 == -1}).count,
                  entry["coordinate_space"] as? String=="RGBA_MEMORY_ROW_ORDER_UNVERIFIED"
            else{return nil}
            output[name]=vals
        }
        return output.count==bounds.count ? output : nil
    }
    private static func stats(_ a:[Int],_ b:[Int])->(Int,Int,Int,Int) {
        let good=zip(a,b).filter({$0.0>=0 && $0.1>=0})
        if good.isEmpty{return (0,0,0,0)}
        let left=good.map{$0.0},right=good.map{$0.1}
        let meanA=left.reduce(0,+)/left.count,meanB=right.reduce(0,+)/right.count
        let raw=good.reduce(0){$0+abs($1.0-$1.1)}/good.count
        let shape=good.reduce(0){$0+abs(($1.0-meanA)-($1.1-meanB))}/good.count
        let spanA=(left.max() ?? 0)-(left.min() ?? 0)
        let spanB=(right.max() ?? 0)-(right.min() ?? 0)
        return (good.count,raw,shape,min(spanA,spanB))
    }
    /// All comparisons are *candidate evidence*; no species, switch or Mega claim.
    static func timeline(_ frames:[[String:Any]])->[String:Any] {
        guard frames.count<=8 else {return reject("FRAME_LIMIT")}
        var previous:[String:Any]?=nil,previousGrids:[String:[Int]]?=nil
        var seen=Set<String>(),pairs=[[String:Any]]()
        for frame in frames {
            guard frame["schema"] as? String==schema,
                  let epoch=frame["epoch"] as? Int64,epoch>0,
                  let id=frame["frame_id"] as? Int64,id>0,
                  let ms=frame["observed_ms_monotonic"] as? Int64,ms>0,
                  let hash=frame["image_sha256"] as? String,validHash(hash),
                  seen.insert("\(epoch):\(id)").inserted,
                  frame["owner_certified"] as? Bool==false,
                  frame["species_certified"] as? Bool==false,
                  frame["mega_certified"] as? Bool==false,
                  frame["current_state_eligible"] as? Bool==false,
                  let status=frame["status"] as? String,
                  ["HISTORICAL_APPEARANCE_SAMPLES_ONLY","HOLD_RASTER_UNAVAILABLE"].contains(status)
            else {return reject("SOURCE_PROVENANCE_OR_CERTIFICATION")}
            let current=status=="HISTORICAL_APPEARANCE_SAMPLES_ONLY" ? grids(frame) : nil
            if status=="HISTORICAL_APPEARANCE_SAMPLES_ONLY" && current==nil {
                return reject("INVALID_APPEARANCE_GRID")
            }
            if let before=previous {
                guard let prevEpoch=before["epoch"] as? Int64,
                      let prevId=before["frame_id"] as? Int64,
                      let prevMS=before["observed_ms_monotonic"] as? Int64,
                      epoch>=prevEpoch,
                      epoch != prevEpoch || (id>prevId && ms>prevMS)
                else {return reject("NON_MONOTONIC_FRAMES")}
                var result="HOLD_CROSS_EPOCH_OR_MISSING_RASTER"
                var actors=[[String:Any]]()
                if epoch==prevEpoch,let old=previousGrids,let now=current,
                   frame["image_width"] as? Int==before["image_width"] as? Int,
                   frame["image_height"] as? Int==before["image_height"] as? Int {
                    guard let bgOld=old["MEMORY_BACKGROUND_REFERENCE"],
                          let bgNow=now["MEMORY_BACKGROUND_REFERENCE"] else {
                        return reject("MISSING_BACKGROUND_REFERENCE")
                    }
                    let background=stats(bgOld,bgNow)
                    let backgroundChanged=background.0<160 || background.1>18 || background.2>16
                    result=backgroundChanged ? "HOLD_BACKGROUND_OR_CAMERA_CHANGE" : "UNCERTIFIED_APPEARANCE_CANDIDATES"
                    for key in ["MEMORY_LEFT_ACTOR_HYPOTHESIS","MEMORY_RIGHT_ACTOR_HYPOTHESIS"] {
                        guard let x=old[key],let y=now[key] else{return reject("MISSING_ACTOR_REGION")}
                        let s=stats(x,y)
                        var verdict="HOLD_BACKGROUND_OR_CAMERA_CHANGE"
                        if !backgroundChanged {
                            if s.0<160 { verdict="HOLD_INCOMPLETE_SAMPLES" }
                            else if s.3<25 { verdict="HOLD_LOW_TEXTURE" }
                            else { verdict=s.2>=19 ? "APPEARANCE_DIFFERENCE_CANDIDATE" : "APPEARANCE_SIMILARITY_CANDIDATE" }
                        }
                        actors.append(["region":key,"status":verdict,
                                       "valid_samples":s.0,"raw_luma_distance":s.1,
                                       "brightness_normalized_distance":s.2,
                                       "min_frame_luma_range":s.3,
                                       "is_species_identity":false,"is_mega_evidence":false])
                    }
                }
                pairs.append(["epoch":epoch,"from_frame_id":before["frame_id"]!,"to_frame_id":id,
                              "from_sha256":before["image_sha256"]!,"to_sha256":hash,
                              "status":result,"actors":actors,
                              "mega_confirmed":false,"switch_confirmed":false,"owner":"UNKNOWN"])
            }
            previous=frame;previousGrids=current
        }
        return ["schema":schema,"status":"HISTORICAL_APPEARANCE_AUDIT_ONLY",
                "pair_count":pairs.count,"pairs":pairs,
                "owner_certified":false,"species_certified":false,
                "mega_certified":false,"current_state_eligible":false,"automatic_upload":false,
                "limitations":"UNREGISTERED_RENDERED_IMAGE_ROIS; COLOR_AND_ANIMATION_AMBIGUOUS; MAX_8_SAVED_FRAMES"]
    }
}
