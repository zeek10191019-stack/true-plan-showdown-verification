import Foundation
@main struct R676Smoke {
typealias T=R668PlainHUDReader.Token
static let sha=String(repeating:"a",count:64)
static func t(_ id:String,_ s:String,_ x:Double,_ y:Double)->T {
T(ref:id,text:s,x:x,y:y,w:0.04,h:0.025)
}
static func main() {
var n=0
func ck(_ b:Bool,_ s:String) {precondition(b,s);n+=1}
let a=[t("own","148/197",0.22,0.86),t("opp","81%",0.79,0.10)]
let hud=R668PlainHUDReader.scan(a,width:1280,height:720)
ck(hud["status"] as? String=="HUD_PLAIN_OCR_HYPOTHESES_ONLY","HUD")
let test=a+[t("w","雨",0.45,0.20),
t("gr","グラスフィールド残り3ターン",0.43,0.28),
t("screen","リフレクター",0.30,0.42),
t("time","残り5ターン",0.43,0.42),
t("menu","トリックルーム",0.80,0.67)]
let r=R676FieldOverlayOCR.scan(test,hud:hud,width:1280,height:720)
let rows=r["records"] as? [[String:Any]] ?? []
ck(rows.count==3,"3 effects")
ck(rows.contains{$0["effect_code"] as? String=="RAIN"},"rain")
ck(rows.contains{$0["effect_code"] as? String=="GRASSY" &&
$0["visible_turn_count_candidate"] as? Int==3},"inline turn")
ck(rows.contains{$0["effect_code"] as? String=="REFLECT" &&
$0["visible_turn_count_candidate"] as? Int==5},"adjacent turn")
ck(rows.allSatisfy{$0["owner_verified"] as? Bool==false},"unverified")
let inv=test.map { x -> [String:Any] in
let px=Int((x.x-x.w/2)*1280),py=Int((x.y-x.h/2)*720)
return ["evidence_ref":x.ref,"raw_text":x.text,
"image_sha256":sha,"capture_session_id":"S", "epoch":1,"frame_id":123456,
"owner_verified":false,"roi":["x":px,"y":py,"width":51,"height":18]]
}
var h=hud
h["source_kind"]="LIVE_RETAINED_FRAME"
h["source_image_sha256"]=sha;h["analysis_image_sha256"]=sha
h["capture_session_id"]="S";h["epoch"]=1;h["frame_id"]=123456
let snap:[String:Any]=["source_validation":"PASS_FRAME_BINDING_ONLY",
"current_state_eligible":false,"battle_advice_authorized":false,
"image_sha256":sha,"capture_session_id":"S","epoch":1,
"frame_id":123456,"ocr_source_inventory":inv]
let doc:[String:Any]=["r668_plain_hud_ocr":h,"png_sha256":sha,
"image_width":1280,"image_height":720,"screen_read_state":snap]
let verified=R676FieldOverlayOCR.audit(doc,sourceKind:"LIVE_RETAINED_FRAME")
ck(verified["field_count"] as? Int==3,"source bound and high frame")
print("R676_FIELD_OVERLAY_CI_PASS \(n)")
}
}
