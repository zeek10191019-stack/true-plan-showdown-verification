import Foundation
@main struct R678Smoke {
typealias T=R668PlainHUDReader.Token
static let sha=String(repeating:"a",count:64)
static func t(_ id:String,_ s:String,_ x:Double,_ y:Double)->T {
T(ref:id,text:s,x:x,y:y,w:0.04,h:0.025)
}
static func main() {
var n=0
func ck(_ v:Bool,_ message:String){precondition(v,message);n+=1}
let a=[t("own","148/197",0.22,0.86),
t("opp","81%",0.79,0.10)]
let names=["かえんほうしゃ","なみのり","10まんボルト","じゃれつく"]
let types=["ほのお","みず","でんき","フェアリー"]
let yy=[0.43,0.55,0.67,0.79]
var full=a
for i in 0..<4 {
full.append(t("move\(i)",names[i],0.64,yy[i]))
full.append(t("pp\(i)","12/16",0.86,yy[i]))
full.append(t("type\(i)",types[i],0.54,yy[i]))
}
let original=R668PlainHUDReader.scan(full,width:1280,height:720)
ck(original["status"] as? String == "HUD_PLAIN_OCR_HYPOTHESES_ONLY","hud origin")
ck(original["move_pair_count"] as? Int == 4,"four moves")
let r=R678MoveTypeOCR.scan(full,hud:original,width:1280,height:720)
ck(r["candidate_count"] as? Int == 4,"type labels")
let rows=r["records"] as? [[String:Any]] ?? []
for i in 0..<4 {
ck(rows[i]["slot_index_candidate"] as? Int == i,"row mapping")
ck(rows[i]["displayed_type_candidate"] as? String == types[i],"type value")
ck(rows[i]["type_evidence_ref"] as? String == "type\(i)","evidence")
}
ck(r["move_type_certified"] as? Bool == false,"uncertified")
let missing=R678MoveTypeOCR.scan(a,hud:R668PlainHUDReader.scan(a,
width:1280,height:720),width:1280,height:720)
ck(missing["status"] as? String == "HOLD_NO_SOURCE_BOUND_MOVE_PP_PAIRS","no panel")
let noType=full.filter{!$0.ref.hasPrefix("type")}
let empty=R678MoveTypeOCR.scan(noType,hud:R668PlainHUDReader.scan(
noType,width:1280,height:720),width:1280,height:720)
ck(empty["candidate_count"] as? Int == 0,"no inference")
var duplicate=full
duplicate.append(t("extra","いわ",0.58,yy[0]))
let bad=R678MoveTypeOCR.scan(duplicate,hud:original,
width:1280,height:720)
ck(bad["status"] as? String == "HOLD_AMBIGUOUS_TYPE_ON_MOVE_ROW","ambiguous type")
var wrong=full
wrong.append(t("background","くさ",0.19,0.26))
let outside=R678MoveTypeOCR.scan(wrong,hud:original,
width:1280,height:720)
ck(outside["candidate_count"] as? Int == 4,"outside panel")
wrong=full;wrong.append(full[0])
let conflict=R678MoveTypeOCR.scan(wrong,hud:original,
width:1280,height:720)
ck(conflict["status"] as? String == "HOLD_NO_SOURCE_BOUND_MOVE_PP_PAIRS","duplicate refs")
let frame=214748364
let inventory=full.map{x -> [String:Any] in
["evidence_ref":x.ref,"raw_text":x.text,
"image_sha256":sha,"capture_session_id":"S",
"epoch":1,"frame_id":frame,"owner_verified":false,
"roi":["x":Int((x.x-x.w/2)*1280),
"y":Int((x.y-x.h/2)*720),"width":51,"height":18]]
}
var hud=original
hud["source_kind"]="LIVE_RETAINED_FRAME"
hud["source_image_sha256"]=sha;hud["analysis_image_sha256"]=sha
hud["capture_session_id"]="S";hud["epoch"]=1;hud["frame_id"]=frame
let snap:[String:Any]=["source_validation":"PASS_FRAME_BINDING_ONLY",
"current_state_eligible":false,"battle_advice_authorized":false,
"image_sha256":sha,"capture_session_id":"S","epoch":1,
"frame_id":frame,"ocr_source_inventory":inventory]
var doc:[String:Any]=["r668_plain_hud_ocr":hud,"png_sha256":sha,
"image_width":1280,"image_height":720,"screen_read_state":snap]
let audited=R678MoveTypeOCR.audit(doc,sourceKind:"LIVE_RETAINED_FRAME")
ck(audited["candidate_count"] as? Int == 4,"binding")
ck(audited["frame_id"] as? Int == frame,"frame id")
doc["png_sha256"]=String(repeating:"b",count:64)
let mismatched=R678MoveTypeOCR.audit(doc,sourceKind:"LIVE_RETAINED_FRAME")
ck(mismatched["status"] as? String == "HOLD_SOURCE_FRAME_OR_HUD_MISMATCH","sha mismatch")
doc["png_sha256"]=sha
var corrupt=inventory;corrupt[3]["image_sha256"]=String(repeating:"c",count:64)
var badsnap=snap;badsnap["ocr_source_inventory"]=corrupt
doc["screen_read_state"]=badsnap
let badinv=R678MoveTypeOCR.audit(doc,sourceKind:"LIVE_RETAINED_FRAME")
ck(badinv["status"] as? String == "HOLD_OCR_SOURCE_CONFLICT","bad token")
print("R678_MOVE_TYPE_OCR_SMOKE_PASS \(n)")
}
}
