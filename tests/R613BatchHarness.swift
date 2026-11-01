import Foundation

enum R548ResearchArchive {
    struct Entry {let name:String;let bytes:Data}
    static let maximumMembers=24
}
enum R598OneButtonFormAttachment {
    static let png1=Data([1,2,3,4,5]);static let png2=Data([5,4,3,2,1])
    static let sha1=String(repeating:"a",count:64);static let sha2=String(repeating:"b",count:64)
    static func testDigest(_ d:Data)->String {
        d==png1 ? sha1 : (d==png2 ? sha2 : String(repeating:"f",count:64))
    }
}
@main struct R613BatchHarness {
    static func main() throws {
        var count=0
        func check(_ condition:Bool,_ text:String) {
            precondition(condition,text);count += 1;print("PASS_R613",text)
        }
        func blob(_ obj:[String:Any])->Data {try! JSONSerialization.data(withJSONObject:obj)}
        func obj(_ item:R548ResearchArchive.Entry)->[String:Any] {
            try! JSONSerialization.jsonObject(with:item.bytes) as! [String:Any]
        }
        let baseFlags:[String:Any]=[
            "certified_for_battle":false,"owner_verified":false,"roi_verified":false,
            "mega_verified":false,"display_orientation_verified":false]
        func complete() -> [R548ResearchArchive.Entry] {
            var raw=[[String:Any]](),text=[[String:Any]](),cross=[[String:Any]]()
            var entries=[R548ResearchArchive.Entry]()
            for frame in [11,12] {
                let sha=frame==11 ? R598OneButtonFormAttachment.sha1 : R598OneButtonFormAttachment.sha2
                let png=frame==11 ? R598OneButtonFormAttachment.png1 : R598OneButtonFormAttachment.png2
                let name="f\(frame).png"
                entries.append(.init(name:name,bytes:png))
                var id=baseFlags
                id["epoch"]=Int64(2);id["frame_id"]=Int64(frame)
                id["original_png_sha256"]=sha;id["archive_png"]=name
                var p=id;p["unverified_region_candidates"]=[[String:Any]]()
                raw.append(p)
                var t=id
                t["ocr_observations"]=[
                  ["text":"148/197","confidence":0.9,
                   "rect_norm_bottom_left":["x":0.2,"y":0.6,"width":0.2,"height":0.05]]]
                text.append(t)
                var c=id;c["candidate_count"]=1
                c["unverified_hp_shape_proximity_candidates"]=[
                  ["ocr_index":0,"color_candidate_index":0,
                   "coordinate_hypothesis":"RAW_ROW_FLIPPED_VERTICALLY",
                   "visual_shape":"NUMERIC_FRACTION_SHAPE_UNVERIFIED",
                   "review_priority_score_not_probability":0.8,
                   "verification":"HOLD_HUD_ROLE_AND_COORDINATES_NOT_CALIBRATED"]]
                cross.append(c)
            }
            func report(_ schema:String,_ status:String,_ data:[[String:Any]]) -> [String:Any] {
                var d=baseFlags;d["schema"]=schema;d["status"]=status;d["bindings"]=data
                return d
            }
            entries.append(.init(name:R613R616IntegratedReadiness.sourceNames[0],
                 bytes:blob(report("trueplan.r608.raw_png_visual_evidence.v1",
                                   "HOLD_VISUAL_OWNER_ROI_AND_ORIENTATION_UNCERTIFIED",raw))))
            entries.append(.init(name:R613R616IntegratedReadiness.sourceNames[1],
                 bytes:blob(report("trueplan.r609.vision_text_spatial_evidence.v1",
                                   "HOLD_OCR_AND_SPATIAL_RELATIONS_NOT_CALIBRATED",text))))
            entries.append(.init(name:R613R616IntegratedReadiness.sourceNames[2],
                 bytes:blob(report("trueplan.r610.hud_cross_evidence.v1",
                                   "HOLD_REVIEW_UNCERTIFIED_HUD_CANDIDATES",cross))))
            entries=R611TemporalHUDReview.beforeZip(entries)
            entries=R612ArchiveEvidenceClosure.beforeZip(entries)
            return entries
        }
        // Strict original frame/SHA/receipt and OCR geometry checks.
        var sample=complete()
        check(sample.count==7,"five_evidence_members_plus_two_png")
        check(obj(sample[sample.count-2])["status"] as? String ==
              "HOLD_UNCERTIFIED_VISUAL_LOCATION_HYPOTHESES","r611_chain_accepted")
        check(obj(sample.last!)["status"] as? String ==
              "HOLD_COMPLETE_UNCERTIFIED_RESEARCH_RECEIPTS","r612_chain_accepted")
        var out=R613R616IntegratedReadiness.beforeZip(sample)
        check(out.count==sample.count+1,"one_new_report_only")
        var result=obj(out.last!)
        check(result["status"] as? String == "HOLD_NEEDS_LABELED_UI_CALIBRATION","explicit_hold")
        check(result["owner_verified"] as? Bool==false,"owner_not_certified")
        check(result["mega_verified"] as? Bool==false,"mega_not_certified")
        check(result["display_orientation_verified"] as? Bool==false,"orientation_not_certified")
        let rows=result["frame_rows"] as! [[String:Any]]
        check(rows.count==2,"both_frames_recorded")
        check(rows[0]["role_assignment"] as? String == "UNKNOWN_UNTIL_GAME_UI_CALIBRATED","not_role_identity")
        let r615=result["r615_own_opponent_role"] as! [String:Any]
        check(r615["requires_ground_truth"] as? Bool==true,"calibration_required")
        check(R613R616IntegratedReadiness.beforeZip(out).count==out.count,"duplicate_report_guard")
        let empty=R613R616IntegratedReadiness.beforeZip([])
        check(obj(empty.last!)["status"] as? String == "HOLD_SOURCE_MISSING_OR_CONTRADICTORY","empty_fail_closed")
        // tamper PNG bytes while leaving prior evidence intact
        sample=complete()
        sample[0] = .init(name:sample[0].name,bytes:Data([1,2,3,4,6]))
        out=R613R616IntegratedReadiness.beforeZip(sample);result=obj(out.last!)
        check(result["status"] as? String == "HOLD_FRAME_OR_IMAGE_LINEAGE_CONTRADICTION","png_tamper_rejected")
        // tamper receipt digest
        sample=complete();var closure=obj(sample.last!)
        var receipts=closure["checked_members"] as! [[String:Any]]
        receipts[0]["sha256"]=String(repeating:"0",count:64)
        closure["checked_members"]=receipts
        sample[sample.count-1] = .init(name:sample.last!.name,bytes:blob(closure))
        check(obj(R613R616IntegratedReadiness.beforeZip(sample).last!)["status"] as? String == 
              "HOLD_SOURCE_MISSING_OR_CONTRADICTORY","receipt_tamper_rejected")
        // injected false owner certification
        sample=complete();var own=obj(sample[3]);own["owner_verified"]=true
        sample[3] = .init(name:sample[3].name,bytes:blob(own))
        check(obj(R613R616IntegratedReadiness.beforeZip(sample).last!)["status"] as? String == 
              "HOLD_SOURCE_MISSING_OR_CONTRADICTORY","false_ownership_rejected")
        // alteration of coordinate hypothesis rect in R611 receipt
        sample=complete()
        var r611=obj(sample[sample.count-2]);var rr=r611["bindings"] as! [[String:Any]]
        var cs=rr[0]["candidates"] as! [[String:Any]]
        cs[0]["uncertified_raw_row_rect"]=["x":0.99,"y":0.20,"width":0.2,"height":0.05]
        rr[0]["candidates"]=cs;r611["bindings"]=rr
        sample[sample.count-2] = .init(name:sample[sample.count-2].name,bytes:blob(r611))
        // receipt must update too; otherwise the R612 guard alone correctly rejects
        let alteredStatus=obj(R613R616IntegratedReadiness.beforeZip(sample).last!)["status"] as? String
        print("R616_ALTERED_RECEIPT_STATUS",alteredStatus ?? "MISSING")
        check(alteredStatus != "HOLD_NEEDS_LABELED_UI_CALIBRATION" &&
              (alteredStatus?.hasPrefix("HOLD_") == true),"altered_rect_unsigned_receipt_rejected")
        // Same-length altered rectangle can pass an unsigned byte-count receipt;
        // the independent geometry recomputation still rejects it.
        sample=complete()
        var altered=obj(sample[sample.count-2])
        var bindings=altered["bindings"] as! [[String:Any]]
        var candidates=bindings[0]["candidates"] as! [[String:Any]]
        candidates[0]["uncertified_raw_row_rect"]=["x":0.9,"y":0.35,"width":0.2,"height":0.05]
        bindings[0]["candidates"]=candidates
        altered["bindings"]=bindings
        let alteredBytes=blob(altered)
        // If the serialized size changes, update the unsigned length receipt
        // to exercise geometry verification rather than just size checking.
        sample[sample.count-2] = .init(name:sample[sample.count-2].name,bytes:alteredBytes)
        var meta=obj(sample.last!)
        var recorded=meta["checked_members"] as! [[String:Any]]
        for idx in recorded.indices where recorded[idx]["archive_member"] as? String ==
                "r611_temporal_hud_review.json" {
            recorded[idx]["byte_count"]=alteredBytes.count
            recorded[idx]["sha256"]=R598OneButtonFormAttachment.testDigest(alteredBytes)
        }
        meta["checked_members"]=recorded
        sample[sample.count-1] = .init(name:sample.last!.name,bytes:blob(meta))
        let geometryStatus=obj(R613R616IntegratedReadiness.beforeZip(sample).last!)["status"] as? String
        check(geometryStatus == "HOLD_OCR_RECT_OR_HYPOTHESIS_CONTRADICTION",
              "independent_geometry_recheck_rejects_unsigned_receipt_tamper")
        // source capacity boundary: must not silently append
        sample=complete()
        for i in 0..<17 {sample.append(.init(name:"unused\(i).json",bytes:Data()))}
        check(sample.count==24,"capacity_fixture_24")
        check(R613R616IntegratedReadiness.beforeZip(sample).count==24,"capacity_no_silent_overflow")
        print("R613_R616_STANDALONE_CHECKS=\(count)_NO_GAME_CERTIFICATION")
    }
}
