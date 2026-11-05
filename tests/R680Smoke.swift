import Foundation
@main struct R680Smoke {
    static let sha=String(repeating:"a",count:64)
    static let shb=String(repeating:"b",count:64)
    static func grid(_ shift:Int=0)->[Int] {
        (0..<192).map{($0*7+shift)%180+32}
    }
    static func frame(_ id:Int64,_ hash:String=sha,
                      weak:Bool=false)->[String:Any] {
        let names=["MEMORY_LEFT_ACTOR_HYPOTHESIS",
                   "MEMORY_RIGHT_ACTOR_HYPOTHESIS",
                   "MEMORY_BACKGROUND_REFERENCE"]
        let rr=names.enumerated().map { n,name -> [String:Any] in
            let g=weak && n==0 ? [Int](repeating:64,count:192) : grid(n*9)
            return ["name":name,"grid_width":16,"grid_height":12,
                    "luma_grid":g,"transparent_samples":0,
                    "coordinate_space":"RGBA_MEMORY_ROW_ORDER_UNVERIFIED"]
        }
        return ["schema":"trueplan.r594.historical-actor-appearance.v1",
                "status":"HISTORICAL_APPEARANCE_SAMPLES_ONLY",
                "epoch":Int64(3),"frame_id":id,"image_sha256":hash,
                "image_width":1280,"image_height":720,
                "regions":rr,"owner_certified":false,"species_certified":false,
                "mega_certified":false,"current_state_eligible":false]
    }
    static func snap(_ id:Int64,_ hash:String=sha)->[String:Any] {
        ["file":"frames/frame_3_\(id).png","frame_id":id,
         "epoch":Int64(3),"png_sha256":hash,"width":1280,"height":720]
    }
    static func main() {
        var n=0
        func ck(_ ok:Bool,_ name:String) {precondition(ok,name);n+=1}
        let one=R680MegaReferenceSeeds.make(frames:[frame(12)],snapshots:[snap(12)])
        ck(one["draft_count"] as? Int==2,"both actors")
        let drafts=one["drafts"] as? [[String:Any]] ?? []
        ck(drafts.count==2,"length")
        ck(drafts.allSatisfy{$0["human_label_reviewed"] as? Bool==false},"unreviewed")
        ck(drafts.allSatisfy{$0["source_png_file"] as? String=="frames/frame_3_12.png"},"png")
        ck(drafts.allSatisfy{$0["needs_species_token"] as? Bool==true},"no labels")
        ck(drafts.allSatisfy{$0["reference_image_sha256"] as? String==sha},"sha")
        ck(one["catalog_auto_installed"] as? Bool==false,"no auto")
        ck(JSONSerialization.isValidJSONObject(one),"json")
        let two=R680MegaReferenceSeeds.make(
            frames:[frame(12),frame(13,shb)],snapshots:[snap(12),snap(13,shb)])
        ck(two["draft_count"] as? Int==4,"two frames")
        var wrong=snap(12);wrong["png_sha256"]=shb
        let bad=R680MegaReferenceSeeds.make(frames:[frame(12)],snapshots:[wrong])
        ck(bad["draft_count"] as? Int==0,"hash reject")
        ck((bad["status"] as? String ?? "").hasPrefix("HOLD"),"failure")
        ck(R680MegaReferenceSeeds.make(frames:[frame(12)],snapshots:[])["draft_count"] as? Int==0,"count")
        let duplicate=R680MegaReferenceSeeds.make(
            frames:[frame(12),frame(12)],snapshots:[snap(12),snap(12)])
        ck(duplicate["draft_count"] as? Int==0,"same frame reject")
        let low=R680MegaReferenceSeeds.make(frames:[frame(12,sha,weak:true)],snapshots:[snap(12)])
        ck(low["draft_count"] as? Int==1,"low texture filtered")
        var corrupt=frame(12)
        var rr=corrupt["regions"] as! [[String:Any]]
        rr[0]["luma_grid"]=[999]
        corrupt["regions"]=rr
        ck(R680MegaReferenceSeeds.make(frames:[corrupt],snapshots:[snap(12)])["draft_count"] as? Int==0,"corrupt")
        let empty=R680MegaReferenceSeeds.make(frames:[],snapshots:[])
        ck(empty["draft_count"] as? Int==0,"empty")
        ck(empty["human_label_reviewed"] as? Bool==false,"never certified")
        print("R680_REAL_IMAGE_REFERENCE_DRAFT_SMOKE_PASS \(n)")
    }
}
