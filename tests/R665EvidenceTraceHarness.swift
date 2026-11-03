import Foundation
@main struct R665EvidenceTraceHarness {
    static func main() {
        var n=0
        func test(_ yes:Bool,_ name:String) {
            precondition(yes,"R665_"+name);n+=1
        }
        let hash=String(repeating:"a",count:64)
        let fields=R581ReadabilityCoverage.tracks.map{$0.0}
        test(fields.count==79,"canonical")
        let rows=fields.map{field in
            ["field":field,"attempt_status":"NO_MATCH_IN_AVAILABLE_OCR",
             "ocr_evidence":[] as [[String:Any]],
             "owner_verified":false,"turn_verified":false,
             "game_value_certified":false,"current_state_eligible":false]
             as [String:Any]
        }
        let cvRows=fields.map{field in
            ["field":field,"status":"UNKNOWN","owner_verified":false,
             "time_verified":false,"current_value_admitted":false]
             as [String:Any]
        }
        let coverage:[String:Any]=[
            "schema":R581ReadabilityCoverage.schema,
            "source_kind":"LIVE_RETAINED_FRAME",
            "source_binding_valid":true,"snapshot_binding_valid":true,
            "image_sha256":hash,"analysis_image_sha256":hash,
            "field_count":79,"fields":cvRows,
            "owner_certified":false,"turn_certified":false,
            "mega_visual_form_certified":false,
            "battle_advice_authorized":false,
            "current_state_eligible":false,
            "actual_game_accuracy_certified":false,
            "candidate_field_count":0,"unknown_field_count":79
        ]
        var reader:[String:Any]=[
            "schema":"trueplan.r646.field-signal-readers.v1",
            "source_kind":"LIVE_RETAINED_FRAME",
            "status":"79_SOURCE_READER_ATTEMPTS_NOT_GAME_CERTIFIED",
            "raw_image_sha256":hash,"analysis_image_sha256":hash,
            "frame_id":10,"epoch":2,"capture_session_id":"test",
            "owner_verified":false,"current_state_eligible":false,
            "battle_advice_authorized":false,"game_fields_certified":0,
            "fields_with_source_signal":0,"field_count":79,
            "field_read_attempts":rows
        ]
        var snap:[String:Any]=[
            "image_sha256":hash,"frame_id":10,"epoch":2,
            "capture_session_id":"test",
            "ocr_source_inventory":[] as [[String:Any]]
        ]
        func make()->[String:Any] {
            let sc=R664ReadoutScorecard.audit(coverage:coverage,
                reader:reader,sourceKind:"LIVE_RETAINED_FRAME")
            return ["r581_full_read_coverage":coverage,
                    "r646_field_readers":reader,
                    "r664_readout_scorecard":sc,
                    "screen_read_state":snap]
        }
        func status(_ d:[String:Any])->String {
            R665EvidenceTraceAudit.audit(d,
                sourceKind:"LIVE_RETAINED_FRAME")["status"] as? String ?? ""
        }
        let pass="HISTORICAL_EVIDENCE_TRACE_REPRODUCED_ONLY"
        var d=make()
        test(status(d)==pass,"zero_success")
        var out=R665EvidenceTraceAudit.audit(d,
            sourceKind:"LIVE_RETAINED_FRAME")
        test(out["source_signal_count"] as? Int==0,"no_signal")
        test(out["field_count"] as? Int==79,"79_present")
        test((out["field_diagnostics"] as? [[String:Any]])?.count==79,"79_diagnostics")
        test(out["game_fields_certified"] as? Int==0,"no_game_values")
        test(out["battle_advice_authorized"] as? Bool==false,"no_advice")
        test(out["real_game_accuracy"] as? String=="NOT_MEASURED","not_accuracy")
        // Respect the canonical domain of each signal. A metadata
        // signal on a screen field is intentionally rejected.
        let uiIndex=fields.firstIndex(of:"screen.ui_state")!
        let captureIndex=fields.firstIndex(of:"capture.frame_id")!
        let hpIndex=fields.firstIndex(of:"own.hp")!
        var updated=rows
        updated[uiIndex]["attempt_status"]="UI_CLASSIFICATION_CANDIDATE"
        updated[captureIndex]["attempt_status"]="CAPTURE_METADATA_ONLY"
        updated[hpIndex]["attempt_status"]="HISTORICAL_HP_POSITION_OWNER_UNVERIFIED"
        reader["field_read_attempts"]=updated
        reader["fields_with_source_signal"]=3
        d=make()
        test(status(d)==pass,"signal_success")
        out=R665EvidenceTraceAudit.audit(d,
            sourceKind:"LIVE_RETAINED_FRAME")
        test(out["source_signal_count"] as? Int==3,"3_signals")
        test(out["battle_candidate_signal_count_not_accuracy"] as? Int==1,"one_battle_candidate")
        test(out["capture_metadata_count"] as? Int==1,"one_metadata")
        test(out["screen_ui_count"] as? Int==1,"one_ui")
        test(out["historical_layout_count"] as? Int==1,"one_layout")
        // Regression: a capture-only signal must never be accepted
        // on a screen UI field, even when R664 counts the token.
        var falseReader=reader
        var falseRows=updated
        falseRows[uiIndex]["attempt_status"]="CAPTURE_METADATA_ONLY"
        falseRows[captureIndex]["attempt_status"]="UI_CLASSIFICATION_CANDIDATE"
        falseReader["field_read_attempts"]=falseRows
        var falseDoc=d
        falseDoc["r646_field_readers"]=falseReader
        falseDoc["r664_readout_scorecard"]=R664ReadoutScorecard.audit(
            coverage:coverage,reader:falseReader,
            sourceKind:"LIVE_RETAINED_FRAME")
        test(status(falseDoc)=="HOLD_METADATA_AS_GAME_VALUE",
             "metadata_not_screen_game_field")
        var tamper=d
        var score=tamper["r664_readout_scorecard"] as! [String:Any]
        score["candidate_fields"]=[fields[hpIndex],fields[uiIndex],fields[captureIndex]]
        tamper["r664_readout_scorecard"]=score
        test(status(tamper)=="HOLD_SCORECARD_CONTRADICTION","candidate_order")
        score=d["r664_readout_scorecard"] as! [String:Any]
        score["fields_with_source_signal"]=5
        tamper["r664_readout_scorecard"]=score
        test(status(tamper)=="HOLD_SCORECARD_CONTRADICTION","score_count")
        score=d["r664_readout_scorecard"] as! [String:Any]
        score["source_image_sha256"]=String(repeating:"b",count:64)
        tamper["r664_readout_scorecard"]=score
        test(status(tamper).hasPrefix("HOLD_"),"tampered_hash")
        tamper=d;tamper["screen_read_state"]=[String:Any]()
        test(status(tamper).hasPrefix("HOLD_"),"missing_snapshot")
        tamper=d;var r=reader;r["owner_verified"]=true
        tamper["r646_field_readers"]=r
        test(status(tamper).hasPrefix("HOLD_"),"claimed_owner")
        tamper=d;r=reader;r["game_fields_certified"]=1
        tamper["r646_field_readers"]=r
        test(status(tamper).hasPrefix("HOLD_"),"claimed_certified")
        tamper=d;r=reader;r["frame_id"]=11
        tamper["r646_field_readers"]=r
        test(status(tamper).hasPrefix("HOLD_"),"frame_mismatch")
        tamper=d;r=reader;r["capture_session_id"]="other"
        tamper["r646_field_readers"]=r
        test(status(tamper).hasPrefix("HOLD_"),"session_mismatch")
        tamper=d;r=reader;var rr=updated;rr[1]["field"]="wrong"
        r["field_read_attempts"]=rr;tamper["r646_field_readers"]=r
        test(status(tamper).hasPrefix("HOLD_"),"field_mismatch")
        tamper=d;r=reader;rr=updated
        rr[hpIndex]["game_value_certified"]=true
        r["field_read_attempts"]=rr;tamper["r646_field_readers"]=r
        test(status(tamper).hasPrefix("HOLD_"),"bad_proof")
        tamper=d;score=d["r664_readout_scorecard"] as! [String:Any]
        score["real_game_accuracy"]="1.0"
        tamper["r664_readout_scorecard"]=score
        test(status(tamper).hasPrefix("HOLD_"),"faked_accuracy")
        let ref="ocr:frame10:1"
        let roi:[String:Int]=["x":11,"y":8,"width":70,"height":30]
        let token:[String:Any]=[
          "evidence_ref":ref,"raw_text":"90/100",
          "image_sha256":hash,"capture_session_id":"test",
          "frame_id":10,"epoch":2,"owner_verified":false,"roi":roi]
        snap["ocr_source_inventory"]=[token]
        rr=updated
        rr[hpIndex]["ocr_evidence"] = [["evidence_ref":ref,"text":"90/100",
            "side":"UNKNOWN_OWNER","current_value_admitted":false,
            "analysis_roi":roi]] as [[String:Any]]
        r=reader;r["field_read_attempts"]=rr
        reader=r
        d=make()
        test(status(d)==pass,"ocr_provenance")
        out=R665EvidenceTraceAudit.audit(d,
            sourceKind:"LIVE_RETAINED_FRAME")
        test(out["ocr_evidence_references"] as? Int==1,"one_ocr_ref")
        tamper=d;r=reader;rr=r["field_read_attempts"] as! [[String:Any]]
        rr[hpIndex]["ocr_evidence"] = [["evidence_ref":ref,"text":"WRONG",
            "side":"UNKNOWN_OWNER","current_value_admitted":false,
            "analysis_roi":roi]] as [[String:Any]]
        r["field_read_attempts"]=rr;tamper["r646_field_readers"]=r
        test(status(tamper).hasPrefix("HOLD_"),"forged_ocr_text")
        tamper=d;r=reader;rr=r["field_read_attempts"] as! [[String:Any]]
        rr[hpIndex]["ocr_evidence"] = [["evidence_ref":ref,"text":"90/100",
            "side":"UNKNOWN_OWNER","current_value_admitted":false,
            "analysis_roi":["x":12,"y":8,"width":70,"height":30]]] as [[String:Any]]
        r["field_read_attempts"]=rr;tamper["r646_field_readers"]=r
        test(status(tamper).hasPrefix("HOLD_"),"forged_ocr_roi")
        tamper=d;var ss=snap;ss["ocr_source_inventory"]=[token,token]
        tamper["screen_read_state"]=ss
        test(status(tamper).hasPrefix("HOLD_"),"dup_source_ref")
        tamper=d;ss=snap;var badToken=token;badToken["image_sha256"]=String(repeating:"b",count:64)
        ss["ocr_source_inventory"]=[badToken];tamper["screen_read_state"]=ss
        test(status(tamper).hasPrefix("HOLD_"),"stale_ocr_hash")
        tamper=d;var cc=coverage;cc["snapshot_binding_valid"]=false
        tamper["r581_full_read_coverage"]=cc
        test(status(tamper).hasPrefix("HOLD_"),"source_not_bound")
        tamper=d;ss=snap;ss["epoch"]=5
        tamper["screen_read_state"]=ss
        test(status(tamper).hasPrefix("HOLD_"),"epoch_mismatch")
        var doc=d;R665EvidenceTraceAudit.enrich(&doc,
            sourceKind:"LIVE_RETAINED_FRAME")
        let saved=doc["r665_evidence_trace_audit"] as? [String:Any]
        test(saved?["status"] as? String == pass,"enrich")
        let wrongSource=R665EvidenceTraceAudit.audit(d,
            sourceKind:"USER_IMPORTED_PNG_OFFLINE_ONLY")
        test(wrongSource["status"] as? String != pass,"wrong_source_kind")
        test((R665EvidenceTraceAudit.audit(d,
            sourceKind:"LIVE_RETAINED_FRAME")["ground_truth_count"]
            as? Int)==0,"truth_count_zero")
        print("R665_EVIDENCE_TRACE_TESTS_PASS",n)
    }
}
