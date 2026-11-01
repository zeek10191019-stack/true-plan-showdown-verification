import Foundation
@main struct R644Harness {
 static func main() {
  var n=0
  func ok(_ b:Bool,_ s:String){precondition(b,s);n+=1;print("R644_PASS",s)}
  let a=String(repeating:"a",count:64),b=String(repeating:"b",count:64),sid="test"
  let names=["じしん","れいとう","かえん","シャドー"]
  let pp=["1/8","2/16","3/24","4/32"]
  func src(_ ref:String,_ txt:String)->[String:Any] {
   ["evidence_ref":ref,"raw_text":txt,"image_sha256":a,
    "capture_session_id":sid,"frame_id":1,"epoch":2,"owner_verified":false]
  }
  func mapped(_ role:String,_ slot:Int,_ ref:String,_ txt:String)->[String:Any] {
   ["role_hint":role,"slot":slot,"reference":ref,"raw_text":txt,
    "source_image_sha256":b,"analysis_image_sha256":a,
    "owner_verified":false,"current_value_admitted":false]
  }
  func candidate(_ role:String,_ slot:Int,_ ref:String,_ txt:String,_ v:Any)->[String:Any] {
   ["role_hint":role,"slot":slot,"source_ref":ref,"raw_text":txt,
    "source_sha256":a,"side":"UNKNOWN_OWNER","owner_verified":false,
    "current_value_admitted":false,"value":v]
  }
  var inv=[[String:Any]](),bound=[[String:Any]](),typed=[[String:Any]]()
  for i in 0..<4 {
   let nr="n\(i)",pr="p\(i)"
   inv += [src(nr,names[i]),src(pr,pp[i])]
   bound += [mapped("move_name",i,nr,names[i]),mapped("move_pp",i,pr,pp[i])]
   typed += [candidate("move_name",i,nr,names[i],names[i]),
    candidate("move_pp",i,pr,pp[i],["current":i+1,"maximum":8*(i+1)])]
  }
  let base:[String:Any]=["schema":"trueplan.r642.raw-frame-roi-evidence.v1",
   "source_kind":"LIVE_RETAINED_FRAME","owner_verified":false,
   "source_orientation_verified":false,"battle_advice_authorized":false,
   "game_fields_certified":0,"frame_id":1,"epoch":2,
   "capture_session_id":sid,"raw_image_sha256":b,
   "analysis_image_sha256":a,"mapped_values":bound]
  let hud:[String:Any]=["schema":"trueplan.r641.four-way-independent-layout.v1",
   "source_kind":"LIVE_RETAINED_FRAME","source_image_sha256":a,
   "matching_profile_count":1,"source_orientation_verified":false,
   "owner_verified":false,"candidate_values":typed]
  let snap:[String:Any]=["image_sha256":a,"capture_session_id":sid,
   "frame_id":1,"epoch":2,"current_state_eligible":false,
   "battle_advice_authorized":false,"ocr_source_inventory":inv]
  let original:[String:Any]=[
   "r642_status":"PROVISIONAL_RAW_FRAME_ROIS_ONLY",
   "r642_raw_frame_roi_evidence":base,
   "r641_status":"UNIQUE_LAYOUT_HYPOTHESIS_NOT_CERTIFIED",
   "r641_rotated_hud_candidates":hud,
   "screen_read_state":snap,"r643_status":"HOLD_NO_BOUND_LAYOUT"]
  func run(_ x:[String:Any],kind:String="LIVE_RETAINED_FRAME")->[String:Any] {
   var y=x;R644MoveSlotCoupler.enrich(&y,sourceKind:kind);return y
  }
  func status(_ x:[String:Any])->String {run(x)["r644_status"] as? String ?? ""}
  let good=run(original)
  ok(status(original)=="FOUR_HISTORICAL_PAIRS_UNCERTIFIED","four")
  let receipt=good["r644_four_move_slots"] as! [String:Any]
  ok(receipt["matched_pair_count"] as? Int==4,"count")
  ok(receipt["game_fields_certified"] as? Int==0,"never_promote")
  ok(receipt["battle_advice_authorized"] as? Bool==false,"never_advice")
  ok(JSONSerialization.isValidJSONObject(good),"json")
  let slots=receipt["four_slots"] as! [[String:Any]]
  ok(slots.count==4 && slots[3]["status"] as? String=="COUPLED_OCR_CANDIDATE_ONLY","slot4")
  var edit=original;var s=snap;s["epoch"]=4;edit["screen_read_state"]=s
  ok(status(edit)=="HOLD_UNBOUND_PARENT_EVIDENCE","cross_frame")
  edit=original;s=snap;s["ocr_source_inventory"]=inv+[inv[0]];edit["screen_read_state"]=s
  ok(status(edit)=="HOLD_OCR_INVENTORY_CONFLICT","duplicate")
  edit=original;var h=hud;var t=typed;var v=t[0];v["value"]="かえん";t[0]=v
  h["candidate_values"]=t;edit["r641_rotated_hud_candidates"]=h
  ok(status(edit)=="HOLD_DUPLICATE_MOVE_NAME","name_conflict")
  edit=original;h=hud;t=typed;v=t[1];v["value"]=["current":0,"maximum":8];t[1]=v
  h["candidate_values"]=t;edit["r641_rotated_hud_candidates"]=h
  ok(status(edit)=="HOLD_DUPLICATE_OR_INVALID_PP","pp_conflict")
  edit=original;h=hud;t=typed;t.remove(at:7);h["candidate_values"]=t
  edit["r641_rotated_hud_candidates"]=h
  ok(status(edit)=="PARTIAL_HISTORICAL_PAIRS_UNCERTIFIED","partial")
  var bb=base;var mm=bound;mm.remove(at:7);bb["mapped_values"]=mm
  s=snap;var ii=inv;ii.remove(at:7)
  ii += [src("x","4"),src("y","/32")]
  s["ocr_source_inventory"]=ii
  edit["r642_raw_frame_roi_evidence"]=bb
  edit["screen_read_state"]=s
  let fragment:[String:Any]=[
   "schema":"trueplan.r643.split-pp-evidence.v1",
   "source_kind":"LIVE_RETAINED_FRAME","raw_image_sha256":b,
   "analysis_image_sha256":a,"capture_session_id":sid,
   "frame_id":1,"epoch":2,"owner_verified":false,
   "game_fields_certified":0,"ambiguous_slots":[Int](),
   "split_pp_candidates":[["slot":3,"current":4,"maximum":32,
    "source_refs":["x","y"],"raw_texts":["4","/32"]]]]
  edit["r643_status"]="PROVISIONAL_PP_FRAGMENTS_ONLY"
  edit["r643_split_pp_evidence"]=fragment
  ok(status(edit)=="FOUR_HISTORICAL_PAIRS_UNCERTIFIED","split_pp")
  let coupled=run(edit)["r644_four_move_slots"] as! [String:Any]
  let cp=coupled["four_slots"] as! [[String:Any]]
  ok(cp[3]["pp_method"] as? String=="SPLIT_OCR_PP","split_kind")
  var f=fragment;f["split_pp_candidates"]=[["slot":3,"current":3,"maximum":32,
    "source_refs":["x","y"],"raw_texts":["4","/32"]]]
  edit["r643_split_pp_evidence"]=f
  ok(status(edit)=="HOLD_SPLIT_PP_COLLISION","split_tamper")
  f=fragment;f["ambiguous_slots"]=[3];f["split_pp_candidates"]=[[String:Any]]()
  edit["r643_split_pp_evidence"]=f
  edit["r643_status"]="HOLD_AMBIGUOUS_PP_FRAGMENTS"
  ok(status(edit)=="HOLD_AMBIGUOUS_PP_SLOTS","ambiguous")
  ok(run(original,kind:"BAD")["r644_status"] as? String=="HOLD_UNBOUND_PARENT_EVIDENCE","bad_kind")
  print("R644_ALL_PASS",n)
 }
}
