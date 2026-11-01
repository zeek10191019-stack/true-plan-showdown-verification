import Foundation
@main struct R640FieldGapHarness {
static func main() {
var t=0
func ok(_ v:Bool){precondition(v,"R640_CASE_\(t)");t+=1}
let sha=String(repeating:"a",count:64)
let names=R581ReadabilityCoverage.tracks.map{$0.0}
ok(names.count==79 && Set(names).count==79)
var rows=names.map{["field":$0,"candidate_refs":[] as [String],
"candidate_count":0,"owner_verified":false,"time_verified":false,
"current_value_admitted":false,
"reader_producing_verified_game_value":false] as [String:Any]}
rows[5]["observed_metadata_value"]=32
rows[21]["candidate_count"]=1
rows[21]["candidate_refs"]=["ref"]
rows[21]["bounded_ocr_evidence"]=[[
"actor":"UNKNOWN","verification":"UNVERIFIED"]]
rows[27]["r635_structured_layout_candidates"]=[[
"owner_verified":false,"current_value_admitted":false]]
rows[28]["r636_typed_candidates"]=[[
"owner_verified":false,"current_value_admitted":false]]
let c:[String:Any]=["schema":R581ReadabilityCoverage.schema,
"source_kind":"LIVE_RETAINED_FRAME","field_count":79,
"image_sha256":sha,"analysis_image_sha256":sha,
"snapshot_binding_valid":true,"source_binding_valid":true,
"r634_schema":"trueplan.r634.field-reader-routing.v1",
"r635_schema":"trueplan.r635.structured-layout-field-evidence.v1",
"r636_schema":"trueplan.r636.typed-hud-hypotheses.v1",
"owner_certified":false,"turn_certified":false,
"live_capture_certified":false,"actual_game_accuracy_certified":false,
"current_state_eligible":false,"battle_advice_authorized":false,
"fields":rows]
let orientation:[String:Any]=[
"schema":"trueplan.r639.orientation-anchor-probe.v1",
"image_sha256":sha,"status":"UNIQUE_ROTATION_HYPOTHESIS_NOT_CERTIFIED",
"orientation_verified":false,"owner_verified":false,
"battle_advice_authorized":false]
let base:[String:Any]=["png_sha256":sha,"r581_full_read_coverage":c,
"screen_read_state":["image_sha256":sha,"current_state_eligible":false,
"battle_advice_authorized":false],"r639_orientation_probe":orientation]
func run(_ doc:[String:Any])->[String:Any]{var d=doc
R640FieldGapAudit.enrich(&d,sourceKind:"LIVE_RETAINED_FRAME");return d}
func cov(_ changes:(inout [String:Any])->Void)->[String:Any]{
var d=base;var v=c;changes(&v);d["r581_full_read_coverage"]=v
return run(d)}
func re(_ changes:(inout [[String:Any]])->Void)->[String:Any]{
cov{v in var r=rows;changes(&r);v["fields"]=r}}
let good=run(base);let report=good["r640_field_gap_report"] as! [String:Any]
let counts=report["evidence_stage_counts"] as! [String:Int]
ok(good["r640_status"] as? String == "HISTORICAL_79_FIELD_GAP_REPORT_NOT_CERTIFIED")
ok((report["field_diagnostics"] as? [[String:Any]])?.count==79)
ok(counts.values.reduce(0,+)==79)
ok(counts["CAPTURE_RECEIPT_ONLY"]==1)
ok(counts["OCR_TEXT_CANDIDATE"]==1)
ok(counts["LAYOUT_HYPOTHESIS"]==1)
ok(counts["TYPED_HYPOTHESIS"]==1)
ok(counts["NO_FIELD_EVIDENCE"]==75)
ok(report["game_fields_certified"] as? Int==0)
ok(report["owner_verified"] as? Bool==false)
ok(report["battle_advice_authorized"] as? Bool==false)
ok(report["bound_analysis_snapshot_present"] as? Bool==true)
ok(report["orientation_hypothesis_status"] as? String ==
"UNIQUE_ROTATION_HYPOTHESIS_NOT_CERTIFIED")
ok(JSONSerialization.isValidJSONObject(good))
ok(re{$0[1]=$0[0]}["r640_field_gap_report"] == nil)
ok(cov{$0["actual_game_accuracy_certified"]=true}["r640_field_gap_report"] == nil)
ok(re{$0[21]["owner_verified"]=true}["r640_status"] as? String == "HOLD_TAMPERED_FIELD_EVIDENCE")
ok((re{$0[28]["r636_typed_candidates"]=[[
"owner_verified":true,"current_value_admitted":false]]})["r640_status"] as? String == "HOLD_TAMPERED_FIELD_EVIDENCE")
var d=base;d["png_sha256"]=String(repeating:"b",count:64)
ok(run(d)["r640_field_gap_report"] == nil)
ok((cov{_ = $0.removeValue(forKey:"r636_schema")})["r640_field_gap_report"] != nil)
ok((cov{_ = $0.removeValue(forKey:"r634_schema")})["r640_field_gap_report"] != nil)
print("R640_HARNESS_ALL_PASS",t)
}
}
