import Foundation
@main struct R655RealRegistryHarness {
    static func main(){
        precondition(R649MegaRegistryAudit.validCatalog())
        precondition(R649MegaRegistryAudit.entries.count == 81)
        let expected:[(String,String)] = [
           ("Charizard","X"),("Charizard","Y"),
           ("Raichu","X"),("Raichu","Y"),
           ("Absol","N"),("Absol","Z"),
           ("Garchomp","N"),("Garchomp","Z"),
           ("Lucario","N"),("Lucario","Z"),
           ("Golisopod","N")]
        var count=0
        for (species,variant) in expected {
           precondition(R649MegaRegistryAudit.entries.contains {
              $0.species==species && $0.variant==variant
           });count+=1
        }
        let sha=String(repeating:"e",count:64)
        let roi="MEMORY_LEFT_ACTOR_HYPOTHESIS"
        let grid=(0..<192).map{($0 * 17) % 255}
        func ref(_ species:String,_ form:String,_ id:String)->[String:Any]{
           ["reference_id":id,"region":roi,"species_token":species,
            "form_token":form,"mega_label_claim":form != "BASE",
            "human_label_reviewed":true,"certified_as_game_state":false,
            "reference_image_sha256":sha,"luma_grid":grid,
            "coordinate_space":"RGBA_MEMORY_ROW_ORDER_UNVERIFIED"]
        }
        let yes=R655MegaReferenceConflictGate.audit(references:[ref("CHARIZARD","MEGA_X","REF1")])
        precondition(yes["status"] as? String == "REVIEWED_LABEL_CONSISTENCY_ONLY")
        count+=1
        let wrong=R655MegaReferenceConflictGate.audit(references:[ref("CHARIZARD","MEGA_Z","REF1")])
        precondition(wrong["status"] as? String == "HOLD_INVALID_REFERENCE")
        count+=1
        let mismatch=R655MegaReferenceConflictGate.audit(references:[ref("CHARIZARD","MEGA_X","REF1"),ref("CHARIZARD","MEGA_Y","REF2")])
        precondition(mismatch["status"] as? String == "HOLD_SAME_IMAGE_CONTRADICTORY_FORM")
        count+=1
        let goli=R655MegaReferenceConflictGate.audit(references:[ref("GOLISOPOD","MEGA","REF1")])
        precondition(goli["status"] as? String == "REVIEWED_LABEL_CONSISTENCY_ONLY")
        count+=1
        print("R655_REAL_REGISTRY_PASS \(count)/\(count)")
    }
}
