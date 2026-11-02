import Foundation
@main struct R664ReadoutScorecardHarness {
    static func main() {
        var n=0
        func chk(_ pass:Bool,_ label:String) {
            precondition(pass,"R664_FAIL_"+label);n+=1
        }
        let source=String(repeating:"a",count:64)
        let fields=R581ReadabilityCoverage.tracks.map{$0.0}
        chk(fields.count==79,"79_fields")
        var cov:[String:Any]=[
            "schema":R581ReadabilityCoverage.schema,
            "source_kind":"LIVE_RETAINED_FRAME",
            "source_binding_valid":true,"snapshot_binding_valid":true,
            "owner_certified":false,"turn_certified":false,
            "mega_visual_form_certified":false,
            "battle_advice_authorized":false,
            "current_state_eligible":false,
            "actual_game_accuracy_certified":false,
            "image_sha256":source,
            "analysis_image_sha256":source,
            "field_count":79,"candidate_field_count":0,
            "unknown_field_count":79,
            "fields":fields.map{["field":$0,"status":"UNKNOWN",
                "owner_verified":false,"time_verified":false,
                "current_value_admitted":false] as [String:Any]}
        ]
        func row(_ field:String,_ stage:String) -> [String:Any] {
            ["field":field,"attempt_status":stage,
             "ocr_evidence":[] as [[String:Any]],
             "owner_verified":false,"turn_verified":false,
             "game_value_certified":false,"current_state_eligible":false]
        }
        let normal=fields.map{row($0,"NO_MATCH_IN_AVAILABLE_OCR")}
        var reader:[String:Any]=[
            "schema":"trueplan.r646.field-signal-readers.v1",
            "source_kind":"LIVE_RETAINED_FRAME",
            "status":"79_SOURCE_READER_ATTEMPTS_NOT_GAME_CERTIFIED",
            "raw_image_sha256":source,
            "analysis_image_sha256":source,
            "frame_id":23,"epoch":2,"capture_session_id":"test-session",
            "field_count":79,"game_fields_certified":0,
            "owner_verified":false,"battle_advice_authorized":false,
            "current_state_eligible":false,
            "fields_with_source_signal":0,
            "field_read_attempts":normal
        ]
        func status(_ c:[String:Any],_ r:[String:Any],
                    _ kind:String="LIVE_RETAINED_FRAME")->String {
            R664ReadoutScorecard.audit(coverage:c,reader:r,
                                      sourceKind:kind)["status"] as? String ?? ""
        }
        let pass="HISTORICAL_FIELD_SIGNAL_COUNTS_ONLY"
        chk(status(cov,reader)==pass,"empty_valid")
        var result=R664ReadoutScorecard.audit(coverage:cov,
                      reader:reader,sourceKind:"LIVE_RETAINED_FRAME")
        chk(result["fields_with_source_signal"] as? Int == 0,"none")
        chk(result["fields_without_source_signal"] as? Int == 79,"79_unknown")
        chk(result["real_game_accuracy"] as? String == "NOT_MEASURED","no_accuracy")
        chk(result["game_fields_certified"] as? Int == 0,"no_certification")
        chk(result["battle_advice_authorized"] as? Bool == false,"no_advice")
        var rows=normal
        rows[0]=row(fields[0],"UI_CLASSIFICATION_CANDIDATE")
        rows[3]=row(fields[3],"CAPTURE_METADATA_ONLY")
        rows[21]=row(fields[21],"HISTORICAL_HP_POSITION_OWNER_UNVERIFIED")
        reader["field_read_attempts"]=rows
        reader["fields_with_source_signal"]=3
        result=R664ReadoutScorecard.audit(coverage:cov,reader:reader,
                                         sourceKind:"LIVE_RETAINED_FRAME")
        chk(result["status"] as? String == pass,"nonzero")
        chk(result["fields_with_source_signal"] as? Int == 3,"three")
        chk(result["capture_metadata_signal_count"] as? Int == 1,"metadata")
        chk(result["screen_classifier_signal_count"] as? Int == 1,"screen")
        chk(result["historical_layout_signal_count"] as? Int == 1,"layout")
        chk(result["source_signal_fraction_not_accuracy"] as? Double == 3.0/79,"fraction")
        chk((result["candidate_fields"] as? [String]) == [fields[0],fields[3],fields[21]],"order")
        var doc:[String:Any] = ["r581_full_read_coverage":cov,
                                "r646_field_readers":reader]
        R664ReadoutScorecard.enrich(&doc,sourceKind:"LIVE_RETAINED_FRAME")
        chk((doc["r664_readout_scorecard"] as? [String:Any])?["status"] as? String == pass,"enrich")
        chk(status(cov,reader, "USER_IMPORTED_PNG_OFFLINE_ONLY").hasPrefix("HOLD_"),"source_kind")
        var bad=reader;bad["field_read_attempts"] = Array(rows.dropFirst())
        chk(status(cov,bad).hasPrefix("HOLD_"),"missing")
        bad=reader;bad["fields_with_source_signal"]=4
        chk(status(cov,bad)=="HOLD_SIGNAL_COUNT_CONTRADICTION","count_mismatch")
        bad=reader;bad["raw_image_sha256"]=String(repeating:"b",count:64)
        chk(status(cov,bad).hasPrefix("HOLD_"),"sha_mismatch")
        bad=reader;bad["game_fields_certified"]=1
        chk(status(cov,bad).hasPrefix("HOLD_"),"fake_certification")
        bad=reader;bad["owner_verified"]=true
        chk(status(cov,bad).hasPrefix("HOLD_"),"fake_owner")
        bad=reader;rows[3]["field"]="WRONG";bad["field_read_attempts"]=rows
        chk(status(cov,bad).hasPrefix("HOLD_"),"field_wrong")
        rows[3]=row(fields[3],"CAPTURE_METADATA_ONLY")
        bad=reader;rows[5]["ocr_evidence"] = [["side":"own","current_value_admitted":false]]
        bad["field_read_attempts"]=rows
        chk(status(cov,bad).hasPrefix("HOLD_"),"owner_signal_rejected")
        rows[5]=row(fields[5],"NO_MATCH_IN_AVAILABLE_OCR")
        cov["actual_game_accuracy_certified"]=true
        chk(status(cov,reader).hasPrefix("HOLD_"),"fake_accuracy")
        cov["actual_game_accuracy_certified"]=false
        cov["field_count"]=78
        chk(status(cov,reader).hasPrefix("HOLD_"),"field_count")
        cov["field_count"]=79
        bad=reader;bad["frame_id"]=0
        chk(status(cov,bad).hasPrefix("HOLD_"),"bad_frame")
        bad=reader;bad["capture_session_id"]=""
        chk(status(cov,bad).hasPrefix("HOLD_"),"bad_session")
        bad=reader;bad["epoch"] = 0
        chk(status(cov,bad).hasPrefix("HOLD_"),"bad_epoch")
        print("R664_READOUT_SCORECARD_TESTS_PASS",n)
    }
}
