import Foundation
import CoreFoundation

/// R27.501: constrained, research-only lexical interpretation of actual OCR text.
/// Reads raw_text (not pre-labelled effect keys). Never changes the battle state,
/// declares game mechanics, certifies ROIs, or recommends a move.
final class TP501VisualOCRProbe: @unchecked Sendable {
    static let shared = TP501VisualOCRProbe()
    enum Decision: String { case withheld = "WITHHELD", malformed = "MALFORMED", research = "RESEARCH_ONLY" }
    struct Report {
        let decision: Decision
        let lexicalHits: Int
        let roiQualified: Int
        let corroborated: Int
        let blocked: Int
        let collisions: Int
        let continuityCut: Bool
        var concise: String {
            if decision != .research { return "R501:" + decision.rawValue }
            return "R501文字候補\(lexicalHits)／ROI照合\(roiQualified)／2画面一致\(corroborated)／保留\(blocked)／競合\(collisions)／研究のみ"
        }
    }
    private struct Candidate {
        let value: String
        let frame: Int64
        let time: Int64
        let hash: String
    }
    private struct Hit { let key: String; let value: String; let owner: String }
    private let lock = NSLock()
    private var battle: String?
    private var epoch: Int64?
    private var lastFrame: Int64 = -1
    private var lastTime: Int64 = -1
    private var lastHash: String = ""
    private var prior = [String:Candidate]()

    func reset() { lock.lock(); defer { lock.unlock() }; clear() }
    private func clear() {
        battle=nil; epoch=nil;lastFrame = -1;lastTime = -1;lastHash="";prior.removeAll()
    }
    private static func uint(_ d:[String:Any],_ k:String) -> Int64? {
        guard let n=d[k] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              let v=Int64(n.stringValue),v>=0 else {return nil}
        return v
    }
    /// Deliberately exact, screen-label hypotheses only. Generic move names, percentages,
    /// species with no documented screen context, and inferred timers are unsupported.
    private static func classify(_ raw:String,_ owner:String) -> Hit? {
        guard raw.utf8.count<=80 else {return nil}
        let s=raw.precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of:" ",with:"")
            .replacingOccurrences(of:"\u{3000}",with:"")
        if owner == "FIELD" {
            let labels: [String:(String,String)] = [
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
            guard let (k,v)=labels[s] else {return nil}
            return Hit(key:k,value:v,owner:owner)
        }
        guard owner == "OWN" || owner == "OPP" else {return nil}
        let suffix=owner == "OWN" ? "own":"opp"
        let named:[String:(String,String)] = [
            "メガギャラドス":("mega_"+suffix,"mega:gyarados"),
            "メガグソクムシャ":("mega_"+suffix,"mega:golisopod"),
            "リフレクター発動中":("reflect_"+suffix,"active"),
            "ひかりのかべ発動中":("light_screen_"+suffix,"active"),
            "やけど":("status_"+suffix,"brn"),
            "まひ":("status_"+suffix,"par"),
            "どく":("status_"+suffix,"psn"),
            "もうどく":("status_"+suffix,"tox"),
            "ねむり":("status_"+suffix,"slp"),
            "こおり":("status_"+suffix,"frz")
        ]
        guard let (k,v)=named[s] else {return nil}
        return Hit(key:k,value:v,owner:owner)
    }
    func observe(_ wire:String?,admitted:Bool)->Report {
        lock.lock(); defer {lock.unlock()}
        func result(_ decision:Decision,_ hits:Int=0,_ ok:Int=0,_ matched:Int=0,
                    _ blocked:Int=0,_ collisions:Int=0,_ cut:Bool=false)->Report {
            Report(decision:decision,lexicalHits:hits,roiQualified:ok,
                   corroborated:matched,blocked:blocked,collisions:collisions,continuityCut:cut)
        }
        guard admitted else {clear();return result(.withheld,0,0,0,0,0,true)}
        guard let wire,wire.utf8.count<=1_000_000,
              let bytes=wire.data(using:.utf8),
              let wrapper=try? JSONSerialization.jsonObject(with:bytes) as? [String:Any] else {
            clear(); return result(.malformed,0,0,0,0,0,true)
        }
        var body=wrapper
        if let nested=wrapper["payload_json"] {
            guard let s=nested as? String,s.utf8.count<=1_000_000,
                  let inner=s.data(using:.utf8),
                  let obj=try? JSONSerialization.jsonObject(with:inner) as? [String:Any] else {
                clear();return result(.malformed,0,0,0,0,0,true)
            }
            body=obj
        }
        guard let id=body["battle_id"] as? String,!id.isEmpty,id.utf8.count<=128,
              let ep=Self.uint(body,"epoch"),let fr=Self.uint(body,"frame_id"),
              let ms=Self.uint(body,"observed_at_ms"),
              let sha=body["image_sha256"] as? String,sha.utf8.count==64,
              sha.utf8.allSatisfy({($0>=48 && $0<=57) || ($0>=97 && $0<=102)}),
              let readings=body["readings"] as? [Any],readings.count<=128 else {
            clear();return result(.malformed,0,0,0,0,0,true)
        }
        let changed=battle != nil && (battle != id || epoch != ep)
        if changed {clear()}
        if battle == id && epoch == ep && (fr<=lastFrame || ms<=lastTime || sha==lastHash) {
            prior.removeAll();return result(.withheld,0,0,0,readings.count,0,true)
        }
        let gap=battle == id && epoch == ep && (fr-lastFrame>16 || ms-lastTime>1500)
        if gap {prior.removeAll()}
        battle=id;epoch=ep;lastFrame=fr;lastTime=ms;lastHash=sha
        var hits=0,blocked=0,matched=0,collisions=0
        var current=[String:String]()
        var duplicates=Set<String>()
        for item in readings {
            guard let r=item as? [String:Any],let raw=r["raw_text"] as? String,
                  let owner=r["roi_owner"] as? String,
                  let h=Self.classify(raw,owner) else {
                blocked+=1;continue
            }
            hits+=1
            let expected="VERIFIED_ROI_OWNER_"+h.owner
            guard let reason=r["reason"] as? String,reason==expected,
                  let c=r["confidence"] as? NSNumber,CFGetTypeID(c) != CFBooleanGetTypeID(),
                  c.doubleValue.isFinite,c.doubleValue>=0.92,c.doubleValue<=1.0 else {
                blocked+=1;prior.removeValue(forKey:h.key);duplicates.insert(h.key);continue
            }
            if current[h.key] != nil {duplicates.insert(h.key)} else {current[h.key]=h.value}
        }
        for k in duplicates {current.removeValue(forKey:k);prior.removeValue(forKey:k);collisions+=1}
        for (k,v) in current {
            if let previous=prior[k],previous.value==v,
               previous.frame<fr,fr-previous.frame<=16,
               ms-previous.time<=1500,previous.hash != sha {matched+=1}
            prior[k]=Candidate(value:v,frame:fr,time:ms,hash:sha)
        }
        // No interpolation across blank, uncertain, conflicting or unowned screens.
        prior=prior.filter{current[$0.key] != nil}
        return result(.research,hits,current.count,matched,blocked,collisions,changed || gap)
    }
}
