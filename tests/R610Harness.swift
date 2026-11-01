import Foundation

enum R548ResearchArchive {
    struct Entry {let name:String;let bytes:Data}
    static let maximumMembers=24
}
enum R598OneButtonFormAttachment {
    static let sample=Data([0x89,0x50,0x4e,0x47,0x00])
    static let digest=String(repeating:"a",count:64)
    static func testDigest(_ d:Data)->String {d==sample ? digest : "invalid"}
}
@main struct R610Harness {
    static func main() throws {
        var n=0
        func check(_ v:Bool,_ key:String) {
            precondition(v,key)
            n+=1
            print("PASS_R610",key)
        }
        let sha=R598OneButtonFormAttachment.digest
        let frame:[String:Any]=[
            "epoch":Int64(1),"frame_id":Int64(11),
            "original_png_sha256":sha,"archive_png":"frame11.png",
            "owner_verified":false,"roi_verified":false,
            "display_orientation_verified":false,"frame_identity_verified":false,
            "mega_verified":false,"png_ihdr_crc_verified":true,
            "decoded_pixels_verified":true,
            "unverified_region_candidates":[["x_norm":0.12,"y_norm":0.44,
                "width_norm":0.4,"height_norm":0.02]]
        ]
        let obs:[[String:Any]]=[
            ["text":"148/197","confidence":0.89,
             "rect_norm_bottom_left":["x":0.12,"y":0.40,"width":0.20,"height":0.08]],
            ["text":"81%","confidence":0.92,
             "rect_norm_bottom_left":["x":0.13,"y":0.40,"width":0.15,"height":0.07]],
            ["text":"ほのお","confidence":0.99,
             "rect_norm_bottom_left":["x":0.1,"y":0.40,"width":0.2,"height":0.08]]
        ]
        func relation(_ idx:Int,_ orient:String="RAW_ROW_EQUALS_VISION_BOTTOM") -> [String:Any] {
            ["ocr_index":idx,"color_candidate_index":0,
             "coordinate_hypothesis":orient,
             "spatial_relation":"UNVERIFIED_PROXIMITY_NOT_HUD_BINDING",
             "horizontal_overlap_fraction":idx==2 ? 0.9 : 1.0,
             "vertical_center_delta_normalized":idx==1 ? 0.015 : 0.010]
        }
        var r9=frame
        r9.removeValue(forKey:"png_ihdr_crc_verified")
        r9.removeValue(forKey:"decoded_pixels_verified")
        r9.removeValue(forKey:"unverified_region_candidates")
        r9["ocr_observations"]=obs
        r9["text_color_associations"]=[relation(0),relation(1),relation(2)]
        func run(_ r8:[[String:Any]]=[frame],_ r9s:[[String:Any]]?=nil,
                 includeImage:Bool=true,alterTop:Bool=false)->[String:Any] {
            var a:[String:Any]=[
                "schema":"trueplan.r608.raw_png_visual_evidence.v1",
                "status":"HOLD_VISUAL_OWNER_ROI_AND_ORIENTATION_UNCERTIFIED",
                "certified_for_battle":false,"owner_verified":false,
                "roi_verified":false,"display_orientation_verified":false,
                "frame_identity_verified":false,"mega_verified":false,
                "bindings":r8]
            if alterTop {a["owner_verified"]=true}
            let rows9=r9s ?? [r9]
            let b:[String:Any]=[
                "schema":"trueplan.r609.vision_text_spatial_evidence.v1",
                "status":"HOLD_OCR_AND_SPATIAL_RELATIONS_NOT_CALIBRATED",
                "certified_for_battle":false,"owner_verified":false,
                "roi_verified":false,"display_orientation_verified":false,
                "mega_verified":false,
                "frames_truncated":r8.count>3,
                "bindings":rows9]
            var entries:[R548ResearchArchive.Entry]=[
                .init(name:"r608_original_pixel_evidence.json",bytes:try! JSONSerialization.data(withJSONObject:a)),
                .init(name:"r609_vision_text_spatial_evidence.json",bytes:try! JSONSerialization.data(withJSONObject:b))]
            if includeImage {entries.append(.init(name:"frame11.png",bytes:R598OneButtonFormAttachment.sample))}
            let result=R610CrossEvidenceCandidate.beforeZip(entries)
            check(result.count==entries.count+1,"receipt_added")
            check(result.last!.name==R610CrossEvidenceCandidate.memberName,"receipt_name")
            return try! JSONSerialization.jsonObject(with:result.last!.bytes) as! [String:Any]
        }
        check(R610CrossEvidenceCandidate.visualShape("148/197") != nil,"fraction_shape")
        check(R610CrossEvidenceCandidate.visualShape(" 81 %") != nil,"percent_shape")
        check(R610CrossEvidenceCandidate.visualShape("999/197")==nil,"impossible_hp_fraction_rejected")
        check(R610CrossEvidenceCandidate.visualShape("110%")==nil,"over100_percent_rejected")
        check(R610CrossEvidenceCandidate.visualShape("41/0")==nil,"zero_max_rejected")
        check(R610CrossEvidenceCandidate.visualShape("ほのお")==nil,"nonnumeric_not_hp")
        let good=run()
        check(good["status"] as? String == "HOLD_REVIEW_UNCERTIFIED_HUD_CANDIDATES","only_candidate_status")
        check(good["certified_for_battle"] as? Bool == false,"no_battle_cert")
        let gr=good["bindings"] as! [[String:Any]]
        check(gr.count==1,"one_bound_frame")
        check(gr[0]["owner_verified"] as? Bool == false,"actor_not_verified")
        check(gr[0]["mega_verified"] as? Bool == false,"mega_not_verified")
        let candidates=gr[0]["unverified_hp_shape_proximity_candidates"] as! [[String:Any]]
        check(candidates.count==2,"two_numeric_candidates_no_role")
        check(candidates.allSatisfy{($0["verification"] as? String)=="HOLD_HUD_ROLE_AND_COORDINATES_NOT_CALIBRATED"},"no_roi_claim")
        var bad=r9;bad["frame_id"]=Int64(12)
        let mismatch=run([frame],[bad])
        check(mismatch["status"] as? String == "HOLD_R608_R609_FRAME_OR_COORDINATE_CONTRADICTION","frame_disagreement_rejected")
        var wrong=r9;wrong["original_png_sha256"]=String(repeating:"f",count:64)
        check(run([frame],[wrong])["status"] as? String == "HOLD_R608_R609_FRAME_OR_COORDINATE_CONTRADICTION","sha_disagreement_rejected")
        check(run([frame],[r9],includeImage:false)["status"] as? String == "HOLD_R608_R609_FRAME_OR_COORDINATE_CONTRADICTION","missing_png_rejected")
        check(run([frame],[r9],alterTop:true)["status"] as? String == "HOLD_R608_R609_SOURCE_EVIDENCE_MISSING_OR_INVALID","false_certification_rejected")
        var dup=r9;dup["text_color_associations"]=[relation(0),relation(0)]
        check(run([frame],[dup])["status"] as? String == "HOLD_R608_R609_FRAME_OR_COORDINATE_CONTRADICTION","repeated_relation_rejected")
        dup=r9;dup["text_color_associations"]=[relation(999)]
        check(run([frame],[dup])["status"] as? String == "HOLD_R608_R609_FRAME_OR_COORDINATE_CONTRADICTION","out_of_range_index_rejected")
        dup=r9;dup["text_color_associations"]=[relation(0,"UNSUPPORTED_ORIENTATION")]
        check(run([frame],[dup])["status"] as? String == "HOLD_R608_R609_FRAME_OR_COORDINATE_CONTRADICTION","invalid_orientation_hypothesis_rejected")
        dup=r9;dup["text_color_associations"]=[["ocr_index":0,"color_candidate_index":0,
         "coordinate_hypothesis":"RAW_ROW_EQUALS_VISION_BOTTOM",
         "spatial_relation":"UNVERIFIED_PROXIMITY_NOT_HUD_BINDING",
         "horizontal_overlap_fraction":0.88,
         "vertical_center_delta_normalized":0.010]]
        check(run([frame],[dup])["status"] as? String == "HOLD_R608_R609_FRAME_OR_COORDINATE_CONTRADICTION","fabricated_overlap_rejected")
        let empty=R610CrossEvidenceCandidate.beforeZip([])
        check(empty.count==1,"empty_input_emits_hold_receipt")
        let null=try JSONSerialization.jsonObject(with:empty[0].bytes) as! [String:Any]
        check(null["status"] as? String == "HOLD_R608_R609_SOURCE_EVIDENCE_MISSING_OR_INVALID","empty_input_hold")
        print("R610_STANDALONE_OK_TESTS=\(n)_NOT_HUD_CERTIFIED")
    }
}
