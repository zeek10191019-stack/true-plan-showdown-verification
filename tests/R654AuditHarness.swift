import Foundation
struct R649MegaEntry { let species: String; let variant: String }
enum R649MegaRegistryAudit {
 static let entries:[R649MegaEntry] = {
  var x = [R649MegaEntry]()
  x.append(.init(species:"Gyarados",variant:"N"))
  x.append(.init(species:"Charizard",variant:"X"))
  x.append(.init(species:"Charizard",variant:"Y"))
  for i in 3..<81 { x.append(.init(species:"Test\(i)",variant:"N")) }
  return x
 }()
 static func validCatalog()->Bool { entries.count==81 }
}
enum R595FormReferenceMatcher {
 static let schema="trueplan.r595.reference-form-matcher.v1"
 static func audit(_ frames:[[String:Any]],references:[[String:Any]])->[String:Any] {
   ["schema":schema,"status":references.isEmpty ?
    "HOLD_NO_LABELED_FORM_REFERENCES" :
    "HISTORICAL_REFERENCE_FORM_CANDIDATES_ONLY"]
 }
}
@main struct R654AuditHarness {
 static func main() {
  let sha=String(repeating:"a",count:64)
  let side="MEMORY_LEFT_ACTOR_HYPOTHESIS"
  let other="MEMORY_RIGHT_ACTOR_HYPOTHESIS"
  let grid=(0..<192).map{50+($0%90)}
  let reversed=grid.reversed().map{$0}
  func ref(_ form:String,_ data:[Int],_ id:String)->[String:Any] {
   ["region":side,"species_token":"GYARADOS","form_token":form,
    "luma_grid":data,"reference_id":id]
  }
  let regions:[[String:Any]] = [
   ["name":side,"luma_grid":grid],
   ["name":other,"luma_grid":grid],
   ["name":"MEMORY_BACKGROUND_REFERENCE","luma_grid":grid]
  ]
  let f:[String:Any] = ["regions":regions,"epoch":Int64(1),
                        "frame_id":Int64(7),"image_sha256":sha]
  var n=0
  func ok(_ x:Bool,_ message:String){ precondition(x,message);n+=1 }
  let r=R654MegaVisualClassGate.audit(frames:[f],references:[
   ref("MEGA",grid,"mega"),ref("MEGA",grid,"same_class"),
   ref("BASE",reversed,"base")])
  ok(r["status"] as? String=="HISTORICAL_FORM_CLASS_CANDIDATES_ONLY","audit_report")
  ok(r["mega_event_certified"] as? Bool == false,"no_event_certification")
  ok(r["owner_certified"] as? Bool == false,"no_owner_certification")
  ok(r["battle_advice_authorized"] as? Bool == false,"no_advice")
  let rows=(r["frames"] as! [[String:Any]])[0]["regions"] as! [[String:Any]]
  ok(rows.count==2,"two_historical_regions")
  ok(rows[0]["region"] as? String == side,"left_region_binding")
  ok(rows[0]["distinct_form_classes"] as? Int==2,"dedup_classes")
  ok(rows[0]["status"] as? String=="VISUAL_FORM_CANDIDATE_ONLY","class_match")
  ok(rows[0]["form_claim"] as? String=="MEGA","mega_claim_only")
  ok(rows[1]["status"] as? String=="HOLD_NO_REFERENCES","unlabeled_opposite_held")
  let unbalanced=R654MegaVisualClassGate.audit(frames:[f],references:[ref("MEGA",grid,"mega")])
  let unbalancedRow=((unbalanced["frames"] as! [[String:Any]])[0]["regions"] as! [[String:Any]])[0]
  ok(unbalancedRow["status"] as? String=="HOLD_MISSING_SAME_SPECIES_FORMS","missing_base_hold")
  let empty=R654MegaVisualClassGate.audit(frames:[f],references:[])
  ok((empty["status"] as? String ?? "").hasPrefix("HOLD_UPSTREAM_"),"no_references")
  print("R654_INTEGRATION_AUDIT_PASS \(n)/\(n)")
 }
}
