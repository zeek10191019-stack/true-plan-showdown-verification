import Foundation

/// R590. Pixel color and historical OCR correlation; never a live battle reading.
/// Colors/regions are uncalibrated visual hypotheses. No owner, HP value, form or
/// display orientation may be certified by these heuristics.
enum R590ColorHUDCorroboration {
    static let schema = "trueplan.r590.historical-three-color-hud-crosscheck.v1"
    static let maxBytes = 64 * 1024 * 1024
    private static let classes = ["GREEN", "YELLOW", "RED"]
    private static let regions:[(String,Double,Double,Double,Double)] = [
        ("LOWER_LEFT_HUD_REGION",0.10,0.33,0.82,0.97),
        ("UPPER_RIGHT_HUD_REGION",0.77,0.96,0.055,0.16)
    ]
    private static func hashOK(_ hash:String)->Bool {
        hash.utf8.count == 64 && hash.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
    private static func colorClass(_ r:Int,_ g:Int,_ b:Int)->String? {
        if g>=115 && r<170 && g*10>r*14 && g*10>b*11 {return "GREEN"}
        if r>=150 && g>=105 && b<130 && r*10>=g*9 && r*10<=g*19 {return "YELLOW"}
        if r>=125 && g<140 && r*10>g*15 && r*10>b*15 {return "RED"}
        return nil
    }
    private static func rejection(_ reason:String)->[String:Any] {
        ["schema":schema,"status":"HOLD_INVALID_PIXEL_INPUT","hold_reason":reason,
         "candidate_count":0,"color_run_candidates":[[String:Any]](),
         "owner_certified":false,"hp_certified":false,
         "orientation_certified":false,"current_state_eligible":false,
         "automatic_upload":false]
    }
    // R591: Group horizontally long color runs into vertically connected, thin
    // components. Separate rows or disconnected UI decorations are NOT bars.
    private struct Run { let left:Int;let right:Int;let y:Int }
    private struct Track {
        var firstY:Int;var lastY:Int;var lastLeft:Int;var lastRight:Int
        var left:Int;var right:Int;var minWidth:Int;var pixelSum:Int;var rows:Int
        init(_ r:Run) {
            firstY=r.y;lastY=r.y;lastLeft=r.left;lastRight=r.right
            left=r.left;right=r.right;minWidth=r.right-r.left
            pixelSum=r.right-r.left;rows=1
        }
        mutating func append(_ r:Run) {
            lastY=r.y;lastLeft=r.left;lastRight=r.right
            left=min(left,r.left);right=max(right,r.right)
            minWidth=min(minWidth,r.right-r.left)
            pixelSum+=r.right-r.left;rows+=1
        }
    }
    private static func shape(_ pixels:[UInt8],width:Int,height:Int,rowBytes:Int,
                              bounds:(Double,Double,Double,Double),color:String,
                              flipped:Bool) -> (Track,Int)? {
        let (x0,x1,y0,y1)=bounds
        let left=max(0,Int(Double(width)*x0)),right=min(width,Int(Double(width)*x1))
        let top=max(0,Int(Double(height)*y0)),bottom=min(height,Int(Double(height)*y1))
        guard right>left,bottom>top else {return nil}
        let minRun=max(12,Int(Double(width)*0.026))
        var active:Track?=nil, accepted=[Track]()
        func rowRun(_ y:Int)->Run? {
            let iy=flipped ? height-1-y : y
            var best=0,bestStart=0,start = -1
            // right is a sentinel. The byte offset is never computed at x==right.
            for x in left...right {
                var match=false
                if x<right {
                    let i=iy*rowBytes+x*4
                    if pixels[i+3]>160 {
                        match=colorClass(Int(pixels[i]),Int(pixels[i+1]),Int(pixels[i+2]))==color
                    }
                }
                if match && start<0 {start=x}
                if !match && start>=0 {
                    if x-start>best {best=x-start;bestStart=start}
                    start = -1
                }
            }
            return best>=minRun ? Run(left:bestStart,right:bestStart+best,y:y) : nil
        }
        for y in top..<bottom {
            let next=rowRun(y)
            if let candidate=next {
                if var t=active {
                    let overlap=max(0,min(t.lastRight,candidate.right)-max(t.lastLeft,candidate.left))
                    let smaller=min(t.lastRight-t.lastLeft,candidate.right-candidate.left)
                    if overlap*2>=smaller {
                        t.append(candidate);active=t;continue
                    }
                    accepted.append(t)
                }
                active=Track(candidate)
            } else if let t=active {
                accepted.append(t);active=nil
            }
        }
        if let t=active {accepted.append(t)}
        let maximumHeight=max(8,Int(Double(height)*0.065))
        let valid=accepted.filter { t in
            t.rows>=2 && t.rows<=maximumHeight && t.minWidth>=minRun &&
            t.minWidth>=t.rows*4 && t.right-t.left<=right-left &&
            t.lastY-t.firstY+1==t.rows
        }
        guard let top=valid.max(by:{$0.pixelSum<$1.pixelSum}) else {return nil}
        return (top,valid.count)
    }
    /// RGBA bytes must be the exact already-rendered bitmap of the retained CGImage.
    static func inspect(pixels:[UInt8],width:Int,height:Int,rowBytes:Int,
                        epoch:Int64,frame:Int64,observedMs:Int64,imageSHA:String)->[String:Any] {
        guard width>=128,height>=128,width<=4096,height<=4096,
              rowBytes>=width*4,rowBytes<=width*4+4096,
              rowBytes<=maxBytes/height,pixels.count==rowBytes*height,
              epoch>0,frame>0,observedMs>0,hashOK(imageSHA) else {
            return rejection("GEOMETRY_MEMORY_OR_PROVENANCE_REJECTED")
        }
        var candidates=[[String:Any]]()
        for flip in [false,true] {
            for (region,x0,x1,y0,y1) in regions {
                for target in classes {
                    guard let (bar,number)=shape(pixels,width:width,height:height,rowBytes:rowBytes,
                            bounds:(x0,x1,y0,y1),color:target,flipped:flip) else {continue}
                    candidates.append([
                        "region_hypothesis":region,"color_hypothesis":target,
                        "raster_row_order_hypothesis":flip ? "MEMORY_LAST_ROW_TOP_HYPOTHESIS" : "MEMORY_FIRST_ROW_TOP_HYPOTHESIS",
                        "run_pixels":bar.minWidth,"passing_scanlines":bar.rows,
                        "candidate_x_normalized":Double(bar.left+bar.right)/Double(width*2),
                        "candidate_y_normalized_top":Double(bar.firstY+bar.lastY)/Double(height*2),
                        "bounds_left_normalized":Double(bar.left)/Double(width),
                        "bounds_right_normalized":Double(bar.right)/Double(width),
                        "bounds_top_normalized":Double(bar.firstY)/Double(height),
                        "bounds_bottom_normalized":Double(bar.lastY+1)/Double(height),
                        "horizontal_aspect_min":Double(bar.minWidth)/Double(bar.rows),
                        "disjoint_shape_count":number,"shape_ambiguous":number>1,
                        "shape_provenance":"R591_CONNECTED_SCANLINE_GEOMETRY_HYPOTHESIS",
                        "owner":"UNKNOWN","hp_fraction":NSNull(),
                        "status":"UNCALIBRATED_COLOR_RUN_CANDIDATE_ONLY"
                    ])
                }
            }
        }
        return ["schema":schema,"status":candidates.isEmpty ? "NO_COLOR_RUN_CANDIDATES" : "UNCALIBRATED_COLOR_RUN_CANDIDATES",
                "hold_reason":NSNull(),"image_sha256":imageSHA,"epoch":epoch,
                "frame_id":frame,"observed_ms_monotonic":observedMs,
                "image_width":width,"image_height":height,
                "candidate_count":candidates.count,"color_run_candidates":candidates,
                "r591_connected_scanline_filter":true,
                "owner_certified":false,"hp_certified":false,"orientation_certified":false,
                "mega_visual_form_certified":false,"actual_game_accuracy_certified":false,
                "current_state_eligible":false,"automatic_upload":false]
    }
    private static func held(_ reason:String)->[String:Any] {
        ["schema":schema,"status":"HOLD_INCONSISTENT_FRAME_EVIDENCE","hold_reason":reason,
         "frame_count":0,"frames":[[String:Any]](),
         "owner_certified":false,"hp_certified":false,"orientation_certified":false,
         "current_state_eligible":false,"actual_game_accuracy_certified":false,
         "automatic_upload":false]
    }
    /// Join per-frame pixel reports to the R587 OCR HUD anchor lists. Never turn
    /// string or color into a trusted health ratio, role, turn or battle action.
    static func correlate(pixelFrames:[[String:Any]],associations:[String:Any])->[String:Any] {
        guard pixelFrames.count<=8,
              associations["schema"] as? String == "trueplan.r587.frame-hud-association.v1",
              associations["status"] as? String == "HISTORICAL_FRAME_HUD_ASSOCIATIONS_ONLY",
              associations["current_state_eligible"] as? Bool == false,
              associations["owner_certified"] as? Bool == false,
              associations["orientation_certified"] as? Bool == false,
              let originals=associations["frames"] as? [[String:Any]],
              let count=associations["frame_count"] as? Int,count==originals.count,
              count==pixelFrames.count else {return held("SOURCE_ROOT_OR_FRAME_COUNT_MISMATCH")}
        var results=[[String:Any]](),ids=Set<String>()
        for index in 0..<count {
            let p=pixelFrames[index],o=originals[index]
            guard p["schema"] as? String == schema,
                  let ep=p["epoch"] as? Int64,let fr=p["frame_id"] as? Int64,
                  let tm=p["observed_ms_monotonic"] as? Int64,
                  ep>0,fr>0,tm>0,
                  let sha=p["image_sha256"] as? String,hashOK(sha),
                  o["epoch"] as? Int64 == ep,o["frame_id"] as? Int64 == fr,
                  o["observed_ms_monotonic"] as? Int64 == tm,
                  o["image_sha256"] as? String == sha,
                  let status=p["status"] as? String,
                  ["UNCALIBRATED_COLOR_RUN_CANDIDATES","NO_COLOR_RUN_CANDIDATES","HOLD_PIXEL_BUFFER_NOT_AVAILABLE"].contains(status),
                  let all=o["anchors"] as? [[String:Any]],all.count<=256,
                  let raw=p["color_run_candidates"] as? [[String:Any]],raw.count<=12,
                  (p["candidate_count"] as? Int)==raw.count,
                  p["owner_certified"] as? Bool == false,
                  p["current_state_eligible"] as? Bool == false,
                  ids.insert("\(ep):\(fr)").inserted
            else{return held("FRAME_SHA_CLOCK_OR_PIXEL_SCHEMA_CONFLICT")}
            for c in raw {
                guard let color=c["color_hypothesis"] as? String,classes.contains(color),
                      let role=c["region_hypothesis"] as? String,
                      regions.contains(where:{$0.0==role}),
                      c["owner"] as? String == "UNKNOWN",
                      c["status"] as? String == "UNCALIBRATED_COLOR_RUN_CANDIDATE_ONLY"
                else {return held("MALFORMED_PIXEL_CANDIDATE")}
            }
            let own=raw.filter{$0["region_hypothesis"] as? String == "LOWER_LEFT_HUD_REGION"}
            let opp=raw.filter{$0["region_hypothesis"] as? String == "UPPER_RIGHT_HUD_REGION"}
            let ownOCR=Set(all.filter{$0["hypothesis"] as? String == "HYPOTHESIS_OWN_HP_FRACTION"}.compactMap{$0["value"] as? String})
            let oppOCR=Set(all.filter{$0["hypothesis"] as? String == "HYPOTHESIS_OPPONENT_HP_PERCENT"}.compactMap{$0["value"] as? String})
            func level(_ p:[[String:Any]],_ texts:Set<String>)->String {
                if p.count>1 || texts.count>1 || p.contains(where:{$0["shape_ambiguous"] as? Bool == true}) {return "HOLD_AMBIGUOUS_PIXEL_OR_OCR"}
                if p.count==1 && texts.count==1 {return "PIXEL_AND_OCR_SAME_FRAME_HYPOTHESIS_ONLY"}
                if p.isEmpty && texts.isEmpty {return "NO_EVIDENCE"}
                return "INSUFFICIENT_CROSS_MODAL_EVIDENCE"
            }
            let regionRows:[[String:Any]] = [
                ["region_hypothesis":"LOWER_LEFT_HUD_REGION","pixel_colors":own.compactMap{$0["color_hypothesis"] as? String},"ocr_values":ownOCR.sorted(),"status":level(own,ownOCR)],
                ["region_hypothesis":"UPPER_RIGHT_HUD_REGION","pixel_colors":opp.compactMap{$0["color_hypothesis"] as? String},"ocr_values":oppOCR.sorted(),"status":level(opp,oppOCR)]
            ]
            results.append(["epoch":ep,"frame_id":fr,"observed_ms_monotonic":tm,
                            "image_sha256":sha,"pixel_status":status,
                            "regions":regionRows,"owner":"UNKNOWN","hp_value":NSNull(),
                            "display_orientation":NSNull(),"current_state_eligible":false])
        }
        return ["schema":schema,"status":"HISTORICAL_PIXEL_OCR_CORROBORATION_ONLY",
                "hold_reason":NSNull(),"frame_count":results.count,"frames":results,
                "owner_certified":false,"hp_certified":false,"orientation_certified":false,
                "mega_visual_form_certified":false,"actual_game_accuracy_certified":false,
                "current_state_eligible":false,"automatic_upload":false]
    }
}
