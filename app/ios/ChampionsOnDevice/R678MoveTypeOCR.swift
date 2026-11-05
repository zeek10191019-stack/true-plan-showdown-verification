import Foundation
import CoreFoundation
enum R678MoveTypeOCR {
static let schema="trueplan.r678.move-panel-type-ocr.v1"
typealias Token=R668PlainHUDReader.Token
private static let types=["ノーマル","ほのお","みず","でんき",
"くさ","こおり","かくとう","どく","じめん","ひこう",
"エスパー","むし","いわ","ゴースト","ドラゴン",
"あく","はがね","フェアリー"]
private static func hold(_ why:String)->[String:Any] {
["schema":schema,"status":why,"records":[[String:Any]](),
"candidate_count":0,"owner_verified":false,
"move_type_certified":false,"current_state_eligible":false,
"battle_advice_authorized":false]
}
private static func integer(_ a:Any?)->Int? {
guard let n=a as? NSNumber,
CFGetTypeID(n) != CFBooleanGetTypeID(),
n.doubleValue.isFinite,n.doubleValue>=0,
n.doubleValue<Double(Int32.max),
n.doubleValue==Double(n.intValue) else{return nil}
return n.intValue
}
private static func hash(_ v:Any?)->String? {
guard let s=v as? String,s.utf8.count==64,
s.utf8.allSatisfy({(48...57).contains($0) ||
(97...102).contains($0)}) else{return nil}
return s
}
private static func plain(_ s:String)->String {
s.precomposedStringWithCompatibilityMapping
.replacingOccurrences(of:"　",with:"")
.replacingOccurrences(of:" ",with:"")
.trimmingCharacters(in:.whitespacesAndNewlines)
}
private static func type(_ raw:String)->String? {
let t=plain(raw)
let x=t.hasPrefix("タイプ:") ? String(t.dropFirst(4)) :
(t.hasPrefix("タイプ：") ? String(t.dropFirst(4)) :t)
return types.contains(x) ? x:nil
}
private static func valid(_ t:Token)->Bool {
!t.ref.isEmpty && t.ref.utf8.count<=160 &&
!t.text.isEmpty && t.text.utf8.count<=160 &&
[t.x,t.y,t.w,t.h].allSatisfy{$0.isFinite} &&
(0...1).contains(t.x) && (0...1).contains(t.y) &&
t.w>0 && t.h>0 && t.x-t.w/2>=0 &&
t.y-t.h/2>=0 && t.x+t.w/2<=1 && t.y+t.h/2<=1
}
private static func single(_ matches:[[String:Any]],
field:String)->[String]? {
let rows=matches.filter{$0["field"] as? String==field}
guard rows.count==1,let row=rows.first,
row["owner_verified"] as? Bool==false,
row["current_state_eligible"] as? Bool != true,
let refs=row["evidence_refs"] as? [String],
(1...4).contains(refs.count),Set(refs).count==refs.count
else{return nil}
return refs
}
static func scan(_ tokens:[Token],hud:[String:Any],
width:Int,height:Int)->[String:Any] {
guard (400...8192).contains(width),(180...8192).contains(height),
tokens.count<=288,Set(tokens.map{$0.ref}).count==tokens.count,
tokens.allSatisfy(valid),
hud["schema"] as? String==R668PlainHUDReader.schema,
hud["status"] as? String=="HUD_PLAIN_OCR_HYPOTHESES_ONLY",
hud["owner_verified"] as? Bool==false,
hud["orientation_verified"] as? Bool==false,
hud["current_state_eligible"] as? Bool==false,
let deg=integer(hud["rotation_candidate_degrees"]),
[0,90,180,270].contains(deg),
let matches=hud["matches"] as? [[String:Any]],
let mrefs=single(matches,field:"own.moves_four"),
let prefs=single(matches,field:"own.pp_four"),
mrefs.count==prefs.count,
Set(mrefs).isDisjoint(with:Set(prefs)) else {
return hold("HOLD_NO_SOURCE_BOUND_MOVE_PP_PAIRS")
}
let rw=deg%180==0 ? width:height
let rh=deg%180==0 ? height:width
guard (1.65...2.35).contains(Double(rw)/Double(rh)) else {
return hold("HOLD_NOT_LANDSCAPE")
}
let ts=tokens.map{$0.rotated(deg)}
let by=Dictionary(uniqueKeysWithValues:ts.map{($0.ref,$0)})
var records=[[String:Any]](),used=Set<String>()
let forbidden=Set(mrefs+prefs)
for i in mrefs.indices {
guard let mv=by[mrefs[i]],let pp=by[prefs[i]],
mv.y>=0.35,pp.y>=0.35,mv.y<=0.97,pp.y<=0.97,
mv.x>=0.48,pp.x>=0.73,pp.x<=0.99,
pp.x>mv.x,abs(mv.y-pp.y)<=0.045 else {
return hold("HOLD_MOVE_PP_NOT_ON_SAME_ROW")
}
let labels=ts.filter { t in
!forbidden.contains(t.ref) && type(t.text) != nil &&
t.y>=0.35 && t.y<=0.97 && t.x>=0.47 && t.x<=0.92 &&
abs(t.y-mv.y)<=0.047 &&
t.x>=mv.x-0.22 && t.x<=pp.x-0.035
}
if labels.count>1 {return hold("HOLD_AMBIGUOUS_TYPE_ON_MOVE_ROW")}
if let t=labels.first {
guard used.insert(t.ref).inserted else {
return hold("HOLD_REUSED_TYPE_TOKEN")
}
records.append(["slot_index_candidate":i,
"displayed_type_candidate":type(t.text)!,
"type_evidence_ref":t.ref,"move_evidence_ref":mv.ref,
"pp_evidence_ref":pp.ref,"raw_type_text":t.text,
"source":"SOURCE_BOUND_MOVE_PANEL_OCR",
"owner_verified":false,"move_type_certified":false,
"current_state_eligible":false])
}
}
return ["schema":schema,"status":records.isEmpty ?
"NO_VISIBLE_MOVE_TYPE_LABELS" : "MOVE_PANEL_TYPE_OCR_CANDIDATES_ONLY",
"records":records,"candidate_count":records.count,
"move_pp_slots_seen":mrefs.count,
"rotation_hypothesis_degrees":deg,
"owner_verified":false,"move_type_certified":false,
"current_state_eligible":false,"battle_advice_authorized":false,
"real_game_accuracy":"NOT_MEASURED"]
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
let raw=hash(sourceKind=="LIVE_RETAINED_FRAME" ?
doc["png_sha256"]:doc["image_sha256"]),
let analysis=hash(snap["image_sha256"]),
hash(hud["source_image_sha256"])==raw,
hash(hud["analysis_image_sha256"])==analysis,
let session=snap["capture_session_id"] as? String,!session.isEmpty,
session==hud["capture_session_id"] as? String,
let epoch=integer(snap["epoch"]),epoch>0,
let frame=integer(snap["frame_id"]),frame>0,
integer(hud["epoch"])==epoch,integer(hud["frame_id"])==frame,
let inv=snap["ocr_source_inventory"] as? [[String:Any]],inv.count<=288,
let width=integer(doc["image_width"]),
let height=integer(doc["image_height"]) else {
return hold("HOLD_SOURCE_FRAME_OR_HUD_MISMATCH")
}
var aw=width,ah=height
if raw != analysis {
guard let p=doc["analysis_projection"] as? [String:Any],
p["status"] as? String=="DECLARED_GEOMETRY_ONLY",
p["raw_image_sha256"] as? String==raw,
p["analysis_image_sha256"] as? String==analysis,
p["capture_session_id"] as? String==session,
integer(p["epoch"])==epoch,integer(p["frame_id"])==frame,
integer(p["raw_width"])==width,integer(p["raw_height"])==height,
p["owner_certified"] as? Bool==false,
let w=integer(p["analysis_width"]),
let h=integer(p["analysis_height"]) else {
return hold("HOLD_ANALYSIS_TRANSFORM_MISMATCH")
}
aw=w;ah=h
}
guard aw>0,ah>0 else{return hold("HOLD_DIMENSIONS")}
var ts=[Token](),seen=Set<String>()
for row in inv {
guard let ref=row["evidence_ref"] as? String,
!ref.isEmpty,seen.insert(ref).inserted,
row["image_sha256"] as? String==analysis,
row["capture_session_id"] as? String==session,
integer(row["frame_id"])==frame,integer(row["epoch"])==epoch,
row["owner_verified"] as? Bool==false,
let text=row["raw_text"] as? String,!text.isEmpty,
text.utf8.count<=160,
let box=row["roi"] as? [String:Any],
let x=integer(box["x"]),let y=integer(box["y"]),
let w=integer(box["width"]),let h=integer(box["height"]),
x<aw,y<ah,w>0,h>0,w<=aw-x,h<=ah-y else {
return hold("HOLD_OCR_SOURCE_CONFLICT")
}
if ref.contains(".ocr_alternatives["){continue}
ts.append(Token(ref:ref,text:text,
x:(Double(x)+Double(w)/2)/Double(aw),
y:(Double(y)+Double(h)/2)/Double(ah),
w:Double(w)/Double(aw),h:Double(h)/Double(ah)))
}
var result=scan(ts,hud:hud,width:aw,height:ah)
result["source_image_sha256"]=raw
result["analysis_image_sha256"]=analysis
result["capture_session_id"]=session
result["epoch"]=epoch;result["frame_id"]=frame
result["source_kind"]=sourceKind
return result
}
static func enrich(_ doc:inout [String:Any],sourceKind:String) {
doc["r678_move_type_ocr"]=audit(doc,sourceKind:sourceKind)
}
}
