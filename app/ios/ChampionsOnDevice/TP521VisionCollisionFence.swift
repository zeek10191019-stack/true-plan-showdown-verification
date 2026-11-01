import Foundation
import CoreFoundation
#if canImport(UIKit) && canImport(Vision)
import UIKit
import Vision
#endif
#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
#endif

/// R521: fail-closed filter for overlapping *research-only* second-pass Vision ROIs.
/// This does not locate a Pokemon, infer OWN/OPP, validate HP/PP, or authorize an action.
enum TP521VisionCollisionFence {
    struct Rect {
        let x:Int; let y:Int; let width:Int; let height:Int
        var area:Int64 { Int64(width)*Int64(height) }
        func valid(_ w:Int,_ h:Int)->Bool {
            width>0 && height>0 && x>=0 && y>=0 && x<w && y<h &&
            width<=w-x && height<=h-y
        }
        func conflicts(_ other:Rect)->Bool {
            let ix=max(0,min(x+width,other.x+other.width)-max(x,other.x))
            let iy=max(0,min(y+height,other.y+other.height)-max(y,other.y))
            let intersection=Int64(ix)*Int64(iy)
            guard intersection>0 else{return false}
            let union=area+other.area-intersection
            let smaller=min(area,other.area)
            // Integer comparisons avoid floating point boundary and rounding drift.
            return intersection*5 >= union*2 || intersection*5 >= smaller*4
        }
    }
    struct Result {
        let wire:String
        let kept:Int
        let rejected:Int
        let reason:String
        var ownerCertified:Bool {false}
        var recognitionCertified:Bool {false}
        var decisionEligible:Bool {false}
    }
    struct Snapshot {
        let attempted:Int; let retained:Int; let removed:Int
        let rejectedFrames:Int; let cleanFrames:Int
        let invalidProof:Int; let inconsistent:Int
        var ownerCertified:Bool {false}
        var decisionEligible:Bool {false}
        var redactedJSON:String {
            let o:[String:Any]=[
                "schema":"R521_VISION_ROI_COLLISION_FENCE_V1",
                "scope":"RESEARCH_ONLY_APP_LIFETIME",
                "audited_frames":attempted,
                "retained_research_rects":retained,
                "removed_research_rects":removed,
                "frames_with_rejections":rejectedFrames,
                "frames_without_rejections":cleanFrames,
                "unverified_frames":invalidProof,
                "inconsistent_rows":inconsistent,
                "owner_certified":false,"recognition_certified":false,
                "decision_eligible":false,
                "ocr_text_included":false,"battle_id_included":false,
                "image_hash_included":false,"image_bytes_included":false
            ]
            guard let data=try? JSONSerialization.data(withJSONObject:o,options:[.sortedKeys]),
                  let s=String(data:data,encoding:.utf8) else {return "{}"}
            return s
        }
    }
    private static let lock=NSLock()
    private static var attempted=0,retained=0,removed=0,rejectedFrames=0
    private static var cleanFrames=0,invalidProof=0,inconsistent=0
    private static let sources:Set<String>=[
        "VISION_SECOND_PASS_EXACT_TEXT_UNCERTIFIED",
        "VISION_FIRST_PASS_GEOMETRY_UNCERTIFIED"
    ]
    private static let roiKeys=["roi_rect","source_epoch","source_frame_id",
                                "source_image_sha256","roi_source","roi_owner_certified"]
    private static func integer(_ value:Any?)->Int? {
        guard let n=value as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),
              let i=Int(n.stringValue),i>=0 else {return nil}
        return i
    }
    private static func hex(_ value:Any?)->String? {
        guard let s=value as? String,s.utf8.count==64,
              s.utf8.allSatisfy({($0>=48 && $0<=57)||($0>=97 && $0<=102)})
        else {return nil}
        return s
    }
    private static func rectangle(_ value:Any?)->Rect? {
        guard let o=value as? [String:Any],
              let x=integer(o["x"]),let y=integer(o["y"]),
              let w=integer(o["width"]),let h=integer(o["height"])
        else {return nil}
        return Rect(x:x,y:y,width:w,height:h)
    }
    static func snapshot()->Snapshot {
        lock.lock();defer{lock.unlock()}
        return Snapshot(attempted:attempted,retained:retained,removed:removed,
                        rejectedFrames:rejectedFrames,cleanFrames:cleanFrames,
                        invalidProof:invalidProof,inconsistent:inconsistent)
    }
    private static func record(kept:Int,removed:Int,failed:Bool,inconsistentRows:Int) {
        lock.lock();defer{lock.unlock()}
        attempted+=1
        retained+=kept;self.removed+=removed
        if removed>0 {rejectedFrames+=1}else{cleanFrames+=1}
        if failed {invalidProof+=1}
        inconsistent+=inconsistentRows
    }
    /// `verifiedPNGHash` MUST come from SHA256 of the physically captured PNG bytes.
    /// This pure function never independently attests the supplied hash.
    static func audit(wire:String,verifiedPNGHash:String?,battleID:String,
                      epoch:Int,frameID:Int64,imageWidth:Int,imageHeight:Int)->Result {
        func fail(_ reason:String)->Result {
            record(kept:0,removed:0,failed:true,inconsistentRows:0)
            return Result(wire:wire,kept:0,rejected:0,reason:reason)
        }
        guard wire.utf8.count<=1_000_000, !battleID.isEmpty,
              (1...16384).contains(imageWidth),(1...16384).contains(imageHeight),
              epoch>=0,frameID>0,let proof=hex(verifiedPNGHash),
              let data=wire.data(using:.utf8),
              var outer=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
        else{return fail("R521_NO_VERIFIED_PNG_OR_INVALID_WIRE")}
        let wrapped=outer.keys.contains("payload_json")
        var body=outer
        if wrapped {
            guard let s=outer["payload_json"] as? String,s.utf8.count<=1_000_000,
                  let d=s.data(using:.utf8),
                  let inner=(try? JSONSerialization.jsonObject(with:d)) as? [String:Any]
            else{return fail("R521_INVALID_WRAPPED_WIRE")}
            body=inner
        }
        guard body["battle_id"] as? String==battleID,
              integer(body["epoch"])==epoch,
              integer(body["frame_id"]).map(Int64.init)==frameID,
              hex(body["image_sha256"])==proof,
              let rawRows=body["readings"] as? [[String:Any]],rawRows.count<=256
        else{return fail("R521_FRAME_OR_IMAGE_PROOF_MISMATCH")}
        var rows=rawRows
        var positions=[Int:Rect](),bad=Set<Int>()
        for i in rows.indices {
            guard let src=rows[i]["roi_source"] as? String,
                  sources.contains(src) else{continue}
            guard rows[i]["roi_owner_certified"] as? Bool == false,
                  integer(rows[i]["source_epoch"])==epoch,
                  integer(rows[i]["source_frame_id"]).map(Int64.init)==frameID,
                  hex(rows[i]["source_image_sha256"])==proof,
                  let r=rectangle(rows[i]["roi_rect"]),
                  r.valid(imageWidth,imageHeight)
            else {bad.insert(i);continue}
            positions[i]=r
        }
        let keys=positions.keys.sorted()
        for i in keys.indices {
            guard i+1<keys.count else{continue}
            for j in i+1..<keys.count {
                let a=keys[i],b=keys[j]
                if positions[a]!.conflicts(positions[b]!) {
                    bad.insert(a);bad.insert(b)
                }
            }
        }
        for i in bad {
            for key in roiKeys {rows[i].removeValue(forKey:key)}
            rows[i]["roi_guard_status"]="RESEARCH_ROI_REJECTED_UNVERIFIED"
        }
        let kept=positions.count-bad.intersection(Set(keys)).count
        let rejected=bad.count
        if rejected>0 {
            body["readings"]=rows
            if wrapped {
                guard JSONSerialization.isValidJSONObject(body),
                      let d=try? JSONSerialization.data(withJSONObject:body,options:[.sortedKeys]),
                      let s=String(data:d,encoding:.utf8) else{return fail("R521_ENCODING_FAILED")}
                // Any modified envelope must carry the SHA of its modified payload.
                guard let payloadHash=TP509CaptureAttestation.sha256Hex(d) else {
                    return fail("R530_PAYLOAD_HASH_RECOMPUTE_FAILED")
                }
                outer["payload_json"]=s
                outer["payload_sha256"]=payloadHash
            } else {outer=body}
            guard JSONSerialization.isValidJSONObject(outer),
                  let data=try? JSONSerialization.data(withJSONObject:outer,options:[.sortedKeys]),
                  data.count<=1_000_000,let value=String(data:data,encoding:.utf8)
            else {return fail("R521_ENCODING_FAILED")}
            record(kept:kept,removed:rejected,failed:false,inconsistentRows:rejected)
            return Result(wire:value,kept:kept,rejected:rejected,reason:"RESEARCH_ROI_COLLISION_OR_PROOF_REJECTED")
        }
        record(kept:kept,removed:0,failed:false,inconsistentRows:0)
        return Result(wire:wire,kept:kept,rejected:0,reason:"RESEARCH_ROI_GEOMETRY_ONLY_UNCERTIFIED")
    }
}

