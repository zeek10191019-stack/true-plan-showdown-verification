import Foundation

struct R649MegaEntry {
    let species: String
    let variant: String
}
enum R649MegaRegistryAudit {
    static let entries = [R649MegaEntry(species:"Gyarados",variant:"N")]
}
enum R595FormReferenceMatcher {
    static let catalogSchema = "trueplan.r595.manual-form-reference-library.v1"
    static func loadLocalCatalog(at url:URL?) -> [[String:Any]] {
        guard let url,
              let data=try? Data(contentsOf:url),
              let o=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
              o["schema"] as? String == catalogSchema,
              let r=o["references"] as? [[String:Any]],
              r.count<=512 else {return []}
        return r
    }
}

@main struct R653Harness {
 static func main() throws {
   let root=FileManager.default.temporaryDirectory
     .appendingPathComponent("r653-"+UUID().uuidString)
   try FileManager.default.createDirectory(at:root,
                                        withIntermediateDirectories:true)
   defer {try? FileManager.default.removeItem(at:root)}
   let target=root.appendingPathComponent("refs.json")
   func raw(_ id:String)->Data {
      let b:[String:Any] = [
        "schema":R595FormReferenceMatcher.catalogSchema,
        "references":[["reference_id":id]]
      ]
      return try! JSONSerialization.data(withJSONObject:b,
                                        options:[.sortedKeys])
   }
   let a=raw("a"),b=raw("b")
   var count=0
   func check(_ ok:Bool,_ label:String){precondition(ok,label);count+=1}
   check(try R652MegaCatalogInstaller.transactionalStore(
     a,to:target,count:1)==1,"new_file")
   check(try Data(contentsOf:target)==a,"new_file_data")
   do {
    _ = try R652MegaCatalogInstaller.transactionalStore(
      b,to:target,count:1,writer:{ data,url in
        try Data("corrupt".utf8).write(to:url,options:.atomic)
      })
    preconditionFailure("corrupt accepted")
   }catch {count+=1}
   check(try Data(contentsOf:target)==a,"old_restored")
   do {
    _ = try R652MegaCatalogInstaller.transactionalStore(
      b,to:target,count:1,writer:{ data,url in
        try data.write(to:url,options:.atomic)
        throw NSError(domain:"test",code:1)
      })
    preconditionFailure("writer_error accepted")
   }catch {count+=1}
   check(try Data(contentsOf:target)==a,"writer_error_old_restored")
   do {
    _ = try R652MegaCatalogInstaller.transactionalStore(
      b,to:target,count:2)
    preconditionFailure("mismatched reference_count accepted")
   }catch {count+=1}
   check(try Data(contentsOf:target)==a,"count_mismatch_rollback")
   let missing=root.appendingPathComponent("new.json")
   do {
    _ = try R652MegaCatalogInstaller.transactionalStore(
      b,to:missing,count:1,writer:{ data,url in
        try Data("corrupt".utf8).write(to:url,options:.atomic)
      })
    preconditionFailure("new corruption accepted")
   }catch {count+=1}
   check(!FileManager.default.fileExists(atPath:missing.path),
         "new_file_corruption_deleted")
   check(try R652MegaCatalogInstaller.transactionalStore(
     b,to:target,count:1)==1,"valid_replacement")
   check(try Data(contentsOf:target)==b,"replaced_correctly")
   print("R653_TRANSACTION_ROLLBACK_PASS",count)
 }
}
