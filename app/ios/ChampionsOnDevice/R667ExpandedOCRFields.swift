import Foundation

/// Field-specific interpretation of source-bound OCR candidates.
/// These are observations of TEXT only, not a game-state or actor proof.
enum R667ExpandedOCRFields {
    static let schema = "trueplan.r667.expanded-ocr-fields.v1"
    private static let unverified: [String:Any] = [
        "owner_verified": false, "turn_verified": false,
        "game_value_certified": false, "mega_form_certified": false,
        "current_state_eligible": false,
        "battle_advice_authorized": false]
    private static func hold(_ reason: String)->[String:Any] {
        var r=unverified
        r["schema"]=schema; r["status"]=reason
        r["field_count"]=79; r["game_fields_certified"]=0
        return r
    }
    private static func matched(_ s:String,_ pattern:String)->[String]? {
        guard let regex=try? NSRegularExpression(pattern:pattern) else {
            return nil
        }
        let whole=NSRange(s.startIndex..<s.endIndex,in:s)
        guard let m=regex.firstMatch(in:s,range:whole),
              m.range==whole else {return nil}
        return (1..<m.numberOfRanges).compactMap { i in
            guard let r=Range(m.range(at:i),in:s) else {return nil}
            return String(s[r])
        }
    }
    private static func value(_ kind:String,_ text:String,
                              _ attributes:[String:Any]=[:])->[String:Any] {
        var result:[String:Any] = ["kind":kind,"text":text,
            "visible_text_only":true,"game_value_certified":false]
        for (k,v) in attributes {result[k]=v}
        return result
    }
    static func decode(field:String,text:String)->[String:Any]? {
        let t=text.precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of:"　",with:"")
            .replacingOccurrences(of:" ",with:"")
            .trimmingCharacters(in:.whitespacesAndNewlines)
        guard !t.isEmpty,t.utf8.count<=160,
              !t.contains("\n"),!t.contains("\r") else {return nil}
        let suffix=field.split(separator:".").last.map(String.init) ?? ""
        let weather=["雨","あめ","晴れ","にほんばれ","砂嵐","すなあらし","雪","ゆき"]
        let terrain=["エレキフィールド","グラスフィールド",
                     "サイコフィールド","ミストフィールド"]
        let effects=["リフレクター","ひかりのかべ","光の壁",
                     "オーロラベール","おいかぜ","追い風"]
        let hazards=["ステルスロック","まきびし","どくびし","ねばねばネット"]
        let boost=["こうげき","ぼうぎょ","とくこう","とくぼう",
                   "すばやさ","命中","回避"]
        if ["identity","active_species","active_slot","party_six"].contains(suffix),
           let g=matched(t,#"^(?:名前|ポケモン|相手|手持ち)[：:](.{1,40})$"#) {
            return value("IDENTITY_LABEL_OCR_NOT_SPECIES_PROOF",t,["label":g[0]])
        }
        if ["moves_four","moves_revealed"].contains(suffix),
           let g=matched(t,#"^(?:技|わざ)[：:](.{1,32})$"#) {
            return value("MOVE_LABEL_OCR_NOT_SLOT_PROOF",t,["label":g[0]])
        }
        if suffix=="move_types",
           let g=matched(t,#"^タイプ[：:](ノーマル|ほのお|みず|でんき|くさ|こおり|かくとう|どく|じめん|ひこう|エスパー|むし|いわ|ゴースト|ドラゴン|あく|はがね|フェアリー)$"#) {
            return value("TYPE_LABEL_OCR_NOT_MOVE_ASSOCIATION",t,["type":g[0]])
        }
        if ["ability","held_item"].contains(suffix) {
            let pattern=suffix=="ability" ?
                #"^(?:特性|とくせい)[：:](.{1,40})$"# :
                #"^(?:持ち物|もちもの|どうぐ)[：:](.{1,40})$"#
            if let g=matched(t,pattern) {
                return value("REVEALED_LABEL_NOT_ACTOR_PROOF",t,["label":g[0]])
            }
        }
        if suffix=="volatile_status" {
            let words=["こんらん","混乱","ひるみ","やどりぎ",
                       "みがわり","ちょうはつ","アンコール","かなしばり"]
            if words.contains(t) {
                return value("VOLATILE_TEXT_NOT_CURRENT_STATE",t)
            }
        }
        if suffix=="boost_seven",
           let g=matched(t,#"^(こうげき|ぼうぎょ|とくこう|とくぼう|すばやさ|命中|回避)([+-][1-6])$"#),
           boost.contains(g[0]),let rank=Int(g[1]) {
            return value("BOOST_RANK_TEXT_NOT_ACTOR_PROOF",t,
                         ["stat":g[0],"displayed_rank":rank])
        }
        if ["weather","terrain","trick_room","other_rooms"].contains(suffix) {
            let terms=suffix=="weather" ? weather :
                suffix=="terrain" ? terrain :
                suffix=="trick_room" ? ["トリックルーム"] :
                ["ワンダールーム","マジックルーム"]
            if terms.contains(t) {
                return value("FIELD_NAME_TEXT_NOT_EFFECT_PROOF",t)
            }
        }
        if ["weather_turns","terrain_turns","trick_room_turns",
            "side_effect_turns"].contains(suffix),
           let g=matched(t,#"^(.{1,18})(?:残り|あと)([1-8])ターン$"#),
           let n=Int(g[1]) {
            let terms=suffix=="weather_turns" ? weather :
                suffix=="terrain_turns" ? terrain :
                suffix=="trick_room_turns" ? ["トリックルーム"] : effects
            if terms.contains(g[0]) {
                return value("DURATION_TEXT_NOT_TIMELINE_PROOF",t,
                             ["effect":g[0],"displayed_turns":n])
            }
        }
        if ["reflect","light_screen","aurora_veil","tailwind"].contains(suffix) {
            let terms=suffix=="reflect" ? ["リフレクター"] :
                suffix=="light_screen" ? ["ひかりのかべ","光の壁"] :
                suffix=="aurora_veil" ? ["オーロラベール"] :
                ["おいかぜ","追い風"]
            if terms.contains(t) {
                return value("SIDE_EFFECT_TEXT_NOT_OWNER_PROOF",t)
            }
        }
        if suffix=="safeguard_mist",
           ["しろいきり","白い霧","しんぴのまもり","神秘の守り"].contains(t) {
            return value("SIDE_EFFECT_TEXT_NOT_OWNER_PROOF",t)
        }
        if suffix=="entry_hazards",hazards.contains(t) {
            return value("HAZARD_TEXT_NOT_SIDE_PROOF",t)
        }
        if suffix=="hazard_layers",
           let g=matched(t,#"^(まきびし|どくびし)([1-3])層$"#),
           let n=Int(g[1]),n<=3,
           (g[0] != "どくびし" || n<=2) {
            return value("HAZARD_LAYER_TEXT_NOT_SIDE_PROOF",t,
                         ["hazard":g[0],"displayed_layers":n])
        }
        if suffix=="temporary_effects",
           ["じゅうりょく","重力","ふういん","フェアリーロック"].contains(t) {
            return value("TEMPORARY_EFFECT_TEXT_ONLY",t)
        }
        if suffix=="mega_history" || suffix=="mega_trigger" ||
           suffix=="one_time_resource" {
            let terms=suffix=="one_time_resource" ?
                ["メガシンカ","メガ進化","テラスタル","Zワザ"] :
                ["メガシンカ","メガ進化"]
            if terms.contains(t) {
                return value("RESOURCE_TEXT_NOT_ACTIVATION_PROOF",t)
            }
        }
        if field=="battle.phase",
           ["選出","コマンド","対戦開始","対戦終了"].contains(t) {
            return value("PHASE_TEXT_NOT_SCREEN_CLASSIFIER",t)
        }
        if ["switch_history","faint_history","move_history"].contains(suffix) {
            let words=suffix=="switch_history" ?
                ["引っ込めた","ひっこめた","くりだした","繰り出した"] :
                suffix=="faint_history" ?
                ["倒れた","たおれた","戦闘不能"] :
                ["使った","つかった","使用した"]
            if words.contains(where:{t.contains($0)}) {
                return value("EVENT_TEXT_NOT_TURN_OR_OWNER_PROOF",t)
            }
        }
        return nil
    }
    static func audit(_ doc:[String:Any])->[String:Any] {
        guard let typed=doc["r666_typed_ocr_candidates"] as? [String:Any],
              typed["schema"] as? String == R666TypedOCRCandidates.schema,
              typed["status"] as? String == "TYPED_OCR_CANDIDATES_UNVERIFIED",
              typed["field_count"] as? Int == 79,
              typed["game_fields_certified"] as? Int == 0,
              typed["owner_certified"] as? Bool == false,
              typed["turn_certified"] as? Bool == false,
              typed["mega_form_certified"] as? Bool == false,
              typed["battle_advice_authorized"] as? Bool == false,
              typed["current_state_eligible"] as? Bool == false,
              let fields=typed["fields"] as? [[String:Any]],
              fields.count==79 else {return hold("HOLD_R666_UNVERIFIED_INPUT")}
        let canonical=R581ReadabilityCoverage.tracks.map{$0.0}
        guard canonical.count==79,Set(canonical).count==79 else {
            return hold("HOLD_CANONICAL_FIELD_LIST")
        }
        var output=[[String:Any]](); var n=0
        for i in 0..<79 {
            let row=fields[i]
            guard row["field"] as? String==canonical[i],
                  row["game_value_certified"] as? Bool==false,
                  row["current_state_eligible"] as? Bool==false,
                  let candidates=row["candidates"] as? [[String:Any]],
                  candidates.count<=8 else {return hold("HOLD_FIELD_ORDER")}
            var hits=[[String:Any]]()
            for c in candidates {
                guard c["owner_verified"] as? Bool==false,
                      c["game_value_certified"] as? Bool==false,
                      let ref=c["evidence_ref"] as? String,
                      !ref.isEmpty,ref.utf8.count<=160,
                      let t=c["raw_text"] as? String,
                      !t.isEmpty,t.utf8.count<=160 else {
                    return hold("HOLD_CANDIDATE_PROVENANCE")
                }
                if var hit=decode(field:canonical[i],text:t) {
                    hit["evidence_ref"]=ref
                    hit["owner_verified"]=false
                    hit["turn_verified"]=false
                    hits.append(hit);n+=1
                }
            }
            output.append(["field":canonical[i],"decoded":hits,
                "status":hits.isEmpty ? "NO_MATCHING_OCR_TEXT" :
                    "TEXT_ONLY_UNVERIFIED", "game_value_certified":false,
                "current_state_eligible":false])
        }
        var result=unverified
        result["schema"]=schema
        result["status"]="EXPANDED_TEXT_CANDIDATES_ONLY"
        result["field_count"]=79
        result["fields"]=output
        result["decoded_evidence_count_not_accuracy"]=n
        result["game_fields_certified"]=0
        result["real_game_accuracy"]="NOT_MEASURED"
        return result
    }
    static func enrich(_ doc:inout [String:Any]) {
        doc["r667_expanded_ocr_fields"]=audit(doc)
    }
}
