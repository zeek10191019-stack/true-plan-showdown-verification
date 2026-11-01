import Foundation
import CoreFoundation

/// R543: quantify whether first-pass OCR geometry is actually available in the
/// selected-frame export. This is diagnostic only; geometry does not determine
/// Pokemon side, species, state, turn or an authorized battle action.
enum R543SpatialCoverageAudit {
    static let schema = "trueplan.r543.ocr-spatial-coverage.v1"

    private static func int(_ raw: Any?) -> Int? {
        guard let n=raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue.isFinite, n.doubleValue == Double(n.int64Value),
              n.int64Value >= 0, n.int64Value <= Int64(Int.max) else { return nil }
        return Int(n.int64Value)
    }
    private static func text(_ raw:Any?) -> String? {
        guard let s=raw as? String, !s.isEmpty else {return nil}
        return s
    }
    private static func rect(_ value:Any?, width:Int, height:Int) -> [String:Int]? {
        guard let d=value as? [String:Any],
              let x=int(d["x"]),let y=int(d["y"]),
              let w=int(d["width"]),let h=int(d["height"]),
              w>0,h>0,x<width,y<height,w<=width-x,h<=height-y else {return nil}
        return ["x":x,"y":y,"width":w,"height":h]
    }

    static func inspect(_ root:[String:Any], frame:Int64, epoch:Int64) -> [String:Any] {
        var summary:[String:Any] = [
            "schema":schema, "source_frame_id":frame,"source_epoch":epoch,
            "candidate_present":false,"status":"NO_SAME_FRAME_CANDIDATE",
            "raw_rows":0,"text_rows":0,"geometry_verified_rows":0,
            "geometry_missing_rows":0,"geometry_invalid_rows":0,
            "provenance_mismatch_rows":0,"owner_certified_rows":0,
            "ui_region_hints":[:], "battle_advice_authorized":false,
            "owner_certified":false,"mechanics_certified":false
        ]
        guard let envelope=root["research_candidate_envelope"] as? String else{return summary}
        summary["candidate_present"]=true
        summary["status"]="CANDIDATE_UNPARSEABLE"
        guard let wrapper=try? JSONSerialization.jsonObject(with:Data(envelope.utf8)) as? [String:Any],
              let payload=wrapper["payload_json"] as? String,
              let parsed=try? JSONSerialization.jsonObject(with:Data(payload.utf8)) as? [String:Any],
              let rows=parsed["readings"] as? [[String:Any]], rows.count<=256,
              let candidateFrame=int(parsed["frame_id"]),Int64(candidateFrame)==frame,
              let candidateEpoch=int(parsed["epoch"]),Int64(candidateEpoch)==epoch,
              let analysis=root["analysis_image"] as? [String:Any],
              let width=int(analysis["width"]),let height=int(analysis["height"]),
              width>0,height>0,width<=8192,height<=8192,
              let sourceHash=text(analysis["png_sha256"]),sourceHash.count==64,
              text(parsed["image_sha256"])==sourceHash
        else {return summary}
        var valid=0,missing=0,invalid=0,mismatch=0,uncertified=0,textRows=0
        var regions:[String:Int]=[:]
        for row in rows {
            if text(row["raw_text"]) != nil {textRows += 1}
            guard let rectValue=row["roi_rect"], !(rectValue is NSNull) else {missing += 1; continue}
            guard let box=rect(rectValue,width:width,height:height) else {invalid += 1;continue}
            guard int(row["source_frame_id"]) == candidateFrame,
                  int(row["source_epoch"]) == candidateEpoch,
                  text(row["source_image_sha256"]) == sourceHash,
                  text(row["roi_source"]) != nil else {mismatch += 1;continue}
            valid += 1
            // Pixel position in analysis image, not an own/opponent assertion.
            let x=Double(box["x"]!)+Double(box["width"]!)/2
            let y=Double(box["y"]!)+Double(box["height"]!)/2
            let region = (y < Double(height)/3 ? "TOP" : (y > Double(height)*2/3 ? "BOTTOM":"MIDDLE"))
                + "_" + (x < Double(width)/2 ? "LEFT":"RIGHT")
            regions[region,default:0] += 1
            if row["roi_owner_certified"] as? Bool != true {uncertified += 1}
        }
        summary["status"] = "GEOMETRY_AUDIT_ONLY"
        summary["raw_rows"] = rows.count
        summary["text_rows"] = textRows
        summary["geometry_verified_rows"] = valid
        summary["geometry_missing_rows"] = missing
        summary["geometry_invalid_rows"] = invalid
        summary["provenance_mismatch_rows"] = mismatch
        summary["owner_certified_rows"] = 0 // This tool NEVER certifies an owner.
        summary["roi_owner_uncertified_rows"] = uncertified
        summary["ui_region_hints"] = regions
        return summary
    }

    static func verifyAttached(_ bytes:Data, frame:Int64, epoch:Int64) -> Bool {
        guard let root=try? JSONSerialization.jsonObject(with:bytes) as? [String:Any],
              let audit=root["r543_spatial_coverage"] as? [String:Any],
              audit["battle_advice_authorized"] as? Bool == false,
              audit["owner_certified"] as? Bool == false,
              audit["mechanics_certified"] as? Bool == false else {return false}
        guard let actual=try? JSONSerialization.data(withJSONObject:audit,options:[.sortedKeys]),
              let expected=try? JSONSerialization.data(
                withJSONObject:inspect(root,frame:frame,epoch:epoch),options:[.sortedKeys]) else {return false}
        return actual == expected
    }
}
