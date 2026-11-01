import Foundation

/// Consumes source-bound R553 layout and R557 UI evidence from the same frame.
/// The result is a typed *historical hypothesis*, never an owned current value.
/// R635 cannot establish screen orientation, HP ownership or move legality.
enum R635LayoutToFields {
    static let schema = "trueplan.r635.structured-layout-field-evidence.v1"
    private static let roles: [String:[String]] = [
        "own_hp":["own.hp","own.hp_max"],
        "opponent_hp":["opponent.hp_percent"],
        "own_name":["own.active_species"],
        "opponent_name":["opponent.active_species"],
        "move_name":["own.moves_four"],
        "move_pp":["own.pp_four"]
    ]
    private static let nonSlot = Set(["own_hp","opponent_hp","own_name","opponent_name"])
    private static let slot = Set(["move_name","move_pp"])
    private static let classifiable = Set([
        "move_selection_candidate", "move_selection_with_move_details_overlay_candidate",
        "normal_command_candidate","party_selection_candidate", "party_preview_candidate",
        "switch_selection_candidate","battle_end_candidate", "animation_or_battle_message_candidate"
    ])
    private static func validSHA(_ h:String)->Bool {
        h.utf8.count==64 && h.utf8.allSatisfy{ (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func sameFrame(_ item:[String:Any], _ snapshot:[String:Any]) ->Bool {
        let h=snapshot["image_sha256"] as? String ?? ""
        return validSHA(h) && item["image_sha256"] as? String == h &&
            item["capture_session_id"] as? String == snapshot["capture_session_id"] as? String &&
            item["frame_id"] as? Int64 == snapshot["frame_id"] as? Int64 &&
            item["epoch"] as? Int64 == snapshot["epoch"] as? Int64 &&
            item["current_state_eligible"] as? Bool == false
    }
    static func enrich(_ doc: inout [String:Any], sourceKind:String) {
        let catalog=R581ReadabilityCoverage.tracks.map{$0.0}
        guard catalog.count == 79,Set(catalog).count==79,
              let base=doc["r581_full_read_coverage"] as? [String:Any],
              base["schema"] as? String == R581ReadabilityCoverage.schema,
              base["source_kind"] as? String == sourceKind,
              base["r634_schema"] as? String == R634FieldEvidenceRouting.schema,
              let rows=base["fields"] as? [[String:Any]],
              rows.compactMap({$0["field"] as? String})==catalog,
              let snapshot=doc["screen_read_state"] as? [String:Any],
              snapshot["source_validation"] as? String == "PASS_FRAME_BINDING_ONLY",
              snapshot["current_state_eligible"] as? Bool == false,
              snapshot["battle_advice_authorized"] as? Bool == false else {
            doc["r635_layout_status"]="HOLD_UNVERIFIED_BASE_OR_SNAPSHOT"
            return
        }
        let snapshotHash=snapshot["image_sha256"] as? String ?? ""
        guard validSHA(snapshotHash),
              let layout=snapshot["layout_candidates"] as? [String:Any],
              layout["schema"] as? String == "trueplan.screen-read.layout-candidates.v1",
              doc["r634_field_reader_status"] as? String == "ROUTES_WIRED_NO_GAME_CERTIFICATION",
              sameFrame(layout,snapshot),
              layout["owner_certified"] as? Bool == false,
              layout["calibration_certified"] as? Bool == false,
              let associations=layout["associations"] as? [[String:Any]],
              associations.count<=48 else {
            doc["r635_layout_status"]="HOLD_BAD_LAYOUT_SOURCE_OR_CALIBRATION"
            return
        }
        var candidates=[String:[[String:Any]]]()
        var slotKeys=Set<String>()
        var rejected=0
        var conflict=false
        for a in associations {
            guard let role=a["role_hint"] as? String,
                  let fields=roles[role],
                  sameFrame(a,snapshot),
                  a["verification_status"] as? String == "UNVERIFIED",
                  a["side"] as? String == "UNKNOWN_OWNER",
                  a["current_state_eligible"] as? Bool == false,
                  let refs=a["evidence_refs"] as? [String],refs.count<=4,
                  refs.allSatisfy({!$0.isEmpty && $0.utf8.count<=160}),
                  Set(refs).count==refs.count,
                  let texts=a["raw_texts"] as? [String],texts.count==refs.count,
                  texts.allSatisfy({!$0.isEmpty && $0.utf8.count<=160}),
                  let knowledge=a["knowledge_state"] as? String,
                  ["UNKNOWN","INFERRED","CONFLICT"].contains(knowledge),
                  a["orientation"] as? String ==
                    "ANALYSIS_UP_SOURCE_TRANSFORM_UNVERIFIED",
                  a["roi_coordinate_space"] as? String ==
                    "ANALYSIS_PIXELS_TOP_LEFT" else {
                rejected+=1;continue
            }
            let slotValue:Int?
            if slot.contains(role) {
                guard let n=a["slot"] as? Int,(0..<4).contains(n) else {rejected+=1;continue}
                slotValue=n
            } else if nonSlot.contains(role) {
                guard a["slot"] == nil || a["slot"] is NSNull else {rejected+=1;continue}
                slotValue=nil
            } else {rejected+=1;continue}
            let key="\(role):\(slotValue.map(String.init) ?? "none")"
            if !slotKeys.insert(key).inserted {conflict=true;break}
            let candidate:[String:Any]=[
                "role_hint":role,"slot_candidate":slotValue.map{$0 as Any} ?? NSNull(),
                "unverified_value":a["value"] ?? NSNull(),
                "knowledge_state":knowledge,"evidence_refs":refs,"raw_texts":texts,
                "source_image_sha256":snapshotHash,"side":"UNKNOWN_OWNER",
                "status":"HISTORICAL_LAYOUT_HYPOTHESIS_NOT_CERTIFIED",
                "owner_verified":false,"screen_orientation_verified":false,
                "current_value_admitted":false
            ]
            for field in fields {candidates[field,default:[]].append(candidate)}
        }
        if conflict {
            doc["r635_layout_status"]="HOLD_DUPLICATE_ROLE_SLOT"
            return
        }
        // The screen classifier is useful input but not verified current UI.
        var screen:[String:Any]=[:]
        if let classifier=snapshot["screen_classification"] as? [String:Any],
           classifier["schema"] as? String == "trueplan.screen-read.screen-evidence.v1",
           sameFrame(classifier,snapshot),
           classifier["owner_certified"] as? Bool == false,
           classifier["status"] as? String == "PRIMARY_AND_ALTERNATIVES_AGREE",
           let kind=classifier["screen_kind"] as? String,classifiable.contains(kind),
           snapshot["screen_kind"] as? String == kind {
            let refs=classifier["evaluated_evidence_refs"] as? [String] ?? []
            if refs.count<=96 && refs.allSatisfy({!$0.isEmpty && $0.utf8.count<=160}) {
                screen=["screen_kind_candidate":kind,"evidence_refs":Array(refs.prefix(12)),
                        "screen_verified":false,"historical_only":true]
            }
        }
        var newRows=[[String:Any]]()
        var observed=0
        for old in rows {
            let field=old["field"] as! String
            var updated=old
            let items=(candidates[field] ?? []).prefix(4)
            updated["r635_structured_layout_candidates"]=Array(items)
            updated["r635_source_scoped_hypotheses_present"]=(!items.isEmpty)
            if !items.isEmpty { observed+=1 }
            if ["screen.ui_state","screen.menu_state"].contains(field) && !screen.isEmpty {
                updated["r635_screen_kind_hypothesis"]=screen
                observed+=1
            }
            updated["current_value_admitted"]=false
            updated["owner_verified"]=false
            updated["reader_producing_verified_game_value"]=false
            newRows.append(updated)
        }
        var enhanced=base
        enhanced["fields"]=newRows
        enhanced["r635_schema"]=schema
        enhanced["r635_status"]="HISTORICAL_LAYOUT_EVIDENCE_NOT_GAME_STATE"
        enhanced["r635_structured_fields_with_hypotheses"]=observed
        enhanced["r635_invalid_associations_rejected"]=rejected
        enhanced["r635_screen_kind_candidate"]=screen.isEmpty ? NSNull() as Any : screen
        enhanced["r635_verified_game_fields"]=0
        doc["r581_full_read_coverage"]=enhanced
        doc["r635_layout_status"]="LAYOUT_HYPOTHESES_ATTACHED_WITHOUT_PROMOTION"
    }
}
