import Foundation
import CoreFoundation
enum R641RotatedHUDCandidates {
static let schema = "trueplan.r641.four-way-independent-layout.v1"
private static func integer(_ a:Any?) -> Int? {
guard let n=a as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),
n.doubleValue.isFinite,n.doubleValue>=0,
n.doubleValue<Double(Int.max),n.doubleValue==Double(n.intValue)
else {return nil}
return n.intValue
}
private static func sha(_ a:Any?) -> String? {
guard let s=a as? String,s.utf8.count==64,
s.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)})
else {return nil}
return s
}
private struct Rect {
let x:Int,y:Int,w:Int,h:Int
init?(_ a:Any?,_ width:Int,_ height:Int) {
guard let d=a as? [String:Any],
let x=integer(d["x"]),let y=integer(d["y"]),
let w=integer(d["width"]),let h=integer(d["height"]),
x<width,y<height,w>0,h>0,w<=width-x,h<=height-y
else {return nil}
self.x=x;self.y=y;self.w=w;self.h=h
}
private init(_ x:Int,_ y:Int,_ w:Int,_ h:Int) {
self.x=x;self.y=y;self.w=w;self.h=h
}
func turn(_ d:Int,_ width:Int,_ height:Int)->Rect {
switch d {
case 90:return Rect(height-y-h,x,h,w)
case 180:return Rect(width-x-w,height-y-h,w,h)
case 270:return Rect(y,width-x-w,h,w)
default:return self
}
}
func inRegion(_ area:(Double,Double,Double,Double),_ width:Int,_ height:Int)->Bool {
let x0=Double(x)/Double(width),y0=Double(y)/Double(height)
let x1=Double(x+w)/Double(width),y1=Double(y+h)/Double(height)
let ox=max(0,min(x1,area.0+area.2)-max(x0,area.0))
let oy=max(0,min(y1,area.1+area.3)-max(y0,area.1))
return ox*oy/((x1-x0)*(y1-y0))>=0.90
}
}
private struct Token {
let ref:String,text:String,box:Rect
}
private static func compact(_ s:String)->String {
s.replacingOccurrences(of:" ",with:"")
.replacingOccurrences(of:"　",with:"")
}
private static func hp(_ s:String)->[String:Int]? {
var t=compact(s)
if t.hasPrefix("HP") {t=String(t.dropFirst(2))}
guard t.range(of:#"^[0-9]{1,4}/[0-9]{1,4}$"#,
options:.regularExpression) != nil else{return nil}
let a=t.split(separator:"/").compactMap{Int($0)}
guard a.count==2,a[1]>0,a[0]<=a[1] else{return nil}
return ["current":a[0],"maximum":a[1]]
}
private static func percent(_ s:String)->Double? {
let t=compact(s)
guard t.range(of:#"^[0-9]{1,3}(\.[0-9]{1,2})?%$"#,
options:.regularExpression) != nil,
let n=Double(t.dropLast()),(0...100).contains(n) else{return nil}
return n
}
private static func pp(_ s:String)->[String:Int]? {
guard let a=hp(s),a["maximum"]!<=64 else{return nil}
return a
}
private static func move(_ s:String)->String? {
let t=s.trimmingCharacters(in:.whitespacesAndNewlines)
guard t.count>=2,t.count<=24,
t.range(of:#"^[ぁ-ゖァ-ヺー一-龯A-Za-z0-9・♀♂]+$"#,
options:.regularExpression) != nil,
t.range(of:#"[ぁ-ゖァ-ヺ一-龯]"#,
options:.regularExpression) != nil else{return nil}
return t
}
private static func region(_ role:String,_ slot:Int?=nil)
->(Double,Double,Double,Double) {
switch role {
case "own_hp":return (0.15,0.90,0.12,0.08)
case "opponent_percent":return (0.84,0.10,0.09,0.07)
case "command":return (0.78,0.20,0.10,0.06)
case "move_name":return (0.75,0.44+Double(slot ?? 0)*0.12,0.13,0.065)
default:return (0.88,0.43+Double(slot ?? 0)*0.12,0.05,0.10)
}
}
private static func value(_ t:String,_ role:String)->Any? {
switch role {
case "own_hp":return hp(t)
case "opponent_percent":return percent(t)
case "command":return compact(t).uppercased()=="COMMAND" ? "COMMAND" : nil
case "move_name":return move(t)
default:return pp(t)
}
}
static func enrich(_ doc:inout [String:Any],sourceKind:String) {
doc.removeValue(forKey:"r641_rotated_hud_candidates")
doc["r641_status"]="HOLD_UNBOUND_RAW_OCR"
guard ["LIVE_RETAINED_FRAME","USER_IMPORTED_PNG_OFFLINE_ONLY"].contains(sourceKind),
let cov=doc["r581_full_read_coverage"] as? [String:Any],
cov["source_kind"] as? String == sourceKind,
cov["schema"] as? String == R581ReadabilityCoverage.schema,
cov["snapshot_binding_valid"] as? Bool == true,
cov["source_binding_valid"] as? Bool == true,
cov["owner_certified"] as? Bool == false,
cov["current_state_eligible"] as? Bool == false,
let raw=sha(cov["image_sha256"]),
let source=sha(sourceKind=="LIVE_RETAINED_FRAME" ?
doc["png_sha256"]:doc["image_sha256"]),raw==source,
let snap=doc["screen_read_state"] as? [String:Any],
let analysis=sha(snap["image_sha256"]),
analysis==sha(cov["analysis_image_sha256"]),
snap["source_validation"] as? String == "PASS_FRAME_BINDING_ONLY",
snap["current_state_eligible"] as? Bool == false,
snap["battle_advice_authorized"] as? Bool == false,
let frame=integer(snap["frame_id"]),frame>0,
let epoch=integer(snap["epoch"]),epoch>0,
let session=snap["capture_session_id"] as? String,!session.isEmpty,
let physicalW=integer(doc["image_width"]),
let physicalH=integer(doc["image_height"]),
(180...8192).contains(physicalW),
(180...8192).contains(physicalH),
let sourceTokens=snap["ocr_source_inventory"] as? [[String:Any]],
sourceTokens.count<=288 else{return}
var w=physicalW,h=physicalH
if analysis != raw {
guard cov["declared_analysis_projection_valid"] as? Bool == true,
let projection=doc["analysis_projection"] as? [String:Any],
projection["schema"] as? String ==
"trueplan.screen-read.analysis-projection.v1",
projection["status"] as? String == "DECLARED_GEOMETRY_ONLY",
projection["raw_image_sha256"] as? String == raw,
projection["analysis_image_sha256"] as? String == analysis,
integer(projection["frame_id"]) == frame,
integer(projection["epoch"]) == epoch,
projection["capture_session_id"] as? String == session,
integer(projection["raw_width"]) == physicalW,
integer(projection["raw_height"]) == physicalH,
let aw=integer(projection["analysis_width"]),
let ah=integer(projection["analysis_height"]),
(180...8192).contains(aw),(180...8192).contains(ah),
projection["game_orientation_certified"] as? Bool == false,
projection["owner_certified"] as? Bool == false else {
doc["r641_status"]="HOLD_ANALYSIS_PROJECTION_NOT_BOUND";return
}
w=aw;h=ah
}
var tokens=[Token](),refs=Set<String>()
for row in sourceTokens {
guard let ref=row["evidence_ref"] as? String,!ref.isEmpty,
ref.utf8.count<=160,refs.insert(ref).inserted,
row["image_sha256"] as? String == analysis,
row["capture_session_id"] as? String == session,
integer(row["frame_id"]) == frame,
integer(row["epoch"]) == epoch,
row["owner_verified"] as? Bool == false,
let text=row["raw_text"] as? String,!text.isEmpty,
text.utf8.count<=160,
let box=Rect(row["roi"],w,h) else {
doc["r641_status"]="HOLD_CORRUPTED_OCR_INVENTORY";return
}
if !ref.contains(".ocr_alternatives[") {
tokens.append(Token(ref:ref,text:text,box:box))
}
}
var summaries=[[String:Any]](),possible=[[String:Any]]()
for deg in [0,90,180,270] {
let rw=deg%180==0 ? w : h,rh=deg%180==0 ? h : w
let aspect=Double(rw)/Double(rh)
guard rw>=400,rh>=180,abs(aspect-578.0/267.0)<0.025 else {
summaries.append(["degrees":deg,"layout_supported":false,
"anchor_count":0,"move_slot_count":0])
continue
}
func collect(_ role:String,_ slot:Int?=nil)->[[String:Any]] {
let region=region(role,slot)
return tokens.compactMap { tok ->[String:Any]? in
guard tok.box.turn(deg,w,h).inRegion(region,rw,rh),
let parsed=value(tok.text,role) else{return nil}
return ["value":parsed,"ref":tok.ref,"raw_text":tok.text,
"owner_verified":false,"current_value_admitted":false]
}
}
let own=collect("own_hp"),opp=collect("opponent_percent")
let command=collect("command")
let names=(0..<4).map{collect("move_name",$0)}
let pps=(0..<4).map{collect("move_pp",$0)}
let goodSlots=names.filter{$0.count==1}.count
let anchors=[own,opp,command].filter{$0.count==1}.count
let strong=anchors==3
let fallback=own.count==1 && opp.count==1 && goodSlots>=2
summaries.append(["degrees":deg,"layout_supported":true,
"anchor_count":anchors,"move_slot_count":goodSlots,
"strict_three_anchor_candidate":strong,
"two_hp_two_moves_candidate":fallback])
guard strong || fallback else {continue}
var values=[[String:Any]](),used=Set<String>(),conflict=false
let specs:[(String,Int?,[[String:Any]])]=[
("own_hp",nil,own),("opponent_percent",nil,opp),
("command",nil,command)
]+(0..<4).flatMap{slot in
[("move_name",slot,names[slot]),("move_pp",slot,pps[slot])]
}
for (role,slot,items) in specs {
if items.count>1 {conflict=true;continue}
guard let item=items.first,let ref=item["ref"] as? String else{continue}
if !used.insert(ref).inserted {conflict=true;continue}
values.append(["role_hint":role,"slot":slot.map{$0 as Any} ?? NSNull(),
"value":item["value"] ?? NSNull(),"source_ref":ref,
"raw_text":item["raw_text"] ?? NSNull(),
"source_sha256":analysis,"side":"UNKNOWN_OWNER",
"orientation_verified":false,"owner_verified":false,
"current_value_admitted":false,
"status":"PROVISIONAL_LAYOUT_VALUE_ONLY"])
}
if !conflict {
possible.append(["degrees":deg,"anchor_count":anchors,
"values":values,"strict":strong])
}
}
let unique=possible.count==1
let status=unique ? "UNIQUE_LAYOUT_HYPOTHESIS_NOT_CERTIFIED" :
possible.isEmpty ? "HOLD_NO_SUPPORTED_LAYOUT" :
"HOLD_MULTIPLE_LAYOUT_HYPOTHESES"
let report:[String:Any]=[
"schema":schema,"source_kind":sourceKind,"source_image_sha256":analysis,
"source_frame_id":frame,"source_epoch":epoch,
"profiles":summaries,"matching_profile_count":possible.count,
"rotation_candidate_degrees":unique ? possible[0]["degrees"]! : NSNull(),
"candidate_values":unique ? possible[0]["values"]! : [],
"source_orientation_verified":false,"owner_verified":false,
"game_fields_certified":0,"battle_advice_authorized":false,
"requires_real_game_ground_truth":true,"status":status]
guard JSONSerialization.isValidJSONObject(report) else {
doc["r641_status"]="HOLD_JSON_FAILURE";return
}
doc["r641_rotated_hud_candidates"]=report
doc["r641_status"]=status
}
}
