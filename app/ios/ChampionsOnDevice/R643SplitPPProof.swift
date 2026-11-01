import Foundation
import CoreFoundation
enum R643SplitPPProof {
static let schema="trueplan.r643.split-pp-evidence.v1"
private static func num(_ v:Any?)->Int? {
guard let n=v as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),
n.doubleValue.isFinite,n.doubleValue>=0,n.doubleValue<1_000_000,
n.doubleValue==Double(n.intValue) else{return nil}
return n.intValue
}
private static func sha(_ v:Any?)->String? {
guard let s=v as? String,s.utf8.count==64,
s.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)}) else{return nil}
return s
}
private struct Box {
let x:Int,y:Int,w:Int,h:Int
init?(_ v:Any?,_ width:Int,_ height:Int) {
guard let d=v as? [String:Any],let x=num(d["x"]),let y=num(d["y"]),
let w=num(d["width"]),let h=num(d["height"]),w>0,h>0,
x<width,y<height,w<=width-x,h<=height-y else{return nil}
self.x=x;self.y=y;self.w=w;self.h=h
}
private init(_ x:Int,_ y:Int,_ w:Int,_ h:Int){self.x=x;self.y=y;self.w=w;self.h=h}
var json:[String:Int]{["x":x,"y":y,"width":w,"height":h]}
func rotated(_ d:Int,_ width:Int,_ height:Int)->Box {
switch d {
case 90:return Box(height-y-h,x,h,w)
case 180:return Box(width-x-w,height-y-h,w,h)
case 270:return Box(y,width-x-w,h,w)
default:return self
}
}
func zone(_ slot:Int,_ width:Int,_ height:Int)->Bool {
let minX=0.865*Double(width),maxX=0.96*Double(width)
let minY=(0.43+Double(slot)*0.12)*Double(height)
let maxY=minY+0.10*Double(height)
let area=max(0,min(Double(x+w),maxX)-max(Double(x),minX)) *
max(0,min(Double(y+h),maxY)-max(Double(y),minY))
return area/Double(w*h)>=0.90
}
}
private struct Token {let ref:String;let text:String;let box:Box;let raw:Box}
private static func compact(_ s:String)->String {
s.replacingOccurrences(of:" ",with:"")
.replacingOccurrences(of:"　",with:"")
}
private static func part(_ text:String,denominator:Bool)->Int? {
var s=compact(text)
if denominator {guard s.hasPrefix("/") else{return nil};s.removeFirst()}
else if s.uppercased().hasPrefix("PP") {
s=String(s.dropFirst(2))
if s.hasPrefix(":") || s.hasPrefix("："){s.removeFirst()}
}
guard (1...2).contains(s.count),s.utf8.allSatisfy({(48...57).contains($0)}),
let n=Int(s),n<=64 else{return nil}
return n
}
static func enrich(_ doc:inout [String:Any],sourceKind:String) {
doc.removeValue(forKey:"r643_split_pp_evidence")
doc["r643_status"]="HOLD_NO_BOUND_LAYOUT"
guard ["LIVE_RETAINED_FRAME","USER_IMPORTED_PNG_OFFLINE_ONLY"].contains(sourceKind),
doc["r642_status"] as? String=="PROVISIONAL_RAW_FRAME_ROIS_ONLY",
doc["r641_status"] as? String=="UNIQUE_LAYOUT_HYPOTHESIS_NOT_CERTIFIED",
let p=doc["r642_raw_frame_roi_evidence"] as? [String:Any],
p["schema"] as? String==R642MappedFrameProof.schema,
p["source_kind"] as? String==sourceKind,
p["owner_verified"] as? Bool==false,
p["source_orientation_verified"] as? Bool==false,
p["battle_advice_authorized"] as? Bool==false,
num(p["game_fields_certified"])==0,
let angle=num(p["image_turn_candidate_degrees"]),[0,90,180,270].contains(angle),
let rawSHA=sha(p["raw_image_sha256"]),let aSHA=sha(p["analysis_image_sha256"]),
let frame=num(p["frame_id"]),frame>0,let epoch=num(p["epoch"]),epoch>0,
let session=p["capture_session_id"] as? String,!session.isEmpty,
let aw=num(p["analysis_width"]),let ah=num(p["analysis_height"]),
let rw=num(p["raw_width"]),let rh=num(p["raw_height"]),
aw>=180,ah>=180,aw<=3072,ah<=3072,rw>0,rh>0,rw<=3072,rh<=3072,
let snap=doc["screen_read_state"] as? [String:Any],
snap["image_sha256"] as? String==aSHA,
snap["capture_session_id"] as? String==session,
num(snap["frame_id"])==frame,num(snap["epoch"])==epoch,
snap["current_state_eligible"] as? Bool==false,
let inventory=snap["ocr_source_inventory"] as? [[String:Any]],inventory.count<=288,
let assigned=p["mapped_values"] as? [[String:Any]],assigned.count<=11 else{return}
let outW=angle%180==0 ? aw:ah,outH=angle%180==0 ? ah:aw
guard outW>=400,outH>=180,
abs(Double(outW)/Double(outH)-578.0/267.0)<0.025 else{return}
var excluded=Set<String>()
var existing=Set<Int>()
for row in assigned {
guard let ref=row["reference"] as? String,!ref.isEmpty,
excluded.insert(ref).inserted else {doc["r643_status"]="HOLD_DUPLICATE_PARENT_REF";return}
if row["role_hint"] as? String=="move_pp",let slot=num(row["slot"]),slot<4 {existing.insert(slot)}
}
var rawByRef=[String:Box]()
if rawSHA != aSHA {
guard let projection=doc["analysis_projection"] as? [String:Any],
projection["status"] as? String=="DECLARED_GEOMETRY_ONLY",
projection["analysis_image_sha256"] as? String==aSHA,
projection["raw_image_sha256"] as? String==rawSHA,
projection["capture_session_id"] as? String==session,
num(projection["frame_id"])==frame,num(projection["epoch"])==epoch,
num(projection["analysis_width"])==aw,num(projection["analysis_height"])==ah,
num(projection["raw_width"])==rw,num(projection["raw_height"])==rh,
let turns=num(projection["quarter_turns_ccw"]),turns<=3,
let crop=R556AnalysisProjection.rect(projection["pixel_crop"]),
let maps=projection["mapped_rois"] as? [[String:Any]],maps.count<=512 else {
doc["r643_status"]="HOLD_PROJECTION_ABSENT";return
}
let plan=R556AnalysisProjection.Plan(rawWidth:rw,rawHeight:rh,crop:crop,quarterTurnsCCW:turns)
guard plan.valid,plan.analysisWidth==aw,plan.analysisHeight==ah else {
doc["r643_status"]="HOLD_PROJECTION_INVALID";return
}
for m in maps {
guard let ref=m["evidence_ref"] as? String,!ref.isEmpty,rawByRef[ref]==nil,
let ar=R556AnalysisProjection.rect(m["analysis_rect"]),
let rr=R556AnalysisProjection.rect(m["raw_rect"]),
plan.sourceRect(ar)==rr,let raw=Box(rr.object,rw,rh) else {
doc["r643_status"]="HOLD_PROJECTION_COLLISION";return
}
rawByRef[ref]=raw
}
}
var tokenRefs=Set<String>(),tokens=[Token]()
for row in inventory {
guard let ref=row["evidence_ref"] as? String,!ref.isEmpty,
tokenRefs.insert(ref).inserted,
row["image_sha256"] as? String==aSHA,
row["capture_session_id"] as? String==session,
num(row["frame_id"])==frame,num(row["epoch"])==epoch,
row["owner_verified"] as? Bool==false,
let txt=row["raw_text"] as? String,!txt.isEmpty,txt.utf8.count<=160,
let rect=Box(row["roi"],aw,ah) else {
doc["r643_status"]="HOLD_INVALID_SOURCE_TOKEN";return
}
if ref.contains(".ocr_alternatives[") || excluded.contains(ref) {continue}
let raw:Box
if rawSHA==aSHA {raw=rect}
else {guard let mapped=rawByRef[ref] else {continue};raw=mapped}
tokens.append(Token(ref:ref,text:txt,box:rect,raw:raw))
}
var accepted=[[String:Any]](),uncertain=[Int](),used=excluded
for slot in 0..<4 where !existing.contains(slot) {
let zone=tokens.filter{$0.box.rotated(angle,aw,ah).zone(slot,outW,outH)}
let n=zone.compactMap{tok->(Token,Int)? in
guard let v=part(tok.text,denominator:false) else{return nil}
return (tok,v)
}
let d=zone.compactMap{tok->(Token,Int)? in
guard let v=part(tok.text,denominator:true),v>0 else{return nil}
return (tok,v)
}
var options=[(Token,Token,Int,Int)]()
for (first,current) in n {for (last,maxPP) in d {
let f=first.box.rotated(angle,aw,ah),l=last.box.rotated(angle,aw,ah)
let fy=Double(f.y)+Double(f.h)/2,ly=Double(l.y)+Double(l.h)/2
guard first.ref != last.ref,current<=maxPP,
l.x>=f.x+f.w-2,l.x-f.x-f.w<=Int(Double(outW)*0.025),
abs(fy-ly)<=Double(outH)*0.03 else{continue}
options.append((first,last,current,maxPP))
}}
if options.count>1 {uncertain.append(slot);continue}
guard let (first,last,current,maxPP)=options.first else{continue}
guard used.insert(first.ref).inserted,used.insert(last.ref).inserted else {
doc["r643_status"]="HOLD_REUSED_OCR_REFERENCE";return
}
accepted.append(["slot":slot,"current":current,"maximum":maxPP,
"source_refs":[first.ref,last.ref],"raw_texts":[first.text,last.text],
"raw_rects":[first.raw.json,last.raw.json],
"analysis_image_sha256":aSHA,"raw_image_sha256":rawSHA,
"owner_verified":false,"orientation_verified":false,
"current_value_admitted":false,"status":"PROVISIONAL_SPLIT_PP_ONLY"])
}
let report:[String:Any]=["schema":schema,"source_kind":sourceKind,
"raw_image_sha256":rawSHA,"analysis_image_sha256":aSHA,
"capture_session_id":session,"frame_id":frame,"epoch":epoch,
"candidate_degrees":angle,"split_pp_candidates":accepted,
"ambiguous_slots":uncertain,"candidate_count":accepted.count,
"owner_verified":false,"game_fields_certified":0,
"battle_advice_authorized":false,
"status":!uncertain.isEmpty ? "HOLD_AMBIGUOUS_PP_FRAGMENTS" :
accepted.isEmpty ? "HOLD_NO_SPLIT_PP_MATCH" : "PROVISIONAL_PP_FRAGMENTS_ONLY"]
guard JSONSerialization.isValidJSONObject(report) else {
doc["r643_status"]="HOLD_INVALID_JSON";return
}
doc["r643_split_pp_evidence"]=report
doc["r643_status"]=report["status"]
}
}
