import Foundation
import CoreFoundation
enum R676FieldOverlayOCR {
static let schema = "trueplan.r676.field-effect-overlay-ocr.v1"
typealias Token = R668PlainHUDReader.Token
private static let terms: [(String,String,[String])] = [
("field.weather","RAIN",["雨","あめ"]),
("field.weather","SUN",["晴れ","にほんばれ","日差しが強い"]),
("field.weather","SAND",["砂嵐","すなあらし"]),
("field.weather","SNOW",["雪","ゆき"]),
("field.terrain","ELECTRIC",["エレキフィールド"]),
("field.terrain","GRASSY",["グラスフィールド"]),
("field.terrain","PSYCHIC",["サイコフィールド"]),
("field.terrain","MISTY",["ミストフィールド"]),
("field.trick_room","TRICK_ROOM",["トリックルーム"]),
("field.other_rooms","MAGIC_ROOM",["マジックルーム"]),
("field.other_rooms","WONDER_ROOM",["ワンダールーム"]),
("field.temporary_effects","GRAVITY",["じゅうりょく","重力"]),
("side.screen","REFLECT",["リフレクター"]),
("side.screen","LIGHT_SCREEN",["ひかりのかべ","光の壁"]),
("side.screen","AURORA_VEIL",["オーロラベール"]),
("side.screen","TAILWIND",["おいかぜ","追い風"]),
("side.hazard","STEALTH_ROCK",["ステルスロック"]),
("side.hazard","SPIKES",["まきびし"]),
("side.hazard","TOXIC_SPIKES",["どくびし"]),
("side.hazard","STICKY_WEB",["ねばねばネット"])
]
private static func hold(_ why:String)->[String:Any] {
["schema":schema,"status":why,"records":[[String:Any]](),
"field_count":0,"owner_verified":false,"turn_verified":false,
"current_state_eligible":false,"battle_advice_authorized":false]
}
private static func number(_ v:Any?)->Int? {
guard let n=v as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),
n.doubleValue.isFinite,n.doubleValue>=0,
n.doubleValue<Double(Int32.max),n.doubleValue==Double(n.intValue)
else{return nil}
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
private static func effect(_ raw:String)->(String,String,Int?)? {
let s=plain(raw)
guard !s.isEmpty,s.utf8.count<=100 else{return nil}
var head=s,turns:Int?=nil
if let r=s.range(of:#"(?:残り|あと)[1-8]ターン$"#,
options:.regularExpression),
let digits=s[r].first(where:{$0.isNumber}),
let count=digits.wholeNumberValue {
head=String(s[..<r.lowerBound]);turns=count
}
for (field,code,words) in terms where words.contains(head) {
return (field,code,turns)
}
return nil
}
private static func duration(_ raw:String)->Int? {
let s=plain(raw)
guard s.range(of:#"^(?:残り|あと)[1-8]ターン$"#,
options:.regularExpression) != nil,
let c=s.first(where:{$0.isNumber})?.wholeNumberValue
else{return nil}
return c
}
private static func valid(_ t:Token)->Bool {
!t.ref.isEmpty && t.ref.utf8.count<=160 &&
!t.text.isEmpty && t.text.utf8.count<=160 &&
[t.x,t.y,t.w,t.h].allSatisfy{$0.isFinite} &&
(0...1).contains(t.x) && (0...1).contains(t.y) &&
t.w>0 && t.h>0 && t.x-t.w/2>=0 && t.y-t.h/2>=0 &&
t.x+t.w/2<=1 && t.y+t.h/2<=1
}
private static func overlay(_ t:Token)->Bool {
t.x>=0.08 && t.x<=0.92 && t.y>=0.06 && t.y<=0.73 &&
!(t.x>=0.53 && t.y>=0.34)
}
static func scan(_ tokens:[Token],hud:[String:Any],
width:Int,height:Int)->[String:Any] {
guard (400...8192).contains(width),(180...8192).contains(height),
tokens.count<=288,Set(tokens.map{$0.ref}).count==tokens.count,
tokens.allSatisfy(valid),
hud["schema"] as? String==R668PlainHUDReader.schema,
hud["status"] as? String=="HUD_PLAIN_OCR_HYPOTHESES_ONLY",
hud["owner_verified"] as? Bool==false,
hud["current_state_eligible"] as? Bool==false,
let deg=number(hud["rotation_candidate_degrees"]),
[0,90,180,270].contains(deg) else {
return hold("HOLD_UNBOUND_HUD_OR_TOKENS")
}
let rw=deg%180==0 ? width:height
let rh=deg%180==0 ? height:width
guard (1.65...2.35).contains(Double(rw)/Double(rh)) else {
return hold("HOLD_NON_LANDSCAPE_LAYOUT")
}
let situated=tokens.map{$0.rotated(deg)}.filter(overlay)
var output=[[String:Any]](),used=Set<String>()
var usedDurationRefs=Set<String>()
var exclusiveFieldNames=Set<String>()
for t in situated {
guard let (field,code,inlineTurns)=effect(t.text) else{continue}
guard used.insert(code).inserted else {
return hold("HOLD_DUPLICATE_VISIBLE_EFFECT")
}
if ["field.weather","field.terrain","field.trick_room"].contains(field),
!exclusiveFieldNames.insert(field).inserted {
return hold("HOLD_CONFLICTING_GLOBAL_EFFECTS")
}
var chosen=inlineTurns,adjacentRef:String?=nil
if inlineTurns==nil {
let neighbors=situated.filter {
$0.ref != t.ref && duration($0.text) != nil &&
abs($0.y-t.y)<=0.065 && abs($0.x-t.x)<=0.22
}
if neighbors.count>1 {
return hold("HOLD_AMBIGUOUS_EFFECT_DURATION")
}
if let only=neighbors.first {
guard usedDurationRefs.insert(only.ref).inserted else {
return hold("HOLD_SHARED_DURATION_REFERENCE")
}
chosen=duration(only.text);adjacentRef=only.ref
}
}
var record:[String:Any]=[
"field":field,"effect_code":code,"raw_text":t.text,
"label_evidence_ref":t.ref,
"side_hint":"UNRESOLVED_FIELD_OR_SCREEN_POSITION",
"display_x":t.x,"display_y":t.y,
"owner_verified":false,"turn_verified":false,
"active_effect_certified":false,
"current_state_eligible":false]
if let turns=chosen {record["visible_turn_count_candidate"]=turns}
if let ref=adjacentRef {record["turn_evidence_ref"]=ref}
output.append(record)
}
output.sort {($0["effect_code"] as? String ?? "") <
($1["effect_code"] as? String ?? "")}
return ["schema":schema,"status":output.isEmpty ?
"NO_GEOMETRIC_FIELD_EFFECT_OCR" :
"FIELD_EFFECT_TEXT_AND_POSITION_CANDIDATES_ONLY",
"records":output,"field_count":output.count,
"rotation_hypothesis_degrees":deg,
"owner_verified":false,"turn_verified":false,
"current_state_eligible":false,
"battle_advice_authorized":false,
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
doc["png_sha256"] : doc["image_sha256"]),
let analysis=hash(snap["image_sha256"]),
hash(hud["source_image_sha256"])==raw,
hash(hud["analysis_image_sha256"])==analysis,
let session=snap["capture_session_id"] as? String,
!session.isEmpty,session==hud["capture_session_id"] as? String,
let epoch=number(snap["epoch"]),epoch>0,
let frame=number(snap["frame_id"]),frame>0,
number(hud["epoch"])==epoch,number(hud["frame_id"])==frame,
let inv=snap["ocr_source_inventory"] as? [[String:Any]],
inv.count<=288,
let width=number(doc["image_width"]),
let height=number(doc["image_height"]) else {
return hold("HOLD_SOURCE_OR_IDENTITY_MISMATCH")
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
return hold("HOLD_PROJECTION_MISMATCH")
}
aw=w;ah=h
}
var tokens=[Token](),seen=Set<String>()
for row in inv {
guard let ref=row["evidence_ref"] as? String,
!ref.isEmpty,seen.insert(ref).inserted,
row["image_sha256"] as? String==analysis,
row["capture_session_id"] as? String==session,
number(row["frame_id"])==frame,
number(row["epoch"])==epoch,
row["owner_verified"] as? Bool==false,
let s=row["raw_text"] as? String,
!s.isEmpty,s.utf8.count<=160,
let box=row["roi"] as? [String:Any],
let x=number(box["x"]),let y=number(box["y"]),
let w=number(box["width"]),let h=number(box["height"]),
x<aw,y<ah,w>0,h>0,w<=aw-x,h<=ah-y else {
return hold("HOLD_CORRUPT_OCR_SOURCE")
}
if ref.contains(".ocr_alternatives[") {continue}
tokens.append(Token(ref:ref,text:s,
x:(Double(x)+Double(w)/2)/Double(aw),
y:(Double(y)+Double(h)/2)/Double(ah),
w:Double(w)/Double(aw),h:Double(h)/Double(ah)))
}
var result=scan(tokens,hud:hud,width:aw,height:ah)
result["source_image_sha256"]=raw
result["analysis_image_sha256"]=analysis
result["frame_id"]=frame;result["epoch"]=epoch
result["capture_session_id"]=session
result["source_kind"]=sourceKind
return result
}
static func enrich(_ doc:inout [String:Any],sourceKind:String) {
doc["r676_field_overlay_ocr"]=audit(doc,sourceKind:sourceKind)
}
}
