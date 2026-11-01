import Foundation
import CoreFoundation

/// Research-only, shareable evidence packet. Never carries OCR text, screenshots,
/// identifiers for people, or a decision-ready side assignment.
/// Its purpose is to make device ROI calibration failures reproducible in Chat.
enum TP514ROIAuditExport {
    enum Verdict: String {
        case ready = "R514_REDACTED_PACKET_READY_UNCERTIFIED"
        case blocked = "R514_FRAME_OR_PNG_EVIDENCE_NOT_VERIFIED"
        case malformed = "R514_WIRE_UNPARSABLE"
    }
    struct Packet {
        let verdict: Verdict
        let json: String
        let exported: Int
        let total: Int
        let outside: Int
        let missing: Int
        var concise: String {
            "R514診断JSON:" + verdict.rawValue + " 件数\(exported)/\(total) 座標無\(missing) 画外\(outside) 帰属未認証"
        }
        var ownerCertified: Bool { false }
        var decisionEligible: Bool { false }
    }
    private static func number(_ value: Any?) -> Int? {
        guard let n=value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              let v=Int(n.stringValue),v>=0 else { return nil }
        return v
    }
    private static func object(_ text: String?) -> [String:Any]? {
        guard let text,text.utf8.count<=1_000_000,let data=text.data(using:.utf8),
              let outer=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
        else { return nil }
        guard outer.keys.contains("payload_json") else { return outer }
        guard let inner=outer["payload_json"] as? String,inner.utf8.count<=1_000_000,
              let data=inner.data(using:.utf8),
              let result=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
        else { return nil }
        return result
    }
    private static func category(_ key: Any?) -> String {
        guard let s=key as? String,s.utf8.count<=64 else{return "UNKNOWN"}
        let k=s.lowercased()
        if k.hasPrefix("hp_") || k=="hp" {return "HP"}
        if k.hasPrefix("pp_") || k=="pp" {return "PP"}
        return "UNKNOWN"
    }
    private static func claim(_ key: Any?, _ reason: Any?) -> String {
        guard let s=key as? String,s.utf8.count<=64 else {
            if let reason=reason as? String {
                if reason=="UNVERIFIED_ROI_OWNER_OWN" {return "OWN_HINT_ONLY"}
                if reason=="UNVERIFIED_ROI_OWNER_OPP" {return "OPP_HINT_ONLY"}
            }
            return "UNKNOWN"
        }
        let lower=s.lowercased()
        if lower.hasSuffix("_own") {return "OWN_KEY_CLAIM"}
        if lower.hasSuffix("_opp") {return "OPP_KEY_CLAIM"}
        return "UNKNOWN"
    }
    private static func serialize(_ data:[String:Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(data),
              let bytes=try? JSONSerialization.data(withJSONObject:data,options:[.sortedKeys]),
              bytes.count<=12_000 else{return nil}
        return String(data:bytes,encoding:.utf8)
    }
    static func create(_ wire:String?, audit:TP513ROIClaimConsistency.Report,
                       actual:TP510PNGGeometryProof.Dimensions?,
                       battleID:String,epoch:Int,frameID:Int64,
                       pngVerified:Bool) -> Packet {
        func fail(_ why:Verdict) -> Packet {
            let payload:[String:Any] = ["schema":"R514_REDACTED_V1", "status":why.rawValue,
                                      "ocr_text_included":false,"owner_certified":false,
                                      "decision_eligible":false]
            return Packet(verdict:why,json:serialize(payload) ?? "{}",exported:0,
                          total:0,outside:0,missing:0)
        }
        guard pngVerified,audit.verdict == .analyzed,let actual,
              actual.width>0,actual.height>0,epoch>=0,frameID>0
        else{return fail(.blocked)}
        guard let root=object(wire),let id=root["battle_id"] as? String,
              id==battleID,number(root["epoch"])==epoch,
              number(root["frame_id"]).map(Int64.init)==frameID,
              let sha=root["image_sha256"] as? String,sha.count==64,
              let readings=root["readings"] as? [[String:Any]],readings.count<=256
        else {return fail(.malformed)}
        var exported=[[String:Any]](),missing=0,outside=0
        for (index,row) in readings.enumerated() {
            let c=claim(row["key"],row["reason"])
            var type="missing", rect:[Int]=[]
            let sourceE=row["source_epoch"] == nil || number(row["source_epoch"])==epoch
            let sourceF=row["source_frame_id"] == nil || number(row["source_frame_id"]).map(Int64.init)==frameID
            let sourceH=row["source_image_sha256"] == nil || (row["source_image_sha256"] as? String)==sha
            if !(sourceE && sourceF && sourceH) {type="source_mismatch"}
            else if let raw=row["roi_rect"] as? [String:Any] {
                if let x=number(raw["x"]),let y=number(raw["y"]),
                   let w=number(raw["width"]),let h=number(raw["height"]),w>0,h>0 {
                    // Never use x+w; subtraction prevents overflow.
                    type=(x<actual.width && y<actual.height && w<=actual.width-x && h<=actual.height-y) ? "inside" : "outside"
                    if type=="outside" {outside+=1}
                    rect=[x,y,w,h]
                } else {type="invalid"}
            } else {missing+=1}
            if exported.count<10 {
                exported.append(["i":index,"kind":category(row["key"]),
                                 "claim_only":c,"roi_state":type,"rect_xywh":rect,
                                 "owner_certified":false])
            }
        }
        let data:[String:Any]=["schema":"R514_REDACTED_V1","status":Verdict.ready.rawValue,
                               "frame_id":frameID,"epoch":epoch,
                               "capture_width":actual.width,"capture_height":actual.height,
                               "readings_total":readings.count,"exported":exported,
                               "truncated":readings.count>exported.count,
                               "missing_roi_total":missing,"outside_roi_total":outside,
                               "ocr_text_included":false,"image_bytes_included":false,
                               "owner_certified":false,"decision_eligible":false]
        guard let json=serialize(data) else{return fail(.malformed)}
        return Packet(verdict:.ready,json:json,exported:exported.count,total:readings.count,
                      outside:outside,missing:missing)
    }
}
