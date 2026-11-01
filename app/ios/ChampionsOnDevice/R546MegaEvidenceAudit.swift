import Foundation
import CoreFoundation

/// R546: evidence inventory only. Never infer the active Pokemon, mega activation,
/// or an authorised turn action from OCR, a stone, weather, or a change of appearance.
/// This module intentionally does not connect to R525's certified observation ledger:
/// that requires a validated image-event detector and roster/owner binding.
enum R546MegaEvidenceAudit {
    static let schema = "trueplan.r546.mega-evidence-inventory.v1"

    private static func nonnegative(_ v: Any?) -> Int? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue.isFinite, n.doubleValue == Double(n.int64Value),
              n.int64Value >= 0 && n.int64Value <= Int64(Int.max) else { return nil }
        return Int(n.int64Value)
    }

    private static func hint(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count > 0 && value.count <= 128 else { return nil }
        if value == "メガシンカ" || value == "メガ進化" || value.contains("メガシンカした") {
            return "MEGA_ACTIVATION_TEXT_HINT_NOT_EVENT"
        }
        // Displayed names and UI prompts can be seen before or after activation;
        // treating them as a completed event would be unsafe.
        if value.hasPrefix("メガ") && value.count >= 4 {
            return "MEGA_FORM_NAME_TEXT_HINT_NOT_OWNER"
        }
        return nil
    }

    private static func aligned(_ r:[String:Any],frame:Int,epoch:Int,sha:String,
                                width:Int,height:Int) -> Bool {
        guard nonnegative(r["source_frame_id"]) == frame,
              nonnegative(r["source_epoch"]) == epoch,
              r["source_image_sha256"] as? String == sha,
              let source=r["roi_source"] as? String, !source.isEmpty,
              let rect=r["roi_rect"] as? [String:Any],
              let x=nonnegative(rect["x"]),let y=nonnegative(rect["y"]),
              let w=nonnegative(rect["width"]),let h=nonnegative(rect["height"]),
              w>0,h>0,x<width,y<height,w<=width-x,h<=height-y else {return false}
        return true
    }

    static func inspect(_ root:[String:Any],frame:Int64,epoch:Int64) -> [String:Any] {
        var result:[String:Any] = [
            "schema":schema,"source_frame_id":frame,"source_epoch":epoch,
            "status":"NO_SAME_FRAME_OCR", "hint_count":0,
            "source_aligned_hint_count":0,"source_unaligned_hint_count":0,
            "activation_text_hints":0,"form_text_hints":0,
            "r525_ledger_connected":false,
            "mega_visual_detector_certified":false,
            "roster_identity_certified":false,
            "own_opponent_certified":false,
            "mega_activation_certified":false,
            "mega_state":"UNKNOWN",
            "battle_advice_authorized":false,
            "missing_gates":["CERTIFIED_MEGA_VISUAL_OR_EVENT_DETECTOR",
                             "CERTIFIED_OWN_OPP_AND_ROSTER_IDENTITY",
                             "CROSS_FRAME_MEGA_STATE_LEDGER",
                             "ACTUAL_GAME_SCREEN_FIELD_VALIDATION"]
        ]
        guard let env=root["research_candidate_envelope"] as? String,
              env.utf8.count <= 100_000, !env.isEmpty,
              let wrapper=try? JSONSerialization.jsonObject(with:Data(env.utf8)) as? [String:Any],
              let wrapped=wrapper["payload_json"] as? String,
              wrapped.utf8.count<=100_000,
              let payload=try? JSONSerialization.jsonObject(with:Data(wrapped.utf8)) as? [String:Any],
              let rows=payload["readings"] as? [[String:Any]],rows.count<=256,
              let f=nonnegative(payload["frame_id"]),Int64(f)==frame,
              let e=nonnegative(payload["epoch"]),Int64(e)==epoch,
              let analysis=root["analysis_image"] as? [String:Any],
              let sha=analysis["png_sha256"] as? String,sha.count==64,
              payload["image_sha256"] as? String == sha,
              let width=nonnegative(analysis["width"]),
              let height=nonnegative(analysis["height"]),
              width>0,height>0,width<=8192,height<=8192 else { return result }
        var count=0,alignedCount=0,unbound=0,activation=0,form=0
        for row in rows {
            guard let raw=row["raw_text"] as? String,
                  let type=hint(raw) else { continue }
            count += 1
            if type == "MEGA_ACTIVATION_TEXT_HINT_NOT_EVENT" { activation += 1 }
            else { form += 1 }
            if aligned(row,frame:f,epoch:e,sha:sha,width:width,height:height) {
                alignedCount += 1
            } else { unbound += 1 }
        }
        result["hint_count"] = count
        result["source_aligned_hint_count"] = alignedCount
        result["source_unaligned_hint_count"] = unbound
        result["activation_text_hints"] = activation
        result["form_text_hints"] = form
        result["status"] = count > 0 ? "MEGA_TEXT_HINTS_ONLY_NOT_CERTIFIED" : "NO_MEGA_TEXT_HITS"
        return result
    }

    static func verifyAttached(_ bytes:Data,frame:Int64,epoch:Int64) -> Bool {
        guard let root=try? JSONSerialization.jsonObject(with:bytes) as? [String:Any],
              let actual=root["r546_mega_evidence_audit"] as? [String:Any],
              actual["battle_advice_authorized"] as? Bool == false,
              actual["mega_visual_detector_certified"] as? Bool == false,
              actual["mega_activation_certified"] as? Bool == false,
              actual["mega_state"] as? String == "UNKNOWN",
              let lhs=try? JSONSerialization.data(withJSONObject:actual,options:[.sortedKeys]),
              let rhs=try? JSONSerialization.data(withJSONObject:inspect(root,frame:frame,epoch:epoch),options:[.sortedKeys])
        else {return false}
        return lhs==rhs
    }
}
