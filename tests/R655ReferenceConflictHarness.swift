import Foundation
struct R649MegaEntry { let species:String; let variant:String }
enum R649MegaRegistryAudit {
    static let entries:[R649MegaEntry] = {
        var e=[R649MegaEntry(species:"Charizard",variant:"X"),
               R649MegaEntry(species:"Charizard",variant:"Y"),
               R649MegaEntry(species:"Gyarados",variant:"N"),
               R649MegaEntry(species:"Lucario",variant:"N"),
               R649MegaEntry(species:"Lucario",variant:"Z")]
        for i in 5..<81 {e.append(.init(species:"P\(i)",variant:"N"))}
        return e
    }()
    static func validCatalog()->Bool {entries.count == 81}
}
@main struct R655ReferenceConflictHarness {
    static func main(){
        var n=0
        func check(_ b:Bool,_ what:String) {precondition(b,what);n+=1}
        let right="MEMORY_RIGHT_ACTOR_HYPOTHESIS"
        let left="MEMORY_LEFT_ACTOR_HYPOTHESIS"
        let shaa=String(repeating:"a",count:64)
        let shab=String(repeating:"b",count:64)
        let shac=String(repeating:"c",count:64)
        let sha0=String(repeating:"0",count:64)
        func ref(_ id:String,_ species:String="CHARIZARD",_ form:String="MEGA_X",
                 _ hash:String=shaa,_ region:String=left,_ shift:Int=0)->[String:Any]{
            let data=(0..<192).map {($0*7+shift)%256}
            return ["reference_id":id.uppercased(),"species_token":species,"form_token":form,
                    "region":region,"mega_label_claim":form != "BASE",
                    "human_label_reviewed":true,"certified_as_game_state":false,
                    "reference_image_sha256":hash,"luma_grid":data,
                    "coordinate_space":"RGBA_MEMORY_ROW_ORDER_UNVERIFIED"]
        }
        func status(_ rs:[[String:Any]])->String {
            R655MegaReferenceConflictGate.audit(references:rs)["status"] as! String
        }
        let good=[ref("a"),ref("b","CHARIZARD","MEGA_Y",shab,left,33),
                  ref("c","CHARIZARD","BASE",shac,left,67)]
        check(status(good)=="REVIEWED_LABEL_CONSISTENCY_ONLY","three_variants")
        check(status([ref("a"),ref("b","CHARIZARD","MEGA_Y",shaa)]) ==
              "HOLD_SAME_IMAGE_CONTRADICTORY_FORM","same_img_wrong_variant")
        check(status([ref("a"),ref("b","CHARIZARD","BASE",shaa)]) ==
              "HOLD_SAME_IMAGE_CONTRADICTORY_FORM","same_img_base_conflict")
        check(status([ref("a"),ref("b","LUCARIO","MEGA",shaa)]) ==
              "HOLD_SAME_IMAGE_CONTRADICTORY_FORM","same_img_species_conflict")
        check(status([ref("a"),ref("b","CHARIZARD","MEGA_X",shaa,left,50)]) ==
              "HOLD_SAME_IMAGE_CONTRADICTORY_PIXELS","same_img_pixel_conflict")
        check(status([ref("a"),ref("b","CHARIZARD","MEGA_Y",shab)]) ==
              "HOLD_IDENTICAL_GRID_DIFFERENT_FORM","same_grid_variant_conflict")
        check(status([ref("a"),ref("b","CHARIZARD","BASE",shab)]) ==
              "HOLD_IDENTICAL_GRID_DIFFERENT_FORM","same_grid_base_conflict")
        check(status([ref("a"),ref("b","CHARIZARD","MEGA_Y",shaa,right)]) ==
              "REVIEWED_LABEL_CONSISTENCY_ONLY","separate_actor_region")
        check(status([ref("a"),ref("b","CHARIZARD","MEGA_X",shaa)]) ==
              "REVIEWED_LABEL_CONSISTENCY_ONLY","duplicate_same_class_allowed")
        check(status([ref("a"),ref("a","CHARIZARD","MEGA_X",shab,left,2)]) ==
              "HOLD_INVALID_REFERENCE","duplicate_ref_id")
        check(status([ref("a","MEWTWO","MEGA_X")]) ==
              "HOLD_INVALID_REFERENCE","unlisted_species")
        check(status([ref("a","CHARIZARD","MEGA_Z")]) ==
              "HOLD_INVALID_REFERENCE","wrong_variant")
        check(status([ref("a","CHARIZARD","MEGA_X",sha0)]) ==
              "REVIEWED_LABEL_CONSISTENCY_ONLY","valid_sha_0")
        check(status([])=="HOLD_NO_LOCAL_REFERENCES","empty_hold")
        var tampered=ref("a");tampered["human_label_reviewed"]=false
        check(status([tampered])=="HOLD_INVALID_REFERENCE","unreviewed_hold")
        tampered=ref("a");tampered["certified_as_game_state"]=true
        check(status([tampered])=="HOLD_INVALID_REFERENCE","false_certification")
        tampered=ref("a");tampered["mega_label_claim"]=false
        check(status([tampered])=="HOLD_INVALID_REFERENCE","mega_claim_mismatch")
        tampered=ref("a");tampered["region"]="MEMORY_BACKGROUND_REFERENCE"
        check(status([tampered])=="HOLD_INVALID_REFERENCE","background_reject")
        let result=R655MegaReferenceConflictGate.audit(references:good)
        check(result["owner_certified"] as? Bool == false,"no_owner_claim")
        check(result["mega_form_certified"] as? Bool == false,"no_mega_claim")
        check(result["battle_advice_authorized"] as? Bool == false,"no_advice")
        check(result["distinct_form_classes"] as? Int == 3,"class_count")
        check(result["reference_count"] as? Int == 3,"reference_count")
        print("R655_REFERENCE_CONFLICT_PASS \(n)/\(n)")
    }
}
