import Foundation
@main struct R649CapacityHarness {
 static func main() throws {
  let reference = (0..<192).map { ($0*7)%234 }
  func row(_ n:Int)->[String:Any] {
   ["reference_id":"FORM_\(n)",
    "region":"MEMORY_LEFT_ACTOR_HYPOTHESIS",
    "species_token":"SPECIES_\(n)",
    "form_token":"MEGA_FORM_\(n)",
    "mega_label_claim":true,
    "human_label_reviewed":true,
    "reference_image_sha256":String(repeating:"a",count:64),
    "luma_grid":reference,
    "coordinate_space":"RGBA_MEMORY_ROW_ORDER_UNVERIFIED",
    "certified_as_game_state":false]
  }
  func test(_ n:Int)->Int {
   let path=URL(fileURLWithPath:NSTemporaryDirectory())
    .appendingPathComponent("r649_\(n).json")
   let obj:[String:Any] = [
    "schema":R595FormReferenceMatcher.catalogSchema,
    "references":Array(0..<n).map{row($0)}]
   let data=try! JSONSerialization.data(withJSONObject:obj)
   try! data.write(to:path)
   defer { try? FileManager.default.removeItem(at:path) }
   return R595FormReferenceMatcher.loadLocalCatalog(at:path).count
  }
  precondition(test(81)==81,"81_refs_required")
  precondition(test(512)==512,"512_refs_allowed")
  precondition(test(513)==0,"513_refs_rejected")
  print("R649_REFERENCE_CAPACITY_PASS 81 512 513_REJECT")
 }
}
