import Foundation

// R621: independent PNG-frame lineage, R622: four-orientation OCR token review,
// R623: provisional UI slot hints + Mega scene words, R624: archive/HOLD contract.
// No inferred token can establish actor, orientation, current HP or Mega form.
enum R621R624VisualCandidates {
    static let memberName = "r621_r624_visual_candidates.json"
    private static let maxInput = 160_000
    private static let maxReport = 240_000
    private static let orientations = ["UP", "RIGHT", "DOWN", "LEFT"]
    private static let flags = ["certified_for_battle", "owner_verified", "roi_verified",
                                "mega_verified", "display_orientation_verified"]
    private static func hold(_ r:[String:Any]) -> Bool {
        flags.allSatisfy { r[$0] as? Bool == false }
    }
    private static func shaOK(_ s:String) -> Bool {
        s.utf8.count == 64 && s.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
    private static func rect(_ v:[String:Any]) -> (Double, Double, Double, Double)? {
        guard let x=v["x"] as? Double,let y=v["y"] as? Double,
              let w=v["width"] as? Double,let h=v["height"] as? Double,
              [x,y,w,h].allSatisfy({$0.isFinite}),
              x>=0,y>=0,w>0,h>0,x+w<=1.000001,y+h<=1.000001 else {return nil}
        return (x,y,w,h)
    }
    private static func doc(_ entries:[R548ResearchArchive.Entry],_ name:String)->[String:Any]? {
        guard let e=entries.first(where:{$0.name==name}),e.bytes.count<=maxInput,
              let parsed=(try? JSONSerialization.jsonObject(with:e.bytes)) as? [String:Any]
        else {return nil}
        return parsed
    }
    private static func frame(_ r:[String:Any]) -> (String,String,Int64,Int64)? {
        guard let s=r["original_png_sha256"] as? String,shaOK(s),
              let p=r["archive_png"] as? String,!p.isEmpty,p.utf8.count<=160,
              p.hasSuffix(".png"),!p.hasPrefix("/"),!p.contains(".."),
              !p.contains("\\"),!p.contains("//"),
              let e=r["epoch"] as? Int64,e>0,
              let i=r["frame_id"] as? Int64,i>0 else {return nil}
        return (s,p,e,i)
    }
    private static func semanticallyIdentical(_ actual:[String:Any],_ parsed:[String:Any])->Bool {
        guard let a=actual["kind"] as? String,let b=parsed["kind"] as? String,a==b else{return false}
        switch a {
        case "FRACTION_HP_OR_PP_UNASSIGNED":
            return actual["numerator"] as? Int == parsed["numerator"] as? Int &&
                   actual["denominator"] as? Int == parsed["denominator"] as? Int
        case "PERCENT_HP_OR_OTHER_UNASSIGNED":
            return actual["percent"] as? Int == parsed["percent"] as? Int
        case "STATUS_WORD_UNASSIGNED":
            return actual["status_code"] as? String == parsed["status_code"] as? String
        case "MEGA_SCENE_TEXT_CUE_UNASSIGNED": return true
        default: return false
        }
    }
    private static func unverifiedHint(_ kind:String)->String {
        switch kind {
        case "FRACTION_HP_OR_PP_UNASSIGNED":return "FRACTION_STYLE_OWN_OR_PP_POSSIBLE_NOT_PROVEN"
        case "PERCENT_HP_OR_OTHER_UNASSIGNED":return "PERCENT_STYLE_OPP_OR_OTHER_POSSIBLE_NOT_PROVEN"
        case "STATUS_WORD_UNASSIGNED":return "STATUS_WORD_NOT_ACTOR_BOUND"
        case "MEGA_SCENE_TEXT_CUE_UNASSIGNED":return "MEGA_EVENT_WORD_NOT_ACTOR_OR_FORM"
        default:return "NOT_MAPPED"
        }
    }
    static func review(_ frame:[String:Any])->[[String:Any]]? {
        guard let scans=frame["orientation_probes"] as? [[String:Any]],
              scans.count==4,Set(scans.compactMap({$0["hypothesis"] as? String})) == Set(orientations)
        else{return nil}
        var observations=[[String:Any]]()
        for hypothesis in orientations {
            guard let scan=scans.first(where:{$0["hypothesis"] as? String==hypothesis}),
                  let status=scan["status"] as? String,
                  ["OCR_OBSERVED_NOT_ORIENTATION_CALIBRATED","HOLD_VISION_REQUEST_FAILED",
                   "HOLD_VISION_UNAVAILABLE"].contains(status),
                  let tokens=scan["visual_tokens"] as? [[String:Any]],tokens.count<=12
            else {return nil}
            if status != "OCR_OBSERVED_NOT_ORIENTATION_CALIBRATED" && !tokens.isEmpty {return nil}
            for (index,tok) in tokens.enumerated() {
                guard let label=tok["token"] as? String,label.utf8.count<=96,
                      let conf=tok["confidence"] as? Double,conf.isFinite,conf>=0,conf<=1,
                      let vb=tok["rect_norm_bottom_left_in_orientation_hypothesis"] as? [String:Any],
                      let box=rect(vb),
                      let sem=tok["visual_semantics"] as? [String:Any],
                      let parsed=R617R620RotationReadout.parseVisualToken(label),
                      semanticallyIdentical(sem,parsed),
                      tok["battle_field_certified"] as? Bool == false,
                      tok["identity"] as? String == "UNKNOWN" else {return nil}
                let kind=parsed["kind"] as! String
                observations.append([
                    "orientation_hypothesis":hypothesis,"token_index":index,
                    "text":label,"kind":kind,"confidence":conf,
                    "normalized_rect_in_hypothesis":vb,
                    "visual_half_in_hypothesis":box.1+box.3/2>=0.5 ? "UPPER" : "LOWER",
                    "role_hint_not_ground_truth":unverifiedHint(kind),
                    "owner":"UNKNOWN","mega_form":"UNKNOWN",
                    "exact_hp":"UNKNOWN","battle_field_certified":false
                ])
            }
        }
        return observations
    }
    private static func temporal(_ frames:[[String:Any]]) -> [[String:Any]] {
        guard frames.count==2,let a=frames[0]["observations"] as? [[String:Any]],
              let b=frames[1]["observations"] as? [[String:Any]] else{return []}
        var links=[[String:Any]](),used=Set<Int>()
        for (i,left) in a.enumerated() {
            guard let h=left["orientation_hypothesis"] as? String,
                  let kind=left["kind"] as? String,
                  let box=left["normalized_rect_in_hypothesis"] as? [String:Any],
                  let r=rect(box) else {continue}
            let near=b.enumerated().filter {j,right in
                guard !used.contains(j),right["orientation_hypothesis"] as? String==h,
                      right["kind"] as? String==kind,
                      let other=right["normalized_rect_in_hypothesis"] as? [String:Any],
                      let v=rect(other) else{return false}
                return abs(r.0+r.2/2-v.0-v.2/2)<=0.04 &&
                       abs(r.1+r.3/2-v.1-v.3/2)<=0.04
            }
            if near.count==1 {
                used.insert(near[0].offset)
                links.append(["orientation_hypothesis":h,"first_index":i,
                              "second_index":near[0].offset,
                              "status":"UNVERIFIED_REPEATED_UI_LOCATION_NOT_ACTOR_ID"])
            }
        }
        return Array(links.prefix(24))
    }
    static func beforeZip(_ entries:[R548ResearchArchive.Entry])->[R548ResearchArchive.Entry] {
        let names=entries.map(\.name)
        // R624 embeds into the already-present R617 JSON: no extra ZIP member.
        guard names.count==Set(names).count,!names.contains(memberName),
              names.contains(R617R620RotationReadout.memberName) else{return entries}
        var status="HOLD_REQUIRED_ORIGINAL_EVIDENCE_MISSING"
        var output=[[String:Any]]()
        let raw=doc(entries,"r608_original_pixel_evidence.json")
        let prior=doc(entries,"r613_r616_integrated_readiness.json")
        let rotations=doc(entries,R617R620RotationReadout.memberName)
        if let raw,let prior,let rotations,
           raw["schema"] as? String=="trueplan.r608.raw_png_visual_evidence.v1",
           prior["schema"] as? String=="trueplan.r613-r616.integrated_readiness.v1",
           rotations["schema"] as? String=="trueplan.r617-r620.rotation_readout.v1",
           [raw,prior,rotations].allSatisfy({hold($0)}),
           rotations["status"] as? String == "HOLD_ROTATION_SWEEP_RESEARCH_NOT_ACTOR_CERTIFICATION",
           let all=rotations["frames"] as? [[String:Any]],all.count<=2,
           let r8=raw["bindings"] as? [[String:Any]],r8.count<=8 {
            status="HOLD_UI_SLOTS_REQUIRE_LABELED_GAME_FRAMES"
            var ids=Set<String>(),hashes=Set<String>(),images=Set<String>()
            for row in all {
                guard let bound=frame(row),ids.insert("\(bound.2):\(bound.3)").inserted,
                      images.insert(bound.1).inserted,hashes.insert(bound.0).inserted,
                      let original=r8.first(where:{frame($0)?.2==bound.2 && frame($0)?.3==bound.3}),
                      let parent=frame(original),parent.0==bound.0,parent.1==bound.1,
                      original["decoded_pixels_verified"] as? Bool==true,
                      original["png_ihdr_crc_verified"] as? Bool==true,
                      let image=entries.first(where:{$0.name==bound.1}),
                      image.bytes.count<=8_000_000,
                      R598OneButtonFormAttachment.testDigest(image.bytes)==bound.0,
                      let observations=review(row) else {
                    status="HOLD_FRAME_HASH_OR_OCR_CONTRADICTION";output=[];break
                }
                output.append(["epoch":bound.2,"frame_id":bound.3,
                   "original_png_sha256":bound.0,"archive_png":bound.1,
                   "observations":observations,"orientation":"UNKNOWN",
                   "owner":"UNKNOWN","opponent":"UNKNOWN"])
            }
        }
        let linked=temporal(output)
        let megaWords=output.reduce(0) { v,row in
            v + ((row["observations"] as? [[String:Any]]) ?? []).filter {
                $0["kind"] as? String == "MEGA_SCENE_TEXT_CUE_UNASSIGNED"
            }.count
        }
        let report:[String:Any]=[
            "schema":"trueplan.r621-r624.visual_candidate_slots.v1",
            "status":status,"r621_lineage_frame_count":output.count,
            "r622_ui_slot_hypotheses":output,
            "r623_repeated_visual_locations":linked,
            "r623_mega_scene_text_cues":megaWords,
            "r623_mega_form":"UNKNOWN_NO_LABELLED_SPRITE_REFERENCE",
            "r624_required_ground_truth":["confirmed_orientation", "labelled_own_opponent_rois",
                                        "actor_sprite_form_reference", "real_game_frames"],
            "r624_coverage":["target_fields":79,"certified_fields":0],
            "certified_for_battle":false,"owner_verified":false,"roi_verified":false,
            "mega_verified":false,"display_orientation_verified":false,
            "limitations":"UI positions, numerical OCR and Mega words are hypotheses only; cannot assign side, HP, species or Mega form."
        ]
        guard let priorMember=doc(entries,R617R620RotationReadout.memberName),
              priorMember["r621_r624_embedded_candidate_report"] == nil else{return entries}
        var merged=priorMember
        merged["r621_r624_embedded_candidate_report"]=report
        guard let bytes=try? JSONSerialization.data(withJSONObject:merged,options:[.sortedKeys]),
              bytes.count<=maxReport else{return entries}
        return entries.map { item in
            item.name == R617R620RotationReadout.memberName
              ? .init(name:item.name,bytes:bytes) : item
        }
    }
    static func containsReport(_ entries:[R548ResearchArchive.Entry])->Bool {
        guard let item=entries.first(where:{$0.name==R617R620RotationReadout.memberName}),
              item.bytes.count<=maxReport,
              let obj=(try? JSONSerialization.jsonObject(with:item.bytes)) as? [String:Any],
              let result=obj["r621_r624_embedded_candidate_report"] as? [String:Any]
        else {return false}
        return result["schema"] as? String == "trueplan.r621-r624.visual_candidate_slots.v1" &&
               result["certified_for_battle"] as? Bool == false &&
               result["owner_verified"] as? Bool == false &&
               result["mega_verified"] as? Bool == false

    }
}
