import Foundation
struct R649MegaEntry { let species: String; let variant: String }
enum R649MegaRegistryAudit {
 static let entries = [
  R649MegaEntry(species:"Gyarados",variant:"N"),
  R649MegaEntry(species:"Charizard",variant:"X"),
  R649MegaEntry(species:"Charizard",variant:"Y")
 ]
 static func validCatalog()->Bool { true }
}
enum R595FormReferenceMatcher {
 static let schema="trueplan.r595.reference-form-matcher.v1"
 static func audit(_ frames:[[String:Any]],references:[[String:Any]])->[String:Any] {
  ["schema":schema,"status":"HISTORICAL_REFERENCE_FORM_CANDIDATES_ONLY"]
 }
}
@main struct Harness {
 static func main() {
  var n=0
  func ok(_ value:Bool,_ message:String) {precondition(value,message);n+=1}
  let gy=["GYARADOS":Set(["BASE","MEGA"])]
  func d(_ rows:[(Int,String,String)],_ db:[String:Set<String>]=gy) -> R654MegaVisualClassGate.Decision {
   R654MegaVisualClassGate.adjudicate(rows, expected:db)
  }
  let normal=[(0,"GYARADOS","MEGA"),(35,"GYARADOS","BASE")]
  ok(d(normal).candidate,"valid_candidate")
  ok(d(normal).species=="GYARADOS","species_claim")
  ok(d(normal).form=="MEGA","form_claim")
  ok(d(normal).megaCertified == false,"no_mega_cert")
  ok(d(normal).ownerCertified == false,"no_owner_cert")
  ok(d(normal).battleAdviceAuthorized == false,"no_advice")
  let duplicate=[(0,"GYARADOS","MEGA"),(1,"GYARADOS","MEGA"),(35,"GYARADOS","BASE")]
  ok(d(duplicate).candidate,"same_class_duplicates_not_a_competitor")
  ok(d(duplicate).distinctClasses==2,"duplicates_not_classes")
  ok(d([(0,"GYARADOS","MEGA")]).status == "HOLD_MISSING_SAME_SPECIES_FORMS","missing_base")
  ok(d([(0,"GYARADOS","BASE")]).status == "HOLD_MISSING_SAME_SPECIES_FORMS","missing_mega")
  ok(d([(0,"GYARADOS","MEGA"),(3,"GYARADOS","BASE")]).status == "HOLD_CLASS_AMBIGUITY","near_tie")
  ok(d([(30,"GYARADOS","MEGA"),(55,"GYARADOS","BASE")]).status == "HOLD_NO_CLOSE_MATCH","poor_match")
  ok(d([(-1,"GYARADOS","MEGA")]).status == "HOLD_UNREGISTERED_FORM","negative_score")
  ok(d([(0,"GYARADOS","MEGA"),(40,"GYARADOS","MEGA_Z")]).status == "HOLD_UNREGISTERED_FORM","invented_variant")
  ok(d([(0,"GYARADOS","MEGA"),(40,"CHARIZARD","MEGA_X")]).status == "HOLD_UNREGISTERED_FORM","foreign_without_registry")
  ok(d(Array(repeating:(1,"GYARADOS","BASE"),count:513)).status == "HOLD_CAPACITY","over_capacity")
  let cdb=["CHARIZARD":Set(["BASE","MEGA_X","MEGA_Y"])]
  ok(d([(0,"CHARIZARD","MEGA_X"),(40,"CHARIZARD","BASE")],cdb).status == "HOLD_MISSING_SAME_SPECIES_FORMS","missing_y")
  ok(d([(0,"CHARIZARD","MEGA_X"),(40,"CHARIZARD","BASE"),(30,"CHARIZARD","MEGA_Y")],cdb).candidate,"full_xy")
  ok(d([(0,"CHARIZARD","MEGA_X"),(40,"CHARIZARD","BASE"),(4,"CHARIZARD","MEGA_Y")],cdb).status == "HOLD_CLASS_AMBIGUITY","confusable_xy")
  ok(d([(0,"CHARIZARD","MEGA_X"),(40,"CHARIZARD","BASE"),(40,"CHARIZARD","MEGA_X")],cdb).status == "HOLD_MISSING_SAME_SPECIES_FORMS","duplicated_x_not_y")
  let zdb=["LUCARIO":Set(["BASE","MEGA","MEGA_Z"])]
  ok(d([(0,"LUCARIO","MEGA_Z"),(35,"LUCARIO","BASE")],zdb).status == "HOLD_MISSING_SAME_SPECIES_FORMS","missing_normal_mega")
  ok(d([(0,"LUCARIO","MEGA_Z"),(35,"LUCARIO","BASE"),(29,"LUCARIO","MEGA")],zdb).candidate,"normal_vs_z")
  ok(d([(0,"GYARADOS","MEGA"),(20,"GYARADOS","BASE")]).best == 0,"distance_record")
  print("R654_MEGA_FORM_CLASS_HARNESS_PASS \(n)/\(n)")
 }
}
