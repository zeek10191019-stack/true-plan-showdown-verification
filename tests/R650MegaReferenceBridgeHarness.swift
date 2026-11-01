import Foundation
@main struct R650Harness {
 static func main() {
  var count=0
  func check(_ yes:Bool,_ tag:String) {
   precondition(yes,tag);count += 1
  }
  let empty=R650MegaReferenceBridge.audit(frames:[],references:[])
  check(empty["status"] as? String == "HOLD_NO_GAME_REFERENCES",
        "no_refs_hold")
  check(empty["mega_form_certified"] as? Bool == false,
        "no_certification_from_empty")
  let foreign:[[String:Any]] = [["species_token":"MEWTWO",
   "form_token":"MEGA_X","mega_label_claim":true,
   "certified_as_game_state":false]]
  let wrong=R650MegaReferenceBridge.audit(frames:[],
                                           references:foreign)
  check(wrong["status"] as? String ==
        "HOLD_FOREIGN_OR_CONFLICTING_LABEL","not_regulated")
  for entry in R649MegaRegistryAudit.entries {
   let form=entry.variant == "N" ? "MEGA" :
    "MEGA_" + entry.variant
   let ref:[String:Any] = [
    "species_token":entry.species.uppercased(),
    "form_token":form,"mega_label_claim":true,
    "certified_as_game_state":false]
   let row=R650MegaReferenceBridge.audit(
     frames:[],references:[ref])
   check(row["status"] as? String ==
     "HOLD_UPSTREAM_REFERENCE_GATE","never_catalog_only_\(entry.id)")
  }
  let cheated:[[String:Any]] = [["species_token":"CHARIZARD",
    "form_token":"MEGA_Y","mega_label_claim":false,
    "certified_as_game_state":false]]
  let fail=R650MegaReferenceBridge.audit(frames:[],
                                        references:cheated)
  check(fail["status"] as? String ==
     "HOLD_FOREIGN_OR_CONFLICTING_LABEL","mismatched_mega_claim")
  // The real R594/R595 implementation is supplied in Apple CI.
  let sha=String(repeating:"a",count:64)
  let pixels:[UInt8]=(0..<(256*192)).flatMap { i -> [UInt8] in
   let x=i%256,y=i/256
   return [UInt8((x*7+y*3)%256),
           UInt8((x*2+y*11)%256),
           UInt8((x*13+y*5)%256),255]
  }
  let frame=R594ActorAppearance.capture(pixels:pixels,
   width:256,height:192,rowBytes:1024,epoch:1,frame:1,
   ms:100,sha:sha)
  let zones=frame["regions"] as! [[String:Any]]
  let left=zones.first {
   $0["name"] as? String == "MEMORY_LEFT_ACTOR_HYPOTHESIS"
  }!
  let genuine:[String:Any]=[
   "reference_id":"R650_GAME_CAP_1",
   "region":"MEMORY_LEFT_ACTOR_HYPOTHESIS",
   "species_token":"GYARADOS", "form_token":"MEGA",
   "mega_label_claim":true,"human_label_reviewed":true,
   "reference_image_sha256":sha,
   "luma_grid":left["luma_grid"]!,
   "coordinate_space":"RGBA_MEMORY_ROW_ORDER_UNVERIFIED",
   "certified_as_game_state":false]
  let candidate=R650MegaReferenceBridge.audit(
   frames:[frame],references:[genuine])
  check(candidate["status"] as? String ==
   "HISTORICAL_IMAGE_CANDIDATES_NOT_CERTIFICATION",
   "matched_reference_stays_candidate")
  check(candidate["bounded_image_matches"] as? Int == 1,
   "one_visually_matched_region")
  check(candidate["mega_form_certified"] as? Bool == false,
   "no_mega_promotion_from_visual_match")
  check(candidate["owner_verified"] as? Bool == false,
   "no_owner_promotion_from_visual_match")
  check(count == 89,"assertion_count")
  print("R650_SWIFT_BOUNDARY_PASS",count)
 }
}
