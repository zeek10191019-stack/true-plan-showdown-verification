import Foundation

/// A historical, bounded per-frame text index produced from existing four-rotation OCR.
/// It does not invoke Vision again, infer a side, or certify game/turn/mega state.
enum R583FrameReadabilityIndex {
    static let schema = "trueplan.r583.retained-frame-text-index.v1"
    private static let allowedRotations: Set<Int> = [0,90,180,270]
    private static let maxIndexedObservations = 128
    private static let maxRefsPerField = 12

    private static func validSHA(_ s:String)->Bool {
        s.utf8.count == 64 && s.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func numericPercent(_ s:String)->Bool {
        guard s.last == "%", s.count <= 4,
              let v=Int(s.dropLast()),(0...100).contains(v) else{return false}
        return s.dropLast().allSatisfy{$0.isASCII && $0.isNumber}
    }
    private static func fraction(_ s:String)->Bool {
        let parts=s.split(separator:"/",omittingEmptySubsequences:false)
        guard parts.count==2,parts.allSatisfy({!$0.isEmpty && $0.count<=5 && $0.allSatisfy({$0.isASCII && $0.isNumber})}),
              let a=Int(parts[0]),let b=Int(parts[1]) else{return false}
        return b>0 && a>=0 && a<=b && b<=9999
    }
    /// These are text *hints*, not diagnoses or side/slot/state identification.
    /// Use only positive, known Japanese literals; no Pokémon-species predictions.
    private static func domains(_ input:String)->[String] {
        let text=input.trimmingCharacters(in:.whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .folding(options:[.widthInsensitive],locale:Locale(identifier:"ja_JP"))
        if numericPercent(text) {return ["hp_percent"]}
        // "10/10" is indistinguishable from HP vs PP without a verified ROI.
        if fraction(text) {return ["UNBOUND_HP_OR_PP_FRACTION"]}
        var result=[String]()
        let mapping:[(String,[String])] = [
            ("メガシンカ",["mega_text"]),("メガ進化",["mega_text"]),
            ("グラスフィールド",["terrain"]),("エレキフィールド",["terrain"]),
            ("サイコフィールド",["terrain"]),("ミストフィールド",["terrain"]),
            ("トリックルーム",["room"]),("マジックルーム",["room"]),
            ("ワンダールーム",["room"]),
            ("リフレクター",["screen_or_side_effect"]),
            ("ひかりのかべ",["screen_or_side_effect"]),
            ("オーロラベール",["screen_or_side_effect"]),
            ("おいかぜ",["screen_or_side_effect"]),
            ("しんぴのまもり",["screen_or_side_effect"]),
            ("しろいきり",["screen_or_side_effect"]),
            ("ステルスロック",["entry_hazard"]),("ねばねばネット",["entry_hazard"]),
            ("どくびし",["entry_hazard"]),("まきびし",["entry_hazard"]),
            ("すなあらし",["weather"]),("あられ",["weather"]),
            ("雨がふり",["weather"]),("雨が降り",["weather"]),
            ("日差しが強",["weather"]),("ひざしがつよ",["weather"]),
            ("こんらん",["visible_volatile"]),("みがわり",["visible_volatile"]),
            ("ちょうはつ",["visible_volatile"]),("アンコール",["visible_volatile"]),
            ("かなしばり",["visible_volatile"]),("ほろびのうた",["visible_volatile"])
        ]
        for (word,fields) in mapping where text.contains(word) {
            for f in fields where !result.contains(f) {result.append(f)}
        }
        if ["まひ","やけど","ねむり","こおり","もうどく","どく"].contains(text) {
            result.append("major_status")
        }
        return result.sorted()
    }
    private static func rectIsValid(_ roi:[String:Any])->Bool {
        guard let x=roi["x"] as? Double,let y=roi["y"] as? Double,
              let w=roi["width"] as? Double,let h=roi["height"] as? Double,
              [x,y,w,h].allSatisfy({$0.isFinite}),x>=0,y>=0,w>0,h>0,
              x+w<=1.000001,y+h<=1.000001 else {return false}
        return true
    }
    static func make(frame:Int64,epoch:Int64,observedMs:Int64,imageSHA:String,
                     ocr:[String:Any])->[String:Any] {
        let ok=frame>0 && epoch>0 && observedMs>0 && validSHA(imageSHA)
            && ocr["image_sha256"] as? String == imageSHA
            && ocr["schema"] as? String == "trueplan.r551.rotation-ocr-evidence.v1"
            && ocr["mega_certified"] as? Bool == false
            && ocr["visual_form_certified"] as? Bool == false
            && ocr["own_opponent"] as? String == "UNKNOWN"
        let evidence=ocr["orientation_evidence"] as? [[String:Any]] ?? []
        let structurallyValid=evidence.count<=4 && evidence.allSatisfy {
            guard let angle=$0["orientation_degrees"] as? Int else {return false}
            return allowedRotations.contains(angle)
        } && Set(evidence.compactMap{$0["orientation_degrees"] as? Int}).count==evidence.count
        let accepted=ok && structurallyValid
        var rows=[[String:Any]]()
        var rejected=0,ambiguous=0
        if accepted {
            for group in evidence {
                guard group["status"] as? String == "OCR_CANDIDATES_ONLY",
                      let degrees=group["orientation_degrees"] as? Int,
                      let observations=group["observations"] as? [[String:Any]] else {continue}
                for (i,observation) in observations.prefix(250).enumerated() {
                    guard rows.count < maxIndexedObservations else {break}
                    guard let rect=observation["roi"] as? [String:Any],rectIsValid(rect),
                          let candidates=observation["candidates"] as? [[String:Any]],
                          !candidates.isEmpty,candidates.count<=3 else {rejected+=1;continue}
                    let texts=candidates.compactMap { candidate -> String? in
                        guard let text=candidate["text"] as? String,!text.isEmpty,
                              text.utf8.count<=256,
                              let c=candidate["confidence"] as? Double,c.isFinite,
                              (0...1).contains(c) else{return nil}
                        return text
                    }
                    guard texts.count==candidates.count else {rejected+=1;continue}
                    let labels=texts.map{domains($0)}
                    let first=labels[0]
                    let same=labels.dropFirst().allSatisfy{$0==first}
                    if !same {ambiguous+=1}
                    rows.append(["ref":"rotation_\(degrees).observations[\(i)]",
                                 "rotation_degrees":degrees,
                                 "roi":rect,"primary_text":String(texts[0].prefix(128)),
                                 "candidate_count":texts.count,
                                 "provisional_domains":same ? first : [],
                                 "status":same ? "UNBOUND_TEXT_CANDIDATE" : "HOLD_ALTERNATIVE_DOMAIN_CONFLICT",
                                 "source_image_sha256":imageSHA,
                                 "owner":"UNKNOWN","game_turn":NSNull(),
                                 "visual_mega_certified":false])
                }
            }
        }
        let possibleObservations=evidence.reduce(0) { sum,group in
            guard accepted,group["status"] as? String == "OCR_CANDIDATES_ONLY",
                  let items=group["observations"] as? [[String:Any]] else{return sum}
            return sum+min(250,items.count)
        }
        let trackMap:[(String,[String])] = R581ReadabilityCoverage.tracks
        let fields:[[String:Any]]=trackMap.map { field in
            let refs=rows.filter {row in
                let labels=row["provisional_domains"] as? [String] ?? []
                return labels.contains(where:{field.1.contains($0)})
            }.compactMap{$0["ref"] as? String}
            return ["field":field.0,"status":refs.isEmpty ? "UNKNOWN" : "OCR_CANDIDATE_UNBOUND",
                    "candidate_refs":Array(refs.prefix(maxRefsPerField)),
                    "candidate_count":refs.count,
                    "owner_verified":false,"game_turn_verified":false,
                    "current_state_eligible":false]
        }
        return ["schema":schema,"image_sha256":validSHA(imageSHA) ? imageSHA as Any : NSNull(),
                "frame_id":frame,"epoch":epoch,"observed_ms_monotonic":observedMs,
                "source_binding_valid":accepted,"status":accepted ? "HISTORICAL_OCR_INDEX_ONLY" : "HOLD_BAD_SOURCE_OR_ORIENTATION",
                "source":"EXISTING_4_ROTATION_VISION_OCR_NO_EXTRA_REQUEST",
                "indexed_observations":rows.count,"rejected_observations":rejected,
                "ambiguous_variant_observations":ambiguous,"observations":rows,
                "truncated_by_limit":possibleObservations>maxIndexedObservations,
                "field_count":fields.count,"fields":fields,
                "fields_with_candidate_text":fields.filter{$0["status"] as? String == "OCR_CANDIDATE_UNBOUND"}.count,
                "owner_certified":false,"turn_certified":false,
                "mega_visual_form_certified":false,"actual_game_accuracy_certified":false,
                "current_state_eligible":false,"battle_advice_authorized":false,
                "automatic_upload":false]
    }
}
