import Foundation
@main struct R641LayoutHarness {
static func main() {
var total=0
func check(_ b:Bool,_ s:String){precondition(b,s);total+=1;print("PASS_R641",s)}
let hash=String(repeating:"a",count:64)
func rect(_ x:Int,_ y:Int,_ w:Int,_ h:Int)->[String:Int]{
["x":x,"y":y,"width":w,"height":h]
}
let base:[(String,[String:Int])]=[
("170/185",rect(205,492,65,21)),
("81%",rect(986,64,55,20)),
("COMMAND",rect(915,111,70,20)),
("じしん",rect(885,245,76,18)),
("りゅうせいぐん",rect(885,310,76,18)),
("10/10",rect(1030,248,34,28)),
("8/10",rect(1030,312,34,28))
]
func withRotation(_ turn:Int,_ tamper:Bool=false,_ duplicate:Bool=false)
->[String:Any] {
let (w,h) = turn%180==0 ? (1156,534):(534,1156)
func source(_ box:[String:Int])->[String:Int] {
let x=box["x"]!,y=box["y"]!,bw=box["width"]!,bh=box["height"]!
switch turn {
case 90:return rect(y,1156-x-bw,bh,bw)
case 180:return rect(1156-x-bw,534-y-bh,bw,bh)
case 270:return rect(534-y-bh,x,bh,bw)
default:return box
}
}
var items=[[String:Any]]()
for (i,p) in base.enumerated() {
items.append(["evidence_ref":"payload_json.readings[\(i)]",
"raw_text":p.0,"roi":source(p.1),"image_sha256":hash,
"capture_session_id":"s1","frame_id":Int64(9),"epoch":Int64(2),
"owner_verified":false] as [String:Any])
}
if tamper {items[1]["image_sha256"]=String(repeating:"b",count:64)}
if duplicate {items.append(items[0])}
return ["image_width":w,"image_height":h,"png_sha256":hash,
"screen_read_state":["image_sha256":hash,"capture_session_id":"s1",
"frame_id":Int64(9),"epoch":Int64(2),"source_validation":"PASS_FRAME_BINDING_ONLY",
"current_state_eligible":false,"battle_advice_authorized":false,
"ocr_source_inventory":items] as [String:Any],
"r581_full_read_coverage":["schema":R581ReadabilityCoverage.schema,
"source_kind":"LIVE_RETAINED_FRAME","snapshot_binding_valid":true,
"source_binding_valid":true,
"owner_certified":false,"current_state_eligible":false,
"image_sha256":hash,"analysis_image_sha256":hash] as [String:Any]]
}
func run(_ doc:[String:Any],_ kind:String="LIVE_RETAINED_FRAME")->[String:Any]{
var d=doc;R641RotatedHUDCandidates.enrich(&d,sourceKind:kind);return d
}
for turn in [0,90,180,270] {
let result=run(withRotation(turn))
let status=result["r641_status"] as? String
check(status=="UNIQUE_LAYOUT_HYPOTHESIS_NOT_CERTIFIED","rotation_\(turn)")
let o=result["r641_rotated_hud_candidates"] as! [String:Any]
check(o["rotation_candidate_degrees"] as? Int==turn,"degrees_\(turn)")
let vals=o["candidate_values"] as! [[String:Any]]
check(vals.contains{$0["role_hint"] as? String=="move_name"},"names_\(turn)")
check(vals.contains{$0["role_hint"] as? String=="move_pp"},"pp_\(turn)")
check(vals.allSatisfy{$0["owner_verified"] as? Bool==false},"never_owner_\(turn)")
}
check(run(withRotation(90,true))["r641_status"] as? String=="HOLD_CORRUPTED_OCR_INVENTORY","sha_tamper")
check(run(withRotation(0,false,true))["r641_status"] as? String=="HOLD_CORRUPTED_OCR_INVENTORY","duplicate_token")
var wrong=withRotation(0);wrong["png_sha256"]=String(repeating:"b",count:64)
check(run(wrong)["r641_status"] as? String=="HOLD_UNBOUND_RAW_OCR","raw_sha")
var noSnap=withRotation(0);noSnap.removeValue(forKey:"screen_read_state")
check(run(noSnap)["r641_status"] as? String=="HOLD_UNBOUND_RAW_OCR","snapshot_required")
let val=run(withRotation(0))["r641_rotated_hud_candidates"] as! [String:Any]
check(val["game_fields_certified"] as? Int==0,"never_certify")
check(JSONSerialization.isValidJSONObject(run(withRotation(90))),"serializable")
var portrait=withRotation(90)
if var cov=portrait["r581_full_read_coverage"] as? [String:Any] {
cov["snapshot_binding_valid"]=false;portrait["r581_full_read_coverage"]=cov
}
check(run(portrait)["r641_status"] as? String=="HOLD_UNBOUND_RAW_OCR","projection_gate")
var projected=withRotation(90)
let analysisSHA=hash,rawSHA=String(repeating:"c",count:64)
projected["png_sha256"]=rawSHA
projected["image_width"]=2000
projected["image_height"]=1000
var projectedCov=projected["r581_full_read_coverage"] as! [String:Any]
projectedCov["image_sha256"]=rawSHA
projectedCov["declared_analysis_projection_valid"]=true
projected["r581_full_read_coverage"]=projectedCov
projected["analysis_projection"]=[
"schema":"trueplan.screen-read.analysis-projection.v1",
"status":"DECLARED_GEOMETRY_ONLY", "raw_image_sha256":rawSHA,
"analysis_image_sha256":analysisSHA,"frame_id":Int64(9),
"epoch":Int64(2),"capture_session_id":"s1",
"raw_width":2000,"raw_height":1000,"analysis_width":534,
"analysis_height":1156,"game_orientation_certified":false,
"owner_certified":false] as [String:Any]
check(run(projected)["r641_status"] as? String ==
"UNIQUE_LAYOUT_HYPOTHESIS_NOT_CERTIFIED","projection_uses_analysis_dimensions")
var badProjection=projected
var proj=projected["analysis_projection"] as! [String:Any]
proj["analysis_height"]=1000
badProjection["analysis_projection"]=proj
check(run(badProjection)["r641_status"] as? String ==
"HOLD_NO_SUPPORTED_LAYOUT","projection_wrong_dimensions_no_match")
var noCommand=withRotation(90)
var snapshot=noCommand["screen_read_state"] as! [String:Any]
var inventory=snapshot["ocr_source_inventory"] as! [[String:Any]]
inventory.remove(at:2);snapshot["ocr_source_inventory"]=inventory
noCommand["screen_read_state"]=snapshot
check(run(noCommand)["r641_status"] as? String ==
"UNIQUE_LAYOUT_HYPOTHESIS_NOT_CERTIFIED","two_hp_two_moves_fallback")
print("R641_LOCAL_ALL_PASS",total)
}
}
