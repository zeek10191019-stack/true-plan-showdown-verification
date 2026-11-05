import Foundation
import CoreFoundation

enum R679TypeColorProbe {
static let schema="trueplan.r679.pixel-move-type-color.v1"
private static let families=["WARM","YELLOW","GREEN","CYAN","BLUE","VIOLET"]
private static func hash(_ s:String)->Bool {
s.utf8.count==64 && s.utf8.allSatisfy {
(48...57).contains($0) || (97...102).contains($0)
}
}
private static func number(_ a:Any?)->Int? {
guard let n=a as? NSNumber,
CFGetTypeID(n) != CFBooleanGetTypeID(),
n.doubleValue.isFinite,n.doubleValue>=0,
n.doubleValue<Double(Int32.max),
n.doubleValue==Double(n.intValue) else {return nil}
return n.intValue
}
private static func identity(_ a:Any?)->Int64? {
guard let n=a as? NSNumber,
CFGetTypeID(n) != CFBooleanGetTypeID(),
n.doubleValue.isFinite,n.doubleValue>=0,
n.doubleValue<9_000_000_000_000_000,
n.doubleValue==Double(n.int64Value) else {return nil}
return n.int64Value
}
private static func hold(_ why:String,epoch:Int64,frame:Int64,
sha:String)->[String:Any] {
["schema":schema,"status":why,"epoch":epoch,"frame_id":frame,
"raw_image_sha256":sha,"samples":[[String:Any]](),
"sample_count":0,"move_type_certified":false,
"owner_certified":false,"orientation_certified":false,
"current_state_eligible":false,"battle_advice_authorized":false]
}
static func unavailable(epoch:Int64,frame:Int64,sha:String)->[String:Any] {
hold("HOLD_RGBA_UNAVAILABLE",epoch:epoch,frame:frame,sha:sha)
}
private static func hueBin(_ r:Int,_ g:Int,_ b:Int,_ alpha:Int)->Int? {
guard alpha>=200 else{return nil}
let hi=max(r,g,b),lo=min(r,g,b),d=hi-lo
guard hi>=78,d>=48,Double(d)/Double(hi)>=0.35 else{return nil}
let hue:Double
if hi==r {hue=60*Double(g-b)/Double(d)}
else if hi==g {hue=60*(Double(b-r)/Double(d)+2)}
else {hue=60*(Double(r-g)/Double(d)+4)}
let h=hue<0 ? hue+360:hue
if h<38 || h>=345 {return 0}
if h<75 {return 1}
if h<165 {return 2}
if h<200 {return 3}
if h<265 {return 4}
return 5
}
private static func validBox(_ v:Any?,w:Int,h:Int)->(Int,Int,Int,Int)? {
guard let b=v as? [String:Any],
let x=number(b["x"]),let y=number(b["y"]),
let dx=number(b["width"]),let dy=number(b["height"]),
dx>0,dy>0,x<w,y<h,dx<=w-x,dy<=h-y else{return nil}
return (x,y,dx,dy)
}
private static func sample(_ pixels:[UInt8],w:Int,h:Int,rowBytes:Int,
box:(Int,Int,Int,Int),flip:Bool)->[String:Any] {
let (x,y,bw,bh)=box
let left=max(0,x-max(22,min(76,bw*2)))
let right=max(0,x-2)
let top=max(0,y-bh/2),bottom=min(h,y+bh+bh/2)
var counts=[Int](repeating:0,count:6),n=0
if right>left && bottom>top {
for yy in top..<bottom {for xx in left..<right {
let sourceY=flip ? h-1-yy:yy
let i=sourceY*rowBytes+xx*4
if let c=hueBin(Int(pixels[i]),Int(pixels[i+1]),
Int(pixels[i+2]),Int(pixels[i+3])) {counts[c]+=1;n+=1}
}}
}
let best=counts.enumerated().max {a,b in
if a.element != b.element {return a.element<b.element}
return a.offset>b.offset
}
let topCount=best?.element ?? 0
let next=counts.enumerated().filter{$0.offset != best?.offset}
.map{$0.element}.max() ?? 0
let distinct=n>=25 && topCount*100>=55*n &&
(topCount-next)*100>=17*n
return ["status":distinct ? "UNVERIFIED_COLOR_BAND" :
"HOLD_NO_DISTINCT_COLOR_BAND",
"dominant_color_family_unverified":distinct ?
families[best?.offset ?? 0] : "UNKNOWN",
"bin_counts":counts,"saturated_pixel_count":n,
"band_left_px":left,"band_right_px":right,
"band_top_px":top,"band_bottom_px":bottom,
"raster_y_flip_hypothesis":flip,
"label_bbox_source":"SOURCE_BOUND_OCR_ROI",
"actual_type_from_color_certified":false] as [String:Any]
}
static func inspect(pixels:[UInt8],width:Int,height:Int,rowBytes:Int,
epoch:Int64,frame:Int64,observedMs:Int64,sha:String,
document:[String:Any])->[String:Any] {
func reject(_ why:String)->[String:Any] {
hold(why,epoch:epoch,frame:frame,sha:sha)
}
guard width>=400,height>=180,width<=4096,height<=4096,
rowBytes>=width*4,rowBytes<=width*4+4096,
rowBytes<=64*1024*1024/height,
pixels.count==rowBytes*height,
epoch>0,frame>0,observedMs>0,hash(sha),
document["png_sha256"] as? String==sha,
number(document["image_width"])==width,
number(document["image_height"])==height,
let status=document["r678_move_type_ocr"] as? [String:Any],
status["schema"] as? String=="trueplan.r678.move-panel-type-ocr.v1",
status["status"] as? String=="MOVE_PANEL_TYPE_OCR_CANDIDATES_ONLY",
status["source_kind"] as? String=="LIVE_RETAINED_FRAME",
status["source_image_sha256"] as? String==sha,
status["analysis_image_sha256"] as? String==sha,
identity(status["frame_id"])==frame,
identity(status["epoch"])==epoch,
status["owner_verified"] as? Bool==false,
status["move_type_certified"] as? Bool==false,
status["current_state_eligible"] as? Bool==false,
let session=status["capture_session_id"] as? String,
!session.isEmpty,session.utf8.count<=128,
let records=status["records"] as? [[String:Any]],
(1...4).contains(records.count),
number(status["candidate_count"])==records.count,
let snap=document["screen_read_state"] as? [String:Any],
snap["image_sha256"] as? String==sha,
snap["capture_session_id"] as? String==session,
identity(snap["frame_id"])==frame,
identity(snap["epoch"])==epoch,
let inventory=snap["ocr_source_inventory"] as? [[String:Any]],
inventory.count<=288 else {
return reject("HOLD_UNMATCHED_SELECTED_FRAME_OR_OCR")
}
var boxes=[String:(Int,Int,Int,Int)](),seen=Set<String>()
for entry in inventory {
guard let ref=entry["evidence_ref"] as? String,
!ref.isEmpty,seen.insert(ref).inserted,
entry["image_sha256"] as? String==sha,
entry["capture_session_id"] as? String==session,
identity(entry["frame_id"])==frame,
identity(entry["epoch"])==epoch,
entry["owner_verified"] as? Bool==false,
let box=validBox(entry["roi"],w:width,h:height) else {
return reject("HOLD_OCR_INVENTORY_CONTRADICTION")
}
boxes[ref]=box
}
var used=Set<String>(),slots=Set<Int>(),output=[[String:Any]]()
for r in records {
guard let slot=number(r["slot_index_candidate"]),slot<4,
slots.insert(slot).inserted,
let type=r["displayed_type_candidate"] as? String,
!type.isEmpty,type.utf8.count<=40,
let tref=r["type_evidence_ref"] as? String,
let mref=r["move_evidence_ref"] as? String,
let pref=r["pp_evidence_ref"] as? String,
Set([tref,mref,pref]).count==3,
used.insert(tref).inserted,
let box=boxes[tref],boxes[mref] != nil,boxes[pref] != nil,
let rawText=r["raw_type_text"] as? String,
rawText==inventory.first(where:{$0["evidence_ref"] as? String==tref})?["raw_text"] as? String,
r["source"] as? String=="SOURCE_BOUND_MOVE_PANEL_OCR",
r["move_type_certified"] as? Bool==false,
r["owner_verified"] as? Bool==false else {
return reject("HOLD_TYPE_ROW_OR_PROVENANCE_CONFLICT")
}
var candidates=[[String:Any]]()
for flip in [false,true] {
var s=sample(pixels,w:width,h:height,rowBytes:rowBytes,
box:box,flip:flip)
s["slot_index_candidate"]=slot
s["ocr_type_claim_unverified"]=type
s["type_evidence_ref"]=tref
s["move_evidence_ref"]=mref
s["pp_evidence_ref"]=pref
s["frame_id"]=frame
s["raw_image_sha256"]=sha
candidates.append(s)
}
output.append(contentsOf:candidates)
}
return ["schema":schema,"status":"HISTORICAL_TYPE_COLOR_SAMPLES_ONLY",
"epoch":epoch,"frame_id":frame,"observed_ms":observedMs,
"raw_image_sha256":sha,"sample_count":output.count,
"samples":output,"type_label_source":"R678_OCR_AND_REAL_RGBA",
"color_is_type_ground_truth":false,
"raster_row_order_calibrated":false,
"owner_certified":false,"move_type_certified":false,
"orientation_certified":false,"current_state_eligible":false,
"battle_advice_authorized":false,"real_game_accuracy":"NOT_MEASURED"]
}
}
