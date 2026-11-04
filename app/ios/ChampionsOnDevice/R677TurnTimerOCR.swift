import Foundation
import CoreFoundation
enum R677TurnTimerOCR {
static let schema = "trueplan.r677.battle-turn-timer-ocr.v1"
typealias Token = R668PlainHUDReader.Token
private static func hold(_ reason:String)->[String:Any] {
["schema":schema,"status":reason,"records":[[String:Any]](),
"candidate_count":0,"turn_verified":false,
"owner_verified":false,"current_state_eligible":false,
"battle_advice_authorized":false]
}
private static func number(_ value:Any?)->Int? {
guard let n=value as? NSNumber,
CFGetTypeID(n) != CFBooleanGetTypeID(),
n.doubleValue.isFinite,n.doubleValue>=0,
n.doubleValue<Double(Int32.max),
n.doubleValue==Double(n.intValue) else{return nil}
return n.intValue
}
private static func sha(_ value:Any?)->String? {
guard let s=value as? String,s.utf8.count==64,
s.utf8.allSatisfy({(48...57).contains($0) ||
(97...102).contains($0)}) else{return nil}
return s
}
private static func normalized(_ s:String)->String {
s.precomposedStringWithCompatibilityMapping
.replacingOccurrences(of:"　",with:"")
.replacingOccurrences(of:" ",with:"")
.trimmingCharacters(in:.whitespacesAndNewlines)
}
private static func match(_ s:String,_ pattern:String)->[String]? {
guard let r=try? NSRegularExpression(pattern:pattern) else{return nil}
let whole=NSRange(s.startIndex..<s.endIndex,in:s)
guard let m=r.firstMatch(in:s,range:whole),m.range==whole else{return nil}
return (1..<m.numberOfRanges).compactMap { i in
guard let a=Range(m.range(at:i),in:s) else{return nil}
return String(s[a])
}
}
private static func turn(_ s:String)->Int? {
let t=normalized(s)
let g=match(t,#"^(?:第([0-9]{1,3})ターン|([0-9]{1,3})ターン目|Turn([0-9]{1,3}))$"#)
guard let raw=g?.first(where:{!$0.isEmpty}),
let n=Int(raw),n>0,n<=999 else{return nil}
return n
}
private static func seconds(_ s:String)->Int? {
let t=normalized(s)
if let a=match(t,#"^(?:残り|あと)([0-9]{1,2})秒$"#),
let n=Int(a[0]),n<=90{return n}
if let a=match(t,#"^([0-1]):([0-5][0-9])$"#),
let m=Int(a[0]),let sec=Int(a[1]),m*60+sec<=90 {
return m*60+sec
}
return nil
}
private static func valid(_ t:Token)->Bool {
!t.ref.isEmpty && t.ref.utf8.count<=160 &&
!t.text.isEmpty && t.text.utf8.count<=160 &&
[t.x,t.y,t.w,t.h].allSatisfy{$0.isFinite} &&
(0...1).contains(t.x) && (0...1).contains(t.y) &&
t.w>0 && t.h>0 && t.x-t.w/2>=0 && t.y-t.h/2>=0 &&
t.x+t.w/2<=1 && t.y+t.h/2<=1
}
static func scan(_ tokens:[Token],hud:[String:Any],
width:Int,height:Int)->[String:Any] {
guard (400...8192).contains(width),
(180...8192).contains(height),tokens.count<=288,
Set(tokens.map{$0.ref}).count==tokens.count,
tokens.allSatisfy(valid),
hud["schema"] as? String==R668PlainHUDReader.schema,
hud["status"] as? String=="HUD_PLAIN_OCR_HYPOTHESES_ONLY",
hud["owner_verified"] as? Bool==false,
hud["orientation_verified"] as? Bool==false,
hud["current_state_eligible"] as? Bool==false,
let deg=number(hud["rotation_candidate_degrees"]),
[0,90,180,270].contains(deg) else {
return hold("HOLD_UNBOUND_HUD_OR_GEOMETRY")
}
let rw=deg%180==0 ? width:height
let rh=deg%180==0 ? height:width
guard (1.65...2.35).contains(Double(rw)/Double(rh)) else {
return hold("HOLD_NOT_LANDSCAPE")
}
var turns=[(Token,Int)](),clocks=[(Token,Int)]()
for t in tokens.map({$0.rotated(deg)}) {
if t.x>=0.25 && t.x<=0.73 && t.y>=0.04 && t.y<=0.34,
let value=turn(t.text) {turns.append((t,value))}
if t.x>=0.52 && t.x<=0.96 && t.y>=0.05 && t.y<=0.43,
let value=seconds(t.text) {clocks.append((t,value))}
}
guard turns.count<=1,clocks.count<=1 else {
return hold("HOLD_CONFLICTING_TURN_OR_CLOCK_TOKENS")
}
var records=[[String:Any]]()
if let (t,value)=turns.first {
records.append(["field":"battle.turn","value":value,
"raw_text":t.text,"evidence_ref":t.ref,
"source":"SOURCE_BOUND_VISIBLE_HEADER_OCR",
"turn_verified":false,"current_state_eligible":false])
}
if let (t,value)=clocks.first {
records.append(["field":"battle.timer","value_seconds":value,
"raw_text":t.text,"evidence_ref":t.ref,
"source":"SOURCE_BOUND_VISIBLE_HEADER_OCR",
"turn_verified":false,"current_state_eligible":false])
}
return ["schema":schema,"status":records.isEmpty ?
"NO_HEADER_TURN_TIMER_OCR" : "HEADER_TURN_TIMER_OCR_CANDIDATES_ONLY",
"records":records,"candidate_count":records.count,
"rotation_hypothesis_degrees":deg,
"turn_verified":false,"owner_verified":false,
"current_state_eligible":false,"battle_advice_authorized":false,
"actual_game_accuracy":"NOT_MEASURED"]
}
static func audit(_ doc:[String:Any],sourceKind:String)->[String:Any] {
guard ["LIVE_RETAINED_FRAME","USER_IMPORTED_PNG_OFFLINE_ONLY"]
.contains(sourceKind),
let hud=doc["r668_plain_hud_ocr"] as? [String:Any],
hud["source_kind"] as? String==sourceKind,
let snap=doc["screen_read_state"] as? [String:Any],
snap["source_validation"] as? String=="PASS_FRAME_BINDING_ONLY",
snap["current_state_eligible"] as? Bool==false,
snap["battle_advice_authorized"] as? Bool==false,
let raw=sha(sourceKind=="LIVE_RETAINED_FRAME" ?
doc["png_sha256"] : doc["image_sha256"]),
let analysis=sha(snap["image_sha256"]),
sha(hud["source_image_sha256"])==raw,
sha(hud["analysis_image_sha256"])==analysis,
let session=snap["capture_session_id"] as? String,
!session.isEmpty,session==hud["capture_session_id"] as? String,
let epoch=number(snap["epoch"]),epoch>0,
let frame=number(snap["frame_id"]),frame>0,
number(hud["epoch"])==epoch,number(hud["frame_id"])==frame,
let inv=snap["ocr_source_inventory"] as? [[String:Any]],
inv.count<=288,
let width=number(doc["image_width"]),
let height=number(doc["image_height"]) else {
return hold("HOLD_SOURCE_FRAME_OR_HUD_MISMATCH")
}
var aw=width,ah=height
if raw != analysis {
guard let p=doc["analysis_projection"] as? [String:Any],
p["status"] as? String=="DECLARED_GEOMETRY_ONLY",
p["raw_image_sha256"] as? String==raw,
p["analysis_image_sha256"] as? String==analysis,
p["capture_session_id"] as? String==session,
number(p["epoch"])==epoch,number(p["frame_id"])==frame,
number(p["raw_width"])==width,
number(p["raw_height"])==height,
p["owner_certified"] as? Bool==false,
let w=number(p["analysis_width"]),
let h=number(p["analysis_height"]) else {
return hold("HOLD_ANALYSIS_IMAGE_TRANSFORM_MISMATCH")
}
aw=w;ah=h
}
guard aw>0,ah>0 else{return hold("HOLD_INVALID_DIMENSIONS")}
var tokens=[Token](),seen=Set<String>()
for row in inv {
guard let ref=row["evidence_ref"] as? String,
!ref.isEmpty,seen.insert(ref).inserted,
row["image_sha256"] as? String==analysis,
row["capture_session_id"] as? String==session,
number(row["frame_id"])==frame,
number(row["epoch"])==epoch,
row["owner_verified"] as? Bool==false,
let text=row["raw_text"] as? String,
!text.isEmpty,text.utf8.count<=160,
let box=row["roi"] as? [String:Any],
let x=number(box["x"]),let y=number(box["y"]),
let w=number(box["width"]),let h=number(box["height"]),
x<aw,y<ah,w>0,h>0,w<=aw-x,h<=ah-y else {
return hold("HOLD_OCR_INVENTORY_PROVENANCE_CONFLICT")
}
if ref.contains(".ocr_alternatives["){continue}
tokens.append(Token(ref:ref,text:text,
x:(Double(x)+Double(w)/2)/Double(aw),
y:(Double(y)+Double(h)/2)/Double(ah),
w:Double(w)/Double(aw),h:Double(h)/Double(ah)))
}
var result=scan(tokens,hud:hud,width:aw,height:ah)
result["source_image_sha256"]=raw
result["analysis_image_sha256"]=analysis
result["capture_session_id"]=session
result["epoch"]=epoch;result["frame_id"]=frame
result["source_kind"]=sourceKind
return result
}
static func enrich(_ doc:inout [String:Any],sourceKind:String) {
doc["r677_header_turn_timer_ocr"]=audit(doc,sourceKind:sourceKind)
}
}
