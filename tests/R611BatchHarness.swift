import Foundation

enum R548ResearchArchive {
    struct Entry {let name:String;let bytes:Data}
    static let maximumMembers=24
}
enum R598OneButtonFormAttachment {
    static let sample=Data([0x89,0x50,0x4E,0x47,0x00])
    static let sample2=Data([0x89,0x50,0x4E,0x47,0x01])
    static let digest=String(repeating:"a",count:64)
    static let digest2=String(repeating:"b",count:64)
    static func testDigest(_ d:Data)->String {
        if d==sample{return digest}
        if d==sample2{return digest2}
        return "invalid"
    }
}
@main struct R611BatchHarness {
    static func main() throws {
        var n=0
        func check(_ condition:Bool,_ label:String) {
            precondition(condition,label)
            n+=1
            print("PASS_BATCH",label)
        }
        func blob(_ json:[String:Any])->Data {try! JSONSerialization.data(withJSONObject:json)}
        func base()->[R548ResearchArchive.Entry] {
            var r609=[[String:Any]](),r610=[[String:Any]]()
            for frame in [11,12] {
                let sha = frame == 11 ? R598OneButtonFormAttachment.digest : R598OneButtonFormAttachment.digest2
                let fields:[String:Any] = ["epoch":Int64(1),"frame_id":Int64(frame),
                      "archive_png":"f\(frame).png","original_png_sha256":sha,
                      "owner_verified":false,"roi_verified":false,
                      "display_orientation_verified":false,"mega_verified":false,
                      "certified_for_battle":false]
                var a=fields
                a["ocr_observations"]=[
                    ["text":"148/197","confidence":0.90,
                     "rect_norm_bottom_left":["x":0.20,"y":0.60,
                          "width":0.22,"height":0.05]]]
                r609.append(a)
                var b=fields
                b["candidate_count"]=1
                b["unverified_hp_shape_proximity_candidates"]=[
                    ["ocr_index":0,"color_candidate_index":0,
                     "coordinate_hypothesis":"RAW_ROW_FLIPPED_VERTICALLY",
                     "visual_shape":"NUMERIC_FRACTION_SHAPE_UNVERIFIED",
                     "review_priority_score_not_probability":0.8,
                     "verification":"HOLD_HUD_ROLE_AND_COORDINATES_NOT_CALIBRATED"]]
                r610.append(b)
            }
            let r9:[String:Any]=[
                "schema":"trueplan.r609.vision_text_spatial_evidence.v1",
                "status":"HOLD_OCR_AND_SPATIAL_RELATIONS_NOT_CALIBRATED",
                "owner_verified":false,"roi_verified":false,
                "display_orientation_verified":false,"mega_verified":false,
                "certified_for_battle":false,"bindings":r609]
            let r10:[String:Any]=[
                "schema":"trueplan.r610.hud_cross_evidence.v1",
                "status":"HOLD_REVIEW_UNCERTIFIED_HUD_CANDIDATES",
                "owner_verified":false,"roi_verified":false,
                "display_orientation_verified":false,"mega_verified":false,
                "certified_for_battle":false,"bindings":r610]
            return [.init(name:"r609_vision_text_spatial_evidence.json",bytes:blob(r9)),
              .init(name:"r610_hud_cross_evidence_candidates.json",bytes:blob(r10)),
              .init(name:"f11.png",bytes:R598OneButtonFormAttachment.sample),
              .init(name:"f12.png",bytes:R598OneButtonFormAttachment.sample2)]
        }
        func doc(_ entry:R548ResearchArchive.Entry)->[String:Any] {
            try! JSONSerialization.jsonObject(with:entry.bytes) as! [String:Any]
        }
        check(R611TemporalHUDReview.normalizedRawRowRect([
          "rect_norm_bottom_left":["x":0.20,"y":0.60,"width":0.22,"height":0.05]],
          hypothesis:"RAW_ROW_FLIPPED_VERTICALLY" ).map { abs(($0["y"] ?? -1)-0.35)<0.000001 } == true,"bottom_left_flip")
        check(R611TemporalHUDReview.normalizedRawRowRect([
          "rect_norm_bottom_left":["x":0.20,"y":0.60,"width":0.22,"height":0.05]],
          hypothesis:"RAW_ROW_EQUALS_VISION_BOTTOM" ).map { abs(($0["y"] ?? -1)-0.60)<0.000001 } == true,"bottom_left_hypothesis")
        check(R611TemporalHUDReview.normalizedRawRowRect([:],hypothesis:"ANY")==nil,"bad_box_reject")
        let initial=base()
        let result=R611TemporalHUDReview.beforeZip(initial)
        check(result.count==initial.count+1,"r611_report_added")
        let report=doc(result.last!)
        check(report["status"] as? String=="HOLD_UNCERTIFIED_VISUAL_LOCATION_HYPOTHESES","unverified_hypotheses")
        check(report["certified_for_battle"] as? Bool==false,"not_battle_certified")
        let rows=report["bindings"] as! [[String:Any]]
        check(rows.count==2,"two_frames")
        let second=(rows[1]["candidates"] as! [[String:Any]])[0]
        check(second["location_consistent_with_previous_candidate"] as? Bool==true,"temporal_location_only")
        check((report["location_continuity_hypotheses"] as! [[String:Any]]).count==1,"one_temporal_pair")
        var changed=base()
        var wrong=doc(changed[1]);var badRows=wrong["bindings"] as! [[String:Any]]
        badRows[1]["frame_id"]=Int64(13)
        wrong["bindings"]=badRows
        changed[1] = .init(name:changed[1].name,bytes:blob(wrong))
        check(doc(R611TemporalHUDReview.beforeZip(changed).last!)["status"] as? String=="HOLD_FRAME_LINEAGE_OR_ORDER_CONTRADICTION","changed_frame_reject")
        changed=base();wrong=doc(changed[1]);badRows=wrong["bindings"] as! [[String:Any]]
        badRows[1]["original_png_sha256"]=String(repeating:"c",count:64)
        wrong["bindings"]=badRows;changed[1] = .init(name:changed[1].name,bytes:blob(wrong))
        check(doc(R611TemporalHUDReview.beforeZip(changed).last!)["status"] as? String=="HOLD_FRAME_LINEAGE_OR_ORDER_CONTRADICTION","changed_png_reject")
        changed=base();wrong=doc(changed[1]);badRows=wrong["bindings"] as! [[String:Any]]
        var opts=badRows[0]["unverified_hp_shape_proximity_candidates"] as! [[String:Any]]
        opts[0]["visual_shape"]="FAKE_CERTIFIED";badRows[0]["unverified_hp_shape_proximity_candidates"]=opts
        wrong["bindings"]=badRows;changed[1] = .init(name:changed[1].name,bytes:blob(wrong))
        check(doc(R611TemporalHUDReview.beforeZip(changed).last!)["status"] as? String=="HOLD_CANDIDATE_POSITION_OR_SHAPE_CONTRADICTION","false_hp_shape_reject")
        changed=base();wrong=doc(changed[1]);wrong["owner_verified"]=true
        changed[1] = .init(name:changed[1].name,bytes:blob(wrong))
        check(doc(R611TemporalHUDReview.beforeZip(changed).last!)["status"] as? String=="HOLD_UPSTREAM_MISSING_OR_INVALID","false_owner_cert_reject")
        let once=R611TemporalHUDReview.beforeZip(initial)
        check(R611TemporalHUDReview.beforeZip(once).count==once.count,"r611_duplicate_guard")
        // A status receipt must still be emitted when image/other source is missing.
        check(doc(R611TemporalHUDReview.beforeZip([]).last!)["status"] as? String=="HOLD_UPSTREAM_MISSING_OR_INVALID","missing_input_hold")
        let closure=R612ArchiveEvidenceClosure.beforeZip(once)
        check(closure.count==once.count+1,"r612_closure_added")
        check(doc(closure.last!)["status"] as? String=="HOLD_MISSING_OR_INVALID_RESEARCH_EVIDENCE","missing_r608_hold")
        check(doc(closure.last!)["certified_for_battle"] as? Bool==false,"closure_no_cert")
        check(R612ArchiveEvidenceClosure.beforeZip(closure).count==closure.count,"closure_duplicate_guard")
        check(R612ArchiveEvidenceClosure.beforeZip([]).count==1,"empty_closure_hold_added")
        print("R611_R612_BATCH_STANDALONE_CHECKS=\(n)_NO_GAME_CERTIFICATION")
    }
}
