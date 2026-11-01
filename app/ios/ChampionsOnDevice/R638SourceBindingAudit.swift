import Foundation
import CoreFoundation

/// Bind layout evidence to all raw OCR tokens from the SAME decoded PNG.
/// No semantic, owner, orientation or live-game certification is issued.
enum R638SourceBindingAudit {
    static let schema = "trueplan.r638.full-ocr-layout-binding.v1"
    private static func number(_ a:Any?) -> Int? {
        guard let n=a as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue.isFinite,n.doubleValue >= 0,
              n.doubleValue < Double(Int.max),n.doubleValue == Double(n.intValue)
        else {return nil}
        return n.intValue
    }
    private static func rect(_ a:Any?, w:Int,h:Int) -> [String:Int]? {
        guard let d=a as? [String:Any],let x=number(d["x"]),
              let y=number(d["y"]),let dw=number(d["width"]),
              let dh=number(d["height"]),dw>0,dh>0,
              x<w,y<h,dw<=w-x,dh<=h-y else {return nil}
        return ["x":x*10000/w,"y":y*10000/h,
                "width":dw*10000/w,"height":dh*10000/h]
    }
    static func enrich(_ doc:inout [String:Any],sourceKind:String) {
        doc["r638_status"]="HOLD_SOURCE_INVENTORY_OR_GEOMETRY_MISSING"
        guard ["LIVE_RETAINED_FRAME","USER_IMPORTED_PNG_OFFLINE_ONLY"].contains(sourceKind),
              doc["r637_status"] as? String == "PROVISIONAL_ROI_AUDIT",
              let report=doc["r637_geometry_audit"] as? [String:Any],
              report["schema"] as? String == R637GeometryDiagnostics.schema,
              report["source_kind"] as? String == sourceKind,
              report["owner_verified"] as? Bool == false,
              report["source_orientation_verified"] as? Bool == false,
              number(report["game_fields_certified"]) == 0,
              number(report["cross_role_ref_collisions"]) == 0,
              let boxes=report["geometry_candidates"] as? [[String:Any]],
              boxes.count<=48,
              let snap=doc["screen_read_state"] as? [String:Any],
              snap["current_state_eligible"] as? Bool == false,
              snap["battle_advice_authorized"] as? Bool == false,
              let hash=snap["image_sha256"] as? String,
              hash.utf8.count == 64,report["image_sha256"] as? String == hash,
              let inventory=snap["ocr_source_inventory"] as? [[String:Any]],
              inventory.count<=288,
              let w=number(doc["image_width"]),let h=number(doc["image_height"]),
              (400...8192).contains(w),(180...8192).contains(h),
              let layout=snap["layout_candidates"] as? [String:Any],
              layout["image_sha256"] as? String == hash,
              let groups=layout["associations"] as? [[String:Any]],
              groups.count<=48 else {return}
        // Do not reconstruct the OCR source from semantic-only snapshot candidates:
        // free-form move names often have NO semantic domain classification.
        var index=[String:[String:Any]]()
        for row in inventory {
            guard let ref=row["evidence_ref"] as? String,!ref.isEmpty,
                  ref.utf8.count<=160,index[ref]==nil,
                  let raw=row["raw_text"] as? String,raw.utf8.count<=160,
                  let r=rect(row["roi"],w:w,h:h),
                  row["image_sha256"] as? String == hash,
                  row["capture_session_id"] as? String == snap["capture_session_id"] as? String,
                  number(row["frame_id"]) == number(snap["frame_id"]),
                  number(row["epoch"]) == number(snap["epoch"]),
                  row["owner_verified"] as? Bool == false else {
                doc["r638_status"]="HOLD_INVALID_OR_DUPLICATE_OCR_SOURCE";return
            }
            index[ref]=["raw_text":raw,"rect":r]
        }
        var verified=0, missing=0, mismatch=0, empty=0
        var usedRefs=Set<String>()
        var tagged=[[String:Any]]()
        for box in boxes {
            guard box["image_sha256"] as? String == hash,
                  box["owner_verified"] as? Bool == false,
                  box["orientation_verified"] as? Bool == false,
                  box["status"] as? String == "PROVISIONAL_IMAGE_GEOMETRY_ONLY",
                  let role=box["role_hint"] as? String,
                  let refs=box["source_refs"] as? [String],
                  let rois=box["rects_top_left_10000"] as? [[String:Int]],
                  refs.count==rois.count,refs.count<=4,
                  let group=groups.first(where:{
                    $0["role_hint"] as? String == role &&
                    ($0["slot"] as? Int) == (box["slot"] as? Int)
                  }),
                  groups.filter({
                    $0["role_hint"] as? String == role &&
                    ($0["slot"] as? Int) == (box["slot"] as? Int)
                  }).count == 1,
                  let rawTexts=group["raw_texts"] as? [String],
                  let groupRefs=group["evidence_refs"] as? [String],
                  let groupROIs=group["rois"] as? [[String:Any]],
                  refs == groupRefs,refs.count == rawTexts.count,
                  refs.count == groupROIs.count else {
                doc["r638_status"]="HOLD_GEOMETRY_LAYOUT_CONTRADICTION";return
            }
            for i in refs.indices {
                let ref=refs[i]
                guard usedRefs.insert(ref).inserted else {
                    doc["r638_status"]="HOLD_DUPLICATE_REF_ACROSS_SLOTS";return
                }
                guard let source=index[ref] else {missing+=1;continue}
                guard let candidate=rect(groupROIs[i],w:w,h:h),
                      candidate == rois[i],
                      let authoritative=source["rect"] as? [String:Int],
                      authoritative == rois[i],
                      source["raw_text"] as? String == rawTexts[i] else {
                    mismatch+=1;continue
                }
                verified+=1
            }
            if refs.isEmpty {empty+=1}
            tagged.append(["role_hint":role,"slot":box["slot"] ?? NSNull(),
                           "reference_count":refs.count,"owner_verified":false,
                           "game_value_admitted":false])
        }
        let success=missing==0 && mismatch==0 && verified>0
        let receipt:[String:Any]=[
            "schema":schema,"source_kind":sourceKind,"image_sha256":hash,
            "ocr_inventory_count":inventory.count,"geometry_groups":boxes.count,
            "source_matched_observations":verified,
            "unmatched_source_refs":missing,"mismatched_rect_or_text":mismatch,
            "empty_region_groups":empty,"source_orientation_verified":false,
            "owner_verified":false,"game_fields_certified":0,
            "battle_advice_authorized":false,"groups":tagged,
            "status":success ? "SOURCE_AND_LAYOUT_BOUND_HISTORICAL_ONLY" :
                "HOLD_SOURCE_REFERENCE_OR_TEXT_MISMATCH"]
        doc["r638_binding_audit"]=receipt
        doc["r638_status"]=receipt["status"]
    }
}
