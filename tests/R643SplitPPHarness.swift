import Foundation
@main struct R643CIHarness {
static func main(){
var c=0
func ok(_ b:Bool,_ s:String){precondition(b,s);c+=1;print("PASS_R643",s)}
let hash=String(repeating:"a",count:64),sid="f"
func token(_ id:String,_ t:String,_ x:Int,_ y:Int)->[String:Any]{[
"evidence_ref":id,"raw_text":t,"roi":["x":x,"y":y,"width":12,"height":12],
"image_sha256":hash,"capture_session_id":sid,"frame_id":1,
"epoch":2,"owner_verified":false]}
let a=token("a","10",510,123),b=token("b","/16",523,123)
let p:[String:Any]=["schema":R642MappedFrameProof.schema,
"source_kind":"LIVE_RETAINED_FRAME","owner_verified":false,
"source_orientation_verified":false,"battle_advice_authorized":false,
"game_fields_certified":0,"image_turn_candidate_degrees":0,
"raw_image_sha256":hash,"analysis_image_sha256":hash,
"frame_id":1,"epoch":2,"capture_session_id":sid,
"analysis_width":578,"analysis_height":267,
"raw_width":578,"raw_height":267,"mapped_values":[] as [[String:Any]]]
let snap:[String:Any]=["image_sha256":hash,"capture_session_id":sid,
"frame_id":1,"epoch":2,"current_state_eligible":false,
"ocr_source_inventory":[a,b]]
let base:[String:Any]=["r642_status":"PROVISIONAL_RAW_FRAME_ROIS_ONLY",
"r641_status":"UNIQUE_LAYOUT_HYPOTHESIS_NOT_CERTIFIED",
"r642_raw_frame_roi_evidence":p,"screen_read_state":snap]
func run(_ v:[String:Any])->[String:Any]{var x=v;R643SplitPPProof.enrich(&x,sourceKind:"LIVE_RETAINED_FRAME");return x}
func report(_ v:[String:Any])->[String:Any]{run(v)["r643_split_pp_evidence"] as! [String:Any]}
let good=run(base),g=good["r643_split_pp_evidence"] as! [String:Any]
let values=g["split_pp_candidates"] as! [[String:Any]]
ok(good["r643_status"] as? String=="PROVISIONAL_PP_FRAGMENTS_ONLY","valid")
ok(values.count==1,"one_pair")
ok(values[0]["slot"] as? Int==0,"slot")
ok(values[0]["current"] as? Int==10 && values[0]["maximum"] as? Int==16,"values")
ok(values[0]["owner_verified"] as? Bool==false &&
values[0]["current_value_admitted"] as? Bool==false,"no_promote")
ok(g["game_fields_certified"] as? Int==0,"uncertified")
ok(JSONSerialization.isValidJSONObject(good),"json")
func withTokens(_ t:[[String:Any]])->[String:Any]{var x=base;var s=snap;s["ocr_source_inventory"]=t;x["screen_read_state"]=s;return x}
let dup=run(withTokens([a,a,b]))
ok(dup["r643_status"] as? String=="HOLD_INVALID_SOURCE_TOKEN","duplicate")
var fake=a;fake["frame_id"]=3
ok(run(withTokens([fake,b]))["r643_status"] as? String=="HOLD_INVALID_SOURCE_TOKEN","frame")
fake=a;fake["owner_verified"]=true
ok(run(withTokens([fake,b]))["r643_status"] as? String=="HOLD_INVALID_SOURCE_TOKEN","owner")
fake=a;fake["image_sha256"]=String(repeating:"b",count:64)
ok(run(withTokens([fake,b]))["r643_status"] as? String=="HOLD_INVALID_SOURCE_TOKEN","hash")
let ambiguous=report(withTokens([a,b,token("c","/14",523,123)]))
ok(ambiguous["status"] as? String=="HOLD_AMBIGUOUS_PP_FRAGMENTS","ambiguous")
ok((report(withTokens([token("a","17",510,123),b]))["split_pp_candidates"] as! [[String:Any]]).isEmpty,"bad_fraction")
ok((report(withTokens([a,token("b","/65",523,123)]))["split_pp_candidates"] as! [[String:Any]]).isEmpty,"max64")
var r=base;var parent=p
parent["image_turn_candidate_degrees"]=90
parent["analysis_width"]=267;parent["analysis_height"]=578
parent["raw_width"]=267;parent["raw_height"]=578
r["r642_raw_frame_roi_evidence"]=parent
var s=snap;s["ocr_source_inventory"]=[token("a","10",123,56),token("b","/16",123,43)]
r["screen_read_state"]=s
ok((report(r)["split_pp_candidates"] as! [[String:Any]]).count==1,"portrait90")
r=base;parent=p;parent["mapped_values"]=[["reference":"a","role_hint":"move_name"]]
r["r642_raw_frame_roi_evidence"]=parent
ok((report(r)["split_pp_candidates"] as! [[String:Any]]).isEmpty,"no_ref_reuse")
print("R643_CI_ALL_PASS",c)
}
}
