import Foundation
enum TP492BattleEffectOCRBridge {
    static let schema = "trueplan.battle-effect-ocr-bridge.v1"
    struct Audit: Codable {
        let schema: String
        let inputValid: Bool
        let battleIDPresent: Bool
        let epoch: Int?
        let frameID: Int?
        let turnVerified: Bool
        let readingCount: Int
        let unkeyedCount: Int
        let unboundReasonCount: Int
        let effectTextHintCounts: [String: Int]
        let verifiedEffectEvents: Int
        let admittedEffects: Int
        let adviceAllowed: Bool
        let reason: String
    }
    private static let lexicon: [(TPResearchEffectDomain, [String])] = [
        (.megaActivation, ["メガシンカ"]),
        (.form, ["メガギャラドス", "メガグソクムシャ"]),
        (.majorStatus, ["まひ", "やけど", "どく", "こおり", "ねむり"]),
        (.weather, ["あめ", "ひざし", "すなあらし", "ゆき", "あられ"]),
        (.terrain, ["エレキフィールド", "グラスフィールド", "ミストフィールド", "サイコフィールド"]),
        (.trickRoom, ["トリックルーム"]),
        (.reflect, ["リフレクター"]),
        (.lightScreen, ["ひかりのかべ"]),
        (.auroraVeil, ["オーロラベール"]),
        (.tailwind, ["おいかぜ"]),
        (.stealthRock, ["ステルスロック"]),
        (.spikes, ["まきびし"]),
        (.toxicSpikes, ["どくびし"]),
        (.stickyWeb, ["ねばねばネット"]),
        (.yawn, ["あくび"]),
        (.leechSeed, ["やどりぎのタネ"]),
        (.substitute, ["みがわり"]),
        (.encore, ["アンコール"]),
        (.taunt, ["ちょうはつ"]),
        (.protect, ["まもる"])
    ]
    static func audit(_ text: String) -> Audit {
        func invalid(_ why: String) -> Audit {
            Audit(schema:schema,inputValid:false,battleIDPresent:false,
                  epoch:nil,frameID:nil,turnVerified:false,
                  readingCount:0,unkeyedCount:0,unboundReasonCount:0,
                  effectTextHintCounts:[:],verifiedEffectEvents:0,
                  admittedEffects:0,adviceAllowed:false,reason:why)
        }
        guard !text.isEmpty, text.utf8.count <= 100_000,
              let topData = text.data(using:.utf8),
              let top = (try? JSONSerialization.jsonObject(with:topData)) as? [String:Any]
        else { return invalid("NO_OR_OVERSIZE_JSON") }
        let payload: [String:Any]
        if let inner = top["payload_json"] as? String {
            guard inner.utf8.count <= 100_000,
                  let innerData=inner.data(using:.utf8),
                  let parsed=(try? JSONSerialization.jsonObject(with:innerData)) as? [String:Any]
            else { return invalid("INVALID_WRAPPED_PAYLOAD") }
            payload=parsed
        } else { payload=top }
        guard let battle=payload["battle_id"] as? String, !battle.isEmpty,
              let epoch=payload["epoch"] as? Int, epoch>=0,
              let frame=payload["frame_id"] as? Int, frame>=0,
              let readings=payload["readings"] as? [[String:Any]], readings.count <= 256
        else { return invalid("INVALID_BATTLE_FRAME_OR_READINGS") }
        let turn=payload["turn"] as? Int
        var textMentions: [String:Int] = [:]
        var noKey=0, unbound=0
        for r in readings {
            if r["key"] == nil || r["key"] is NSNull { noKey += 1 }
            let reason=r["reason"] as? String ?? ""
            if reason.contains("UNBOUND") || reason.contains("UNVERIFIED") || reason.contains("INVALID") {
                unbound += 1
            }
            guard let raw=r["raw_text"] as? String,
                  !raw.isEmpty, raw.utf8.count <= 128 else {continue}
            for (domain, aliases) in lexicon where aliases.contains(where: {raw.contains($0)}) {
                textMentions[domain.rawValue, default: 0] += 1
            }
        }
        return Audit(schema:schema,inputValid:true,battleIDPresent:true,
             epoch:epoch,frameID:frame,turnVerified:turn != nil && turn! >= 0,
             readingCount:readings.count,unkeyedCount:noKey,
             unboundReasonCount:unbound,effectTextHintCounts:textMentions,
             verifiedEffectEvents:0,admittedEffects:0,adviceAllowed:false,
             reason:"RAW_OCR_MENTIONS_NOT_VERIFIED_EVENTS")
    }
    static func display(_ text: String) -> String {
        let a=audit(text)
        guard a.inputValid else {
            return "R492効果候補：観測待ち／Battle State認証なし"
        }
        let fields=a.effectTextHintCounts.keys.sorted().map { code in
            let name=TPResearchEffectDomain(rawValue:code).map {
                TPResearchEffectChannels.label($0)
            } ?? code
            return "\(name)=\(a.effectTextHintCounts[code] ?? 0)"
        }.joined(separator:", ")
        let suffix=fields.isEmpty ? "関連文字候補なし" : fields
        return "R492効果候補：OCR \(a.readingCount)件、未割当 \(a.unkeyedCount)件。\(suffix)。文字の出現≠効果発動・メガ確定。"
    }
}
