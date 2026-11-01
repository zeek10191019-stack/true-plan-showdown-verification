import Foundation
import CoreFoundation

/// R27.502: compare structured effect hints with constrained OCR text hints.
/// Both originate from the SAME frame and are NOT independent evidence.
/// Research diagnostics only. No canonical state mutation or action recommendation.
final class TP502EffectReconciler: @unchecked Sendable {
    static let shared = TP502EffectReconciler()
    enum Decision: String { case withheld = "WITHHELD", malformed = "MALFORMED", research = "RESEARCH_ONLY" }
    struct Report {
        let decision: Decision
        let structured: Int
        let lexical: Int
        let agreements: Int
        let disagreements: Int
        let tainted: Int
        let unpaired: Int
        var concise: String {
            guard decision == .research else { return "R502:" + decision.rawValue }
            return "R502構造\(structured)／文字\(lexical)／整合\(agreements)／不整合\(disagreements)／汚染\(tainted)／片系\(unpaired)／研究のみ"
        }
    }
    private struct Hint { let key:String; let value:String; let owner:String }
    private let lock=NSLock()
    private let keys:Set<String> = ["weather","terrain","trick_room","mega_own","mega_opp","reflect_own","reflect_opp","light_screen_own","light_screen_opp","status_own","status_opp"]
    private static let fieldLex:[String:(String,String)] = [
        "あめがふっている":("weather","rain"),
        "ひざしがつよい":("weather","sun"),
        "すなあらしがふいている":("weather","sand"),
        "ゆきがふっている":("weather","snow"),
        "エレキフィールド":("terrain","electric"),
        "グラスフィールド":("terrain","grassy"),
        "サイコフィールド":("terrain","psychic"),
        "ミストフィールド":("terrain","misty"),
        "トリックルーム発動中":("trick_room","active")
    ]
    private static let sideLex:[String:(String,String)] = [
        "メガギャラドス":("mega","mega:gyarados"),
        "メガグソクムシャ":("mega","mega:golisopod"),
        "リフレクター発動中":("reflect","active"),
        "ひかりのかべ発動中":("light_screen","active"),
        "やけど":("status","brn"),
        "まひ":("status","par"),
        "どく":("status","psn"),
        "もうどく":("status","tox"),
        "ねむり":("status","slp"),
        "こおり":("status","frz")
    ]
    private static func clean(_ value:String)->String? {
        guard value.utf8.count <= 80 else { return nil }
        return value.precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of:" ",with:"")
            .replacingOccurrences(of:"\u{3000}",with:"")
    }
    private static func lex(_ raw:String,_ owner:String)->Hint? {
        guard let s=clean(raw) else {return nil}
        if let (k,v)=fieldLex[s] { return Hint(key:k,value:v,owner:"FIELD") }
        if let (k,v)=sideLex[s],owner == "OWN" || owner == "OPP" {
            return Hint(key:k+"_"+(owner == "OWN" ? "own":"opp"),value:v,owner:owner)
        }
        return nil
    }
    private static func knownSideWord(_ raw:String)->Bool {
        guard let s=clean(raw) else {return false}
        return sideLex[s] != nil
    }
    private static func expectedOwner(_ key:String)->String {
        if key.hasSuffix("_own") {return "OWN"}
        if key.hasSuffix("_opp") {return "OPP"}
        return "FIELD"
    }
    private static func valid(_ key:String,_ raw:String)->Bool {
        let states:Set<String>=["active","clear"]
        switch key {
        case "weather":return ["rain","sun","snow","sand","none"].contains(raw)
        case "terrain":return ["electric","grassy","psychic","misty","none"].contains(raw)
        case "trick_room","reflect_own","reflect_opp","light_screen_own","light_screen_opp":return states.contains(raw)
        case "status_own","status_opp":return ["brn","par","psn","tox","slp","frz","none"].contains(raw)
        case "mega_own","mega_opp":return ["mega:gyarados","mega:golisopod"].contains(raw)
        default:return false
        }
    }
    private static func number(_ body:[String:Any],_ k:String)->Int64? {
        guard let n=body[k] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              let v=Int64(n.stringValue),v>=0 else{return nil}
        return v
    }
    /// Each qualified source can contribute at most one key. Conflicts taint that key.
    /// Cross-source agreement is informational only: both hints may reflect one OCR error.
    func inspect(_ wire:String?,admitted:Bool)->Report {
        lock.lock();defer{lock.unlock()}
        func report(_ d:Decision,_ st:Int=0,_ le:Int=0,_ a:Int=0,_ diff:Int=0,_ t:Int=0,_ u:Int=0)->Report {
            Report(decision:d,structured:st,lexical:le,agreements:a,disagreements:diff,tainted:t,unpaired:u)
        }
        guard admitted else{return report(.withheld)}
        guard let wire,wire.utf8.count<=1_000_000,let bytes=wire.data(using:.utf8),
              let wrapper=try? JSONSerialization.jsonObject(with:bytes) as? [String:Any] else {return report(.malformed)}
        var body=wrapper
        if let payload=wrapper["payload_json"] {
            guard let str=payload as? String,str.utf8.count<=1_000_000,
                  let inner=str.data(using:.utf8),
                  let obj=try? JSONSerialization.jsonObject(with:inner) as? [String:Any] else {return report(.malformed)}
            body=obj
        }
        guard let battle=body["battle_id"] as? String,!battle.isEmpty,battle.utf8.count<=128,
              Self.number(body,"epoch") != nil,Self.number(body,"frame_id") != nil,
              Self.number(body,"observed_at_ms") != nil,
              let sha=body["image_sha256"] as? String,sha.utf8.count==64,
              sha.utf8.allSatisfy({($0>=48 && $0<=57) || ($0>=97 && $0<=102)}),
              let values=body["readings"] as? [Any],values.count<=128 else {return report(.malformed)}
        var structured=[String:String](),lexical=[String:String]()
        var tainted=Set<String>()
        func collect(_ hint:Hint?,_ dest:inout [String:String],trusted:Bool) {
            guard let hint else{return}
            guard trusted else {tainted.insert(hint.key);return}
            if dest[hint.key] != nil {tainted.insert(hint.key);dest.removeValue(forKey:hint.key)}
            else if !tainted.contains(hint.key){dest[hint.key]=hint.value}
        }
        for value in values {
            guard let r=value as? [String:Any] else {continue}
            let anyKey=r["key"] as? String
            let anyRaw=r["raw_text"] as? String
            let anyOwner=r["roi_owner"] as? String
            guard let raw=anyRaw,let owner=anyOwner,
                  let reason=r["reason"] as? String else {
                if let k=anyKey,keys.contains(k) {tainted.insert(k)}
                if let raw=anyRaw,let cleaned=Self.clean(raw) {
                    if let hint=Self.fieldLex[cleaned] {tainted.insert(hint.0)}
                    if let hint=Self.sideLex[cleaned] {
                        if anyOwner == "OWN" || anyOwner == "OPP" {
                            tainted.insert(hint.0+"_"+(anyOwner == "OWN" ? "own":"opp"))
                        } else {
                            tainted.insert(hint.0+"_own")
                            tainted.insert(hint.0+"_opp")
                        }
                    }
                }
                continue
            }
            let confidence=(r["confidence"] as? NSNumber)
            let good=confidence != nil && CFGetTypeID(confidence!) != CFBooleanGetTypeID() &&
                confidence!.doubleValue.isFinite && confidence!.doubleValue >= 0.95 && confidence!.doubleValue <= 1.0
            if let key=r["key"] as? String, keys.contains(key),
                (reason == "VERIFIED_EFFECT_UI" || reason == "UNVERIFIED_EFFECT_UI" || Self.lex(raw,owner) == nil) {
                collect(Hint(key:key,value:raw,owner:Self.expectedOwner(key)),&structured,
                    trusted:good && reason == "VERIFIED_EFFECT_UI" && owner == Self.expectedOwner(key) && Self.valid(key,raw))
            }
            if let hint=Self.lex(raw,owner) {
                collect(hint,&lexical,trusted:good && reason == "VERIFIED_ROI_OWNER_"+hint.owner && owner == hint.owner)
            } else if Self.knownSideWord(raw) {
                // A mega/status mention with unknown side cannot establish either owner's state.
                for prefix in ["mega_","reflect_","light_screen_","status_"] {
                    let normalized=Self.clean(raw) ?? raw
                    if (prefix == "mega_" && normalized.hasPrefix("メガ")) ||
                        (prefix == "reflect_" && normalized.contains("リフレクター")) ||
                        (prefix == "light_screen_" && normalized.contains("ひかりのかべ")) ||
                        (prefix == "status_" && !normalized.hasPrefix("メガ") && !normalized.contains("リフレクター") && !normalized.contains("ひかりのかべ")) {
                        tainted.insert(prefix+"own");tainted.insert(prefix+"opp")
                    }
                }
            }
        }
        for key in tainted {structured.removeValue(forKey:key);lexical.removeValue(forKey:key)}
        let both=Set(structured.keys).intersection(lexical.keys)
        var agreements=0,disagreements=0
        for key in both {if structured[key] == lexical[key] {agreements+=1}else{disagreements+=1}}
        let unpaired=Set(structured.keys).symmetricDifference(Set(lexical.keys)).count
        return report(.research,structured.count,lexical.count,agreements,disagreements,tainted.count,unpaired)
    }
}
