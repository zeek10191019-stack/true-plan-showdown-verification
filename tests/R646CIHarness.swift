import Foundation
@main struct R646CIHarness {
static func main() {
var n=0
func ck(_ value:Bool,_ name:String){precondition(value,name);n+=1}
let sha=String(repeating:"a",count:64),session="ci-sid"
let names=R581ReadabilityCoverage.tracks.map{$0.0}
ck(names.count==79,"79")
ck(Set(names).count==79,"unique")
func token(_ i:Int,_ value:String)->[String:Any]{
["evidence_ref":"ref\(i)","raw_text":value,
"roi":["x":20+i*10,"y":50,"width":60,"height":20],
"image_sha256":sha,"capture_session_id":session,
"frame_id":1,"epoch":1,"owner_verified":false]}
let src=["あめ 残り3ターン","やけど","リフレクター",
"81%","メガシンカ","10/16","引っ込めた"]
var snap:[String:Any]=["source_validation":"PASS_FRAME_BINDING_ONLY",
"current_state_eligible":false,"battle_advice_authorized":false,
"image_sha256":sha,"capture_session_id":session,
"frame_id":1,"epoch":1,
"ocr_source_inventory":src.enumerated().map{token($0.offset,$0.element)},
"screen_kind":"move_selection_candidate"]
let cover:[String:Any]=["schema":R581ReadabilityCoverage.schema,
"source_kind":"USER_IMPORTED_PNG_OFFLINE_ONLY",
"source_binding_valid":true,"snapshot_binding_valid":true,
"current_state_eligible":false,"battle_advice_authorized":false,
"image_sha256":sha,"analysis_image_sha256":sha,
"fields":names.map{["field":$0,"observed_metadata_value":NSNull()] as [String:Any]}]
var doc:[String:Any]=["image_sha256":sha,"image_width":1000,
"image_height":500,"screen_read_state":snap,
"r581_full_read_coverage":cover]
func run(_ d:[String:Any])->[String:Any]{var c=d
R646FieldSignalReaders.enrich(&c,
sourceKind:"USER_IMPORTED_PNG_OFFLINE_ONLY");return c}
let output=run(doc)
ck(output["r646_status"] as? String ==
"79_SOURCE_READER_ATTEMPTS_NOT_GAME_CERTIFIED","status")
let report=output["r646_field_readers"] as! [String:Any]
let fields=report["field_read_attempts"] as! [[String:Any]]
ck(fields.count==79,"count")
ck(fields.compactMap{$0["field"] as? String}==names,"order")
func item(_ name:String)->[String:Any]{fields.first{$0["field"] as? String == name}!}
func refs(_ name:String)->Int{
(item(name)["ocr_evidence"] as! [[String:Any]]).count}
ck(refs("field.weather")==1,"weather")
ck(refs("own.major_status")==1,"status_candidate")
ck(refs("own.reflect")==1,"reflect")
ck(refs("opponent.reflect")==1,"owner_unproved")
ck(refs("battle.mega_history")==1,"mega")
ck(refs("opponent.hp_percent")==1,"hp_percent")
ck(refs("battle.switch_history")==1,"switch_mention")
ck(item("own.mega_visual_form")["attempt_status"] as? String ==
"MODEL_OR_CALIBRATION_MISSING","sprite_unimplemented")
ck(fields.allSatisfy{$0["owner_verified"] as? Bool==false},"no_owners")
ck(fields.allSatisfy{$0["game_value_certified"] as? Bool==false},"no_game")
ck(report["battle_advice_authorized"] as? Bool==false,"no_advice")
ck(JSONSerialization.isValidJSONObject(report),"json")
let source=snap["ocr_source_inventory"] as! [[String:Any]]
snap["ocr_source_inventory"]=source+[source[0]]
doc["screen_read_state"]=snap
ck(run(doc)["r646_status"] as? String ==
"HOLD_OCR_SOURCE_CONTRADICTION","duplicates_rejected")
print("R646_CI_ALL_PASS",n)
}}
