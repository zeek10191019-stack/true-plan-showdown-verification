import Foundation
import CoreFoundation

/// Preserves the provenance and ROI geometry of provisional visual side hints.
/// A layout position is never evidence that proves own/opponent ownership.
/// This gate NEVER writes to battle state, certifies a turn, or authorizes advice.
enum R564OwnerHintFence {
    private static let roles: Set<String> = ["own_hp", "opponent_hp", "own_name", "opponent_name", "move_name", "move_pp"]
    private static func exact(_ value: Any?) -> Int64? {
        guard let number=value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue >= 0,
              number.doubleValue < Double(Int64.max),number.doubleValue==Double(number.int64Value) else {return nil}
        return number.int64Value
    }
    private static func goodSHA(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {(48...57).contains($0) || (97...102).contains($0)}
    }
    private static func rectangle(_ value: Any, width: Int,height: Int) -> [String:Int64]? {
        guard let rect=value as? [String:Any], Set(rect.keys)==Set(["x","y","width","height"]),
              let x=exact(rect["x"]),let y=exact(rect["y"]),
              let w=exact(rect["width"]),let h=exact(rect["height"]),w>0,h>0,
              x<Int64(width),y<Int64(height),w<=Int64(width)-x,h<=Int64(height)-y else {return nil}
        return ["x":x,"y":y,"width":w,"height":h]
    }
    static func report(layout: [String:Any], session: String, frame: Int64, epoch: Int64,
                       imageSHA: String,width: Int,height: Int) -> [String:Any] {
        var result:[String:Any] = ["schema":"trueplan.screen-read.owner-hints.v1",
            "status":"HOLD_LAYOUT_OR_SOURCE_NOT_VERIFIED", "scope":"SINGLE_HISTORICAL_FRAME_HINTS_ONLY",
            "capture_session_id":session,"frame_id":frame,"epoch":epoch,"image_sha256":imageSHA,
            "hints":[[String:Any]](),"owner_certified":false,"current_state_eligible":false,
            "battle_advice_authorized":false,"game_accuracy_certified":false,
            "battle_id":NSNull(),"turn":NSNull()]
        guard !session.isEmpty,session.utf8.count<=128,frame>0,epoch>0,goodSHA(imageSHA),
              width>=400,height>=180,width<=4096,height<=4096,
              layout["schema"] as? String == "trueplan.screen-read.layout-candidates.v1",
              layout["status"] as? String == "PROVISIONAL_PROFILE_MATCH_ONLY",
              layout["capture_session_id"] as? String == session,
              exact(layout["frame_id"]) == frame, exact(layout["epoch"]) == epoch,
              layout["image_sha256"] as? String == imageSHA,
              layout["roi_coordinate_space"] as? String == "ANALYSIS_PIXELS_TOP_LEFT",
              layout["owner_certified"] as? Bool == false,
              layout["current_state_eligible"] as? Bool == false,
              layout["calibration_certified"] as? Bool == false,
              let anchors=layout["anchors"] as? [[String:Any]],
              let rows=layout["associations"] as? [[String:Any]],rows.count<=32 else {return result}
        let anchorRoles=anchors.compactMap {$0["role_hint"] as? String}
        guard Set(anchorRoles).isSuperset(of:["own_hp","opponent_hp","command"]),
              Set(anchorRoles).count==anchorRoles.count else {
            result["status"]="HOLD_MISSING_OR_DUPLICATE_ANCHORS";return result
        }
        var seenRoles=Set<String>(),output=[[String:Any]]()
        for row in rows {
            guard let role=row["role_hint"] as? String,roles.contains(role),
                  exact(row["frame_id"]) == frame,exact(row["epoch"]) == epoch,
                  row["capture_session_id"] as? String == session,
                  row["image_sha256"] as? String == imageSHA,
                  row["side"] as? String == "UNKNOWN_OWNER",
                  row["current_state_eligible"] as? Bool == false,
                  row["verification_status"] as? String == "UNVERIFIED",
                  row["roi_coordinate_space"] as? String == "ANALYSIS_PIXELS_TOP_LEFT",
                  row["battle_id"] is NSNull,row["turn"] is NSNull,
                  let evidence=row["evidence_refs"] as? [String],evidence.count<=32,
                  let rawRects=row["rois"] as? [Any],rawRects.count==evidence.count else {
                result["status"]="HOLD_ASSOCIATION_PROVENANCE_INVALID";return result
            }
            let slot=exact(row["slot"])
            let key=role + ":" + (slot.map {String($0)} ?? "-")
            guard !seenRoles.contains(key),((role=="move_name" || role=="move_pp") == (slot != nil)),
                  slot == nil || (slot!>=0 && slot!<4),
                  Set(evidence).count==evidence.count,
                  evidence.allSatisfy({$0.hasPrefix("payload_json.readings[") && $0.utf8.count<128}) else {
                result["status"]="HOLD_DUPLICATE_OR_MALFORMED_ROLE";return result
            }
            seenRoles.insert(key)
            let rects=rawRects.compactMap {rectangle($0,width:width,height:height)}
            guard rects.count==rawRects.count else {result["status"]="HOLD_ROI_BOUNDS_INVALID";return result}
            let quality=row["knowledge_state"] as? String ?? "UNKNOWN"
            guard ["UNKNOWN","INFERRED","CONFLICT"].contains(quality) else {
                result["status"]="HOLD_UNRECOGNIZED_KNOWLEDGE_STATE";return result
            }
            if quality=="CONFLICT" {result["status"]="HOLD_AMBIGUOUS_OCR_VALUES";return result}
            // Geometry is a suggestion, not a side or species proof.
            if quality=="INFERRED" && !evidence.isEmpty {
                output.append(["role_hint":role,"suggested_side":role.hasPrefix("opponent_") ? "opponent" : "own",
                    "slot":slot.map {$0 as Any} ?? NSNull(),"evidence_refs":evidence,
                    "rois":rects,"knowledge_state":"INFERRED",
                    "verification":"POSITION_ONLY_UNVERIFIED","current_state_eligible":false])
            }
        }
        // An OCR reading cannot be assigned simultaneously to own and opponent HP.
        let own=output.first {$0["role_hint"] as? String == "own_hp"}
        let opp=output.first {$0["role_hint"] as? String == "opponent_hp"}
        if let a=own?["evidence_refs"] as? [String],let b=opp?["evidence_refs"] as? [String],
           !Set(a).isDisjoint(with:Set(b)) {
            result["status"]="HOLD_CROSS_SIDE_EVIDENCE_COLLISION";return result
        }
        result["hints"]=output
        result["status"]="PROVISIONAL_POSITION_HINTS_NO_OWNER_CERTIFICATION"
        return result
    }
    static func displayLines(_ report: [String:Any]) -> [String] {
        let status=report["status"] as? String ?? "HOLD"
        if status.hasPrefix("HOLD") {return ["自分・相手の位置対応を保留：画面証拠の整合性を確認できません"]}
        let count=(report["hints"] as? [[String:Any]])?.count ?? 0
        return ["位置対応候補：\(count)件（自他帰属・メガ発動・現在値は未認証）"]
    }
}
