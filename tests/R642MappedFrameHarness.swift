import Foundation
@main struct Test {
static func main() {
var checked=0
func pass(_ b:Bool,_ label:String) {precondition(b,label);checked+=1; print("R642_PASS",label)}
let a=String(repeating:"a",count:64),b=String(repeating:"b",count:64),session="battle-x"
let roi:[String:Int]=["x":20,"y":30,"width":50,"height":10]
let row:[String:Any]=["evidence_ref":"payload_json.readings[0]","raw_text":"148/197",
"roi":roi,"image_sha256":a,"capture_session_id":session,
"frame_id":Int64(11),"epoch":Int64(2),"owner_verified":false]
let cand:[String:Any]=["role_hint":"own_hp","slot":NSNull(),"source_ref":"payload_json.readings[0]",
"raw_text":"148/197","side":"UNKNOWN_OWNER","owner_verified":false,
"orientation_verified":false,"current_value_admitted":false,
"source_sha256":a,"status":"PROVISIONAL_LAYOUT_VALUE_ONLY"]
let diag:[String:Any]=["schema":R641RotatedHUDCandidates.schema,
"source_kind":"LIVE_RETAINED_FRAME","source_orientation_verified":false,
"owner_verified":false,"game_fields_certified":0,"battle_advice_authorized":false,
"matching_profile_count":1,"rotation_candidate_degrees":90,"source_image_sha256":a,
"candidate_values":[cand]]
let snap:[String:Any]=["current_state_eligible":false,"battle_advice_authorized":false,
"capture_session_id":session,"frame_id":Int64(11),"epoch":Int64(2),
"image_sha256":a,"ocr_source_inventory":[row]]
let cov:[String:Any]=["schema":R581ReadabilityCoverage.schema,
"source_kind":"LIVE_RETAINED_FRAME","snapshot_binding_valid":true,
"source_binding_valid":true,"current_state_eligible":false,
"owner_certified":false,"image_sha256":a,"analysis_image_sha256":a]
let base:[String:Any]=["r641_status":"UNIQUE_LAYOUT_HYPOTHESIS_NOT_CERTIFIED",
"r641_rotated_hud_candidates":diag,"screen_read_state":snap,
"r581_full_read_coverage":cov,"png_sha256":a,
"image_width":1000,"image_height":1000]
func run(_ d:[String:Any],_ kind:String="LIVE_RETAINED_FRAME")->[String:Any] {
var v=d;R642MappedFrameProof.enrich(&v,sourceKind:kind);return v
}
var v=run(base)
pass(v["r642_status"] as? String=="PROVISIONAL_RAW_FRAME_ROIS_ONLY","identity_accept")
var report=v["r642_raw_frame_roi_evidence"] as! [String:Any]
let rec=(report["mapped_values"] as! [[String:Any]])[0]
pass(rec["raw_frame_rect"] as? [String:Int]==roi,"identity_exact_coordinate")
pass(report["image_turn_candidate_degrees"] as? Int==90,"orientation_is_candidate")
pass(report["game_fields_certified"] as? Int==0 && report["owner_verified"] as? Bool==false,"no_game_promotion")
pass(JSONSerialization.isValidJSONObject(v),"json_output_valid")
var mutant=base;mutant["r641_status"]="HOLD_MULTIPLE_LAYOUT_HYPOTHESES"
pass(run(mutant)["r642_status"] as? String=="HOLD_NOT_BOUND_TO_UNIQUE_LAYOUT","reject_multiple_profiles")
mutant=base;var d=diag;d["owner_verified"]=true;mutant["r641_rotated_hud_candidates"]=d
pass(run(mutant)["r642_status"] as? String=="HOLD_NOT_BOUND_TO_UNIQUE_LAYOUT","reject_fake_owner")
mutant=base;var sn=snap;var item=row;item["raw_text"]="0/197";sn["ocr_source_inventory"]=[item];mutant["screen_read_state"]=sn
pass(run(mutant)["r642_status"] as? String=="HOLD_OCR_CANDIDATE_SOURCE_CONFLICT","reject_forged_ocr_text")
mutant=base;sn=snap;item=row;item["image_sha256"]=b;sn["ocr_source_inventory"]=[item];mutant["screen_read_state"]=sn
pass(run(mutant)["r642_status"] as? String=="HOLD_CORRUPTED_OCR_INVENTORY","reject_foreign_frame")
mutant=base;d=diag;d["candidate_values"]=[cand,cand];mutant["r641_rotated_hud_candidates"]=d
pass(run(mutant)["r642_status"] as? String=="HOLD_OCR_CANDIDATE_SOURCE_CONFLICT","reject_duplicate_ref")
mutant=base;d=diag;var c=cand;c["slot"]=1;d["candidate_values"]=[c];mutant["r641_rotated_hud_candidates"]=d
pass(run(mutant)["r642_status"] as? String=="HOLD_NONMOVE_SLOT_PRESENT","reject_nonmove_slot")
mutant=base;d=diag;c=cand;c["role_hint"]="move_pp";c["slot"]=4;d["candidate_values"]=[c];mutant["r641_rotated_hud_candidates"]=d
pass(run(mutant)["r642_status"] as? String=="HOLD_INVALID_MOVE_SLOT","reject_move_slot_4")
let original=R556AnalysisProjection.Plan(rawWidth:1000,rawHeight:1000,
crop:.init(x:100,y:100,width:400,height:800),quarterTurnsCCW:1)
pass(original.valid && original.analysisWidth==800 && original.analysisHeight==400,"projection_plan_valid")
let ar=R556AnalysisProjection.Rect(x:20,y:30,width:50,height:10)
let rr=original.sourceRect(ar)!
pass(rr.object==["x":460,"y":120,"width":10,"height":50],"source_rect_expected")
var transformed=base;transformed["png_sha256"]=b
var cover=cov;cover["image_sha256"]=b;cover["declared_analysis_projection_valid"]=true
transformed["r581_full_read_coverage"]=cover
let map:[String:Any]=["evidence_ref":"payload_json.readings[0]", "analysis_rect":ar.object,"raw_rect":rr.object]
let projection:[String:Any]=["schema":"trueplan.screen-read.analysis-projection.v1",
"status":"DECLARED_GEOMETRY_ONLY","raw_image_sha256":b,"analysis_image_sha256":a,
"capture_session_id":session,"frame_id":Int64(11),"epoch":Int64(2),
"pixel_equality_verified":false,"game_orientation_certified":false,"owner_certified":false,
"raw_width":1000,"raw_height":1000,"analysis_width":800,"analysis_height":400,
"pixel_crop":original.crop.object,"quarter_turns_ccw":1,
"mapped_rois":[map],"omitted_rois":[[String:Any]]()]
transformed["analysis_projection"]=projection
v=run(transformed)
pass(v["r642_status"] as? String=="PROVISIONAL_RAW_FRAME_ROIS_ONLY","projection_accept")
report=v["r642_raw_frame_roi_evidence"] as! [String:Any]
let mapped=(report["mapped_values"] as! [[String:Any]])[0]
pass(mapped["raw_frame_rect"] as? [String:Int]==rr.object,"projection_source_exact")
pass(report["transform_source"] as? String=="DECLARED_R556_CROP_ROTATE","projection_not_certified")
for turns in 0...3 {
let p=R556AnalysisProjection.Plan(rawWidth:1000,rawHeight:1000,
crop:.init(x:100,y:100,width:400,height:800),quarterTurnsCCW:turns)
let aw=p.analysisWidth,ah=p.analysisHeight
let inner=R556AnalysisProjection.Rect(x:10,y:20,width:30,height:15)
let sourceRect=p.sourceRect(inner)
pass(p.valid && inner.fits(width:aw,height:ah) && sourceRect != nil &&
sourceRect!.fits(width:1000,height:1000),"four_way_bounds_\(turns)")
}
mutant=transformed;var pr=projection;var forged=map;forged["raw_rect"]=["x":0,"y":0,"width":50,"height":10];pr["mapped_rois"]=[forged];mutant["analysis_projection"]=pr
pass(run(mutant)["r642_status"] as? String=="HOLD_INCONSISTENT_PROJECTION_MAP","reject_forged_raw_rect")
mutant=transformed;pr=projection;pr["mapped_rois"]=[[String:Any]]();mutant["analysis_projection"]=pr
pass(run(mutant)["r642_status"] as? String=="HOLD_SOURCE_RECT_NOT_VERIFIED","reject_missing_map")
mutant=transformed;pr=projection;pr["game_orientation_certified"]=true;mutant["analysis_projection"]=pr
pass(run(mutant)["r642_status"] as? String=="HOLD_RAW_ANALYSIS_TRANSFORM_UNVERIFIED","reject_fake_orientation")
mutant=transformed;var token=sn;token=snap;item=row;item["roi"]=["x":790,"y":390,"width":40,"height":15];token["ocr_source_inventory"]=[item];mutant["screen_read_state"]=token
pass(run(mutant)["r642_status"] as? String=="HOLD_CORRUPTED_OCR_INVENTORY","reject_out_of_bounds")
var offline=base;offline["image_sha256"]=a;offline.removeValue(forKey:"png_sha256")
d=diag;d["source_kind"]="USER_IMPORTED_PNG_OFFLINE_ONLY";offline["r641_rotated_hud_candidates"]=d
cover=cov;cover["source_kind"]="USER_IMPORTED_PNG_OFFLINE_ONLY";offline["r581_full_read_coverage"]=cover
pass(run(offline,"USER_IMPORTED_PNG_OFFLINE_ONLY")["r642_status"] as? String=="PROVISIONAL_RAW_FRAME_ROIS_ONLY","offline_local_only")
print("R642_ALL_PASS",checked)
}
}
