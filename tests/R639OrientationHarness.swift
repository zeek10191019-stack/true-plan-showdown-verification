import Foundation
@main struct R639OrientationHarness {
 static func main(){
  var checks=0
  func ok(_ predicate:Bool,_ name:String){precondition(predicate,name);checks+=1;print("R639_PASS",name)}
  let hash=String(repeating:"a",count:64)
  let session="abc"
  let width=1156,height=534
  // Centred rectangles wholly inside each expected gameplay anchor.
  func box(_ fx:Double,_ fy:Double,_ fw:Double,_ fh:Double)->[String:Int]{
   ["x":Int(fx*Double(width)),"y":Int(fy*Double(height)),
    "width":Int(fw*Double(width)),"height":Int(fh*Double(height))]
  }
  func token(_ ref:String,_ text:String,_ rect:[String:Int])->[String:Any]{
   ["evidence_ref":ref,"raw_text":text,"roi":rect,"image_sha256":hash,
    "capture_session_id":session,"frame_id":9,"epoch":1,"owner_verified":false]
  }
  let source=[token("own","170/185",box(0.18,0.91,0.03,0.04)),
              token("opp","81%",box(0.85,0.11,0.03,0.03)),
              token("cmd","COMMAND",box(0.80,0.21,0.04,0.03))]
  func base(_ toks:[[String:Any]])->[String:Any]{
   ["image_width":width,"image_height":height,
    "r638_status":"SOURCE_AND_LAYOUT_BOUND_HISTORICAL_ONLY",
    "r638_binding_audit":["schema":"trueplan.r638.full-ocr-layout-binding.v1",
      "source_kind":"LIVE_RETAINED_FRAME","game_fields_certified":0,
      "owner_verified":false,"source_orientation_verified":false,"image_sha256":hash],
    "screen_read_state":["current_state_eligible":false,"battle_advice_authorized":false,
      "image_sha256":hash,"capture_session_id":session,"frame_id":9,"epoch":1,
      "ocr_source_inventory":toks]]
  }
  var doc=base(source)
  R639OrientationHypotheses.enrich(&doc,sourceKind:"LIVE_RETAINED_FRAME")
  ok(doc["r639_status"] as? String == "UNIQUE_ROTATION_HYPOTHESIS_NOT_CERTIFIED","unique_zero")
  let receipt=doc["r639_orientation_probe"] as! [String:Any]
  ok(receipt["candidate_rotation_clockwise"] as? Int == 0,"zero_rotation")
  ok(receipt["owner_verified"] as? Bool == false,"no_owner")
  ok(receipt["orientation_verified"] as? Bool == false,"no_false_calibration")
  ok(receipt["game_fields_certified"] as? Int == 0,"no_game_values")
  ok((receipt["profiles"] as! [[String:Any]]).count == 4,"four_directions")
  // Generate a physically rotated portrait image with coordinates reprojected.
  var portrait=source
  for i in portrait.indices {
   let src=portrait[i]["roi"] as! [String:Int]
   portrait[i]["roi"]=["x":src["y"]!,"y":width-src["x"]!-src["width"]!,
                         "width":src["height"]!,"height":src["width"]!]
  }
  var d=base(portrait);d["image_width"]=height;d["image_height"]=width
  R639OrientationHypotheses.enrich(&d,sourceKind:"LIVE_RETAINED_FRAME")
  let pr=d["r639_orientation_probe"] as? [String:Any]
  ok(pr?["candidate_rotation_clockwise"] as? Int == 90,"portrait_to_landscape")
  // All rotations preserve the same exact, frame-bound OCR rectangles.
  for (turn, expected) in [(180,180),(270,270)] {
   var alternate=source
   for i in alternate.indices {
    let src=alternate[i]["roi"] as! [String:Int]
    if turn==180 {
     alternate[i]["roi"]=["x":width-src["x"]!-src["width"]!,
                         "y":height-src["y"]!-src["height"]!,
                         "width":src["width"]!,"height":src["height"]!]
    } else {
     alternate[i]["roi"]=["x":height-src["y"]!-src["height"]!,
                         "y":src["x"]!,"width":src["height"]!,
                         "height":src["width"]!]
    }
   }
   var rotated=base(alternate)
   if turn==270 {rotated["image_width"]=height;rotated["image_height"]=width}
   R639OrientationHypotheses.enrich(&rotated,sourceKind:"LIVE_RETAINED_FRAME")
   let probe=rotated["r639_orientation_probe"] as? [String:Any]
   ok(probe?["candidate_rotation_clockwise"] as? Int == expected,
      "rotation_\(expected)_inverse")
  }
  var inverted=source
  for i in inverted.indices {
   let src=inverted[i]["roi"] as! [String:Int]
   inverted[i]["roi"]=["x":width-src["x"]!-src["width"]!,
                       "y":height-src["y"]!-src["height"]!,
                       "width":src["width"]!,"height":src["height"]!]
   inverted[i]["evidence_ref"]="inverted_\(i)"
  }
  var doubled=base(source+inverted)
  R639OrientationHypotheses.enrich(&doubled,sourceKind:"LIVE_RETAINED_FRAME")
  ok(doubled["r639_status"] as? String == "HOLD_MULTIPLE_ROTATION_MATCHES",
     "ambiguous_rotation_rejected")
  var invalidHP=source
  invalidHP[0]["raw_text"]="170/0"
  var hpDoc=base(invalidHP)
  R639OrientationHypotheses.enrich(&hpDoc,sourceKind:"LIVE_RETAINED_FRAME")
  ok(hpDoc["r639_status"] as? String == "HOLD_NO_THREE_ANCHOR_ROTATION",
     "hp_zero_max_rejected")
  var forged=base(source)
  var forgedAudit=forged["r638_binding_audit"] as! [String:Any]
  forgedAudit["owner_verified"]=true
  forged["r638_binding_audit"]=forgedAudit
  R639OrientationHypotheses.enrich(&forged,sourceKind:"LIVE_RETAINED_FRAME")
  ok(forged["r639_status"] as? String == "HOLD_SOURCE_AND_ORIENTATION_UNVERIFIED",
     "owner_forgery_rejected")
  var bad=base(Array(source.prefix(2)))
  R639OrientationHypotheses.enrich(&bad,sourceKind:"LIVE_RETAINED_FRAME")
  ok(bad["r639_status"] as? String == "HOLD_NO_THREE_ANCHOR_ROTATION","missing_command")
  var dupe=base(source+[source[0]])
  R639OrientationHypotheses.enrich(&dupe,sourceKind:"LIVE_RETAINED_FRAME")
  ok(dupe["r639_status"] as? String == "HOLD_BAD_OCR_INVENTORY","duplicate_ref")
  var mismatch=base(source);var ss=mismatch["screen_read_state"] as! [String:Any];
  var badSource=source;badSource[0]["image_sha256"]=String(repeating:"b",count:64)
  ss["ocr_source_inventory"]=badSource;mismatch["screen_read_state"]=ss
  R639OrientationHypotheses.enrich(&mismatch,sourceKind:"LIVE_RETAINED_FRAME")
  ok(mismatch["r639_status"] as? String == "HOLD_BAD_OCR_INVENTORY","hash_mismatch")
  var invalid=base(source)
  var toks=source;toks[0]["roi"]=["x":2000,"y":500,"width":10,"height":10]
  var snap=invalid["screen_read_state"] as! [String:Any];snap["ocr_source_inventory"]=toks
  invalid["screen_read_state"]=snap
  R639OrientationHypotheses.enrich(&invalid,sourceKind:"LIVE_RETAINED_FRAME")
  ok(invalid["r639_status"] as? String == "HOLD_BAD_OCR_INVENTORY","roi_outside")
  var wrongSource=base(source)
  R639OrientationHypotheses.enrich(&wrongSource,sourceKind:"DIFFERENT")
  ok(wrongSource["r639_status"] as? String == "HOLD_SOURCE_AND_ORIENTATION_UNVERIFIED","wrong_source")
  ok(JSONSerialization.isValidJSONObject(doc),"json_valid")
  print("R639_ALL_PASS",checks)
 }
}
