import Foundation
@main struct R663RelativeMotionHarness {
 static func main() {
  var checks=0
  func test(_ condition:Bool,_ id:String) {
   precondition(condition, "R663_FAIL_"+id);checks+=1
  }
  let ids:[Int64]=[10,11,12,13]
  let times:[Int64]=[100,200,300,400]
  let h=["a","b","c","d"].map{String(repeating:$0,count:64)}
  let zeroFlags:[String:Any]=[
   "owner_certified":false,"species_certified":false,
   "mega_event_certified":false,"mega_form_certified":false,
   "region_calibrated":false,"battle_advice_authorized":false,
   "current_state_eligible":false,"held_out_accuracy":"NOT_MEASURED"]
  func put(_ x:[String:Any],_ changes:[String:Any]) -> [String:Any] {
   x.merging(changes){_,b in b}
  }
  let feature=put(zeroFlags,[
    "status":"HISTORICAL_UNLABELED_VISUAL_MOTION_ONLY",
    "frame_ids":ids,"image_sha256":h,"observed_ms_monotonic":times])
  var joinPairs=[[String:Any]]()
  for i in 0..<3 {
    let distances:[String:Any] = [
       "LEFT_ACTOR_HYPOTHESIS":0.12,
       "RIGHT_ACTOR_HYPOTHESIS":0.25,
       "BACKGROUND_CONTROL":0.04]
    var row=[String:Any]()
    row["from_frame_id"]=ids[i]
    row["to_frame_id"]=ids[i+1]
    row["source_sha256_from"]=h[i]
    row["source_sha256_to"]=h[i+1]
    row["diagnostic_only"]=true
    row["camera_or_actor_motion_distinguished"]=false
    row["mega_event_confirmed"]=false
    row["translation_x_fraction"]=0.02
    row["translation_y_fraction"] = -0.01
    row["translation_magnitude_fraction"]=hypot(0.02,-0.01)
    row["feature_distance_by_region_unscaled"]=distances
    joinPairs.append(row)
  }
  let joined=put(zeroFlags,[
    "status":"HISTORICAL_CROSS_MODAL_EVIDENCE_ONLY",
    "source_join_verified":true,"pairs_checked":3,"pairs":joinPairs])
  let names=["LEFT_REGION_HYPOTHESIS","RIGHT_REGION_HYPOTHESIS"]
  var samples=[[String:Any]]()
  for i in 0..<3 {
    for (j,name) in names.enumerated() {
      var row=[String:Any]()
      row["region"]=name
      row["from_frame_id"]=ids[i]
      row["to_frame_id"]=ids[i+1]
      row["from_observed_ms"]=times[i]
      row["to_observed_ms"]=times[i+1]
      row["from_sha256"]=h[i]
      row["to_sha256"]=h[i+1]
      row["box_x_lower_left"] = j==0 ? 0.11+Double(i)*0.005:0.61
      row["box_y_lower_left"] = j==0 ? 0.32:0.30
      row["box_width"]=0.31
      row["box_height"]=0.30
      row["tracker_confidence_unvalidated"]=0.85
      row["source_is_pokemon"]=false
      row["owner_verified"]=false
      row["camera_vs_actor_distinguished"]=false
      row["mega_form_identified"]=false
      samples.append(row)
    }
  }
  let tracking=put(zeroFlags,[
    "status":"HISTORICAL_UNLABELED_REGION_TRACKS_ONLY",
    "frame_count":4,"seed_coordinates":"TOP_LEFT_FRACTIONS",
    "vision_boxes":"BOTTOM_LEFT_FRACTIONS",
    "assumed_image_orientation":"UP_UNVERIFIED",
    "source_kind":"RETAINED_CAPTURE_ONE_TAP_HISTORY",
    "samples":samples])
  func run(_ f:[String:Any]=feature,_ j:[String:Any]=joined,
           _ t:[String:Any]=tracking) -> [String:Any] {
    R663RelativeMotionAudit.audit(feature:f,joined:j,tracking:t)
  }
  func status(_ f:[String:Any]=feature,_ j:[String:Any]=joined,
              _ t:[String:Any]=tracking) -> String {
    run(f,j,t)["status"] as? String ?? "MISSING"
  }
  func reject(_ v:[String:Any],_ field:String,_ id:String) {
    let r=run(feature,joined,put(tracking,v))
    test((r["status"] as? String ?? "").hasPrefix("HOLD_"),id)
    test(r["battle_advice_authorized"] as? Bool == false,id+"_safe")
  }
  let success=run()
  test(success["status"] as? String == "HISTORICAL_TWO_SIGN_RESIDUALS_ONLY","normal")
  test(success["pairs_compared"] as? Int==3,"pairs")
  let rows=success["rows"] as? [[String:Any]] ?? []
  test(rows.count==6,"rows")
  test(rows[0]["region"] as? String=="LEFT_REGION_HYPOTHESIS","region")
  test(rows[0]["residual_if_scene_added"] as? Double != nil,"plus")
  test(rows[0]["residual_if_scene_subtracted"] as? Double != nil,"minus")
  test(rows[0]["from_sha256"] as? String==h[0],"sha")
  test(success["owner_certified"] as? Bool == false,"noOwner")
  test(success["mega_event_certified"] as? Bool == false,"noMega")
  test(success["camera_or_actor_motion_distinguished"] as? Bool==false,"noMotionProof")
  test(success["battle_advice_authorized"] as? Bool==false,"noAdvice")
  test(success["scene_alignment_sign_calibrated"] as? Bool==false,"noSign")
  test(success["current_state_eligible"] as? Bool==false,"historical")
  test(success["held_out_accuracy"] as? String=="NOT_MEASURED","noAccuracy")
  test(status(put(feature,["status":"HOLD"])).hasPrefix("HOLD_"),"sourceFail")
  test(status(feature,put(joined,["source_join_verified":false])).hasPrefix("HOLD_"),"joinFail")
  test(status(feature,joined,put(tracking,["status":"HOLD"])).hasPrefix("HOLD_"),"trackFail")
  test(status(feature,joined,put(tracking,["owner_certified":true])).hasPrefix("HOLD_"),"ownerGuard")
  test(status(feature,joined,put(tracking,["assumed_image_orientation":"DOWN"])).hasPrefix("HOLD_"),"orientation")
  test(status(feature,joined,put(tracking,["frame_count":3])).hasPrefix("HOLD_"),"frames")
  test(status(put(feature,["frame_ids":[10,11,11,13]])).hasPrefix("HOLD_"),"duplicateFrame")
  test(status(put(feature,["image_sha256":[h[0],h[1],h[2],h[2]]])).hasPrefix("HOLD_"),"duplicateHash")
  test(status(put(feature,["observed_ms_monotonic":[100,200,11000,12000]])).hasPrefix("HOLD_"),"timeGap")
  test(status(put(feature,["frame_ids":[true,11,12,13]])).hasPrefix("HOLD_"),"boolFrame")
  var sampleBad=samples
  sampleBad[0]["to_sha256"]=h[2]
  test(status(feature,joined,put(tracking,["samples":sampleBad])).hasPrefix("HOLD_"),"shaMismatch")
  sampleBad=samples;sampleBad[0]["from_observed_ms"]=101
  test(status(feature,joined,put(tracking,["samples":sampleBad])).hasPrefix("HOLD_"),"timeMismatch")
  sampleBad=samples;sampleBad[0]["box_width"]=0.98
  test(status(feature,joined,put(tracking,["samples":sampleBad])).hasPrefix("HOLD_"),"boxOut")
  sampleBad=samples;sampleBad[0]["source_is_pokemon"]=true
  test(status(feature,joined,put(tracking,["samples":sampleBad])).hasPrefix("HOLD_"),"fakePokemon")
  sampleBad=samples;sampleBad[0]["tracker_confidence_unvalidated"]=Double.nan
  test(status(feature,joined,put(tracking,["samples":sampleBad])).hasPrefix("HOLD_"),"confidenceNan")
  sampleBad=samples;sampleBad.append(samples[0]);sampleBad.remove(at:1)
  test(status(feature,joined,put(tracking,["samples":sampleBad])).hasPrefix("HOLD_"),"duplicateRegion")
  var joinBad=joinPairs;joinBad[0]["translation_x_fraction"]=Double.infinity
  test(status(feature,put(joined,["pairs":joinBad])).hasPrefix("HOLD_"),"cameraInf")
  joinBad=joinPairs;joinBad[0]["translation_magnitude_fraction"]=0.75
  test(status(feature,put(joined,["pairs":joinBad])).hasPrefix("HOLD_"),"magnitudeMismatch")
  joinBad=joinPairs;joinBad[0]["feature_distance_by_region_unscaled"]=[:]
  test(status(feature,put(joined,["pairs":joinBad])).hasPrefix("HOLD_"),"featureMiss")
  print("R663_RELATIVE_MOTION_GATE_PASS",checks)
 }
}
