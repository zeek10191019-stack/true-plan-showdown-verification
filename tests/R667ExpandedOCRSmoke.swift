import Foundation
@main struct R667Smoke {
    static func main() {
        let good:[(String,String,String)]=[
          ("own.identity","名前:ガブリアス","IDENTITY_LABEL_OCR_NOT_SPECIES_PROOF"),
          ("opponent.active_species","相手:ギャラドス","IDENTITY_LABEL_OCR_NOT_SPECIES_PROOF"),
          ("own.moves_four","技:じしん","MOVE_LABEL_OCR_NOT_SLOT_PROOF"),
          ("own.move_types","タイプ:じめん","TYPE_LABEL_OCR_NOT_MOVE_ASSOCIATION"),
          ("own.ability","特性:がんじょう","REVEALED_LABEL_NOT_ACTOR_PROOF"),
          ("opponent.held_item","持ち物:オボンのみ","REVEALED_LABEL_NOT_ACTOR_PROOF"),
          ("own.volatile_status","こんらん","VOLATILE_TEXT_NOT_CURRENT_STATE"),
          ("own.boost_seven","すばやさ+2","BOOST_RANK_TEXT_NOT_ACTOR_PROOF"),
          ("field.weather","砂嵐","FIELD_NAME_TEXT_NOT_EFFECT_PROOF"),
          ("field.terrain","グラスフィールド","FIELD_NAME_TEXT_NOT_EFFECT_PROOF"),
          ("field.trick_room","トリックルーム","FIELD_NAME_TEXT_NOT_EFFECT_PROOF"),
          ("field.weather_turns","雨残り3ターン","DURATION_TEXT_NOT_TIMELINE_PROOF"),
          ("field.terrain_turns","エレキフィールド残り2ターン","DURATION_TEXT_NOT_TIMELINE_PROOF"),
          ("field.trick_room_turns","トリックルーム残り4ターン","DURATION_TEXT_NOT_TIMELINE_PROOF"),
          ("own.side_effect_turns","リフレクター残り3ターン","DURATION_TEXT_NOT_TIMELINE_PROOF"),
          ("own.reflect","リフレクター","SIDE_EFFECT_TEXT_NOT_OWNER_PROOF"),
          ("own.light_screen","光の壁","SIDE_EFFECT_TEXT_NOT_OWNER_PROOF"),
          ("own.aurora_veil","オーロラベール","SIDE_EFFECT_TEXT_NOT_OWNER_PROOF"),
          ("own.tailwind","追い風","SIDE_EFFECT_TEXT_NOT_OWNER_PROOF"),
          ("opponent.safeguard_mist","しろいきり","SIDE_EFFECT_TEXT_NOT_OWNER_PROOF"),
          ("own.entry_hazards","まきびし","HAZARD_TEXT_NOT_SIDE_PROOF"),
          ("own.hazard_layers","まきびし2層","HAZARD_LAYER_TEXT_NOT_SIDE_PROOF"),
          ("field.temporary_effects","じゅうりょく","TEMPORARY_EFFECT_TEXT_ONLY"),
          ("battle.mega_history","メガシンカ","RESOURCE_TEXT_NOT_ACTIVATION_PROOF"),
          ("battle.phase","選出","PHASE_TEXT_NOT_SCREEN_CLASSIFIER"),
          ("battle.switch_history","ガブリアスを引っ込めた","EVENT_TEXT_NOT_TURN_OR_OWNER_PROOF"),
          ("battle.faint_history","ギャラドスは倒れた","EVENT_TEXT_NOT_TURN_OR_OWNER_PROOF"),
          ("battle.move_history","じしんを使った","EVENT_TEXT_NOT_TURN_OR_OWNER_PROOF")
        ]
        for (field,text,expected) in good {
            let result=R667ExpandedOCRFields.decode(field:field,text:text)
            precondition(result?["kind"] as? String==expected,"\(field)\(text)")
            precondition(result?["game_value_certified"] as? Bool == false)
        }
        let bad:[(String,String)]=[
          ("field.weather_turns","雨残り9ターン"),
          ("field.trick_room_turns","雨残り2ターン"),
          ("field.terrain_turns","トリックルーム残り3ターン"),
          ("opponent.hazard_layers","ステルスロック3層"),
          ("own.boost_seven","こうげき+8"),
          ("own.mega_visual_form","メガギャラドス"),
          ("own.gender","♀"),
          ("own.moves_four","HP:148/197"),
          ("own.ability","技:りゅうせいぐん"),
          ("battle.move_history","じしん"),
          ("own.identity","名前:ガブリアス\n命令"),
          ("field.weather","雨のような背景")
        ]
        for (field,text) in bad {
            precondition(R667ExpandedOCRFields.decode(field:field,text:text)==nil,
                         "accepted invalid \(field):\(text)")
        }
        let hold=R667ExpandedOCRFields.audit([:])
        precondition(hold["status"] as? String=="HOLD_R666_UNVERIFIED_INPUT")
        precondition(hold["game_fields_certified"] as? Int==0)
        let names=R581ReadabilityCoverage.tracks.map{$0.0}
        precondition(names.count==79 && Set(names).count==79)
        let rows:[[String:Any]]=names.map {field in
            let hits:[[String:Any]]=field=="field.weather_turns" ?
                [["raw_text":"雨残り3ターン","evidence_ref":"ocr-1",
                  "owner_verified":false,"game_value_certified":false]] : []
            return ["field":field,"candidates":hits,
                "game_value_certified":false,"current_state_eligible":false]
        }
        let doc:[String:Any]=["r666_typed_ocr_candidates": [
            "schema":R666TypedOCRCandidates.schema,
            "status":"TYPED_OCR_CANDIDATES_UNVERIFIED",
            "field_count":79,"fields":rows,"game_fields_certified":0,
            "owner_certified":false,"turn_certified":false,
            "mega_form_certified":false,"battle_advice_authorized":false,
            "current_state_eligible":false] as [String:Any]]
        let result=R667ExpandedOCRFields.audit(doc)
        precondition(result["status"] as? String ==
            "EXPANDED_TEXT_CANDIDATES_ONLY")
        precondition(result["decoded_evidence_count_not_accuracy"] as? Int==1)
        precondition((result["fields"] as? [[String:Any]])?.count==79)
        precondition(result["game_fields_certified"] as? Int==0)
        var forged=doc
        var typed=doc["r666_typed_ocr_candidates"] as! [String:Any]
        var altered=rows;altered[0]["field"]="field.weather_turns"
        typed["fields"]=altered;forged["r666_typed_ocr_candidates"]=typed
        precondition(R667ExpandedOCRFields.audit(forged)["status"] as? String ==
            "HOLD_FIELD_ORDER")
        print("R667_EXPANDED_OCR_SMOKE_PASS \(good.count+bad.count+8)")
    }
}
