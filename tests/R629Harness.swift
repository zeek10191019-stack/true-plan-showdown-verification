import Foundation
@main struct R629Harness {
 static func main() {
  var n=0
  func check(_ yes:Bool,_ name:String){precondition(yes,name);n+=1;print("PASS_R629",name)}
  let digest=String(repeating:"a",count:64)
  let priorFlags:[String:Any] = ["certified_for_battle":false,"owner_verified":false,
   "roi_verified":false,"mega_verified":false,"display_orientation_verified":false]
  let bar:[String:Any]=["rect_top_left_norm":["x":0.1,"y":0.11,"width":0.4,"height":0.025],
   "color_class":"GREEN_LIKE","confirmed_hud":false,"owner":"UNKNOWN"]
  let ocr:[String:Any]=["kind":"FRACTION_HP_OR_PP_UNASSIGNED",
   "orientation_hypothesis":"UP",
   "normalized_rect_in_hypothesis":["x":0.12,"y":0.865,"width":0.21,"height":0.03]]
  func frame(_ id:Int64)->[String:Any] {
   ["epoch":Int64(2),"frame_id":id,"original_png_sha256":digest,
    "pixel_probe":["status":"HOLD_PIXELS_DECODED_NOT_CALIBRATED",
                   "colored_runs":[bar]]]
  }
  func original(_ id:Int64)->[String:Any] {
   ["epoch":Int64(2),"frame_id":id,"original_png_sha256":digest,
    "observations":[ocr]]
  }
  func valid(_ ids:[Int64])->[String:Any] {
   var p=priorFlags
   p["schema"]="trueplan.r617-r620.rotation_readout.v1"
   var r=priorFlags
   r["schema"]="trueplan.r625-r628.pixel_hud_sprite_probes.v1"
   r["status"]="HOLD_PIXEL_LOCATIONS_NOT_GROUND_TRUTH"
   r["frames"]=ids.map(frame)
   p["r625_r628_embedded_pixel_probe_report"]=r
   var old=priorFlags
   old["schema"]="trueplan.r621-r624.visual_candidate_slots.v1"
   old["r622_ui_slot_hypotheses"]=ids.map(original)
   p["r621_r624_embedded_candidate_report"]=old
   return p
  }
  var p=valid([7]);var report=R629R632SlotEvidence.analyze(p)
  check(report["status"] as? String=="HOLD_SLOTS_LOCATED_BUT_OWNER_HP_MEGA_UNVERIFIED","one_frame_spatial")
  check(report["owner_verified"] as? Bool == false,"no_own_cert")
  check(report["mega_verified"] as? Bool == false,"no_mega_cert")
  check(report["certified_for_battle"] as? Bool == false,"no_battle_cert")
  check(report["recognized_own_hp"] is NSNull,"no_hp_value")
  let slots=report["slots"] as? [[String:Any]] ?? []
  check(slots.count==1,"single_ocr_slot")
  check(slots.first?["actor"] as? String=="UNKNOWN","actor_unknown")
  check(slots.first?["role_hint"] as? String=="POSSIBLY_OWN_OR_PP","role_not_certified")
  check(slots.first?["screen_half_hypothesis"] as? String=="TOP","top_image_half")
  check((report["temporal_pixel_tracks"] as? [[String:Any]])?.isEmpty==true,"no_temporal_single")
  R629R632SlotEvidence.enrich(&p)
  check(p[R629R632SlotEvidence.key] is [String:Any],"add_to_existing_json")
  let once=(p[R629R632SlotEvidence.key] as? [String:Any])?["slots"] as? [[String:Any]]
  R629R632SlotEvidence.enrich(&p)
  check((p[R629R632SlotEvidence.key] as? [String:Any])?["slots"] as? [[String:Any]] != nil && once?.count==1,"idempotent")
  report=R629R632SlotEvidence.analyze(valid([7,8]));let tracks=report["temporal_pixel_tracks"] as? [[String:Any]] ?? []
  check(tracks.count==1,"two_frame_same_bar_track")
  check(tracks[0]["hp_change_certified"] as? Bool == false,"track_no_hp_change")
  var bad=valid([7,7]);report=R629R632SlotEvidence.analyze(bad)
  check(report["status"] as? String=="HOLD_UNVERIFIED_INPUT","duplicate_frame_rejected")
  bad=valid([7]);var prior=bad["r625_r628_embedded_pixel_probe_report"] as! [String:Any]
  prior["owner_verified"]=true;bad["r625_r628_embedded_pixel_probe_report"]=prior
  check(R629R632SlotEvidence.analyze(bad)["status"] as? String=="HOLD_UNVERIFIED_INPUT","forged_ownership_rejected")
  bad=valid([7]);var old=bad["r621_r624_embedded_candidate_report"] as! [String:Any]
  var rows=old["r622_ui_slot_hypotheses"] as! [[String:Any]]
  rows[0]["original_png_sha256"]=String(repeating:"b",count:64)
  old["r622_ui_slot_hypotheses"]=rows;bad["r621_r624_embedded_candidate_report"]=old
  check(R629R632SlotEvidence.analyze(bad)["status"] as? String=="HOLD_UNVERIFIED_INPUT","hash_mismatch_rejected")
  bad=valid([7]);old=bad["r621_r624_embedded_candidate_report"] as! [String:Any]
  rows=old["r622_ui_slot_hypotheses"] as! [[String:Any]]
  var obs=(rows[0]["observations"] as! [[String:Any]])[0]
  obs["orientation_hypothesis"]="LEFT"
  rows[0]["observations"]=[obs];old["r622_ui_slot_hypotheses"]=rows
  bad["r621_r624_embedded_candidate_report"]=old
  check((R629R632SlotEvidence.analyze(bad)["slots"] as? [[String:Any]])?.isEmpty==true,"rotated_reading_held")
  bad=valid([7]);old=bad["r621_r624_embedded_candidate_report"] as! [String:Any]
  rows=old["r622_ui_slot_hypotheses"] as! [[String:Any]]
  obs=(rows[0]["observations"] as! [[String:Any]])[0]
  obs["normalized_rect_in_hypothesis"]=["x":Double.nan,"y":0.8,"width":0.2,"height":0.03]
  rows[0]["observations"]=[obs];old["r622_ui_slot_hypotheses"]=rows
  bad["r621_r624_embedded_candidate_report"]=old
  check((R629R632SlotEvidence.analyze(bad)["slots"] as? [[String:Any]])?.isEmpty==true,"nan_coordinate_held")
  print("R629_R632_CHECKS=\(n)_NO_REAL_GAME_CERTIFICATION")
 }
}