#if canImport(UIKit) && canImport(Vision)
extension TP521VisionCollisionFence {
    /// A research-only wrapper after R520's session fence.
    static func enrich(wire:String,png:Data,battleID:String,epoch:Int,
                       frameID:Int64)->TP517VisionROISidecar.Result {
        let upstream=TP520VisionSessionFence.enrich(wire:wire,png:png,
                    battleID:battleID,epoch:epoch,frameID:frameID)
        guard upstream.added>0,
              let cg=UIImage(data:png)?.cgImage,
              let hash=TP509CaptureAttestation.sha256Hex(png),
              TP509CaptureAttestation.verify(upstream.wire,actualPNGHash:hash,
                battleID:battleID,epoch:epoch,frameID:frameID) == .verified
        else{return upstream}
        let checked=audit(wire:upstream.wire,verifiedPNGHash:hash,
            battleID:battleID,epoch:epoch,frameID:frameID,
            imageWidth:cg.width,imageHeight:cg.height)
        // Only retained research-only rectangles count as new evidence.
        return .init(wire:checked.wire,added:checked.kept,reason:checked.reason)
    }
}
#endif

#if canImport(SwiftUI) && canImport(UIKit)
struct TP521VisionCollisionPanel:View {
    var body:some View {
        TimelineView(.periodic(from:.now,by:1)){ _ in
            let s=TP521VisionCollisionFence.snapshot()
            VStack(alignment:.leading,spacing:4) {
                Text("R27.521｜同一画像ROI重複安全監査")
                    .font(.caption).foregroundColor(.orange)
                Text("研究用座標維持 \(s.retained)／矛盾除外 \(s.removed)／判定不可 \(s.invalidProof)")
                    .font(.caption2)
                Text("HP・PP自他帰属、メガ・天候等の認識は未認証")
                    .font(.caption2).foregroundColor(.secondary)
                Button("ROI重複監査JSONをコピー"){
                    UIPasteboard.general.string=s.redactedJSON
                }.font(.caption2)
            }
        }
    }
}
#endif
