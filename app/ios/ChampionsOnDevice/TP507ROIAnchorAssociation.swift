import Foundation
import CoreFoundation

/// R27.507 research-only link between OCR rectangles and frame-scoped geometric anchors.
/// Anchors contained in the wire are NOT independent evidence: no ownership certification,
/// battle-state promotion, opponent inference or gameplay decision is permitted here.
final class TP507ROIAnchorAssociation: @unchecked Sendable {
    static let shared = TP507ROIAnchorAssociation()
    enum Status: String { case withheld = "WITHHELD", malformed = "MALFORMED", research = "RESEARCH_ONLY" }
    struct Rect {
        let x: Double, y: Double, w: Double, h: Double
        var area: Double { w*h }
        var right: Double { x+w }
        var bottom: Double { y+h }
        func inside(_ width: Double, _ height: Double) -> Bool {
            x>=0 && y>=0 && w>0 && h>0 && right<=width && bottom<=height
        }
        func overlapFraction(_ anchor: Rect) -> Double {
            let iw=max(0,min(right,anchor.right)-max(x,anchor.x))
            let ih=max(0,min(bottom,anchor.bottom)-max(y,anchor.y))
            return iw*ih/area
        }
    }
    struct Match { let readingIndex: Int; let anchorName: String; let overlap: Double }
    struct Report {
        let status: Status
        let readings: Int
        let anchors: Int
        let noCalibration: Int
        let invalidCalibration: Int
        let missingProvenance: Int
        let invalidROI: Int
        let unmatched: Int
        let ambiguous: Int
        let ownerConflicts: Int
        let researchMatches: [Match]
        var concise: String {
            guard status == .research else { return "R507:"+status.rawValue }
            return "R507領域研究一致\(researchMatches.count)／較正欠\(noCalibration)／較正矛盾\(invalidCalibration)／出典欠\(missingProvenance)／ROI不正\(invalidROI)／未対応\(unmatched)／候補重複\(ambiguous)／帰属主張矛盾\(ownerConflicts)／実機未認証"
        }
    }
    private let lock=NSLock()
    private static let validAnchorNames: Set<String> = ["OWN_HP","OPP_HP","OWN_PP","OPP_PP","OWN_MEGA","OPP_MEGA","OWN_STATUS","OPP_STATUS","WEATHER","TERRAIN","TRICK_ROOM","OWN_REFLECT","OPP_REFLECT","OWN_LIGHT_SCREEN","OPP_LIGHT_SCREEN"]
    private static func uint(_ dict:[String:Any],_ key:String)->UInt64? {
        guard let value=dict[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              let n=UInt64(value.stringValue) else { return nil }
        return n
    }
    private static func number(_ d:[String:Any],_ key:String)->Double? {
        guard let value=d[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        let n=value.doubleValue
        return n.isFinite && abs(n)<1_000_000 ? n:nil
    }
    private static func rect(_ value:Any?)->Rect? {
        guard let d=value as? [String:Any],let x=number(d,"x"),let y=number(d,"y"),
              let w=number(d,"width"),let h=number(d,"height"),w>0,h>0 else { return nil }
        return Rect(x:x,y:y,w:w,h:h)
    }
    private static func sha(_ value:Any?)->String? {
        guard let s=value as? String,s.utf8.count==64,
              s.utf8.allSatisfy({ ($0>=48 && $0<=57) || ($0>=97 && $0<=102) }) else { return nil }
        return s
    }
    func inspect(_ wire:String?, admitted:Bool, preview:TP506PreviewGeometryFence.Report)->Report {
        lock.lock();defer { lock.unlock() }
        func empty(_ status:Status)->Report { Report(status:status,readings:0,anchors:0,noCalibration:0,
            invalidCalibration:0,missingProvenance:0,invalidROI:0,unmatched:0,ambiguous:0,
            ownerConflicts:0,researchMatches:[]) }
        guard admitted else { return empty(.withheld) }
        guard let wire,wire.utf8.count<=1_000_000, let bytes=wire.data(using:.utf8),
              let top=try? JSONSerialization.jsonObject(with:bytes) as? [String:Any] else { return empty(.malformed) }
        var body=top
        if let wrapped=top["payload_json"] {
            guard let s=wrapped as? String,s.utf8.count<=1_000_000,
                  let b=s.data(using:.utf8),
                  let d=try? JSONSerialization.jsonObject(with:b) as? [String:Any] else { return empty(.malformed) }
            body=d
        }
        guard let battle=body["battle_id"] as? String,!battle.isEmpty,battle.utf8.count<=128,
              let frame=Self.uint(body,"frame_id"),let epoch=Self.uint(body,"epoch"),
              Self.uint(body,"observed_at_ms") != nil,
              let hash=Self.sha(body["image_sha256"]),
              let rows=body["readings"] as? [Any],rows.count<=128 else { return empty(.malformed) }
        let fw=Self.uint(body,"frame_width"),fh=Self.uint(body,"frame_height")
        guard let fw,let fh,fw>0,fh>0,fw<=8192,fh<=8192 else {
            return Report(status:.research,readings:rows.count,anchors:0,noCalibration:rows.count,
                invalidCalibration:0,missingProvenance:0,invalidROI:0,unmatched:0,
                ambiguous:0,ownerConflicts:0,researchMatches:[])
        }
        guard let cal=body["roi_calibration"] as? [String:Any] else {
            return Report(status:.research,readings:rows.count,anchors:0,noCalibration:rows.count,
                invalidCalibration:0,missingProvenance:0,invalidROI:0,unmatched:0,
                ambiguous:0,ownerConflicts:0,researchMatches:[])
        }
        let calMatches=(cal["battle_id"] as? String)==battle &&
            Self.uint(cal,"frame_id")==frame && Self.uint(cal,"epoch")==epoch &&
            Self.sha(cal["image_sha256"])==hash &&
            Self.uint(cal,"frame_width")==fw && Self.uint(cal,"frame_height")==fh &&
            (cal["coordinate_space"] as? String)=="CAPTURE_PIXELS"
        guard calMatches, let rawAnchors=cal["anchors"] as? [Any],
              !rawAnchors.isEmpty,rawAnchors.count<=32 else {
            return Report(status:.research,readings:rows.count,anchors:0,noCalibration:0,
                invalidCalibration:rows.count,missingProvenance:0,invalidROI:0,unmatched:0,
                ambiguous:0,ownerConflicts:0,researchMatches:[])
        }
        var anchors:[(String,Rect)]=[]
        var names=Set<String>()
        for v in rawAnchors {
            guard let a=v as? [String:Any], let name=a["name"] as? String,
                  Self.validAnchorNames.contains(name),!names.contains(name),
                  let rect=Self.rect(a["rect"]),rect.inside(Double(fw),Double(fh)) else {
                return Report(status:.research,readings:rows.count,anchors:0,noCalibration:0,
                    invalidCalibration:rows.count,missingProvenance:0,invalidROI:0,unmatched:0,
                    ambiguous:0,ownerConflicts:0,researchMatches:[])
            }
            names.insert(name);anchors.append((name,rect))
        }
        let previewCandidates=Dictionary(uniqueKeysWithValues:preview.transformCandidates.map { ($0.readingIndex,$0.sourcePixels) })
        var sourceMissing=0,badROI=0,unmatched=0,ambiguous=0,ownerConflict=0
        var matches:[Match]=[]
        for (i,v) in rows.enumerated() {
            guard let row=v as? [String:Any],
                  Self.uint(row,"source_frame_id")==frame,
                  Self.uint(row,"source_epoch")==epoch,
                  Self.sha(row["source_image_sha256"])==hash else { sourceMissing+=1;continue }
            let rect:Rect?
            switch row["roi_coordinate_space"] as? String {
            case "CAPTURE_PIXELS": rect=Self.rect(row["roi_rect"])
            case "PREVIEW_POINTS":
                if let p=previewCandidates[i],preview.status == .research {
                    rect=Rect(x:p.x,y:p.y,w:p.w,h:p.h)
                } else { rect=nil }
            default: rect=nil
            }
            guard let roi=rect,roi.inside(Double(fw),Double(fh)) else { badROI+=1;continue }
            let ranked=anchors.map { ($0.0,roi.overlapFraction($0.1)) }
                .filter { $0.1>=0.75 }.sorted { $0.1>$1.1 }
            guard let best=ranked.first else { unmatched+=1;continue }
            if ranked.count>1 && ranked[1].1>best.1-0.10 { ambiguous+=1;continue }
            // An OCR-asserted owner is never proof. If present and contradictory, withhold.
            if let claim=row["roi_owner"] as? String,
               claim != "UNKNOWN", claim != best.0 { ownerConflict+=1;continue }
            matches.append(Match(readingIndex:i,anchorName:best.0,overlap:best.1))
        }
        return Report(status:.research,readings:rows.count,anchors:anchors.count,
            noCalibration:0,invalidCalibration:0,missingProvenance:sourceMissing,
            invalidROI:badROI,unmatched:unmatched,ambiguous:ambiguous,
            ownerConflicts:ownerConflict,researchMatches:matches)
    }
}
