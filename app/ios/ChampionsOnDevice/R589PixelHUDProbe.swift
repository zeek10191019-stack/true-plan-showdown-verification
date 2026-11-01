import Foundation

/// R589. Inspect ACTUAL CGImage RGBA pixels, independently of Vision text.
/// Color run candidates are NOT certified HP, ownership, displayed orientation or health.
/// A red/yellow/hidden bar can produce no green candidate and MUST remain UNKNOWN.
enum R589PixelHUDProbe {
    static let schema = "trueplan.r589.historical-pixel-hud-green-run.v1"
    static let maxDimension = 4096
    static let maxPixelBytes = 64 * 1024 * 1024

    private static func shaOK(_ s: String) -> Bool {
        s.utf8.count == 64 && s.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
    private static func held(_ reason: String) -> [String:Any] {
        ["schema":schema, "status":"HOLD_INVALID_PIXEL_INPUT", "hold_reason":reason,
         "green_run_candidates":[[String:Any]](), "candidate_count":0,
         "orientation_certified":false, "owner_certified":false,
         "hp_certified":false,"mega_visual_form_certified":false,
         "current_state_eligible":false,"automatic_upload":false]
    }
    private static func green(_ r: UInt8,_ g: UInt8,_ b: UInt8) -> Bool {
        // Deliberately narrow. Real low-HP orange/red or altered UI is UNKNOWN.
        Int(g)>=115 && Int(r)<170 && Int(g)*10>Int(r)*14 &&
            Int(g)*10>Int(b)*11
    }
    private static func scan(_ pixels: [UInt8],width:Int,height:Int,rowBytes:Int,
                             lowX:Double,highX:Double,lowY:Double,highY:Double,
                             invertY:Bool) -> [String:Any]? {
        let left=max(0,Int(Double(width)*lowX)),right=min(width,Int(Double(width)*highX))
        let top=max(0,Int(Double(height)*lowY)),bottom=min(height,Int(Double(height)*highY))
        guard right>left,bottom>top else {return nil}
        let minRun=max(12,Int(Double(width)*0.026))
        var best=0,bestX=0,bestY=0,passingRows=0
        for visualY in top..<bottom {
            let actualY=invertY ? height-1-visualY : visualY
            var start = -1,largest=0,largestX=0
            for x in left...right {
                let matched:Bool
                if x==right {matched=false}
                else {
                    let i=actualY*rowBytes+x*4
                    matched=green(pixels[i],pixels[i+1],pixels[i+2]) && pixels[i+3]>160
                }
                if matched && start<0 {start=x}
                if !matched && start>=0 {
                    let run=x-start
                    if run>largest {largest=run;largestX=start}
                    start = -1
                }
            }
            if largest>=minRun {passingRows+=1}
            if largest>best {best=largest;bestX=largestX;bestY=visualY}
        }
        guard best>=minRun,passingRows>=2 else {return nil}
        return ["green_run_pixels":best,"green_run_scanline_count":passingRows,
                "candidate_center_x_normalized":Double(bestX+best/2)/Double(width),
                "candidate_y_normalized_top":Double(bestY)/Double(height),
                "candidate_run_start_x":bestX,"candidate_scanline_top":bestY]
    }
    static func inspect(pixels:[UInt8],width:Int,height:Int,rowBytes:Int,
                        epoch:Int64,frame:Int64,observedMs:Int64,imageSHA:String) -> [String:Any] {
        guard width>=128,height>=128,width<=maxDimension,height<=maxDimension,
              rowBytes>=width*4,rowBytes<=width*4+4096,
              rowBytes<=maxPixelBytes/height,pixels.count==rowBytes*height,
              epoch>0,frame>0,observedMs>0,shaOK(imageSHA) else {
            return held("GEOMETRY_MEMORY_OR_PROVENANCE_REJECTED")
        }
        var candidates=[[String:Any]](),directions=[String]()
        for (flipped,name) in [(false,"MEMORY_FIRST_ROW_TOP_HYPOTHESIS"),
                                (true,"MEMORY_LAST_ROW_TOP_HYPOTHESIS")] {
            let own=scan(pixels,width:width,height:height,rowBytes:rowBytes,
                         lowX:0.10,highX:0.33,lowY:0.82,highY:0.97,invertY:flipped)
            let opp=scan(pixels,width:width,height:height,rowBytes:rowBytes,
                         lowX:0.77,highX:0.96,lowY:0.055,highY:0.16,invertY:flipped)
            for (role,c) in [("LOWER_LEFT_HUD_REGION",own),("UPPER_RIGHT_HUD_REGION",opp)] {
                if let c {
                    var item=c
                    item["region_hypothesis"]=role
                    item["raster_row_order_hypothesis"]=name
                    item["owner"]="UNKNOWN"
                    item["status"]="UNVERIFIED_GREEN_PIXEL_RUN_ONLY"
                    candidates.append(item)
                }
            }
            if own != nil && opp != nil {directions.append(name)}
        }
        let outcome = candidates.isEmpty ? "NO_GREEN_PIXEL_HUD_ANCHORS" :
                      (directions.count==1 && candidates.count==2 ? "PIXEL_LAYOUT_PAIR_HYPOTHESIS_ONLY" :
                       "AMBIGUOUS_OR_PARTIAL_GREEN_PIXEL_CANDIDATES")
        return ["schema":schema,"status":outcome,"hold_reason":NSNull(),
                "source_kind":"HISTORICAL_RETAINED_CGIMAGE",
                "image_sha256":imageSHA,"frame_id":frame,"epoch":epoch,
                "observed_ms_monotonic":observedMs,"image_width":width,
                "image_height":height,"candidate_count":candidates.count,
                "green_run_candidates":candidates,"pair_row_order_hypotheses":directions,
                "coordinate_space":"NORMALIZED_TOP_LEFT_HYPOTHESIS",
                "green_only_limitations":"RED_YELLOW_BARS_NOT_DETECTED",
                "orientation_certified":false,"owner_certified":false,
                "hp_certified":false,"mega_visual_form_certified":false,
                "current_state_eligible":false,"actual_game_accuracy_certified":false,
                "battle_advice_authorized":false,"automatic_upload":false]
    }
}
