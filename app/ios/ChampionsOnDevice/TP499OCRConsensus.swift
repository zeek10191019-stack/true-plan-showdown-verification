import Foundation
import CoreFoundation

/// Non-authoritative multi-frame OCR research signal.
/// Never converts OCR readings into verified battle state or legal actions.
final class TP499OCRConsensus: @unchecked Sendable {
    static let shared = TP499OCRConsensus()
    struct Report {
        enum Decision: String { case withheld = "WITHHELD", malformed = "MALFORMED", observed = "RESEARCH_ONLY" }
        let decision: Decision
        let usable: Int
        let corroborated: Int
        let excluded: Int
        let discontinuity: Bool
        var concise: String {
            if decision != .observed { return "R499:" + decision.rawValue }
            return "R499候補\(usable)／複数画面一致\(corroborated)／保留\(excluded)／連続性切断\(discontinuity ? 1 : 0)／研究のみ"
        }
    }
    private struct Candidate {
        let raw: String // transient, in-memory only; never logged or persisted
        let frame: Int64
        let time: Int64
        let run: Int
    }
    private let lock = NSLock()
    private var battle: String?
    private var epoch: Int64?
    private var lastFrame: Int64 = -1
    private var lastTime: Int64 = -1
    private var lastImage: String = ""
    private var candidates: [String: Candidate] = [:]
    private let allowed: Set<String> = ["hp_own","hp_opp","own_hp","opp_hp","pp_own","pp_opp","own_pp","opp_pp"]
    func reset() {
        lock.lock(); defer {lock.unlock()}
        clear()
    }
    private func clear() {
        battle=nil;epoch=nil;lastFrame = -1;lastTime = -1;lastImage="";candidates.removeAll()
    }
    private static func number(_ data:[String:Any], _ key:String) -> Int64? {
        guard let n=data[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              let value=Int64(n.stringValue), value >= 0 else {return nil}
        return value
    }
    private static func valid(_ text:String, key:String) -> Bool {
        let slash=text.split(separator:"/",omittingEmptySubsequences:false)
        guard slash.count==2,
              slash.allSatisfy({!$0.isEmpty && $0.count<=3 && $0.allSatisfy({$0.isASCII && $0.isNumber})}),
              let a=Int(slash[0]),let b=Int(slash[1]),a<=b,b>0 else{return false}
        if key.contains("pp") {return b<=64}
        return b<=999
    }
    /// Inconsistent, stale, unowned or low-confidence OCR is withheld even when its text parses.
    /// Only trusted ROI owner reasons are eligible for *research* corroboration.
    func observe(_ wire:String?,admitted:Bool) -> Report {
        lock.lock();defer{lock.unlock()}
        guard admitted else { clear();return Report(decision:.withheld,usable:0,corroborated:0,excluded:0,discontinuity:true) }
        guard let wire, wire.utf8.count<=1_000_000,
              let raw=wire.data(using:.utf8),
              let wrapper=try? JSONSerialization.jsonObject(with:raw) as? [String:Any]
        else {clear();return Report(decision:.malformed,usable:0,corroborated:0,excluded:0,discontinuity:true)}
        var body=wrapper
        if let nested=wrapper["payload_json"] {
            guard let encoded=nested as? String,encoded.utf8.count<=1_000_000,
                  let inner=encoded.data(using:.utf8),
                  let obj=try? JSONSerialization.jsonObject(with:inner) as? [String:Any]
            else {clear();return Report(decision:.malformed,usable:0,corroborated:0,excluded:0,discontinuity:true)}
            body=obj
        }
        guard let bid=body["battle_id"] as? String,!bid.isEmpty,bid.utf8.count<=128,
              let ep=Self.number(body,"epoch"),let frame=Self.number(body,"frame_id"),
              let at=Self.number(body,"observed_at_ms"),
              let sha=body["image_sha256"] as? String,sha.count==64,
              sha.utf8.allSatisfy({($0>=48 && $0<=57) || ($0>=97 && $0<=102)}),
              let readings=body["readings"] as? [Any],readings.count<=128
        else {clear();return Report(decision:.malformed,usable:0,corroborated:0,excluded:0,discontinuity:true)}
        let changed=(battle != nil && (battle != bid || epoch != ep))
        if changed { clear() }
        if battle == bid && epoch == ep && (frame<=lastFrame || at<=lastTime || sha==lastImage) {
            candidates.removeAll()
            return Report(decision:.withheld,usable:0,corroborated:0,excluded:readings.count,discontinuity:true)
        }
        let gap = battle == bid && epoch == ep && (frame - lastFrame > 16 || at - lastTime > 1500)
        if gap {candidates.removeAll()}
        battle=bid;epoch=ep;lastFrame=frame;lastTime=at;lastImage=sha
        var usable=0,corroborated=0,excluded=0
        var seen=Set<String>()
        for item in readings {
            guard let row=item as? [String:Any],
                  let key=row["key"] as? String,allowed.contains(key),
                  let value=row["raw_text"] as? String,Self.valid(value,key:key),
                  let reason=row["reason"] as? String,
                  let conf=row["confidence"] as? NSNumber,
                  CFGetTypeID(conf) != CFBooleanGetTypeID(),conf.doubleValue.isFinite,
                  conf.doubleValue>=0.90,conf.doubleValue<=1.0 else {
                if let row=item as? [String:Any],let invalidKey=row["key"] as? String {
                    candidates.removeValue(forKey:invalidKey)
                }
                excluded+=1;continue
            }
            let own = key.hasSuffix("own") || key.hasPrefix("own_")
            let expected=own ? "VERIFIED_ROI_OWNER_OWN" : "VERIFIED_ROI_OWNER_OPP"
            guard reason==expected else {
                candidates.removeValue(forKey:key)
                excluded+=1;continue
            }
            seen.insert(key)
            usable+=1
            if let earlier=candidates[key], earlier.raw==value,
               earlier.frame<frame,frame-earlier.frame<=16,at-earlier.time<=1500 {
                let count=earlier.run+1
                if count>=2 {corroborated+=1}
                candidates[key]=Candidate(raw:value,frame:frame,time:at,run:min(count,3))
            } else {candidates[key]=Candidate(raw:value,frame:frame,time:at,run:1)}
        }
        // A missing/failed key breaks consecutive evidence continuity.
        candidates=candidates.filter { seen.contains($0.key) }
        return Report(decision:.observed,usable:usable,corroborated:corroborated,
                      excluded:excluded,discontinuity:changed || gap)
    }
}
