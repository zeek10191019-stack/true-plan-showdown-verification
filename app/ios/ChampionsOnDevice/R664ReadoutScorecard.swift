import Foundation

/// One-tap diagnostic of source signals, NOT real-game reading accuracy.
/// In particular, metadata is not treated as an observed battle value.
enum R664ReadoutScorecard {
    static let schema = "trueplan.r664.readout-scorecard.v1"
    private static let signalStages:Set<String> = [
        "CAPTURE_METADATA_ONLY", "UI_CLASSIFICATION_CANDIDATE",
        "HISTORICAL_FOUR_SLOTS_OWNER_UNVERIFIED",
        "HISTORICAL_HP_POSITION_OWNER_UNVERIFIED",
        "OCR_CONFLICTS_NOT_BATTLE_STATE",
        "TEXT_CANDIDATE_OWNER_UNVERIFIED",
        "TEXT_MENTION_NO_TURN_PROOF"
    ]
    private static func hold(_ reason:String)->[String:Any] {
        ["schema":schema,"status":reason,
         "source_binding_verified":false,"field_count":79,
         "game_fields_certified":0,"real_game_accuracy":"NOT_MEASURED",
         "owner_certified":false,"turn_certified":false,
         "mega_form_certified":false,"battle_advice_authorized":false,
         "current_state_eligible":false]
    }
    private static func sha(_ s:String)->Bool {
        s.utf8.count == 64 && s.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
    private static func noProof(_ row:[String:Any],
                                _ names:[String])->Bool {
        names.allSatisfy {row[$0] as? Bool == false}
    }
    static func audit(coverage:[String:Any],
                      reader:[String:Any],
                      sourceKind:String)->[String:Any] {
        let canonical=R581ReadabilityCoverage.tracks.map{$0.0}
        guard canonical.count==79,Set(canonical).count==79,
              ["LIVE_RETAINED_FRAME", "USER_IMPORTED_PNG_OFFLINE_ONLY"]
                .contains(sourceKind),
              coverage["schema"] as? String == R581ReadabilityCoverage.schema,
              reader["schema"] as? String ==
                "trueplan.r646.field-signal-readers.v1",
              coverage["source_kind"] as? String == sourceKind,
              reader["source_kind"] as? String == sourceKind,
              coverage["source_binding_valid"] as? Bool == true,
              coverage["snapshot_binding_valid"] as? Bool == true,
              noProof(coverage,["owner_certified","turn_certified",
                                 "mega_visual_form_certified",
                                 "battle_advice_authorized",
                                 "current_state_eligible",
                                 "actual_game_accuracy_certified"]),
              noProof(reader,["owner_verified",
                               "battle_advice_authorized",
                               "current_state_eligible"]),
              reader["status"] as? String ==
                "79_SOURCE_READER_ATTEMPTS_NOT_GAME_CERTIFIED",
              reader["field_count"] as? Int == 79,
              reader["game_fields_certified"] as? Int == 0,
              let frame=reader["frame_id"] as? Int,frame>0,
              let epoch=reader["epoch"] as? Int,epoch>0,
              let session=reader["capture_session_id"] as? String,
              !session.isEmpty,session.utf8.count<=160,
              let source=reader["raw_image_sha256"] as? String,
              let original=coverage["image_sha256"] as? String,
              sha(source),source==original,
              let analysis=reader["analysis_image_sha256"] as? String,
              let a=coverage["analysis_image_sha256"] as? String,
              sha(analysis),analysis==a,
              let rows=reader["field_read_attempts"] as? [[String:Any]],
              let fields=coverage["fields"] as? [[String:Any]],
              rows.count==79,fields.count==79 else {
            return hold("HOLD_INCONSISTENT_UPSTREAM_COVERAGE")
        }
        var groups=[String:Int]()
        var hinted=[String]()
        var metadata=0,ui=0,layout=0,text=0,unresolved=0
        for (index,field) in canonical.enumerated() {
            let row=rows[index], base=fields[index]
            guard row["field"] as? String == field,
                  base["field"] as? String == field,
                  row["owner_verified"] as? Bool == false,
                  row["turn_verified"] as? Bool == false,
                  row["game_value_certified"] as? Bool == false,
                  row["current_state_eligible"] as? Bool == false,
                  base["owner_verified"] as? Bool == false,
                  base["time_verified"] as? Bool == false,
                  base["current_value_admitted"] as? Bool == false,
                  let stage=row["attempt_status"] as? String,
                  let evidence=row["ocr_evidence"] as? [[String:Any]],
                  evidence.count <= 8,
                  signalStages.contains(stage) || evidence.isEmpty,
                  evidence.allSatisfy({$0["side"] as? String ==
                      "UNKNOWN_OWNER" &&
                      $0["current_value_admitted"] as? Bool == false}),
                  let status=base["status"] as? String,
                  ["UNKNOWN","OCR_TEXT_CANDIDATE_ONLY"].contains(status)
                  else {return hold("HOLD_FIELD_ORDER_OR_PROOF_BOUNDARY")}
            let hasSignal = signalStages.contains(stage) || !evidence.isEmpty
            if hasSignal {hinted.append(field)} else {unresolved+=1}
            if stage=="CAPTURE_METADATA_ONLY" {metadata+=1}
            else if stage=="UI_CLASSIFICATION_CANDIDATE" {ui+=1}
            else if stage.hasPrefix("HISTORICAL_") ||
                    stage=="ORIENTATION_LAYOUT_CANDIDATE" {layout+=1}
            else if !evidence.isEmpty {text+=1}
            groups[stage,default:0]+=1
        }
        guard hinted.count + unresolved == 79,
              reader["fields_with_source_signal"] as? Int == hinted.count,
              coverage["field_count"] as? Int == 79,
              coverage["candidate_field_count"] as? Int != nil,
              coverage["unknown_field_count"] as? Int != nil else {
            return hold("HOLD_SIGNAL_COUNT_CONTRADICTION")
        }
        return ["schema":schema,
                "status":"HISTORICAL_FIELD_SIGNAL_COUNTS_ONLY",
                "source_kind":sourceKind,
                "source_image_sha256":source,
                "analysis_image_sha256":analysis,
                "capture_session_id":session,
                "frame_id":frame,"epoch":epoch,
                "source_binding_verified":true,
                "field_count":79,
                "fields_with_source_signal":hinted.count,
                "fields_without_source_signal":unresolved,
                "source_signal_fraction_not_accuracy":
                    Double(hinted.count)/79.0,
                "capture_metadata_signal_count":metadata,
                "screen_classifier_signal_count":ui,
                "historical_layout_signal_count":layout,
                "other_text_signal_count":text,
                "candidate_fields":hinted,
                "attempt_status_counts":groups,
                "game_fields_certified":0,
                "visible_ground_truth_labels":0,
                "real_game_accuracy":"NOT_MEASURED",
                "owner_certified":false,
                "turn_certified":false,
                "mega_form_certified":false,
                "battle_advice_authorized":false,
                "current_state_eligible":false,
                "limitations":"Counts available source signals, including " +
                    "capture metadata; not items displayed on screen, " +
                    "truth labels, correctness, owner or battle readiness."]
    }
    static func enrich(_ doc:inout [String:Any],sourceKind:String) {
        doc.removeValue(forKey:"r664_readout_scorecard")
        let cov=doc["r581_full_read_coverage"] as? [String:Any] ?? [:]
        let reader=doc["r646_field_readers"] as? [String:Any] ?? [:]
        doc["r664_readout_scorecard"]=audit(
            coverage:cov,reader:reader,sourceKind:sourceKind)
    }
}
