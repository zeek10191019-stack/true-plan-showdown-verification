import Foundation

/// R581: exhaustive *attempt inventory*, not a certification of visual truth.
/// Every possible battle-screen slot must have a place in a one-tap report.
/// A missing OCR result remains UNKNOWN; candidate text is never assigned an owner.
enum R581ReadabilityCoverage {
    static let schema = "trueplan.r581.all-visual-readability-inventory.v1"
    static let tracks: [(String,[String])] = [
        ("screen.ui_state",[]),("screen.menu_state",[]),("screen.orientation",[]),
        ("capture.frame_id",[]),("capture.epoch",[]),("capture.session",[]),
        ("capture.pixel_geometry",[]),("capture.clock",[]),("battle.turn",[]),
        ("battle.phase",[]),("battle.timer",[]),
        ("own.identity",[]),("opponent.identity",[]),
        ("own.party_six",[]),("opponent.party_six",[]),
        ("own.active_species",[]),("opponent.active_species",[]),
        ("own.active_slot",[]),("opponent.active_slot",[]),
        ("own.gender",[]),("opponent.gender",[]),
        ("own.hp",["hp","hp_or_pp"]),("own.hp_max",["hp","hp_or_pp"]),
        ("own.hp_percent",["hp_percent"]),("opponent.hp",["hp","hp_or_pp"]),
        ("opponent.hp_max",["hp","hp_or_pp"]),("opponent.hp_percent",["hp_percent"]),
        ("own.moves_four",[]),("own.move_types",[]),("own.pp_four",["pp","hp_or_pp"]),
        ("opponent.moves_revealed",[]),("opponent.pp_revealed",[]),
        ("own.major_status",["major_status"]),("opponent.major_status",["major_status"]),
        ("own.volatile_status",["visible_volatile"]),("opponent.volatile_status",["visible_volatile"]),
        ("own.boost_seven",["absolute_boost"]),("opponent.boost_seven",["absolute_boost"]),
        ("own.ability",["visible_ability_label"]),("opponent.ability",["visible_ability_label"]),
        ("own.held_item",["visible_item_label"]),("opponent.held_item",["visible_item_label"]),
        ("own.mega_trigger",["mega_text"]),("opponent.mega_trigger",["mega_text"]),
        ("own.mega_visual_form",[]),("opponent.mega_visual_form",[]),
        ("own.mega_history",[]),("opponent.mega_history",[]),
        ("own.one_time_resource",[]),("opponent.one_time_resource",[]),
        ("field.weather",["weather"]),("field.weather_turns",["weather"]),
        ("field.terrain",["terrain"]),("field.terrain_turns",["terrain"]),
        ("field.trick_room",["room"]),("field.trick_room_turns",["room"]),
        ("field.other_rooms",["room"]),
        ("own.reflect",["screen_or_side_effect"]),("opponent.reflect",["screen_or_side_effect"]),
        ("own.light_screen",["screen_or_side_effect"]),("opponent.light_screen",["screen_or_side_effect"]),
        ("own.aurora_veil",["screen_or_side_effect"]),("opponent.aurora_veil",["screen_or_side_effect"]),
        ("own.tailwind",["screen_or_side_effect"]),("opponent.tailwind",["screen_or_side_effect"]),
        ("own.safeguard_mist",["screen_or_side_effect"]),("opponent.safeguard_mist",["screen_or_side_effect"]),
        ("own.side_effect_turns",["screen_or_side_effect"]),("opponent.side_effect_turns",["screen_or_side_effect"]),
        ("own.entry_hazards",["entry_hazard"]),("opponent.entry_hazards",["entry_hazard"]),
        ("own.hazard_layers",[]),("opponent.hazard_layers",[]),
        ("field.temporary_effects",["visible_volatile"]),
        ("battle.switch_history",[]),("battle.faint_history",[]),
        ("battle.move_history",[]),("battle.mega_history",[]),
        ("battle.conflict_and_staleness",[])
    ]
    private static let allowedDomains:Set<String> = Set(tracks.flatMap{$0.1})
    private static func isHex(_ source:String)->Bool {
        source.utf8.count == 64 && source.utf8.allSatisfy{(48...57).contains($0) || (97...102).contains($0)}
    }
    static func make(sourceSHA:String,sourceKind:String,
                     snapshot:[String:Any]?,mega:[String:Any]?,
                     projection:[String:Any]? = nil) -> [String:Any] {
        let validSource = isHex(sourceSHA) && ["LIVE_RETAINED_FRAME","USER_IMPORTED_PNG_OFFLINE_ONLY"].contains(sourceKind)
        let analysisSHA = snapshot?["image_sha256"] as? String ?? ""
        // Live capture can OCR a rotated/cropped PNG. Never claim that the
        // analysis hash equals the raw frame hash; demand explicit frame/epoch
        // geometry provenance in the pre-existing R556 transform report.
        let declaredProjection = validSource && isHex(analysisSHA) &&
            projection?["schema"] as? String == "trueplan.screen-read.analysis-projection.v1" &&
            projection?["status"] as? String == "DECLARED_GEOMETRY_ONLY" &&
            projection?["raw_image_sha256"] as? String == sourceSHA &&
            projection?["analysis_image_sha256"] as? String == analysisSHA &&
            (snapshot?["frame_id"] as? Int64) == (projection?["frame_id"] as? Int64) &&
            (snapshot?["epoch"] as? Int64) == (projection?["epoch"] as? Int64) &&
            snapshot?["capture_session_id"] as? String == projection?["capture_session_id"] as? String
        let validSnapshot = validSource && (analysisSHA==sourceSHA || declaredProjection)
            && snapshot?["current_state_eligible"] as? Bool == false
            && snapshot?["battle_advice_authorized"] as? Bool == false
        let validMega = validSource && mega?["image_sha256"] as? String == sourceSHA
            && mega?["mega_certified"] as? Bool == false
            && mega?["visual_form_certified"] as? Bool == false
        let bound = validSnapshot && snapshot?["source_validation"] as? String == "PASS_FRAME_BINDING_ONLY"
        let candidates:[ [String:Any] ] = bound ?
            (snapshot?["candidates"] as? [[String:Any]] ?? []).filter {
                guard let domain=$0["domain"] as? String, allowedDomains.contains(domain),
                      let ref=$0["evidence_ref"] as? String, !ref.isEmpty, ref.utf8.count<=160,
                      $0["image_sha256"] as? String == analysisSHA,
                      $0["side"] as? String == "UNKNOWN_OWNER",
                      $0["current_state_eligible"] as? Bool == false,
                      $0["verification_status"] as? String == "UNVERIFIED" else {return false}
                return true
            } : []
        let entries:[[String:Any]] = tracks.map { item in
            let related=candidates.filter { item.1.contains($0["domain"] as? String ?? "") }
            let refs=Array(Set(related.compactMap{$0["evidence_ref"] as? String})).sorted()
            return ["field":item.0,"status":refs.isEmpty ? "UNKNOWN" : "OCR_TEXT_CANDIDATE_ONLY",
                    "candidate_refs":refs.prefix(16).map{$0},
                    "candidate_count":related.count,"owner_verified":false,
                    "time_verified":false,"current_value_admitted":false,
                    "reason": !validSource ? "INVALID_SOURCE_SHA_OR_KIND" :
                        (!validSnapshot ? "SOURCE_BOUND_SNAPSHOT_ABSENT_OR_INVALID" :
                         (refs.isEmpty ? "NO_DOMAIN_EVIDENCE_OR_ROI_OWNER_UNKNOWN" : "TEXT_ONLY_NO_OWNER_OR_TURN_PROOF"))]
        }
        return ["schema":schema,"source_kind":sourceKind,
                "image_sha256":validSource ? sourceSHA : NSNull() as Any,
                "source_binding_valid":validSource,
                "snapshot_binding_valid":validSnapshot,
                "declared_analysis_projection_valid":declaredProjection,
                "analysis_image_sha256":isHex(analysisSHA) ? analysisSHA as Any : NSNull(),
                "mega_text_probe_binding_valid":validMega,
                "mega_ocr_available":validMega && ((mega?["text_hints"] as? [String])?.isEmpty == false),
                "live_capture_certified":false,"actual_game_accuracy_certified":false,
                "owner_certified":false,"turn_certified":false,
                "mega_visual_form_certified":false,"current_state_eligible":false,
                "battle_advice_authorized":false,"automated_upload":false,
                "capture_mode":"ONE_TAP_LOCAL_EVIDENCE_ONLY",
                "field_count":tracks.count,"fields":entries,
                "candidate_field_count":entries.filter{$0["status"] as? String == "OCR_TEXT_CANDIDATE_ONLY"}.count,
                "unknown_field_count":entries.filter{$0["status"] as? String == "UNKNOWN"}.count,
                "readiness":"NOT_CERTIFIED_UNTIL_REAL_GAME_GROUND_TRUTH" ]
    }
}
