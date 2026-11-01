import Foundation
import CoreFoundation

/// R27.513 research-only audit of ROI/HP/PP side claims.
/// A correctly bounded ROI and an OCR key containing 'own' do NOT establish
/// true on-screen ownership. Never use this report for battle decisions.
enum TP513ROIClaimConsistency {
    enum Verdict: String {
        case pngUnverified = "R513_PNG_UNVERIFIED"
        case geometryUnverified = "R513_GEOMETRY_UNVERIFIED"
        case malformed = "R513_WIRE_MALFORMED"
        case contextMismatch = "R513_FRAME_CONTEXT_MISMATCH"
        case analyzed = "R513_ROI_CLAIMS_AUDITED_NOT_CERTIFIED"
    }
    struct Report {
        let verdict: Verdict
        let total: Int
        let nullKey: Int
        let missingROI: Int
        let invalidROI: Int
        let outsideROI: Int
        let staleSource: Int
        let sideConflict: Int
        let unverifiedHint: Int
        let ownerUncertified: Int
        let boundedROI: Int
        let numericText: Int
        var concise: String {
            guard verdict == .analyzed else { return "R513:" + verdict.rawValue }
            return "R513帰属:候補\(total) キー無\(nullKey) 位置無\(missingROI) 壊\(invalidROI) 画外\(outsideROI) 出典違\(staleSource) 側矛盾\(sideConflict) 側未検\(ownerUncertified) 数値\(numericText)"
        }
        var decisionsCertified: Int { 0 }
    }
    private static func uint(_ value: Any?) -> Int? {
        guard let n=value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              let v=Int(n.stringValue), v>=0 else {return nil}
        return v
    }
    private static func unpack(_ wire:String?) -> [String:Any]? {
        guard let wire, wire.utf8.count<=1_000_000, let data=wire.data(using:.utf8),
              let top=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
        else {return nil}
        if !top.keys.contains("payload_json") {return top}
        guard let payload=top["payload_json"] as? String, payload.utf8.count<=1_000_000,
              let innerData=payload.data(using:.utf8),
              let inner=(try? JSONSerialization.jsonObject(with:innerData)) as? [String:Any]
        else {return nil}
        return inner
    }
    private static func sideFromKey(_ key: Any?) -> String? {
        guard let key=key as? String, key.utf8.count<=64 else {return nil}
        let lower=key.lowercased()
        if lower.hasSuffix("_own") {return "OWN"}
        if lower.hasSuffix("_opp") {return "OPP"}
        return nil
    }
    private static func sideFromUnverifiedReason(_ value: Any?) -> String? {
        guard let reason=value as? String else {return nil}
        if reason=="UNVERIFIED_ROI_OWNER_OWN" {return "OWN"}
        if reason=="UNVERIFIED_ROI_OWNER_OPP" {return "OPP"}
        return nil
    }
    private static func digitLike(_ text:Any?) -> Bool {
        guard let s=text as? String, !s.isEmpty, s.utf8.count<=64 else {return false}
        return s.utf8.allSatisfy { ($0>=48 && $0<=57) || $0==47 || $0==37 || $0==32 }
    }
    static func audit(_ wire:String?, actual:TP510PNGGeometryProof.Dimensions?,
                      battleID:String, epoch:Int, frameID:Int64,
                      pngVerified:Bool, geometryVerified:Bool) -> Report {
        func empty(_ verdict:Verdict)->Report {
            Report(verdict:verdict,total:0,nullKey:0,missingROI:0,invalidROI:0,
                   outsideROI:0,staleSource:0,sideConflict:0,unverifiedHint:0,
                   ownerUncertified:0,boundedROI:0,numericText:0)
        }
        guard pngVerified else {return empty(.pngUnverified)}
        guard geometryVerified, let actual, actual.width>0,actual.height>0 else {
            return empty(.geometryUnverified)
        }
        guard let root=unpack(wire), let b=root["battle_id"] as? String,
              let ep=uint(root["epoch"]), let fr=uint(root["frame_id"]),
              let hash=root["image_sha256"] as? String,
              hash.utf8.count==64, let readings=root["readings"] as? [Any],
              readings.count<=256, epoch>=0,frameID>0 else {return empty(.malformed)}
        guard b==battleID,ep==epoch,Int64(fr)==frameID else {return empty(.contextMismatch)}
        var nullKey=0,missingROI=0,invalidROI=0,outsideROI=0,staleSource=0
        var sideConflict=0,unverifiedHint=0,ownerUncertified=0,boundedROI=0,numericText=0
        for item in readings {
            guard let row=item as? [String:Any] else {invalidROI+=1;continue}
            if digitLike(row["raw_text"]) {numericText+=1}
            let keySide=sideFromKey(row["key"])
            if row["key"] == nil || row["key"] is NSNull {nullKey+=1}
            let reasonSide=sideFromUnverifiedReason(row["reason"])
            if reasonSide != nil {unverifiedHint+=1}
            if let keySide, let reasonSide, keySide != reasonSide {sideConflict+=1}
            // Research-only: even concordant key/reason does not prove owner.
            ownerUncertified+=1
            if let epR=row["source_epoch"], uint(epR) != epoch {staleSource+=1;continue}
            if let frR=row["source_frame_id"], uint(frR).map(Int64.init) != frameID {
                staleSource+=1;continue
            }
            if let hashR=row["source_image_sha256"],
               (hashR as? String) != hash {staleSource+=1;continue}
            guard let rectRaw=row["roi_rect"], !(rectRaw is NSNull) else {
                missingROI+=1;continue
            }
            guard let rect=rectRaw as? [String:Any],let x=uint(rect["x"]),
                  let y=uint(rect["y"]),let w=uint(rect["width"]),
                  let h=uint(rect["height"]), w>0,h>0 else {invalidROI+=1;continue}
            guard x<actual.width,y<actual.height,
                  w<=actual.width-x,h<=actual.height-y else {outsideROI+=1;continue}
            boundedROI+=1
        }
        return Report(verdict:.analyzed,total:readings.count,nullKey:nullKey,
                      missingROI:missingROI,invalidROI:invalidROI,outsideROI:outsideROI,
                      staleSource:staleSource,sideConflict:sideConflict,
                      unverifiedHint:unverifiedHint,ownerUncertified:ownerUncertified,
                      boundedROI:boundedROI,numericText:numericText)
    }
}
