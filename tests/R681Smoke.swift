import Foundation
@main struct R681Smoke {
    static let hash=String(repeating:"a",count:64)
    static let left="MEMORY_LEFT_ACTOR_HYPOTHESIS"
    static let right="MEMORY_RIGHT_ACTOR_HYPOTHESIS"
    static func draft(_ side:String,_ id:String="A",_ h:String=hash)->[String:Any] {
        ["reference_id":id,"region":side,"source_epoch":Int64(1),
         "source_frame_id":Int64(23),"reference_image_sha256":h,
         "source_png_file":"frames/frame_1_23.png",
         "human_label_reviewed":false,"needs_form_token":true,
         "must_review_actual_png":true]
    }
    static func drafts(_ list:[[String:Any]])->[String:Any] {
        ["schema":"trueplan.r680.real-png-form-reference-drafts.v1",
         "status":list.isEmpty ? "NO_REVIEWABLE_ACTOR_DRAFTS" :
            "UNLABELED_REFERENCE_DRAFTS_FOR_HUMAN_REVIEW",
         "draft_count":list.count,"drafts":list,
         "human_label_reviewed":false,"catalog_auto_installed":false]
    }
    static func ocr(_ id:String,_ text:String,_ x:Double,_ y:Double,
                    _ h:String=hash,_ angle:Int=0)->[String:Any] {
        ["status":"UNVERIFIED_ORIENTATION_SPATIAL_OCR_CANDIDATE",
         "owner":"UNKNOWN","pokemon_identity":"UNKNOWN",
         "current_state_eligible":false,"frame_id":Int64(23),"epoch":Int64(1),
         "image_sha256":h,"evidence_ref":id,"rotation_degrees":angle,
         "text":text,"nominal_source_bottom_left_roi":[
            "x":x,"y":y,"width":0.05,"height":0.02]]
    }
    static func spatial(_ rows:[[String:Any]])->[String:Any] {
        ["schema":"trueplan.r585.historical-spatial-ocr-candidates.v1",
         "status":"HISTORICAL_GEOMETRY_CANDIDATES_ONLY",
         "current_state_eligible":false,"display_orientation_certified":false,
         "roi_owner_certified":false,"truncated_by_limit":false,
         "candidates":rows,"candidate_count":rows.count]
    }
    static func main() {
        var n=0
        func check(_ b:Bool,_ what:String) {precondition(b,what);n+=1}
        let reg=[(species:"GYARADOS",jp:"ギャラドス"),
                 (species:"CHARIZARD",jp:"リザードン")]
        let two=[draft(left,"L"),draft(right,"R")]
        let visible=[ocr("o1","ギャラドス",0.18,0.11),
                     ocr("o2","リザードン",0.79,0.83)]
        func run(_ d:[[String:Any]],_ a:[[String:Any]],
                 _ rg:[(species:String,jp:String)] = reg)->[String:Any] {
            R681MegaSeedOCRHints.make(draftReport:drafts(d),spatial:spatial(a),registry:rg)
        }
        let good=run(two,visible)
        check(good["suggestion_count"] as? Int==2,"two species")
        let rows=good["records"] as? [[String:Any]] ?? []
        check(rows.count==2,"rows")
        check(rows[0]["species_token_suggestion"] as? String=="GYARADOS","own hint")
        check(rows[1]["species_token_suggestion"] as? String=="CHARIZARD","opp hint")
        check(rows.allSatisfy{$0["form_token"] as? String=="UNKNOWN"},"no Mega")
        check(rows.allSatisfy{$0["owner"] as? String=="UNKNOWN"},"no owner")
        check(good["mega_form_certified"] as? Bool==false,"hold Mega")
        check(good["catalog_auto_installed"] as? Bool==false,"no auto install")
        check(run(two,[])["suggestion_count"] as? Int==0,"empty OCR")
        check(run([draft(left)],visible)["suggestion_count"] as? Int==1,"left only")
        check(run([draft(right)],visible)["suggestion_count"] as? Int==1,"right only")
        check(run(two,[ocr("o1","ギャラドス",0.18,0.11, String(repeating:"b",count:64))])["suggestion_count"] as? Int==0,"sha mismatch")
        check(run(two,[ocr("o1","メガギャラドス",0.18,0.11)])["suggestion_count"] as? Int==0,"no Mega prefix inference")
        check(run(two,[ocr("o1","あまごい",0.18,0.11)])["suggestion_count"] as? Int==0,"not species")
        check(run(two,[ocr("o1","ギャラドス",0.64,0.38)])["suggestion_count"] as? Int==0,"mid-screen rejection")
        check(run(two,[ocr("o1","ギャラドス",0.18,0.11),ocr("o2","リザードン",0.19,0.11)])["suggestion_count"] as? Int==0,"conflict hold")
        check(run(two,[ocr("o1","ギャラドス",0.18,0.11),ocr("o2","ギャラドス",0.18,0.11,hash,90)])["suggestion_count"] as? Int==0,"angle conflict")
        check(run([draft(left,"A"),draft(right,"A")],visible)["status"] as? String=="HOLD_INVALID_PNG_REFERENCE_DRAFT","duplicate draft")
        var forged=draft(left);forged["human_label_reviewed"]=true
        check(run([forged],visible)["status"] as? String=="HOLD_INVALID_PNG_REFERENCE_DRAFT","no reviewed forged")
        var malformed=ocr("o1","ギャラドス",0.18,0.11)
        malformed["nominal_source_bottom_left_roi"]=["x":0.98,"y":0.10,"width":0.05,"height":0.02]
        check(run(two,[malformed])["status"] as? String=="HOLD_CORRUPT_OCR_PROVENANCE","bad bounds")
        check(run([],[])["draft_count"] as? Int==0,"zero drafts")
        check(run(two,visible,[(species:"A",jp:"ギャラドス"),(species:"B",jp:"ギャラドス")])["status"] as? String=="HOLD_REGISTRY_LABEL_COLLISION","dup registry")
        check(run(two,visible,[])["status"] as? String=="HOLD_INVALID_SOURCE_OR_INCOMPLETE_OCR","registry empty")
        print("R681_PNG_OCR_SPECIES_HINT_SMOKE_PASS \(n)")
    }
}
