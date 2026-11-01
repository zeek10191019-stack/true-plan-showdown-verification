import Foundation
import CoreFoundation

/// Audit OCR regions in a captured PNG. Geometry is historical and uncalibrated.
/// Never assign a player/opponent owner or authorize battle advice here.
enum R637GeometryDiagnostics {
    static let schema = "trueplan.r637.geometry-evidence-audit.v1"
    private static let roles = Set([
        "own_hp", "opponent_hp", "own_name", "opponent_name", "move_name", "move_pp"
    ])
    private static func number(_ value: Any?) -> Int? {
        guard let v=value as? NSNumber,CFGetTypeID(v) != CFBooleanGetTypeID(),
            v.doubleValue.isFinite,v.doubleValue >= 0,
            v.doubleValue < Double(Int.max),v.doubleValue == Double(v.intValue)
            else {return nil}
        return v.intValue
    }
    private static func sha(_ value: Any?) -> String? {
        guard let s=value as? String,s.utf8.count==64,
              s.utf8.allSatisfy({(48...57).contains($0) || (97...102).contains($0)}) else {return nil}
        return s
    }
    private static func rect(_ raw: Any, w: Int, h: Int) -> [String:Int]? {
        guard let r=raw as? [String:Any],let x=number(r["x"]),
              let y=number(r["y"]),let width=number(r["width"]),
              let height=number(r["height"]),width>0,height>0,
              x<w,y<h,width<=w-x,height<=h-y else{return nil}
        // Quantized top-left origin 0..10000, explicitly NOT an owner proof.
        return ["x":x*10000/w,"y":y*10000/h,
                "width":width*10000/w,"height":height*10000/h]
    }
    static func enrich(_ doc: inout [String:Any], sourceKind: String) {
        doc["r637_status"]="HOLD_SOURCE_OR_PROFILE_UNVERIFIED"
        guard ["LIVE_RETAINED_FRAME","USER_IMPORTED_PNG_OFFLINE_ONLY"].contains(sourceKind),
              doc["r636_status"] as? String == "TYPED_HYPOTHESES_ONLY_NO_OWNER_PROOF",
              let cov=doc["r581_full_read_coverage"] as? [String:Any],
              cov["source_kind"] as? String == sourceKind,
              cov["r636_schema"] as? String == R636TypedHUDEvidence.schema,
              cov["r636_verified_game_fields"] as? Int == 0,
              let fields=cov["fields"] as? [[String:Any]],fields.count==79,
              let snap=doc["screen_read_state"] as? [String:Any],
              snap["current_state_eligible"] as? Bool == false,
              snap["battle_advice_authorized"] as? Bool == false,
              let hash=sha(snap["image_sha256"]),
              let layout=snap["layout_candidates"] as? [String:Any],
              layout["schema"] as? String == "trueplan.screen-read.layout-candidates.v1",
              layout["status"] as? String == "PROVISIONAL_PROFILE_MATCH_ONLY",
              layout["image_sha256"] as? String == hash,
              layout["capture_session_id"] as? String == snap["capture_session_id"] as? String,
              number(layout["frame_id"]) == number(snap["frame_id"]),
              number(layout["epoch"]) == number(snap["epoch"]),
              layout["current_state_eligible"] as? Bool == false,
              layout["calibration_certified"] as? Bool == false,
              layout["owner_certified"] as? Bool == false,
              layout["roi_coordinate_space"] as? String == "ANALYSIS_PIXELS_TOP_LEFT",
              let w=number(doc["image_width"]),let h=number(doc["image_height"]),
              w>=400,h>=180,w<=8192,h<=8192,
              let all=layout["associations"] as? [[String:Any]],all.count<=48 else {return}
        let kind=layout["profile_id"] as? String ?? "UNKNOWN"
        guard kind=="LEGACY_VERTICAL_MOVES_216_V1" ||
              kind=="LEGACY_VERTICAL_MOVES_216_LEFT_DETAILS_V2" else {return}
        // The typed 79-field catalog is stable; this is only an audit receipt.
        let catalog=Set(fields.compactMap{$0["field"] as? String})
        guard catalog.count==79 else {return}
        var boxes=[[String:Any]](),rejected=0,collision=0
        var refRoles=[String:String]()
        for item in all {
            guard let role=item["role_hint"] as? String,roles.contains(role),
                  item["image_sha256"] as? String == hash,
                  item["capture_session_id"] as? String == snap["capture_session_id"] as? String,
                  number(item["frame_id"]) == number(snap["frame_id"]),
                  number(item["epoch"]) == number(snap["epoch"]),
                  item["verification_status"] as? String == "UNVERIFIED",
                  item["side"] as? String == "UNKNOWN_OWNER",
                  item["current_state_eligible"] as? Bool == false,
                  item["orientation"] as? String == "ANALYSIS_UP_SOURCE_TRANSFORM_UNVERIFIED",
                  item["roi_coordinate_space"] as? String == "ANALYSIS_PIXELS_TOP_LEFT",
                  let refs=item["evidence_refs"] as? [String],refs.count<=4,
                  let rois=item["rois"] as? [[String:Any]],rois.count==refs.count,
                  Set(refs).count==refs.count,
                  refs.allSatisfy({!$0.isEmpty && $0.utf8.count<=160}) else {
                rejected+=1;continue
            }
            let slot=number(item["slot"])
            if ["move_name","move_pp"].contains(role) {
                if slot == nil || slot!>3 {rejected+=1;continue}
            } else if item["slot"] != nil && !(item["slot"] is NSNull) {
                rejected+=1;continue
            }
            let resolved=rois.compactMap{rect($0,w:w,h:h)}
            if resolved.count != rois.count {rejected+=1;continue}
            for ref in refs {
                if let previous=refRoles[ref], previous != role {collision+=1}
                refRoles[ref]=role
            }
            if resolved.isEmpty {continue}
            boxes.append(["role_hint":role,"slot":slot.map{$0 as Any} ?? NSNull(),
                          "source_refs":refs,"rects_top_left_10000":resolved,
                          "image_sha256":hash,"owner_verified":false,
                          "orientation_verified":false,
                          "status":"PROVISIONAL_IMAGE_GEOMETRY_ONLY"])
        }
        let audit:[String:Any]=[
            "schema":schema,"image_sha256":hash,"source_kind":sourceKind,
            "profile_id":kind,"image_width":w,"image_height":h,
            "rect_origin":"TOP_LEFT_OF_ANALYSIS_PNG",
            "vision_origin":"BOTTOM_LEFT_NORMALIZED_BEFORE_CONVERSION",
            "source_orientation_verified":false,"owner_verified":false,
            "game_fields_certified":0,"battle_advice_authorized":false,
            "geometry_candidates":boxes,"accepted_region_groups":boxes.count,
            "rejected_associations":rejected,"cross_role_ref_collisions":collision,
            "requires_device_calibration":true,
            "status":collision == 0 ? "PROVISIONAL_ROI_AUDIT" :
                "HOLD_SHARED_EVIDENCE_ACROSS_DIFFERENT_ROLES"]
        doc["r637_geometry_audit"]=audit
        doc["r637_status"]=audit["status"]
    }
}
