import Foundation
import CoreFoundation
enum R642MappedFrameProof {
static let schema = "trueplan.r642.raw-frame-roi-evidence.v1"
private static func int(_ v:Any?) -> Int? {
guard let n=v as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),
n.doubleValue.isFinite,n.doubleValue>=0,n.doubleValue<=Double(Int32.max),
n.doubleValue == Double(n.intValue) else{return nil}
return n.intValue
}
private static func sha(_ v:Any?) -> String? {
guard let s=v as? String,s.utf8.count==64,
s.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)}) else{return nil}
return s
}
private static func rect(_ raw:Any?,_ w:Int,_ h:Int)->R556AnalysisProjection.Rect? {
guard let r=R556AnalysisProjection.rect(raw),r.fits(width:w,height:h) else{return nil}
return r
}
static func enrich(_ doc:inout [String:Any],sourceKind:String) {
doc.removeValue(forKey:"r642_raw_frame_roi_evidence")
doc["r642_status"]="HOLD_NOT_BOUND_TO_UNIQUE_LAYOUT"
guard ["LIVE_RETAINED_FRAME","USER_IMPORTED_PNG_OFFLINE_ONLY"].contains(sourceKind),
doc["r641_status"] as? String == "UNIQUE_LAYOUT_HYPOTHESIS_NOT_CERTIFIED",
let diag=doc["r641_rotated_hud_candidates"] as? [String:Any],
diag["schema"] as? String == R641RotatedHUDCandidates.schema,
diag["source_kind"] as? String == sourceKind,
diag["source_orientation_verified"] as? Bool == false,
diag["owner_verified"] as? Bool == false,
int(diag["game_fields_certified"]) == 0,
diag["battle_advice_authorized"] as? Bool == false,
diag["matching_profile_count"] as? Int == 1,
let angle=int(diag["rotation_candidate_degrees"]),
[0,90,180,270].contains(angle),
let expectedAnalysis=sha(diag["source_image_sha256"]),
let source=doc["screen_read_state"] as? [String:Any],
source["current_state_eligible"] as? Bool == false,
source["battle_advice_authorized"] as? Bool == false,
let session=source["capture_session_id"] as? String,!session.isEmpty,
let frame=int(source["frame_id"]),frame>0,
let epoch=int(source["epoch"]),epoch>0,
let aSHA=sha(source["image_sha256"]),aSHA==expectedAnalysis,
let cov=doc["r581_full_read_coverage"] as? [String:Any],
cov["schema"] as? String == R581ReadabilityCoverage.schema,
cov["source_kind"] as? String == sourceKind,
cov["snapshot_binding_valid"] as? Bool == true,
cov["source_binding_valid"] as? Bool == true,
cov["current_state_eligible"] as? Bool == false,
cov["owner_certified"] as? Bool == false,
let rawSHA=sha(cov["image_sha256"]),
let docSHA=sha(sourceKind=="LIVE_RETAINED_FRAME" ? doc["png_sha256"] : doc["image_sha256"]),
rawSHA==docSHA,
cov["analysis_image_sha256"] as? String == aSHA,
let width=int(doc["image_width"]),let height=int(doc["image_height"]),
width>0,height>0,width<=3072,height<=3072,
width*height<=4_500_000,
let rows=source["ocr_source_inventory"] as? [[String:Any]],rows.count<=288,
let values=diag["candidate_values"] as? [[String:Any]],
(1...11).contains(values.count) else {return}
var analysisWidth=width,analysisHeight=height
var plan:R556AnalysisProjection.Plan?=nil
var lookup=[String:(R556AnalysisProjection.Rect,R556AnalysisProjection.Rect)]()
if rawSHA != aSHA {
guard cov["declared_analysis_projection_valid"] as? Bool == true,
let projection=doc["analysis_projection"] as? [String:Any],
projection["schema"] as? String == "trueplan.screen-read.analysis-projection.v1",
projection["status"] as? String == "DECLARED_GEOMETRY_ONLY",
projection["raw_image_sha256"] as? String == rawSHA,
projection["analysis_image_sha256"] as? String == aSHA,
projection["capture_session_id"] as? String == session,
int(projection["frame_id"]) == frame,
int(projection["epoch"]) == epoch,
projection["pixel_equality_verified"] as? Bool == false,
projection["game_orientation_certified"] as? Bool == false,
projection["owner_certified"] as? Bool == false,
int(projection["raw_width"]) == width,
int(projection["raw_height"]) == height,
let aw=int(projection["analysis_width"]),
let ah=int(projection["analysis_height"]),
let crop=R556AnalysisProjection.rect(projection["pixel_crop"]),
let turns=int(projection["quarter_turns_ccw"]),
(0...3).contains(turns),
let maps=projection["mapped_rois"] as? [[String:Any]],maps.count<=512,
projection["omitted_rois"] is [[String:Any]] else {
doc["r642_status"]="HOLD_RAW_ANALYSIS_TRANSFORM_UNVERIFIED";return
}
let created=R556AnalysisProjection.Plan(rawWidth:width,rawHeight:height,
crop:crop,quarterTurnsCCW:turns)
guard created.valid,created.analysisWidth==aw,created.analysisHeight==ah else {
doc["r642_status"]="HOLD_INVALID_TRANSFORM_GEOMETRY";return
}
plan=created;analysisWidth=aw;analysisHeight=ah
for map in maps {
guard let ref=map["evidence_ref"] as? String,!ref.isEmpty,lookup[ref]==nil,
let ar=rect(map["analysis_rect"],aw,ah),
let rr=rect(map["raw_rect"],width,height),
created.sourceRect(ar)==rr else {
doc["r642_status"]="HOLD_INCONSISTENT_PROJECTION_MAP";return
}
lookup[ref]=(ar,rr)
}
}
var inventory=[String:(String,R556AnalysisProjection.Rect)]()
for row in rows {
guard let ref=row["evidence_ref"] as? String,!ref.isEmpty,
ref.utf8.count<=160,inventory[ref]==nil,
let raw=row["raw_text"] as? String,!raw.isEmpty,raw.utf8.count<=160,
row["image_sha256"] as? String == aSHA,
row["capture_session_id"] as? String == session,
int(row["frame_id"]) == frame,
int(row["epoch"]) == epoch,
row["owner_verified"] as? Bool == false,
let roi=rect(row["roi"],analysisWidth,analysisHeight) else {
doc["r642_status"]="HOLD_CORRUPTED_OCR_INVENTORY";return
}
inventory[ref]=(raw,roi)
}
let allowed=Set(["own_hp","opponent_percent","command","move_name","move_pp"])
var seen=Set<String>()
var result=[[String:Any]]()
for candidate in values {
guard let role=candidate["role_hint"] as? String,allowed.contains(role),
candidate["side"] as? String == "UNKNOWN_OWNER",
candidate["owner_verified"] as? Bool == false,
candidate["orientation_verified"] as? Bool == false,
candidate["current_value_admitted"] as? Bool == false,
candidate["status"] as? String == "PROVISIONAL_LAYOUT_VALUE_ONLY",
candidate["source_sha256"] as? String == aSHA,
let ref=candidate["source_ref"] as? String,!ref.isEmpty,
seen.insert(ref).inserted,
let pair=inventory[ref],
candidate["raw_text"] as? String == pair.0 else {
doc["r642_status"]="HOLD_OCR_CANDIDATE_SOURCE_CONFLICT";return
}
let slot=int(candidate["slot"])
if role=="move_name" || role=="move_pp" {
guard let slot,slot<=3 else {
doc["r642_status"]="HOLD_INVALID_MOVE_SLOT";return
}
} else if candidate["slot"] != nil && !(candidate["slot"] is NSNull) {
doc["r642_status"]="HOLD_NONMOVE_SLOT_PRESENT";return
}
let original:R556AnalysisProjection.Rect
if let plan {
guard let mapped=lookup[ref],mapped.0==pair.1,
let recomputed=plan.sourceRect(pair.1),recomputed==mapped.1 else {
doc["r642_status"]="HOLD_SOURCE_RECT_NOT_VERIFIED";return
}
original=mapped.1
} else {original=pair.1}
result.append(["role_hint":role,"slot":slot.map{$0 as Any} ?? NSNull(),
"reference":ref,"raw_text":pair.0,
"analysis_rect":pair.1.object,"raw_frame_rect":original.object,
"source_image_sha256":rawSHA,"analysis_image_sha256":aSHA,
"owner_verified":false,"orientation_verified":false,
"current_value_admitted":false])
}
let output:[String:Any]=[
"schema":schema,"status":"PROVISIONAL_RAW_FRAME_ROIS_ONLY",
"source_kind":sourceKind,"capture_session_id":session,
"frame_id":frame,"epoch":epoch,
"raw_image_sha256":rawSHA,"analysis_image_sha256":aSHA,
"raw_width":width,"raw_height":height,
"analysis_width":analysisWidth,"analysis_height":analysisHeight,
"image_turn_candidate_degrees":angle,
"transform_source":plan == nil ? "IDENTICAL_PNG_SHA" : "DECLARED_R556_CROP_ROTATE",
"pixel_equality_verified":false,"owner_verified":false,
"source_orientation_verified":false,"game_fields_certified":0,
"battle_advice_authorized":false,"current_state_eligible":false,
"mapped_values":result,"mapped_count":result.count]
guard JSONSerialization.isValidJSONObject(output) else {
doc["r642_status"]="HOLD_OUTPUT_NOT_SERIALIZABLE";return
}
doc["r642_raw_frame_roi_evidence"]=output
doc["r642_status"]="PROVISIONAL_RAW_FRAME_ROIS_ONLY"
}
}
