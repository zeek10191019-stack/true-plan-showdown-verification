import Foundation
import CoreFoundation
import CryptoKit

/// A selected historical frame is a snapshot, never an implicitly live battle.
/// Text meaning remains provisional. Unverified ROIs cannot populate either side.
enum R551ScreenReadState {
    static let schema = "trueplan.screen-read.snapshot.v1"
    private static let labels: [(String, [String])] = [
        ("weather", ["あめ","雨","すなあらし","ひざしがつよい","はれ","晴れ","ゆき","雪"]),
        ("terrain", ["グラスフィールド","エレキフィールド","サイコフィールド","ミストフィールド"]),
        ("room", ["トリックルーム","マジックルーム","ワンダールーム"]),
        ("screen_or_side_effect", ["リフレクター","ひかりのかべ","オーロラベール","おいかぜ","しんぴのまもり","しろいきり"]),
        ("entry_hazard", ["ステルスロック","まきびし","どくびし","ねばねばネット"]),
        ("major_status", ["やけど","まひ","ねむり","こおり","どく","もうどく"]),
        ("visible_volatile", ["こんらん","みがわり","ちょうはつ","アンコール","かなしばり","あくび","ほろびのうた"]),
        ("mega_text", ["メガシンカ","メガ進化","メガギャラドス","メガグソクムシャ","メガバンギラス"])
    ]
    private static func number(_ value: Any?) -> Int64? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue.isFinite, n.doubleValue >= 0,
              n.doubleValue < Double(Int64.max), n.doubleValue == Double(n.int64Value) else { return nil }
        return n.int64Value
    }
    private static func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private static func validSHA(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func isFalseBoolean(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber,CFGetTypeID(number) == CFBooleanGetTypeID() else {return false}
        return !number.boolValue
    }
    /// Missing legacy declarations inherit only the packet's unverified source.
    /// An explicit declaration must be complete and agree even without an ROI.
    private static func declaredSourceMatches(_ row: [String:Any], frame: Int64,
                                              epoch: Int64, imageSHA: String) -> Bool {
        let keys = ["source_frame_id","source_epoch","source_image_sha256"]
        guard keys.contains(where:{row.keys.contains($0)}) else {return true}
        guard keys.allSatisfy({row.keys.contains($0)}) else {return false}
        func exactInteger(_ value: Any?) -> Int64? {
            guard let n=value as? NSNumber,
                  !["f","d"].contains(String(cString:n.objCType)) else {return nil}
            return number(value)
        }
        return exactInteger(row["source_frame_id"]) == frame &&
            exactInteger(row["source_epoch"]) == epoch && row["source_image_sha256"] as? String == imageSHA
    }
    static func unknownField(_ reason: String) -> [String: Any] {
        ["knowledge_state":"UNKNOWN", "value":NSNull(), "side":"UNKNOWN_OWNER",
         "validity":"NO_CURRENT_EVIDENCE", "verification_status":"UNVERIFIED", "reason":reason]
    }
    private static func sideFields() -> [String: Any] {
        var result = [String: Any]()
        for key in ["active_name","party_slot","remaining_count","hp","max_hp","hp_percent",
                    "status","ability","held_item","mega_form","mega_used","one_time_resource",
                    "reflect","light_screen","aurora_veil","tailwind","entry_hazards"] {
            result[key] = unknownField("OWNER_ROI_AND_CURRENT_STATE_NOT_VERIFIED")
        }
        result["moves"] = (0..<4).map { _ in unknownField("MOVE_SLOT_NOT_BOUND") }
        result["pp"] = (0..<4).map { _ in unknownField("PP_SLOT_NOT_BOUND") }
        result["boosts"] = Dictionary(uniqueKeysWithValues:
            ["atk","def","spa","spd","spe","accuracy","evasion"].map { ($0,unknownField("ABSOLUTE_STAGE_NOT_OBSERVED")) })
        return result
    }
    static func make(envelope: String, captureSessionID: String, frame: Int64, epoch: Int64,
                     observedMs: Int64, imageSHA: String, width: Int, height: Int) -> [String: Any] {
        var state: [String: Any] = [
            "schema":schema, "screen_read_engine_version":"r571.snapshot.v1",
            "capture_session_id":captureSessionID, "battle_id":NSNull(),
            "frame_id":frame,"epoch":epoch,"capture_timestamp_ms":NSNull(),
            "receipt_uptime_ms":observedMs,"timestamp_basis":"UNCALIBRATED_HOST_RECEIPT_UPTIME",
            "turn":NSNull(),"orientation":"ANALYSIS_UP_SOURCE_TRANSFORM_UNVERIFIED",
            "image_sha256":imageSHA,"knowledge_state":"UNKNOWN",
            "validity":"HISTORICAL_FRAME_ONLY","stale_deadline_ms":NSNull(),
            "current_state_eligible":false,"battle_advice_authorized":false,
            "own":sideFields(),"opponent":sideFields(),
            "field":Dictionary(uniqueKeysWithValues:["weather","terrain","trick_room","remaining_turns"].map {
                ($0,unknownField("VISIBLE_FIELD_VALUE_NOT_CERTIFIED")) }),
            "screen_kind":"unknown", "screen_kind_verification":"UNVERIFIED",
            "candidates":[[String:Any]](),"conflicts":[[String:Any]](),"source_validation":"HOLD"
        ]
        guard frame > 0,epoch > 0,observedMs > 0,!captureSessionID.isEmpty,
              validSHA(imageSHA),FrameEvidenceExportGate.permitted(width:width,height:height),
              envelope.utf8.count <= 2_000_000,
              let wrapper = try? JSONSerialization.jsonObject(with:Data(envelope.utf8)) as? [String:Any],
              wrapper["schema"] as? String == "trueplan.mobile-envelope.v1",
              let payload = wrapper["payload_json"] as? String,
              let payloadSHA = wrapper["payload_sha256"] as? String,
              validSHA(payloadSHA),sha(Data(payload.utf8)) == payloadSHA,
              let packet = try? JSONSerialization.jsonObject(with:Data(payload.utf8)) as? [String:Any],
              packet["schema"] as? String == "trueplan.mobile-observation.v1",
              packet["battle_id"] as? String == captureSessionID,
              number(packet["frame_id"]) == frame,number(packet["epoch"]) == epoch,
              number(packet["observed_at_ms"]) == observedMs,
              packet["image_sha256"] as? String == imageSHA,
              isFalseBoolean(packet["production_enabled"]),
              let readings = packet["readings"] as? [[String:Any]],readings.count <= 512 else {
            state["reason"] = "MISSING_OR_MISMATCHED_FRAME_PROVENANCE"
            return state
        }
        var candidates = [[String:Any]]()
        var omittedScreenRefs = [String]()
        var sites = [R553LayoutReading.Site]()
        for (index,row) in readings.enumerated() {
            guard row["reason"] as? String == "FULL_FRAME_TEXT_OWNER_AND_TURN_UNBOUND" else {continue}
            guard declaredSourceMatches(row,frame:frame,epoch:epoch,imageSHA:imageSHA) else {
                state["reason"] = "OCR_ROW_SOURCE_CONFLICT"
                return state
            }
            guard let variants = R553OCRAlternatives.expand(row) else {
                state["reason"] = "MALFORMED_OCR_ALTERNATIVES"
                return state
            }
            var roi: Any = NSNull()
            if number(row["source_frame_id"]) == frame,number(row["source_epoch"]) == epoch,
               row["source_image_sha256"] as? String == imageSHA,
               let rect = row["roi_rect"] as? [String:Any],
               let x=number(rect["x"]),let y=number(rect["y"]),
               let w=number(rect["width"]),let h=number(rect["height"]),
               x < Int64(width),y < Int64(height),w > 0,h > 0,
               w <= Int64(width)-x,h <= Int64(height)-y {
                roi = ["x":x,"y":y,"width":w,"height":h]
            }
            if roi is NSNull {omittedScreenRefs.append("payload_json.readings[\(index)]")}
            for variant in variants {
                let raw = variant.text
                let normalized = R552StateValues.normalized(raw)
                if let rect = roi as? [String:Int64] {
                    sites.append(R553LayoutReading.Site(reading:index,rank:variant.rank,text:raw,
                        confidence:variant.confidence,reference:variant.reference(reading:index),roi:rect))
                }
                for domain in domains(normalized) {
                    candidates.append([
                        "domain":domain,"value":literalValue(normalized,domain:domain),
                        "knowledge_state":"INFERRED","raw_text":raw,"normalized_text":normalized,
                        "side":"UNKNOWN_OWNER","battle_id":NSNull(),"capture_session_id":captureSessionID,
                        "frame_id":frame,"epoch":epoch,"turn":NSNull(),
                        "capture_timestamp_ms":NSNull(),"receipt_uptime_ms":observedMs,
                        "orientation":"ANALYSIS_UP_SOURCE_TRANSFORM_UNVERIFIED",
                        "image_sha256":imageSHA,"roi":roi,"roi_coordinate_space":"ANALYSIS_PIXELS_TOP_LEFT",
                        "confidence":variant.confidence.map {$0 as Any} ?? NSNull(),"source":"VISION_OCR_TEXT_CANDIDATE",
                        "evidence_ref":variant.reference(reading:index),"ocr_rank":variant.rank,
                        "validity":"HISTORICAL_FRAME_ONLY","stale_deadline_ms":NSNull(),
                        "verification_status":"UNVERIFIED","current_state_eligible":false
                    ])
                }
            }
        }
        // Complete OCR token index, including arbitrary move-name strings.
        // Not owned and never authoritative for the live battle.
        state["ocr_source_inventory"] = Array(sites.prefix(288)).map { item in
            ["evidence_ref":item.reference,"raw_text":item.text,
             "roi":item.roi,"image_sha256":imageSHA,
             "capture_session_id":captureSessionID,
             "frame_id":frame,"epoch":epoch,
             "owner_verified":false] as [String:Any]
        }
        state["source_validation"] = "PASS_FRAME_BINDING_ONLY"
        state["reason"] = "OCR_MEANING_OWNER_AND_GAME_STATE_UNVERIFIED"
        state["candidates"] = candidates
        let conflicts = R552StateValues.conflicts(candidates)
        state["conflicts"] = conflicts
        let screenEvidence=R557ScreenEvidence.report(sites:sites,omitted:omittedScreenRefs,declared:packet["screen_kind"],
            session:captureSessionID,frame:frame,epoch:epoch,imageSHA:imageSHA,observedMs:observedMs)
        state["screen_classification"]=screenEvidence
        let screenKind=screenEvidence["screen_kind"] as? String ?? "unknown"
        let layout = R553LayoutReading.inspect(sites:sites,width:width,height:height,screenKind:screenKind,
            session:captureSessionID,frame:frame,epoch:epoch,imageSHA:imageSHA,observedMs:observedMs,allowDetailsOverlay:true)
        state["layout_candidates"] = layout
        let positionHints=R564OwnerHintFence.report(layout:layout,session:captureSessionID,
            frame:frame,epoch:epoch,imageSHA:imageSHA,width:width,height:height)
        state["owner_position_hints"] = R565SourceEvidenceFence.report(base:positionHints,sites:sites,
            session:captureSessionID,frame:frame,epoch:epoch,imageSHA:imageSHA)
        if !conflicts.isEmpty || (layout["conflict_count"] as? Int ?? 0)>0 || R557ScreenEvidence.isConflict(screenEvidence) {
            state["knowledge_state"] = "CONFLICT"
            state["reason"] = "CONFLICTING_OCR_INTERPRETATIONS_NO_CURRENT_VALUE_ADOPTED"
        }
        state["screen_kind"] = screenKind
        return state
    }
    static func domains(_ text: String) -> [String] {
        let raw = R552StateValues.normalized(text)
        let compact = raw.replacingOccurrences(of:" ",with:"")
        var result = [String]()
        if raw.range(of:#"^(?:HP|PP)?\s*[0-9]{1,4}\s*/\s*[0-9]{1,4}$"#,options:.regularExpression) != nil {
            let value = compact.replacingOccurrences(of:"HP",with:"").replacingOccurrences(of:"PP",with:"")
            let pair = value.split(separator:"/").compactMap {Int($0)}
            if pair.count == 2,pair[1] > 0,pair[0] <= pair[1] {
                result.append(compact.hasPrefix("PP") ? "pp" : (compact.hasPrefix("HP") ? "hp" : "hp_or_pp"))
            }
        }
        if compact.range(of:#"^[0-9]{1,3}(\.[0-9]{1,2})?%$"#,options:.regularExpression) != nil,
           let percent = Double(compact.dropLast()),(0...100).contains(percent) {result.append("hp_percent")}
        for (domain,words) in labels where words.contains(where: {
            compact == $0 || (R552StateValues.timedDomains.contains(domain) &&
                compact.range(of:"^"+NSRegularExpression.escapedPattern(for:$0)+#":?(?:あと|残り)?[0-9]{1,2}ターン$"#,options:.regularExpression) != nil)
        }) {result.append(domain)}
        if R552StateValues.absoluteBoost(raw) != nil {result.append("absolute_boost")}
        if R552StateValues.visibleLabel(raw,domain:"visible_ability_label") != nil {result.append("visible_ability_label")}
        if R552StateValues.visibleLabel(raw,domain:"visible_item_label") != nil {result.append("visible_item_label")}
        return result
    }
    private static func literalValue(_ raw: String, domain: String) -> Any {
        if domain == "hp_percent",let value = Double(raw.replacingOccurrences(of:" ",with:"").dropLast()) {return value}
        if domain == "hp" || domain == "pp" || domain == "hp_or_pp" {
            let text=raw.replacingOccurrences(of:" ",with:"").replacingOccurrences(of:"HP",with:"").replacingOccurrences(of:"PP",with:"")
            let pair=text.split(separator:"/").compactMap {Int($0)}
            if pair.count == 2 {return ["current":pair[0],"maximum":pair[1]]}
        }
        return R552StateValues.literal(raw,domain:domain)
    }
    static func displayLines(_ state: [String:Any]) -> [String] {
        guard state["source_validation"] as? String == "PASS_FRAME_BINDING_ONLY" else {
            return ["出典が一致せず、読取結果を採用できません"]
        }
        let candidates = state["candidates"] as? [[String:Any]] ?? []
        let screens = ["unknown":"不明","move_selection_candidate":"技選択",
            "move_selection_with_move_details_overlay_candidate":"技選択と技の説明",
            "normal_command_candidate":"通常コマンド","party_selection_candidate":"選出",
            "party_preview_candidate":"パーティ確認","switch_selection_candidate":"交代先選択",
            "battle_end_candidate":"対戦終了","animation_or_battle_message_candidate":"演出・メッセージ"]
        let domains = ["hp_percent":"HP割合","hp":"HP数値","pp":"残りPP","hp_or_pp":"HPまたはPPの数値",
            "weather":"天候の表示","terrain":"フィールドの表示","room":"場の効果",
            "screen_or_side_effect":"壁・陣営効果","entry_hazard":"設置物","major_status":"状態異常",
            "visible_volatile":"一時状態","mega_text":"メガの文字（発動未確認）","absolute_boost":"能力ランク",
            "visible_ability_label":"表示された特性","visible_item_label":"表示された持ち物"]
        let conflicts = state["conflicts"] as? [[String:Any]] ?? []
        let warning = conflicts.isEmpty ? [] : ["同じ領域の文字候補に\(conflicts.count)件の不一致があります。値の確定を保留します"]
        // New snapshots display typed values only after the source/consensus gate.
        // The layout report remains available in evidence for independent review.
        let layoutLines = state["screen_read_engine_version"] as? String == "r571.snapshot.v1" ? [] :
            (state["layout_candidates"] as? [String:Any]).map {R553LayoutReading.displayLines($0)} ?? []
        let classificationLines=(state["screen_classification"] as? [String:Any]).map {R557ScreenEvidence.displayLines($0)} ?? []
        let ownerLines=(state["owner_position_hints"] as? [String:Any]).map {R565SourceEvidenceFence.displayLines($0)} ?? []
        return classificationLines + layoutLines + ownerLines + ["画面分類候補：\(screens[state["screen_kind"] as? String ?? "unknown"] ?? "不明")",
                "自分・相手・現在値は未確認。以下は選択画像の文字候補です"] + warning +
            candidates.prefix(24).compactMap {
                guard let domain=$0["domain"] as? String,let raw=$0["raw_text"] as? String else {return nil}
                return "\(domains[domain] ?? "文字候補")：\(raw)（帰属不明・未認証）"
            }
    }
}
