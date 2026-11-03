import Foundation
@main struct R675Smoke {
static func main(){
let sha=String(repeating:"a",count:64)
let fields:[[String:Any]]=[
["field":"own.hp","value":["current":148,"maximum":197],
"evidence_ref":"ocr_hp","owner_verified":false],
["field":"opponent.hp_percent","value":81,
"evidence_ref":"ocr_opp","owner_verified":false]]
func ocr(_ rows:[[String:Any]]=fields)->[String:Any]{
["schema":R668PlainHUDReader.schema,
"status":"HUD_PLAIN_OCR_HYPOTHESES_ONLY",
"source_image_sha256":sha,"analysis_image_sha256":sha,
"frame_id":Int(2),"epoch":Int(1),
"rotation_candidate_degrees":0,"owner_verified":false,
"current_state_eligible":false,"matches":rows]}
func bar(_ pos:String,_ pct:Double,_ deg:Int=0)->[String:Any]{
["position_hint":pos,"rotation_hypothesis_degrees":deg,
"raw_row_origin_hypothesis":"TOP_FIRST","owner":"UNKNOWN",
"hp_percent_certified":false,
"fill_percentage_candidate_not_hp":pct]}
let own=bar("LOWER_LEFT_HUD_POSITION_ONLY",75)
let opp=bar("UPPER_RIGHT_HUD_POSITION_ONLY",80.8)
func frame(_ tracks:[[String:Any]])->[String:Any]{
["schema":R672PixelHPFillReader.schema,
"status":"PARTIAL_BAR_FILL_TRACKS_UNVERIFIED",
"frame_id":Int64(2),"epoch":Int64(1),
"raw_image_sha256":sha,"track_count":tracks.count,
"owner_certified":false,"hp_percent_certified":false,
"tracks":tracks]}
func run(_ o:[String:Any],_ p:[[String:Any]])->[String:Any]{
R675PixelOCRHPAgreement.audit(ocr:o,pixelFrames:p,
rawSHA:sha,frame:2,epoch:1)}
let good=run(ocr(),[frame([own,opp])])
precondition(good["status"] as? String ==
"PIXEL_OCR_RATIO_AGREEMENT_UNCERTIFIED",String(describing:good))
precondition(good["agreement_count"] as? Int==2)
precondition(good["owner_certified"] as? Bool==false)
print("R675_CROSSMODAL_MATCH_PASS")
var wrong=opp;wrong["fill_percentage_candidate_not_hp"]=20.0
let conflict=run(ocr(),[frame([own,wrong])])
precondition(conflict["status"] as? String ==
"HOLD_PIXEL_OCR_HP_CONTRADICTION")
precondition((conflict["conflicts"] as! [[String:Any]]).count==1)
print("R675_PIXEL_OCR_CONTRADICTION_PASS")
var r=ocr();r["frame_id"]=Int64(3)
precondition(run(r,[frame([own])])["status"] as? String ==
"HOLD_OCR_SOURCE_OR_SCHEMA")
r=ocr();r["analysis_image_sha256"]=String(repeating:"b",count:64)
precondition(run(r,[frame([own])])["status"] as? String ==
"HOLD_RAW_ANALYSIS_ROTATION_UNMAPPED")
var f=frame([own]);f["raw_image_sha256"]=String(repeating:"b",count:64)
precondition(run(ocr(),[f])["status"] as? String ==
"HOLD_RGBA_FRAME_NOT_BOUND")
precondition(run(ocr(),[frame([own,own])])["status"] as? String ==
"HOLD_AMBIGUOUS_BAR_TRACK")
precondition(run(ocr(),[frame([])])["status"] as? String ==
"HOLD_NO_COMMON_HP_READINGS")
r=ocr();r["matches"]=[fields[0],fields[0]]
precondition(run(r,[frame([own])])["status"] as? String ==
"HOLD_DUPLICATE_OCR_FIELD")
r=ocr();r["matches"]=[["field":"own.hp",
"value":["current":198,"maximum":197],
"evidence_ref":"ocr_hp","owner_verified":false]]
precondition(run(r,[frame([own])])["status"] as? String ==
"HOLD_INVALID_OWN_HP_FRACTION")
var b=own;b["fill_percentage_candidate_not_hp"]=Double.nan
precondition(run(ocr(),[frame([b])])["status"] as? String ==
"HOLD_MALFORMED_PIXEL_BAR")
var rot=ocr();rot["rotation_candidate_degrees"]=90
var rotated=own;rotated["rotation_hypothesis_degrees"]=90
precondition(run(rot,[frame([rotated])])["agreement_count"] as? Int==1)
// Full raw-frame CCW quarter turn maps analysis->HUD 90 to raw->HUD 0.
rot["analysis_image_sha256"]=String(repeating:"b",count:64)
let projection:[String:Any]=[
"schema":"trueplan.screen-read.analysis-projection.v1",
"status":"DECLARED_GEOMETRY_ONLY","raw_image_sha256":sha,
"analysis_image_sha256":String(repeating:"b",count:64),
"frame_id":Int64(2),"epoch":Int64(1),
"owner_certified":false,"raw_width":800,"raw_height":400,
"pixel_crop":["x":0,"y":0,"width":800,"height":400],
"quarter_turns_ccw":1]
let mapped=R675PixelOCRHPAgreement.audit(ocr:rot,
pixelFrames:[frame([own])],rawSHA:sha,frame:2,epoch:1,
projection:projection)
precondition(mapped["agreement_count"] as? Int==1,
String(describing:mapped))
var cropped=projection
cropped["pixel_crop"]=["x":10,"y":0,"width":790,"height":400]
let rejected=R675PixelOCRHPAgreement.audit(ocr:rot,
pixelFrames:[frame([own])],rawSHA:sha,frame:2,epoch:1,
projection:cropped)
precondition(rejected["status"] as? String ==
"HOLD_RAW_ANALYSIS_ROTATION_UNMAPPED")
print("R675_FRAME_PROVENANCE_AND_ROTATION_PASS 12")
}
}
