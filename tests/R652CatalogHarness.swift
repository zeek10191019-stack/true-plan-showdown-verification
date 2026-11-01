import Foundation

struct R649MegaEntry {
    let species: String
    let variant: String
}
enum R649MegaRegistryAudit {
    static let entries = [
        R649MegaEntry(species:"Gyarados",variant:"N"),
        R649MegaEntry(species:"Charizard",variant:"X"),
        R649MegaEntry(species:"Charizard",variant:"Y"),
        R649MegaEntry(species:"Lucario",variant:"Z")
    ]
}
// Minimal test double for the upstream gate; Apple CI compiles real R595.
enum R595FormReferenceMatcher {
    static let catalogSchema = "trueplan.r595.manual-form-reference-library.v1"
    static func loadLocalCatalog(at url:URL?) -> [[String:Any]] {
        guard let url,
              let data=try? Data(contentsOf:url),
              let d=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
              d["schema"] as? String == catalogSchema,
              let refs=d["references"] as? [[String:Any]],
              refs.count<=512,
              refs.allSatisfy({r in
                  guard let a=r["luma_grid"] as? [Int],a.count==192,
                        a.allSatisfy({$0>=0 && $0<=255}),
                        r["human_label_reviewed"] as? Bool == true,
                        r["certified_as_game_state"] as? Bool == false,
                        r["reference_image_sha256"] as? String != nil else {return false}
                  return true
              }) else{return []}
        return refs
    }
}
@main struct R652Harness {
    static func main() throws {
        let root=FileManager.default.temporaryDirectory
            .appendingPathComponent("r652-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let source=root.appendingPathComponent("refs.json")
        let grid=[Int](repeating:70,count:96)+[Int](repeating:150,count:96)
        func ref(_ species:String="GYARADOS",_ form:String="MEGA",_ mega:Bool=true) -> [String:Any] {
            ["reference_id":"A_1","region":"MEMORY_LEFT_ACTOR_HYPOTHESIS",
             "species_token":species,"form_token":form,"mega_label_claim":mega,
             "human_label_reviewed":true,"reference_image_sha256":String(repeating:"a",count:64),
             "luma_grid":grid,"coordinate_space":"RGBA_MEMORY_ROW_ORDER_UNVERIFIED",
             "certified_as_game_state":false]
        }
        func write(_ rows:[[String:Any]],_ schema:String=R595FormReferenceMatcher.catalogSchema) throws {
            let body:[String:Any]=["schema":schema,"references":rows]
            let b=try JSONSerialization.data(withJSONObject:body,options:[.sortedKeys])
            try b.write(to:source,options:.atomic)
        }
        var passed=0
        func check(_ good:Bool,_ tag:String){precondition(good,tag);passed += 1}
        func reject(_ tag:String) {
            do { _=try R652MegaCatalogInstaller.importLocalFile(source);preconditionFailure(tag) }
            catch { passed += 1 }
        }
        try write([ref()])
        check(try R652MegaCatalogInstaller.importLocalFile(source)==1,"valid_mega")
        check(R652MegaCatalogInstaller.localCount()==1,"installed_readback")
        try write([ref("CHARIZARD","MEGA_X")])
        check(try R652MegaCatalogInstaller.importLocalFile(source)==1,"variant_x")
        try write([ref("CHARIZARD","MEGA_Y")])
        check(try R652MegaCatalogInstaller.importLocalFile(source)==1,"variant_y")
        try write([ref("LUCARIO","MEGA_Z")])
        check(try R652MegaCatalogInstaller.importLocalFile(source)==1,"variant_z")
        try write([ref("GYARADOS","BASE",false)])
        check(try R652MegaCatalogInstaller.importLocalFile(source)==1,"base")
        try write([ref("GYARADOS","MEGA_Z")]); reject("invalid_gyarados_z")
        try write([ref("CHARIZARD","MEGA")]); reject("ambiguous_charizard_mega")
        try write([ref("OTHER","MEGA")]); reject("unknown_species")
        try write([ref("GYARADOS","BASE",true)]); reject("false_mega_flag")
        try write([]);reject("empty_catalog")
        try write([ref()],"invalid-schema");reject("bad_schema")
        check(R652MegaCatalogInstaller.localCount()==1,"reject_preserves_previous")
        print("R652_CATALOG_IMPORT_GUARD_PASS",passed)
    }
}
