import Foundation
import CoreFoundation

/// Independent audit of one-tap source signals. It cannot validate
/// visual truth, ownership, turns, Mega identity or game commands.
enum R665EvidenceTraceAudit {
    static let schema = "trueplan.r665.evidence-trace-audit.v1"
    private static let stages: Set<String> = [
        "CAPTURE_METADATA_ONLY", "UI_CLASSIFICATION_CANDIDATE",
        "HISTORICAL_FOUR_SLOTS_OWNER_UNVERIFIED",
        "HISTORICAL_HP_POSITION_OWNER_UNVERIFIED",
        "OCR_CONFLICTS_NOT_BATTLE_STATE",
        "TEXT_CANDIDATE_OWNER_UNVERIFIED",
        "TEXT_MENTION_NO_TURN_PROOF"
    ]
    private static func hold(_ reason: String) -> [String:Any] {
        return ["schema":schema,"status":reason,"field_count":79,
          "source_trace_verified":false,"game_fields_certified":0,
          "ground_truth_count":0,"owner_certified":false,
          "turn_certified":false,"mega_form_certified":false,
          "current_state_eligible":false,
          "battle_advice_authorized":false,
          "real_game_accuracy":"NOT_MEASURED"]
    }
    private static func integer(_ v:Any?) -> Int? {
        guard let n=v as? NSNumber,
              CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue.isFinite, n.doubleValue >= 0,
              n.doubleValue < 2_000_000_000,
              n.doubleValue == Double(n.intValue) else {return nil}
        return n.intValue
    }
    private static func sha(_ v: Any?) -> String? {
        guard let s=v as? String,s.utf8.count==64,
            s.utf8.allSatisfy({(48...57).contains($0) ||
                                (97...102).contains($0)}) else {return nil}
        return s
    }
    private static func isFalse(_ d:[String:Any],
                                _ keys:[String]) -> Bool {
        keys.allSatisfy{d[$0] as? Bool == false}
    }
    static func audit(_ doc:[String:Any],
                      sourceKind:String) -> [String:Any] {
        guard ["LIVE_RETAINED_FRAME",
               "USER_IMPORTED_PNG_OFFLINE_ONLY"].contains(sourceKind),
              let coverage=doc["r581_full_read_coverage"] as? [String:Any],
              let reader=doc["r646_field_readers"] as? [String:Any],
              let score=doc["r664_readout_scorecard"] as? [String:Any],
              let snap=doc["screen_read_state"] as? [String:Any],
              coverage["schema"] as? String == R581ReadabilityCoverage.schema,
              reader["schema"] as? String ==
                "trueplan.r646.field-signal-readers.v1",
              score["schema"] as? String == R664ReadoutScorecard.schema,
              score["status"] as? String ==
                "HISTORICAL_FIELD_SIGNAL_COUNTS_ONLY",
              coverage["source_kind"] as? String == sourceKind,
              reader["source_kind"] as? String == sourceKind,
              score["source_kind"] as? String == sourceKind,
              score["source_binding_verified"] as? Bool == true,
              coverage["source_binding_valid"] as? Bool == true,
              coverage["snapshot_binding_valid"] as? Bool == true,
              reader["status"] as? String ==
                "79_SOURCE_READER_ATTEMPTS_NOT_GAME_CERTIFIED",
              isFalse(reader,["owner_verified","current_state_eligible",
                    "battle_advice_authorized"]),
              isFalse(score,["owner_certified","turn_certified",
                    "mega_form_certified","current_state_eligible",
                    "battle_advice_authorized"]),
              integer(reader["game_fields_certified"]) == 0,
              integer(score["game_fields_certified"]) == 0,
              score["real_game_accuracy"] as? String == "NOT_MEASURED",
              integer(score["visible_ground_truth_labels"]) == 0,
              let frame=integer(reader["frame_id"]),frame>0,
              let epoch=integer(reader["epoch"]),epoch>0,
              let session=reader["capture_session_id"] as? String,
              !session.isEmpty,session.utf8.count<=160,
              integer(score["frame_id"]) == frame,
              integer(score["epoch"]) == epoch,
              score["capture_session_id"] as? String == session,
              integer(snap["frame_id"]) == frame,
              integer(snap["epoch"]) == epoch,
              snap["capture_session_id"] as? String == session,
              let raw=sha(reader["raw_image_sha256"]),
              raw == sha(coverage["image_sha256"]),
              raw == sha(score["source_image_sha256"]),
              let analysis=sha(reader["analysis_image_sha256"]),
              analysis == sha(coverage["analysis_image_sha256"]),
              analysis == sha(score["analysis_image_sha256"]),
              analysis == sha(snap["image_sha256"]),
              let inventory=snap["ocr_source_inventory"] as? [[String:Any]],
              inventory.count<=288,
              let fields=reader["field_read_attempts"] as? [[String:Any]],
              let coverageFields=coverage["fields"] as? [[String:Any]],
              let claimed=score["candidate_fields"] as? [String],
              fields.count==79,coverageFields.count==79,
              integer(score["field_count"])==79,
              integer(reader["field_count"])==79,
              integer(coverage["field_count"])==79
        else {return hold("HOLD_SOURCE_PROVENANCE_OR_SCHEMA")}
        var inventoryByRef=[String:[String:Any]]()
        for token in inventory {
            guard let ref=token["evidence_ref"] as? String,
                  !ref.isEmpty,ref.utf8.count<=160,
                  inventoryByRef[ref]==nil,
                  let text=token["raw_text"] as? String,
                  !text.isEmpty,text.utf8.count<=160,
                  token["image_sha256"] as? String==analysis,
                  token["capture_session_id"] as? String==session,
                  integer(token["frame_id"])==frame,
                  integer(token["epoch"])==epoch,
                  token["owner_verified"] as? Bool == false,
                  token["roi"] as? [String:Any] != nil else {
                return hold("HOLD_OCR_INVENTORY_CONTRADICTION")
            }
            inventoryByRef[ref]=token
        }
        let canonical=R581ReadabilityCoverage.tracks.map{$0.0}
        guard canonical.count==79,Set(canonical).count==79 else {
            return hold("HOLD_CANONICAL_FIELD_LIST")
        }
        var entries=[[String:Any]]()
        var observed=[String](),metadata=0,screen=0,layout=0,text=0
        var battleSignal=0,unknown=0,ocrRefs=0
        for idx in 0..<79 {
            let field=canonical[idx]
            let row=fields[idx],base=coverageFields[idx]
            guard row["field"] as? String == field,
                  base["field"] as? String == field,
                  isFalse(row,["owner_verified","turn_verified",
                      "game_value_certified","current_state_eligible"]),
                  isFalse(base,["owner_verified","time_verified",
                      "current_value_admitted"]),
                  let stage=row["attempt_status"] as? String,
                  let evidence=row["ocr_evidence"] as? [[String:Any]],
                  evidence.count<=8,
                  let coverageStatus=base["status"] as? String,
                  ["UNKNOWN","OCR_TEXT_CANDIDATE_ONLY"]
                      .contains(coverageStatus) else {
                return hold("HOLD_FIELD_ORDER_OR_PROOF_BOUNDARY")
            }
            var refs=[String]()
            var seen=Set<String>()
            for e in evidence {
                guard e["side"] as? String == "UNKNOWN_OWNER",
                      e["current_value_admitted"] as? Bool == false,
                      let ref=e["evidence_ref"] as? String,
                      !ref.isEmpty,seen.insert(ref).inserted,
                      let literal=e["text"] as? String,
                      let source=inventoryByRef[ref],
                      source["raw_text"] as? String == literal,
                      let sourceRect=source["roi"] as? [String:Any],
                      let rect=e["analysis_roi"] as? [String:Any],
                      ["x","y","width","height"].allSatisfy({
                        integer(sourceRect[$0]) == integer(rect[$0]) &&
                        integer(rect[$0]) != nil
                      }) else {
                    return hold("HOLD_OCR_EVIDENCE_NOT_REPRODUCIBLE")
                }
                refs.append(ref)
            }
            let hasSignal=stages.contains(stage) || !evidence.isEmpty
            if hasSignal {observed.append(field)} else {unknown+=1}
            let category:String
            if stage=="CAPTURE_METADATA_ONLY" {
                guard field.hasPrefix("capture.") else {
                    return hold("HOLD_METADATA_AS_GAME_VALUE")
                }
                metadata+=1;category="CAPTURE_METADATA"
            } else if stage=="UI_CLASSIFICATION_CANDIDATE" {
                guard field.hasPrefix("screen.") else {
                    return hold("HOLD_UI_AS_GAME_VALUE")
                }
                screen+=1;category="SCREEN_UI_CANDIDATE"
            } else if stage.hasPrefix("HISTORICAL_") ||
                      stage=="ORIENTATION_LAYOUT_CANDIDATE" {
                layout+=1;category="HISTORICAL_LAYOUT_CANDIDATE"
            } else if !evidence.isEmpty {
                text+=1;category="OCR_TEXT_CANDIDATE"
            } else if hasSignal {
                category="OTHER_UNVERIFIED_SIGNAL"
            } else {category="NO_SOURCE_SIGNAL"}
            if hasSignal && !field.hasPrefix("capture.") &&
               !field.hasPrefix("screen.") &&
               field != "battle.conflict_and_staleness" {
                battleSignal+=1
            }
            ocrRefs+=refs.count
            entries.append(["field":field,"source_signal_kind":category,
                "attempt_status":stage,"source_signal_present":hasSignal,
                "evidence_refs":refs,"evidence_count":refs.count,
                "owner_verified":false,"turn_verified":false,
                "game_value_certified":false,
                "current_state_eligible":false])
        }
        guard claimed==observed,
              integer(score["fields_with_source_signal"])==observed.count,
              integer(score["fields_without_source_signal"])==unknown,
              integer(reader["fields_with_source_signal"])==observed.count,
              integer(score["capture_metadata_signal_count"])==metadata,
              integer(score["screen_classifier_signal_count"])==screen,
              integer(score["historical_layout_signal_count"])==layout,
              integer(score["other_text_signal_count"])==text,
              let frac=score["source_signal_fraction_not_accuracy"]
                  as? Double,
              abs(frac-Double(observed.count)/79)<1e-10 else {
            return hold("HOLD_SCORECARD_CONTRADICTION")
        }
        return ["schema":schema,
            "status":"HISTORICAL_EVIDENCE_TRACE_REPRODUCED_ONLY",
            "source_trace_verified":true,"source_kind":sourceKind,
            "frame_id":frame,"epoch":epoch,"capture_session_id":session,
            "source_image_sha256":raw,"analysis_image_sha256":analysis,
            "field_count":79,"field_diagnostics":entries,
            "source_signal_count":observed.count,
            "battle_candidate_signal_count_not_accuracy":battleSignal,
            "unresolved_field_count":unknown,
            "ocr_evidence_references":ocrRefs,
            "capture_metadata_count":metadata,"screen_ui_count":screen,
            "historical_layout_count":layout,"ocr_text_count":text,
            "game_fields_certified":0,"ground_truth_count":0,
            "real_game_accuracy":"NOT_MEASURED",
            "owner_certified":false,"turn_certified":false,
            "mega_form_certified":false,"current_state_eligible":false,
            "battle_advice_authorized":false,
            "limitations":"Proves only same-frame provenance, scorecard counts " +
              "and source-reference integrity. Source signals may be wrong " +
              "or unrelated to Pokemon; no game truth or owner proof."]
    }
    static func enrich(_ doc:inout [String:Any],sourceKind:String) {
        doc.removeValue(forKey:"r665_evidence_trace_audit")
        doc["r665_evidence_trace_audit"]=audit(doc,sourceKind:sourceKind)
    }
}
