import Foundation

/// Converts provenance-checked OCR text to explicitly unverified typed
/// candidates. Does NOT discover sprites, assign owners or certify state.
enum R666TypedOCRCandidates {
    static let schema = "trueplan.r666.typed-ocr-candidates.v1"
    private static func hold(_ reason:String)->[String:Any] {
        ["schema":schema,"status":reason,"field_count":79,
         "game_fields_certified":0,"owner_certified":false,
         "turn_certified":false,"mega_form_certified":false,
         "current_state_eligible":false,
         "battle_advice_authorized":false]
    }
    private static func isSHA(_ v:Any?)->String? {
        guard let s=v as? String,s.utf8.count==64,
          s.utf8.allSatisfy({(48...57).contains($0) ||
                             (97...102).contains($0)}) else {return nil}
        return s
    }
    private static func extract(_ text:String,
                                _ pattern:String)->[Int]? {
        guard let regex=try? NSRegularExpression(pattern:pattern) else {
            return nil
        }
        let range=NSRange(text.startIndex..<text.endIndex,in:text)
        guard let m=regex.firstMatch(in:text,range:range),
              m.range==range else{return nil}
        var values=[Int]()
        for i in 1..<m.numberOfRanges {
            guard let r=Range(m.range(at:i),in:text),
                  let n=Int(text[r]) else{return nil}
            values.append(n)
        }
        return values
    }
    static func decode(field:String,text:String)->[String:Any] {
        let t=text.precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of:"　",with:"")
            .replacingOccurrences(of:" ",with:"")
            .trimmingCharacters(in:.whitespacesAndNewlines)
        let suffix=field.split(separator:".").last.map(String.init) ?? ""
        if ["hp","hp_max"].contains(suffix),
           let v=extract(t,#"^(?:HP)?([0-9]{1,4})/([0-9]{1,4})$"#),
           v[1]>0,v[0]<=v[1] {
            return ["kind":"HP_FRACTION_CANDIDATE",
                    "current":v[0],"maximum":v[1]]
        }
        if suffix=="hp_percent",
           let v=extract(t,#"^([0-9]{1,3})%$"#),v[0]<=100 {
            return ["kind":"HP_PERCENT_CANDIDATE","percent":v[0]]
        }
        if ["pp_four","pp_revealed"].contains(suffix),
           let v=extract(t,#"^(?:PP[：:]?)?([0-9]{1,2})/([0-9]{1,2})$"#),
           v[1]>0,v[0]<=v[1] {
            return ["kind":"MOVE_PP_FRACTION_CANDIDATE",
                    "remaining":v[0],"maximum":v[1]]
        }
        if suffix=="gender",["♀","♂"].contains(t) {
            return ["kind":"GENDER_GLYPH_CANDIDATE","glyph":t]
        }
        if suffix=="major_status" {
            let v=["やけど","まひ","ねむり","こおり","どく",
                   "もうどく","BRN","PAR","SLP","FRZ","PSN"]
            if v.contains(t) {
                return ["kind":"STATUS_TEXT_CANDIDATE","label":t]
            }
        }
        if field=="battle.turn",
           let v=extract(t,#"^(?:第)?([0-9]{1,3})ターン$"#),
           v[0]>0 {
            return ["kind":"TURN_TEXT_CANDIDATE","turn":v[0]]
        }
        if field=="battle.timer",
           let v=extract(t,#"^(?:残り|制限)([0-9]{1,3})(?:秒|sec)$"#) {
            return ["kind":"TIMER_TEXT_CANDIDATE","seconds":v[0]]
        }
        let terms:[String:[String]]=[
            "weather":["あめ","雨","にほんばれ","日差し","晴れ",
                       "すなあらし","砂嵐","ゆき","雪"],
            "terrain":["エレキフィールド","グラスフィールド",
                       "サイコフィールド","ミストフィールド"],
            "trick_room":["トリックルーム"],
            "reflect":["リフレクター"],
            "light_screen":["ひかりのかべ","光の壁"],
            "aurora_veil":["オーロラベール"],
            "tailwind":["おいかぜ","追い風"],
            "mega_trigger":["メガシンカ","メガ進化"],
            "entry_hazards":["ステルスロック","まきびし",
                             "どくびし","ねばねばネット"]]
        if let options=terms[suffix],
           let value=options.first(where:{t.contains($0)}) {
            return ["kind":"TEXT_MENTION_NOT_EFFECT_PROOF",
                    "term":value]
        }
        return ["kind":"UNINTERPRETED_OCR_TEXT_ONLY"]
    }
    static func audit(_ doc:[String:Any],
                      sourceKind:String)->[String:Any] {
        guard ["LIVE_RETAINED_FRAME",
               "USER_IMPORTED_PNG_OFFLINE_ONLY"].contains(sourceKind),
              let trace=doc["r665_evidence_trace_audit"]
                as? [String:Any],
              let reader=doc["r646_field_readers"]
                as? [String:Any],
              trace["schema"] as? String ==
                  "trueplan.r665.evidence-trace-audit.v1",
              trace["status"] as? String ==
                  "HISTORICAL_EVIDENCE_TRACE_REPRODUCED_ONLY",
              trace["source_trace_verified"] as? Bool == true,
              reader["schema"] as? String ==
                  "trueplan.r646.field-signal-readers.v1",
              reader["status"] as? String ==
                  "79_SOURCE_READER_ATTEMPTS_NOT_GAME_CERTIFIED",
              reader["source_kind"] as? String == sourceKind,
              trace["source_kind"] as? String == sourceKind,
              let raw=isSHA(trace["source_image_sha256"]),
              raw==isSHA(reader["raw_image_sha256"]),
              let analysis=isSHA(trace["analysis_image_sha256"]),
              analysis==isSHA(reader["analysis_image_sha256"]),
              let session=trace["capture_session_id"] as? String,
              !session.isEmpty,session.utf8.count<=160,
              session==reader["capture_session_id"] as? String,
              let frame=trace["frame_id"] as? Int,frame>0,
              frame==reader["frame_id"] as? Int,
              let epoch=trace["epoch"] as? Int,epoch>0,
              epoch==reader["epoch"] as? Int,
              trace["owner_certified"] as? Bool == false,
              trace["turn_certified"] as? Bool == false,
              trace["mega_form_certified"] as? Bool == false,
              trace["battle_advice_authorized"] as? Bool == false,
              trace["current_state_eligible"] as? Bool == false,
              trace["game_fields_certified"] as? Int == 0,
              trace["field_count"] as? Int == 79,
              reader["owner_verified"] as? Bool == false,
              reader["battle_advice_authorized"] as? Bool == false,
              reader["current_state_eligible"] as? Bool == false,
              reader["game_fields_certified"] as? Int == 0,
              reader["field_count"] as? Int == 79,
              let traces=trace["field_diagnostics"] as? [[String:Any]],
              let rows=reader["field_read_attempts"]
                as? [[String:Any]],
              rows.count==79,traces.count==79 else {
            return hold("HOLD_SOURCE_TRACE_NOT_VERIFIED")
        }
        let fields=R581ReadabilityCoverage.tracks.map{$0.0}
        guard fields.count==79,Set(fields).count==79 else {
            return hold("HOLD_CANONICAL_FIELDS")
        }
        var report=[[String:Any]](),count=0
        for i in 0..<79 {
            let row=rows[i],tr=traces[i]
            guard let field=row["field"] as? String,
                  field==fields[i],field==tr["field"] as? String,
                  row["owner_verified"] as? Bool == false,
                  row["turn_verified"] as? Bool == false,
                  row["game_value_certified"] as? Bool == false,
                  row["current_state_eligible"] as? Bool == false,
                  tr["owner_verified"] as? Bool == false,
                  tr["turn_verified"] as? Bool == false,
                  tr["game_value_certified"] as? Bool == false,
                  tr["current_state_eligible"] as? Bool == false,
                  let refs=tr["evidence_refs"] as? [String],
                  let ev=row["ocr_evidence"] as? [[String:Any]],
                  refs.count==ev.count,refs.count<=8,
                  Set(refs).count==refs.count,
                  tr["evidence_count"] as? Int == refs.count else {
                return hold("HOLD_FIELD_OR_REF_MISMATCH")
            }
            var candidates=[[String:Any]]()
            for (j,v) in ev.enumerated() {
                guard v["evidence_ref"] as? String==refs[j],
                      let txt=v["text"] as? String,!txt.isEmpty,
                      txt.utf8.count<=160,
                      v["side"] as? String=="UNKNOWN_OWNER",
                      v["current_value_admitted"] as? Bool==false else {
                    return hold("HOLD_OCR_EVIDENCE_MISMATCH")
                }
                var c=decode(field:field,text:txt)
                c["raw_text"]=txt
                c["evidence_ref"]=refs[j]
                c["owner_verified"]=false
                c["game_value_certified"]=false
                candidates.append(c)
                if c["kind"] as? String !=
                   "UNINTERPRETED_OCR_TEXT_ONLY" {count+=1}
            }
            report.append(["field":field,"candidates":candidates,
                "current_state_eligible":false,
                "game_value_certified":false])
        }
        return ["schema":schema,
            "status":"TYPED_OCR_CANDIDATES_UNVERIFIED",
            "field_count":79,"fields":report,
            "typed_candidate_count_not_accuracy":count,
            "source_image_sha256":raw,
            "analysis_image_sha256":analysis,
            "frame_id":frame,"epoch":epoch,
            "game_fields_certified":0,"owner_certified":false,
            "turn_certified":false,"mega_form_certified":false,
            "current_state_eligible":false,
            "battle_advice_authorized":false,
            "real_game_accuracy":"NOT_MEASURED"]
    }
    static func enrich(_ doc:inout [String:Any],
                       sourceKind:String) {
        doc["r666_typed_ocr_candidates"] =
            audit(doc,sourceKind:sourceKind)
    }
}
