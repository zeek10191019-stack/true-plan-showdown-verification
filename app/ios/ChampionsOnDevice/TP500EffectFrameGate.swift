import Foundation
import CoreFoundation

/// R27.500: research-only, fail-closed corroboration of explicitly tagged UI evidence.
/// Does NOT infer effects from pixels, timers, hidden information, or free-form OCR.
/// Does NOT mutate canonical battle state, effect ledger, or action recommendations.
final class TP500EffectFrameGate: @unchecked Sendable {
    static let shared = TP500EffectFrameGate()
    enum Decision: String { case withheld = "WITHHELD", malformed = "MALFORMED", inspected = "RESEARCH_ONLY" }
    struct Report {
        let decision: Decision
        let qualified: Int
        let corroborated: Int
        let rejected: Int
        let conflicted: Int
        let discontinuity: Bool
        var concise: String {
            guard decision == .inspected else { return "R500:" + decision.rawValue }
            return "R500場候補\(qualified)／2画面一致\(corroborated)／拒否\(rejected)／競合\(conflicted)／連続性切断\(discontinuity ? 1 : 0)／研究のみ"
        }
    }
    private struct Candidate {
        let value: String
        let frame: Int64
        let time: Int64
        let imageHash: String
    }
    private let lock = NSLock()
    private var battleID: String?
    private var epoch: Int64?
    private var lastFrame: Int64 = -1
    private var lastTime: Int64 = -1
    private var lastHash = ""
    private var prior: [String:Candidate] = [:]
    private let keys: Set<String> = ["weather", "terrain", "trick_room", "reflect_own", "reflect_opp", "light_screen_own", "light_screen_opp", "status_own", "status_opp", "mega_own", "mega_opp"]
    private let weather: Set<String> = ["sun","rain","snow","sand","none"]
    private let terrain: Set<String> = ["electric","grassy","misty","psychic","none"]
    private let status: Set<String> = ["brn","par","psn","tox","slp","frz","none"]
    func reset() { lock.lock(); defer { lock.unlock() }; clear() }
    private func clear() {
        battleID=nil;epoch=nil;lastFrame = -1;lastTime = -1;lastHash="";prior.removeAll()
    }
    private static func uint(_ d:[String:Any],_ key:String)->Int64? {
        guard let n=d[key] as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),
              let i=Int64(n.stringValue),i>=0 else {return nil}
        return i
    }
    private func valid(_ key:String,_ value:String)->Bool {
        switch key {
        case "weather": return weather.contains(value)
        case "terrain": return terrain.contains(value)
        case "status_own", "status_opp": return status.contains(value)
        case "trick_room", "reflect_own", "reflect_opp", "light_screen_own", "light_screen_opp": return value == "active" || value == "clear"
        case "mega_own", "mega_opp":
            // A permanent evolution *hint*, never a claim that an active Pokémon remains on field.
            guard value.hasPrefix("mega:"), value.utf8.count <= 70 else {return false}
            let suffix=value.dropFirst(5)
            return !suffix.isEmpty && suffix.utf8.allSatisfy { ($0>=97 && $0<=122) || ($0>=48 && $0<=57) || $0==45 }
        default: return false
        }
    }
    private func ownerMatches(_ key:String,_ owner:String)->Bool {
        if key.hasSuffix("_own") { return owner == "OWN" }
        if key.hasSuffix("_opp") { return owner == "OPP" }
        return owner == "FIELD"
    }
    func observe(_ wire: String?, admitted: Bool)->Report {
        lock.lock(); defer {lock.unlock()}
        func result(_ d:Decision,q:Int=0,c:Int=0,r:Int=0,conflict:Int=0,cut:Bool=false)->Report {
            Report(decision:d,qualified:q,corroborated:c,rejected:r,conflicted:conflict,discontinuity:cut)
        }
        guard admitted else { clear();return result(.withheld,cut:true) }
        guard let wire,wire.utf8.count <= 1_000_000,
              let raw=wire.data(using:.utf8),
              let envelope=try? JSONSerialization.jsonObject(with:raw) as? [String:Any] else {
            clear();return result(.malformed,cut:true)
        }
        var body=envelope
        if let encoded=envelope["payload_json"] {
            guard let s=encoded as? String,s.utf8.count <= 1_000_000,
                  let data=s.data(using:.utf8),
                  let nested=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else {
                clear();return result(.malformed,cut:true)
            }
            body=nested
        }
        guard let bid=body["battle_id"] as? String,!bid.isEmpty,bid.utf8.count<=128,
              let ep=Self.uint(body,"epoch"),let fr=Self.uint(body,"frame_id"),
              let ms=Self.uint(body,"observed_at_ms"),
              let sha=body["image_sha256"] as? String,sha.utf8.count==64,
              sha.utf8.allSatisfy({($0>=48 && $0<=57) || ($0>=97 && $0<=102)}),
              let values=body["readings"] as? [Any],values.count<=128 else {
            clear();return result(.malformed,cut:true)
        }
        let switched=battleID != nil && (battleID != bid || epoch != ep)
        if switched {clear()}
        if battleID == bid && epoch == ep && (fr<=lastFrame || ms<=lastTime || sha==lastHash) {
            prior.removeAll()
            return result(.withheld,r:values.count,cut:true)
        }
        let gap=battleID == bid && epoch == ep && (fr-lastFrame>16 || ms-lastTime>1500)
        if gap {prior.removeAll()}
        battleID=bid;epoch=ep;lastFrame=fr;lastTime=ms;lastHash=sha
        var qualified=0,matched=0,rejected=0,conflicted=0
        var unique:[String:String]=[:]
        var duplicate=Set<String>()
        var mentioned=Set<String>()
        // A conflict within one frame is never resolved by choosing first/last OCR candidate.
        for item in values {
            if let row=item as? [String:Any],
               let key=row["key"] as? String,keys.contains(key),
               !mentioned.insert(key).inserted {duplicate.insert(key)}
            guard let row=item as? [String:Any],
                  let key=row["key"] as? String,keys.contains(key),
                  let value=row["raw_text"] as? String,valid(key,value),
                  let provenance=row["reason"] as? String,provenance == "VERIFIED_EFFECT_UI",
                  let owner=row["roi_owner"] as? String,ownerMatches(key,owner),
                  let n=row["confidence"] as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),
                  n.doubleValue.isFinite,n.doubleValue>=0.90,n.doubleValue<=1.0 else {
                if let row=item as? [String:Any],let key=row["key"] as? String {prior.removeValue(forKey:key)}
                rejected+=1;continue
            }
            if unique[key] != nil {duplicate.insert(key)} else {unique[key]=value}
        }
        for key in duplicate {unique.removeValue(forKey:key);prior.removeValue(forKey:key);conflicted+=1}
        for (key,value) in unique {
            qualified+=1
            if let previous=prior[key],previous.value==value,
               previous.frame<fr,fr-previous.frame<=16,ms-previous.time<=1500,
               previous.imageHash != sha {
                matched+=1
            }
            prior[key]=Candidate(value:value,frame:fr,time:ms,imageHash:sha)
        }
        // Missing or rejected readings break consecutive-frame corroboration.
        prior=prior.filter {unique[$0.key] != nil}
        return result(.inspected,q:qualified,c:matched,r:rejected,conflict:conflicted,cut:switched || gap)
    }
}
