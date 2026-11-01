import Foundation

@main struct R593VisualChangeEvidenceHarness {
    static func main() {
        var passed=0
        func check(_ c:Bool,_ reason:String) {
            guard c else {fatalError("R593_\(reason)_FAILED")} ; passed+=1
        }
        let w=512,h=256,sha=String(repeating:"a",count:64)
        func rgba()->[UInt8] {
            var p=[UInt8](repeating:0,count:w*h*4)
            for i in stride(from:3,to:p.count,by:4) {p[i]=255}
            return p
        }
        func draw(_ px:inout [UInt8],_ x0:Int,_ x1:Int,_ y0:Int,_ y1:Int,_ r:UInt8,_ g:UInt8,_ b:UInt8) {
            for y in y0..<y1 {for x in x0..<x1 {
                let k=(y*w+x)*4;px[k]=r;px[k+1]=g;px[k+2]=b
            }}
        }
        func make(_ p:[UInt8],_ frame:Int64,_ ep:Int64=1,_ time:Int64=100,
                  _ hash:String=sha)->[String:Any] {
            R593VisualChangeEvidence.capture(pixels:p,width:w,height:h,rowBytes:w*4,
                    epoch:ep,frame:frame,observedMs:time,imageSHA:hash)
        }
        let a=rgba()
        var b=a;draw(&b,60,275,99,198,200,30,40)
        var c=b;draw(&c,200,350,20,58,145,145,145)
        let first=make(a,1)
        check(first["schema"] as? String==R593VisualChangeEvidence.schema,"schema")
        check(first["status"] as? String=="HISTORICAL_PIXEL_SAMPLES_ONLY","input_status")
        check(first["current_state_eligible"] as? Bool==false,"current_guard")
        check(first["mega_visual_form_certified"] as? Bool==false,"mega_guard")
        check(first["owner_certified"] as? Bool==false,"owner_guard")
        let regions=first["regions"] as? [[String:Any]] ?? []
        check(regions.count==3,"regions")
        check(regions.allSatisfy{($0["samples_rgb"] as? [Int])?.count==144},"region_length")
        check(regions.allSatisfy{$0["coordinate_space"] as? String=="RGBA_MEMORY_ROW_ORDER_UNVERIFIED"},"memory_orientation")
        let second=make(b,2,1,200,String(repeating:"b",count:64))
        let output=R593VisualChangeEvidence.timeline([first,second])
        check(output["status"] as? String=="HISTORICAL_VISUAL_CHANGE_AUDIT_ONLY","sequence")
        check(output["frame_count"] as? Int==2,"count")
        check(output["pair_count"] as? Int==1,"pairs")
        check(output["mega_visual_form_certified"] as? Bool==false,"no_mega")
        check(output["owner_certified"] as? Bool==false,"no_owner")
        let rows=output["pairs"] as? [[String:Any]] ?? []
        check(rows.count==1,"pair_row")
        check(rows[0]["status"] as? String=="LOCALIZED_VISUAL_CHANGE_CANDIDATES_ONLY","local_change")
        check(rows[0]["mega_evolution_confirmed"] as? Bool==false,"no_confirmed_mega")
        check(rows[0]["switch_confirmed"] as? Bool==false,"no_confirmed_switch")
        let changes=rows[0]["regions"] as? [[String:Any]] ?? []
        check(changes.count==3,"changed_regions")
        let left=changes.first{$0["region"] as? String=="MEMORY_LEFT_ACTOR_REGION_HYPOTHESIS"} ?? [:]
        let back=changes.first{$0["region"] as? String=="MEMORY_UPPER_BACKGROUND_REFERENCE"} ?? [:]
        check((left["changed_tiles"] as? Int ?? 0)>0,"left_changed")
        check(back["changed_tiles"] as? Int==0,"background_still")
        check(left["change_is_certified_event"] as? Bool==false,"change_hold")
        let third=make(c,3,1,300,String(repeating:"c",count:64))
        let bg=R593VisualChangeEvidence.timeline([second,third]);let bgRows=bg["pairs"] as? [[String:Any]] ?? []
        check(bgRows.first?["status"] as? String=="HOLD_GLOBAL_BACKGROUND_OR_CAMERA_CHANGE","background_changed")
        let duplicated=R593VisualChangeEvidence.timeline([first,first])
        check(duplicated["status"] as? String=="HOLD_INVALID_FRAME_SEQUENCE","duplicate_frame")
        check(R593VisualChangeEvidence.timeline([second,first])["status"] as? String=="HOLD_INVALID_FRAME_SEQUENCE","nonmono_frame")
        let noPixels=R593VisualChangeEvidence.unavailable(epoch:1,frame:2,observedMs:200,imageSHA:sha,reason:"RG")
        let emptyPair=R593VisualChangeEvidence.timeline([first,noPixels])
        let emptyRows=emptyPair["pairs"] as? [[String:Any]] ?? []
        check(emptyRows.first?["status"] as? String=="HOLD_CROSS_EPOCH_OR_MISSING_PIXELS","missing_pixels")
        let differentEpoch=make(b,1,2,200,String(repeating:"b",count:64))
        let epochs=R593VisualChangeEvidence.timeline([first,differentEpoch])
        let epochsRows=epochs["pairs"] as? [[String:Any]] ?? []
        check(epochsRows.first?["status"] as? String=="HOLD_CROSS_EPOCH_OR_MISSING_PIXELS","epoch_fence")
        check(R593VisualChangeEvidence.timeline(Array(repeating:first,count:9))["status"] as? String=="HOLD_INVALID_FRAME_SEQUENCE","bound")
        check(R593VisualChangeEvidence.timeline([])["pair_count"] as? Int==0,"empty_timeline")
        check(make(a,1,1,100,"bad")["status"] as? String=="HOLD_PIXEL_BUFFER_UNAVAILABLE","bad_sha")
        check(make(Array(a.dropLast()),1)["status"] as? String=="HOLD_PIXEL_BUFFER_UNAVAILABLE","bad_bytes")
        check(make(a,0)["status"] as? String=="HOLD_PIXEL_BUFFER_UNAVAILABLE","bad_frame")
        check(make(a,1,0)["status"] as? String=="HOLD_PIXEL_BUFFER_UNAVAILABLE","bad_epoch")
        check(make(a,1,1,0)["status"] as? String=="HOLD_PIXEL_BUFFER_UNAVAILABLE","bad_clock")
        var corrupted=second
        corrupted["regions"]=[["name":"MEMORY_LEFT_ACTOR_REGION_HYPOTHESIS","samples_rgb":[0]]]
        check(R593VisualChangeEvidence.timeline([first,corrupted])["status"] as? String=="HOLD_INVALID_FRAME_SEQUENCE","corrupt_samples")
        var liar=second;liar["owner_certified"]=true
        check(R593VisualChangeEvidence.timeline([first,liar])["status"] as? String=="HOLD_INVALID_FRAME_SEQUENCE","reject_laundered_owner")
        var badOrder=second;badOrder["observed_ms_monotonic"]=Int64(50)
        check(R593VisualChangeEvidence.timeline([first,badOrder])["status"] as? String=="HOLD_INVALID_FRAME_SEQUENCE","time_reverse")
        var missingReg=second;missingReg.removeValue(forKey:"regions")
        check(R593VisualChangeEvidence.timeline([first,missingReg])["status"] as? String=="HOLD_INVALID_FRAME_SEQUENCE","missing_region")
        check(output["automatic_upload"] as? Bool==false,"no_upload")
        print("R593_VISUAL_CHANGE_TESTS_\(passed)_PASS")
    }
}
