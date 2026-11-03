import Foundation
import CoreFoundation

// R675: independently observed OCR fractions and RGBA bar proportions.
// A pixel-to-OCR match is evidence, not proof of HP, actor identity or turn.
enum R675PixelOCRHPAgreement {
static let schema="trueplan.r675.crossmodal-hp-evidence.v1"
private static func number(_ v:Any?)->Int? {
guard let n=v as? NSNumber,
CFGetTypeID(n) != CFBooleanGetTypeID(),
n.doubleValue.isFinite,n.doubleValue>=0,
n.doubleValue<=10000,n.doubleValue==Double(n.intValue)
else{return nil}
return n.intValue
}
private static func identity(_ v:Any?)->Int64? {
guard let n=v as? NSNumber,
CFGetTypeID(n) != CFBooleanGetTypeID(),
n.doubleValue.isFinite,n.doubleValue>=0,
n.doubleValue<Double(Int64.max),
n.doubleValue==Double(n.int64Value) else{return nil}
return n.int64Value
}
private static func sha(_ s:String)->Bool {
s.utf8.count==64 && s.utf8.allSatisfy {
(48...57).contains($0) || (97...102).contains($0)
}
}
private static func hold(_ why:String)->[String:Any] {
["schema":schema,"status":why,"agreements":[[String:Any]](),
"conflicts":[[String:Any]](),"agreement_count":0,
"owner_certified":false,"hp_percent_certified":false,
"current_state_eligible":false,"battle_advice_authorized":false]
}
private static func degrees(_ ocr:[String:Any],
_ raw:String,_ frame:Int64,_ epoch:Int64,
_ projection:[String:Any]?)->Int? {
guard let deg=number(ocr["rotation_candidate_degrees"]),
[0,90,180,270].contains(deg),
let analysis=ocr["analysis_image_sha256"] as? String,
sha(analysis) else{return nil}
if analysis==raw {return deg}
guard let p=projection,
p["schema"] as? String ==
"trueplan.screen-read.analysis-projection.v1",
p["status"] as? String=="DECLARED_GEOMETRY_ONLY",
p["raw_image_sha256"] as? String==raw,
p["analysis_image_sha256"] as? String==analysis,
identity(p["frame_id"])==frame,
identity(p["epoch"])==epoch,
p["owner_certified"] as? Bool==false,
let w=number(p["raw_width"]),w>0,
let h=number(p["raw_height"]),h>0,
let crop=p["pixel_crop"] as? [String:Any],
number(crop["x"])==0,number(crop["y"])==0,
number(crop["width"])==w,
number(crop["height"])==h,
let turns=number(p["quarter_turns_ccw"]),turns<=3
else{return nil}
return (deg + 360 - 90*turns)%360
}
static func audit(ocr:[String:Any],pixelFrames:[[String:Any]],
rawSHA:String,frame:Int64,epoch:Int64,
projection:[String:Any]?=nil)->[String:Any] {
guard sha(rawSHA),frame>0,epoch>0,
ocr["schema"] as? String==R668PlainHUDReader.schema,
ocr["status"] as? String=="HUD_PLAIN_OCR_HYPOTHESES_ONLY",
ocr["source_image_sha256"] as? String==rawSHA,
identity(ocr["frame_id"])==frame,
identity(ocr["epoch"])==epoch,
ocr["owner_verified"] as? Bool==false,
ocr["current_state_eligible"] as? Bool==false,
let ocrRows=ocr["matches"] as? [[String:Any]],
ocrRows.count<=16,pixelFrames.count<=8 else {
return hold("HOLD_OCR_SOURCE_OR_SCHEMA")
}
guard let rotation=degrees(ocr,rawSHA,frame,epoch,projection)
else{return hold("HOLD_RAW_ANALYSIS_ROTATION_UNMAPPED")}
let matches=pixelFrames.filter {
identity($0["frame_id"])==frame &&
identity($0["epoch"])==epoch &&
$0["raw_image_sha256"] as? String==rawSHA
}
guard matches.count==1,let pixel=matches.first,
pixel["schema"] as? String==R672PixelHPFillReader.schema,
pixel["status"] as? String=="PARTIAL_BAR_FILL_TRACKS_UNVERIFIED",
pixel["owner_certified"] as? Bool==false,
pixel["hp_percent_certified"] as? Bool==false,
let tracks=pixel["tracks"] as? [[String:Any]],
tracks.count<=16,pixel["track_count"] as? Int==tracks.count
else{return hold("HOLD_RGBA_FRAME_NOT_BOUND")}
var agreements=[[String:Any]](),conflicts=[[String:Any]]()
for (field,region) in [
("own.hp","LOWER_LEFT_HUD_POSITION_ONLY"),
("opponent.hp_percent","UPPER_RIGHT_HUD_POSITION_ONLY")] {
let rows=ocrRows.filter {$0["field"] as? String==field}
guard rows.count<=1 else{return hold("HOLD_DUPLICATE_OCR_FIELD")}
guard let row=rows.first else{continue}
guard row["owner_verified"] as? Bool==false,
let ref=row["evidence_ref"] as? String,!ref.isEmpty
else{return hold("HOLD_INVALID_OCR_CANDIDATE")}
var numeric:Double
if field=="own.hp" {
guard let pair=row["value"] as? [String:Any],
let cur=number(pair["current"]),
let max=number(pair["maximum"]),max>0,cur<=max
else{return hold("HOLD_INVALID_OWN_HP_FRACTION")}
numeric=Double(cur)*100/Double(max)
} else {
guard let value=number(row["value"]),value<=100
else{return hold("HOLD_INVALID_OPPONENT_PERCENT")}
numeric=Double(value)
}
let eligible=tracks.filter {
$0["position_hint"] as? String==region &&
$0["rotation_hypothesis_degrees"] as? Int==rotation
}
guard eligible.count<=1 else{return hold("HOLD_AMBIGUOUS_BAR_TRACK")}
guard let bar=eligible.first else{continue}
guard bar["owner"] as? String=="UNKNOWN",
bar["hp_percent_certified"] as? Bool==false,
let fill=bar["fill_percentage_candidate_not_hp"] as? Double,
fill.isFinite,(8...92).contains(fill),
let origin=bar["raw_row_origin_hypothesis"] as? String,
["TOP_FIRST","BOTTOM_FIRST"].contains(origin)
else{return hold("HOLD_MALFORMED_PIXEL_BAR")}
let difference=abs(numeric-fill)
let line:[String:Any]=[
"field_hint":field,"ocr_percent":numeric,
"pixel_fill_percent":fill,"abs_percentage_point_error":difference,
"ocr_evidence_ref":ref,"position_hint":region,
"rotation_degrees":rotation,"raw_row_origin":origin,
"candidate_only":true,"owner_certified":false,
"hp_percent_certified":false]
if difference<=5.0 {agreements.append(line)}
else{conflicts.append(line)}
}
var out=hold(conflicts.isEmpty ?
(agreements.isEmpty ? "HOLD_NO_COMMON_HP_READINGS" :
"PIXEL_OCR_RATIO_AGREEMENT_UNCERTIFIED") :
"HOLD_PIXEL_OCR_HP_CONTRADICTION")
out["agreements"]=agreements
out["conflicts"]=conflicts
out["agreement_count"]=agreements.count
out["frame_id"]=frame;out["epoch"]=epoch
out["raw_image_sha256"]=rawSHA
out["rotation_hypothesis_degrees"]=rotation
out["accuracy"]="NOT_MEASURED"
return out
}
}
