import Foundation
import CoreFoundation

/// R27.504 diagnostics, not a resolver. No conclusion here may grant move advice
/// or authenticated own/opponent ownership. Input is research observation wire.
final class TP504EvidenceReadiness: @unchecked Sendable {
    static let shared = TP504EvidenceReadiness()
    enum Status: String { case withheld = "WITHHELD", malformed = "MALFORMED", research = "RESEARCH_ONLY" }
    struct Report {
        let status: Status
        let count: Int
        let missingFrameDimensions: Int
        let missingRect: Int
        let invalidRect: Int
        let missingSourceBinding: Int
        let sourceMismatch: Int
        let unknownKey: Int
        let unverifiedOwner: Int
        let lowConfidence: Int
        let ambiguousReason: Int
        let actionableBlocker: String
        var concise: String {
            guard status == .research else { return "R504:" + status.rawValue }
            return "R504候補\(count)／画面寸法欠\(missingFrameDimensions)／ROI無\(missingRect)／ROI不正\(invalidRect)／出典欠\(missingSourceBinding)／出典矛盾\(sourceMismatch)／項目不明\(unknownKey)／帰属未認証\(unverifiedOwner)／低信頼\(lowConfidence)／理由曖昧\(ambiguousReason)／次:\(actionableBlocker)／研究のみ"
        }
    }
    private let lock = NSLock()
    private static func uint(_ dict:[String:Any], _ key:String) -> UInt64? {
        guard let v=dict[key] as? NSNumber, CFGetTypeID(v) != CFBooleanGetTypeID(),
            let n=UInt64(v.stringValue) else { return nil }
        return n
    }
    private static func double(_ dict:[String:Any], _ key:String) -> Double? {
        guard let v=dict[key] as? NSNumber, CFGetTypeID(v) != CFBooleanGetTypeID() else { return nil }
        let n=v.doubleValue
        return n.isFinite ? n : nil
    }
    private static func sha(_ any:Any?) -> String? {
        guard let s=any as? String, s.utf8.count==64,
              s.utf8.allSatisfy({($0>=48 && $0<=57) || ($0>=97 && $0<=102)}) else {return nil}
        return s
    }
    func inspect(_ wire:String?, admitted:Bool) -> Report {
        lock.lock(); defer {lock.unlock()}
        func empty(_ status:Status) -> Report {
            Report(status:status,count:0,missingFrameDimensions:0,missingRect:0,invalidRect:0,
                missingSourceBinding:0,sourceMismatch:0,unknownKey:0,unverifiedOwner:0,
                lowConfidence:0,ambiguousReason:0,actionableBlocker:"NONE")
        }
        guard admitted else {return empty(.withheld)}
        guard let wire, wire.utf8.count<=1_000_000, let bytes=wire.data(using:.utf8),
              let outer=try? JSONSerialization.jsonObject(with:bytes) as? [String:Any] else {return empty(.malformed)}
        var body=outer
        if let nested=outer["payload_json"] {
            guard let encoded=nested as? String, encoded.utf8.count<=1_000_000,
                  let nestedBytes=encoded.data(using:.utf8),
                  let parsed=try? JSONSerialization.jsonObject(with:nestedBytes) as? [String:Any] else {return empty(.malformed)}
            body=parsed
        }
        guard let battle=body["battle_id"] as? String, !battle.isEmpty, battle.utf8.count<=128,
              let epoch=Self.uint(body,"epoch"), let frame=Self.uint(body,"frame_id"),
              Self.uint(body,"observed_at_ms") != nil,
              let sourceHash=Self.sha(body["image_sha256"]),
              let candidates=body["readings"] as? [Any],candidates.count<=128 else {return empty(.malformed)}
        let width=Self.uint(body,"frame_width")
        let height=Self.uint(body,"frame_height")
        let dimensionsOK = width != nil && height != nil && width!>0 && height!>0 && width!<=8192 && height!<=8192
        var missingRect=0, invalidRect=0, missingSource=0, sourceConflict=0, unknownKey=0, unverifiedOwner=0, lowConfidence=0, ambiguousReason=0
        for candidate in candidates {
            guard let value=candidate as? [String:Any] else {
                invalidRect+=1; missingSource+=1; unknownKey+=1; unverifiedOwner+=1; continue
            }
            let key=value["key"] as? String
            if key == nil || key!.isEmpty || key!.utf8.count>128 {unknownKey+=1}
            // A side label supplied by the OCR stage never authenticates its owner.
            unverifiedOwner+=1
            if let confidence=Self.double(value,"confidence") {
                if confidence<0 || confidence>1 || confidence<0.70 {lowConfidence+=1}
            } else {lowConfidence+=1}
            let reason=value["reason"] as? String ?? ""
            if reason.isEmpty || reason.contains("UNVERIFIED") || reason.contains("AMBIGUOUS") || reason.contains("UNKNOWN") {
                ambiguousReason+=1
            }
            let hasAllSource = value["source_frame_id"] != nil && value["source_epoch"] != nil && value["source_image_sha256"] != nil
            if !hasAllSource {missingSource+=1}
            if (value["source_frame_id"] != nil && Self.uint(value,"source_frame_id") != frame) ||
               (value["source_epoch"] != nil && Self.uint(value,"source_epoch") != epoch) ||
               (value["source_image_sha256"] != nil && Self.sha(value["source_image_sha256"]) != sourceHash) {
                sourceConflict+=1
            }
            if let rawRect=value["roi_rect"] {
                guard dimensionsOK, let rect=rawRect as? [String:Any],
                      let x=Self.double(rect,"x"), let y=Self.double(rect,"y"),
                      let w=Self.double(rect,"width"),let h=Self.double(rect,"height"),
                      x>=0,y>=0,w>0,h>0,x+w<=Double(width!),y+h<=Double(height!) else {
                    invalidRect+=1;continue
                }
            } else {missingRect+=1}
        }
        let missingDims = dimensionsOK ? 0 : 1
        let blocker:String
        if missingDims>0 {blocker="FRAME_SIZE"}
        else if missingRect>0 {blocker="OCR_ROI_COORDS"}
        else if invalidRect>0 {blocker="ROI_GEOMETRY"}
        else if sourceConflict>0 {blocker="SOURCE_MISMATCH"}
        else if missingSource>0 {blocker="SOURCE_BINDING"}
        else if unknownKey>0 {blocker="FIELD_KEY"}
        else if lowConfidence>0 {blocker="OCR_CONFIDENCE"}
        else {blocker="OWNER_CALIBRATION"}
        return Report(status:.research,count:candidates.count,missingFrameDimensions:missingDims,
            missingRect:missingRect,invalidRect:invalidRect,missingSourceBinding:missingSource,
            sourceMismatch:sourceConflict,unknownKey:unknownKey,unverifiedOwner:unverifiedOwner,
            lowConfidence:lowConfidence,ambiguousReason:ambiguousReason,actionableBlocker:blocker)
    }
}
