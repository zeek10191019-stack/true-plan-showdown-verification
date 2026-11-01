import Foundation
import CoreFoundation

/// R27.503 research-only spatial/provenance audit.
/// Source-provided ROI owners are assertions, NOT certified geometry.
/// The output never promotes evidence into canonical battle state or legal actions.
final class TP503ROIEvidenceAudit: @unchecked Sendable {
    static let shared = TP503ROIEvidenceAudit()
    enum Decision: String { case withheld = "WITHHELD", malformed = "MALFORMED", research = "RESEARCH_ONLY" }
    struct Report {
        let decision: Decision
        let checked: Int
        let geometricallyValid: Int
        let missingGeometry: Int
        let invalidGeometry: Int
        let collisions: Int
        let ownerConflicts: Int
        let provenanceConflicts: Int
        let unverifiedOwnership: Int
        var concise: String {
            guard decision == .research else { return "R503:" + decision.rawValue }
            return "R503領域\(checked)／座標有効\(geometricallyValid)／座標欠落\(missingGeometry)／範囲外\(invalidGeometry)／重複\(collisions)／帰属矛盾\(ownerConflicts)／証拠不一致\(provenanceConflicts)／帰属未認証\(unverifiedOwnership)／研究のみ"
        }
    }
    private struct Rect {
        let x: Double, y: Double, w: Double, h: Double
        var area: Double {w*h}
        func intersects(_ o:Rect) -> Double {
            let iw = max(0, min(x+w,o.x+o.w)-max(x,o.x))
            let ih = max(0, min(y+h,o.y+o.h)-max(y,o.y))
            return iw*ih
        }
        func overlapRatio(_ o:Rect)->Double {
            let a=intersects(o);return a/max(1.0e-12,min(area,o.area))
        }
    }
    private struct Entry {let rect:Rect;let owner:String}
    private let lock=NSLock()
    private static func integer(_ obj:[String:Any],_ key:String)->Int64? {
        guard let n=obj[key] as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),
              let v=Int64(n.stringValue),v>=0 else {return nil}
        return v
    }
    private static func number(_ obj:[String:Any],_ key:String)->Double? {
        guard let n=obj[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else{return nil}
        let v=n.doubleValue
        return v.isFinite ? v : nil
    }
    private static func isSHA(_ value:Any?)->Bool {
        guard let s=value as? String,s.utf8.count==64 else{return false}
        return s.utf8.allSatisfy {($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)}
    }
    func inspect(_ wire:String?,admitted:Bool)->Report {
        lock.lock();defer{lock.unlock()}
        func make(_ d:Decision,_ n:Int=0,_ valid:Int=0,_ missing:Int=0,_ bad:Int=0,_ overlap:Int=0,_ owner:Int=0,_ provenance:Int=0,_ unverified:Int=0)->Report {
            Report(decision:d,checked:n,geometricallyValid:valid,missingGeometry:missing,invalidGeometry:bad,collisions:overlap,ownerConflicts:owner,provenanceConflicts:provenance,unverifiedOwnership:unverified)
        }
        guard admitted else{return make(.withheld)}
        guard let wire,wire.utf8.count<=1_000_000,let bytes=wire.data(using:.utf8),
              let top=try? JSONSerialization.jsonObject(with:bytes) as? [String:Any] else{return make(.malformed)}
        var body=top
        if let nested=top["payload_json"] {
            guard let s=nested as? String,s.utf8.count<=1_000_000,
                  let data=s.data(using:.utf8),
                  let value=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else{return make(.malformed)}
            body=value
        }
        guard let battle=body["battle_id"] as? String,!battle.isEmpty,battle.utf8.count<=128,
              let epoch=Self.integer(body,"epoch"),
              let frame=Self.integer(body,"frame_id"),
              Self.integer(body,"observed_at_ms") != nil,
              Self.isSHA(body["image_sha256"]),
              let observations=body["readings"] as? [Any],observations.count<=128 else{return make(.malformed)}
        let frameSHA=body["image_sha256"] as! String
        let width=Self.integer(body,"frame_width"),height=Self.integer(body,"frame_height")
        let frameDimensionsOK:Bool = width != nil && height != nil && width!>0 && width!<=8192 && height!>0 && height!<=8192
        var valid=0,missing=0,bad=0,collisions=0,ownerConflict=0,provenance=0,unverified=0
        var accepted=[Entry]()
        for value in observations {
            guard let reading=value as? [String:Any] else {bad+=1;continue}
            // A supplied owner never authenticates the ROI. Certification needs real device pixels.
            let owner=reading["roi_owner"] as? String ?? "UNKNOWN"
            unverified+=1
            if let source=reading["source_frame_id"] {
                if Self.integer(reading,"source_frame_id") != frame {provenance+=1}
                _=source
            }
            if reading["source_epoch"] != nil && Self.integer(reading,"source_epoch") != epoch {provenance+=1}
            if reading["source_image_sha256"] != nil &&
               (!(Self.isSHA(reading["source_image_sha256"])) || (reading["source_image_sha256"] as? String) != frameSHA) {provenance+=1}
            guard let rectValue=reading["roi_rect"] else {missing+=1;continue}
            guard frameDimensionsOK,let r=rectValue as? [String:Any],
                  let x=Self.number(r,"x"),let y=Self.number(r,"y"),
                  let w=Self.number(r,"width"),let h=Self.number(r,"height"),
                  x>=0,y>=0,w>0,h>0,
                  x+w <= Double(width!),y+h <= Double(height!) else {bad+=1;continue}
            let rect=Rect(x:x,y:y,w:w,h:h)
            // Same/overlapping pixels are not independent observations.
            for old in accepted where rect.overlapRatio(old.rect)>0.80 {
                collisions+=1
                if owner != old.owner {ownerConflict+=1}
            }
            accepted.append(Entry(rect:rect,owner:owner));valid+=1
        }
        return make(.research,observations.count,valid,missing,bad,collisions,ownerConflict,provenance,unverified)
    }
}
