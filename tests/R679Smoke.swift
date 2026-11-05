import Foundation
@main struct R679Smoke {
static let sha=String(repeating:"a",count:64)
static func doc(frame:Int64=72,digest:String=sha,
kind:String="MOVE_PANEL_TYPE_OCR_CANDIDATES_ONLY")->[String:Any] {
let r:[String:Any]=[
"slot_index_candidate":0,"displayed_type_candidate":"ほのお",
"type_evidence_ref":"type","move_evidence_ref":"move",
"pp_evidence_ref":"pp","raw_type_text":"ほのお",
"source":"SOURCE_BOUND_MOVE_PANEL_OCR","owner_verified":false,
"move_type_certified":false]
let inv=[("type",550),("move",520),("pp",900)].map{(ref,x) -> [String:Any] in
["evidence_ref":ref,"image_sha256":digest,
"capture_session_id":"S","epoch":1,"frame_id":frame,
"owner_verified":false,"raw_text":ref=="type" ? "ほのお" : ref,
"roi":["x":x,"y":440,"width":50,"height":22]]
}
let status:[String:Any]=[
"schema":"trueplan.r678.move-panel-type-ocr.v1",
"status":kind,"source_kind":"LIVE_RETAINED_FRAME",
"source_image_sha256":digest,"analysis_image_sha256":digest,
"frame_id":frame,"epoch":1,"capture_session_id":"S",
"owner_verified":false,"move_type_certified":false,
"current_state_eligible":false,"candidate_count":1,"records":[r]]
return ["png_sha256":digest,"image_width":1280,
"image_height":720,"r678_move_type_ocr":status,
"screen_read_state":["image_sha256":digest,
"capture_session_id":"S","frame_id":frame,"epoch":1,
"ocr_source_inventory":inv]]
}
static func pixels(color:(UInt8,UInt8,UInt8),left:Bool=true)->[UInt8] {
var a=[UInt8](repeating:0,count:1280*720*4)
for y in 429..<472 {for x in (left ? 492:650)..<(left ? 546:700) {
let i=(y*1280+x)*4
a[i]=color.0;a[i+1]=color.1;a[i+2]=color.2;a[i+3]=255
}}
return a
}
static func run(_ p:[UInt8],_ d:[String:Any],frame:Int64=72,
digest:String=sha)->[String:Any] {
R679TypeColorProbe.inspect(pixels:p,width:1280,height:720,
rowBytes:5120,epoch:1,frame:frame,observedMs:1000,
sha:digest,document:d)
}
static func main() {
var n=0
func check(_ b:Bool,_ why:String){precondition(b,why);n+=1}
let red=run(pixels(color:(230,50,40)),doc())
check(red["status"] as? String=="HISTORICAL_TYPE_COLOR_SAMPLES_ONLY","red")
let rows=red["samples"] as! [[String:Any]]
check(rows.count==2,"two flips")
check(rows[0]["dominant_color_family_unverified"] as? String=="WARM","warm")
check(rows[1]["status"] as? String=="HOLD_NO_DISTINCT_COLOR_BAND","origin ambiguity")
check(rows.allSatisfy{$0["actual_type_from_color_certified"] as? Bool==false},"not certified")
for (r,g,b,expected) in [(220,190,40,"YELLOW"),(45,180,60,"GREEN"),
(30,185,200,"CYAN"),(60,90,220,"BLUE"),(170,45,205,"VIOLET")] {
let x=run(pixels(color:(UInt8(r),UInt8(g),UInt8(b))),doc())
let y=(x["samples"] as! [[String:Any]])[0]
check(y["dominant_color_family_unverified"] as? String==expected,expected)
}
let dark=run(pixels(color:(50,50,50)),doc())
check((dark["samples"] as! [[String:Any]])[0]["status"] as? String ==
"HOLD_NO_DISTINCT_COLOR_BAND","gray")
check(run(pixels(color:(230,50,40)),doc(),digest:String(repeating:"b",count:64))["status"] as? String=="HOLD_UNMATCHED_SELECTED_FRAME_OR_OCR","sha")
check(run(pixels(color:(230,50,40)),doc(),frame:73)["status"] as? String=="HOLD_UNMATCHED_SELECTED_FRAME_OR_OCR","frame")
var d=doc();var r=d["r678_move_type_ocr"] as! [String:Any]
let item=(r["records"] as! [[String:Any]])[0]
r["records"]=[item,item]
r["candidate_count"]=2;d["r678_move_type_ocr"]=r
check(run(pixels(color:(230,50,40)),d)["status"] as? String ==
"HOLD_TYPE_ROW_OR_PROVENANCE_CONFLICT","duplicate slot")
var mismatch=doc();var ss=mismatch["screen_read_state"] as! [String:Any]
ss["ocr_source_inventory"] = []
mismatch["screen_read_state"]=ss
check(run(pixels(color:(230,50,40)),mismatch)["status"] as? String ==
"HOLD_TYPE_ROW_OR_PROVENANCE_CONFLICT","missing OCR")
print("R679_TYPE_COLOR_REAL_RGBA_SMOKE_PASS \(n)")
}
}
