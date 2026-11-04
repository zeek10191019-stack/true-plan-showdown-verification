import Foundation
@main struct R677Smoke {
typealias T=R668PlainHUDReader.Token
static let sha=String(repeating:"a",count:64)
static func t(_ id:String,_ s:String,_ x:Double,_ y:Double)->T {
T(ref:id,text:s,x:x,y:y,w:0.04,h:0.025)
}
static func main() {
var n=0
func ck(_ b:Bool,_ s:String){precondition(b,s);n+=1}
let base=[t("own","148/197",0.22,0.86),
t("opp","81%",0.79,0.10)]
let hud=R668PlainHUDReader.scan(base,width:1280,height:720)
ck(hud["status"] as? String=="HUD_PLAIN_OCR_HYPOTHESES_ONLY","anchors")
let ts=base+[t("turn","第3ターン",0.45,0.16),
t("clock","残り35秒",0.81,0.28),
t("fx","トリックルーム残り3ターン",0.43,0.32),
t("move","第8ターン",0.70,0.74)]
let r=R677TurnTimerOCR.scan(ts,hud:hud,width:1280,height:720)
ck(r["candidate_count"] as? Int==2,"turn and clock")
let rows=r["records"] as? [[String:Any]] ?? []
ck(rows.contains{($0["field"] as? String)=="battle.turn" &&
($0["value"] as? Int)==3},"turn3")
ck(rows.contains{($0["field"] as? String)=="battle.timer" &&
($0["value_seconds"] as? Int)==35},"clock35")
ck(r["turn_verified"] as? Bool==false,"no certification")
let m=R677TurnTimerOCR.scan(base+[t("x","Turn10",0.42,0.15),
t("c","0:45",0.80,0.28)],hud:hud,width:1280,height:720)
ck(m["candidate_count"] as? Int==2,"English turn and clock")
let conflict=R677TurnTimerOCR.scan(ts+[t("extra","第4ターン",0.50,0.19)],
hud:hud,width:1280,height:720)
ck(conflict["status"] as? String ==
"HOLD_CONFLICTING_TURN_OR_CLOCK_TOKENS","conflicting turn")
let none=R677TurnTimerOCR.scan(base+[t("fx","残り3ターン",0.45,0.12)],
hud:hud,width:1280,height:720)
ck(none["candidate_count"] as? Int==0,"effect not turn")
let out=R677TurnTimerOCR.scan(base+[t("clock","2:00",0.82,0.21)],
hud:hud,width:1280,height:720)
ck(out["candidate_count"] as? Int==0,"unplausible timer")
let frames=ts.map{x -> [String:Any] in
["evidence_ref":x.ref,"raw_text":x.text,"image_sha256":sha,
"capture_session_id":"S","epoch":1,"frame_id":214748364,
"owner_verified":false,"roi":[
"x":Int((x.x-x.w/2)*1280),
"y":Int((x.y-x.h/2)*720),"width":51,"height":18]]
}
var h=hud
h["source_kind"]="LIVE_RETAINED_FRAME"
h["source_image_sha256"]=sha
h["analysis_image_sha256"]=sha
h["capture_session_id"]="S"
h["epoch"]=1;h["frame_id"]=214748364
let snap:[String:Any]=["source_validation":"PASS_FRAME_BINDING_ONLY",
"current_state_eligible":false,"battle_advice_authorized":false,
"image_sha256":sha,"capture_session_id":"S",
"epoch":1,"frame_id":214748364,"ocr_source_inventory":frames]
var doc:[String:Any]=["r668_plain_hud_ocr":h,"png_sha256":sha,
"image_width":1280,"image_height":720,"screen_read_state":snap]
let audited=R677TurnTimerOCR.audit(doc,sourceKind:"LIVE_RETAINED_FRAME")
ck(audited["candidate_count"] as? Int==2,"full evidence")
doc["png_sha256"]=String(repeating:"b",count:64)
let wrong=R677TurnTimerOCR.audit(doc,sourceKind:"LIVE_RETAINED_FRAME")
ck(wrong["status"] as? String ==
"HOLD_SOURCE_FRAME_OR_HUD_MISMATCH","source mismatch")
doc["png_sha256"]=sha
var corrupt=frames
corrupt[0]["image_sha256"]=String(repeating:"c",count:64)
var snap2=snap;snap2["ocr_source_inventory"]=corrupt
doc["screen_read_state"]=snap2
let mixed=R677TurnTimerOCR.audit(doc,sourceKind:"LIVE_RETAINED_FRAME")
ck(mixed["status"] as? String ==
"HOLD_OCR_INVENTORY_PROVENANCE_CONFLICT","token source")
let alt=R677TurnTimerOCR.scan(base+[t("none","残り5ターン",0.82,0.12)],
hud:hud,width:1280,height:720)
ck(alt["candidate_count"] as? Int == 0,"duration not timer")
print("R677_TURN_TIMER_OCR_SMOKE_PASS \(n)")
}
}
