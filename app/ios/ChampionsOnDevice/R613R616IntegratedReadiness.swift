import Foundation

// R613-R616: a single capped archive member, not an automatic certification.
// R613 original-frame lineage; R614 OCR/geometry cross-check;
// R615 uncalibrated side ambiguity; R616 archive receipt and coverage report.
// No image layout assumption can establish OWN/OPP, HP, orientation or Mega.
enum R613R616IntegratedReadiness {
    static let memberName = "r613_r616_integrated_readiness.json"
    static let sourceNames = [
        "r608_original_pixel_evidence.json",
        "r609_vision_text_spatial_evidence.json",
        "r610_hud_cross_evidence_candidates.json",
        "r611_temporal_hud_review.json",
        "r612_archive_evidence_closure.json"
    ]
    private static let schema = [
        "trueplan.r608.raw_png_visual_evidence.v1",
        "trueplan.r609.vision_text_spatial_evidence.v1",
        "trueplan.r610.hud_cross_evidence.v1",
        "trueplan.r611.temporal_hud_review.v1",
        "trueplan.r612.research_evidence_closure.v1"
    ]
    private static let flags = ["certified_for_battle","owner_verified","roi_verified",
                                "mega_verified","display_orientation_verified"]
    private static func document(_ entries:[R548ResearchArchive.Entry], _ name:String) -> [String:Any]? {
        guard let item=entries.first(where:{$0.name==name}), item.bytes.count<=160_000,
              let obj=(try? JSONSerialization.jsonObject(with:item.bytes)) as? [String:Any] else {return nil}
        return obj
    }
    private static func validSHA(_ s:String) -> Bool {
        s.utf8.count==64 && s.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func frame(_ r:[String:Any]) -> (Int64,Int64,String,String)? {
        guard let epoch=r["epoch"] as? Int64,epoch>0,
              let id=r["frame_id"] as? Int64,id>0,
              let sha=r["original_png_sha256"] as? String,validSHA(sha),
              let png=r["archive_png"] as? String,!png.isEmpty,png.utf8.count<=160,
              png.hasSuffix(".png"),!png.hasPrefix("/"),!png.contains(".."),
              !png.contains("\\"),!png.contains("//") else {return nil}
        return (epoch,id,sha,png)
    }
    private static func near(_ a:Double,_ b:Double) -> Bool { abs(a-b)<=0.000001 }
    private static func safe(_ docs:[[String:Any]]) -> Bool {
        docs.count==sourceNames.count && docs.allSatisfy { d in
            flags.allSatisfy { d[$0] as? Bool == false }
        }
    }
    // Strict check of the unsiged, local R612 receipt. This establishes only
    // byte equality of the archive entries, not authenticity of the game image.
    private static func closureOK(_ entries:[R548ResearchArchive.Entry],_ doc:[String:Any]) -> Bool {
        guard let records=doc["checked_members"] as? [[String:Any]],records.count==4,
              doc["missing_or_invalid"] as? [String] == [],
              doc["status"] as? String == "HOLD_COMPLETE_UNCERTIFIED_RESEARCH_RECEIPTS" else {return false}
        var seen=Set<String>()
        for record in records {
            guard let name=record["archive_member"] as? String,
                  sourceNames.prefix(4).contains(name),seen.insert(name).inserted,
                  let count=record["byte_count"] as? Int,
                  let sha=record["sha256"] as? String,validSHA(sha),
                  let source=entries.first(where:{$0.name==name}),
                  source.bytes.count==count,
                  R598OneButtonFormAttachment.testDigest(source.bytes)==sha,
                  record["certified_for_battle"] as? Bool==false else {return false}
        }
        return seen.count==4
    }
    static func beforeZip(_ entries:[R548ResearchArchive.Entry]) -> [R548ResearchArchive.Entry] {
        let names=entries.map(\.name)
        guard entries.count<R548ResearchArchive.maximumMembers,
              names.count==Set(names).count,!names.contains(memberName) else {return entries}
        var status="HOLD_SOURCE_MISSING_OR_CONTRADICTORY"
        var rows=[[String:Any]]()
        var regions=[String:Int]()
        var missing=[String]()
        for name in sourceNames where !names.contains(name) {missing.append(name)}
        let docs=sourceNames.compactMap {document(entries,$0)}
        if missing.isEmpty && docs.count==5 && safe(docs) &&
           zip(docs,schema).allSatisfy({$0.0["schema"] as? String == $0.1}) &&
           closureOK(entries,docs[4]),
           docs[0]["status"] as? String == "HOLD_VISUAL_OWNER_ROI_AND_ORIENTATION_UNCERTIFIED",
           docs[1]["status"] as? String == "HOLD_OCR_AND_SPATIAL_RELATIONS_NOT_CALIBRATED",
           docs[2]["status"] as? String == "HOLD_REVIEW_UNCERTIFIED_HUD_CANDIDATES",
           docs[3]["status"] as? String == "HOLD_UNCERTIFIED_VISUAL_LOCATION_HYPOTHESES",
           let base=docs[1]["bindings"] as? [[String:Any]],
           let candidates=docs[2]["bindings"] as? [[String:Any]],
           let temporal=docs[3]["bindings"] as? [[String:Any]],
           base.count==candidates.count,base.count==temporal.count,
           !base.isEmpty,base.count<=3 {
            status="HOLD_NEEDS_LABELED_UI_CALIBRATION"
            var seen=Set<String>(),images=Set<String>(),hashes=Set<String>(),last=[Int64:Int64]()
            for index in base.indices {
                guard let b=frame(base[index]),let c=frame(candidates[index]),
                      let t=frame(temporal[index]),
                      b.0==c.0 && b.0==t.0,b.1==c.1 && b.1==t.1,
                      b.2==c.2 && b.2==t.2,b.3==c.3 && b.3==t.3,
                      seen.insert("\(b.0):\(b.1)").inserted,
                      images.insert(b.3).inserted,
                      hashes.insert(b.2).inserted,
                      b.1>(last[b.0] ?? -1),
                      let png=entries.first(where:{$0.name==b.3}),
                      png.bytes.count<=8_000_000,
                      R598OneButtonFormAttachment.testDigest(png.bytes)==b.2,
                      let observations=base[index]["ocr_observations"] as? [[String:Any]],
                      observations.count<=32,
                      let list=temporal[index]["candidates"] as? [[String:Any]],
                      list.count<=24 else {
                    status="HOLD_FRAME_OR_IMAGE_LINEAGE_CONTRADICTION";rows=[];regions=[:];break
                }
                last[b.0]=b.1
                var reviewed=[[String:Any]](),used=Set<String>()
                for v in list {
                    guard let oi=v["ocr_index"] as? Int,oi>=0,oi<observations.count,
                          let ci=v["color_candidate_index"] as? Int,ci>=0,ci<12,
                          let hyp=v["coordinate_hypothesis"] as? String,
                          let shape=v["visual_shape"] as? String,
                          let text=observations[oi]["text"] as? String,
                          R610CrossEvidenceCandidate.visualShape(text)==shape,
                          let raw=R611TemporalHUDReview.normalizedRawRowRect(observations[oi],hypothesis:hyp),
                          let claimed=v["uncertified_raw_row_rect"] as? [String:Double],
                          ["x","y","width","height"].allSatisfy({ key in
                              guard let a=claimed[key],let b=raw[key],a.isFinite else{return false}
                              return near(a,b)
                          }),
                          used.insert("\(oi):\(ci):\(hyp)").inserted,
                          v["status"] as? String == "HOLD_OWNER_HP_AND_ORIENTATION_UNVERIFIED" else {
                        status="HOLD_OCR_RECT_OR_HYPOTHESIS_CONTRADICTION";break
                    }
                    // These labels are image-space regions, never Pokémon sides.
                    let y=(raw["y"] ?? 0)+(raw["height"] ?? 0)/2
                    let key=y<0.5 ? "RAW_LOWER_HALF" : "RAW_UPPER_HALF"
                    regions[key,default:0]+=1
                    reviewed.append(["ocr_index":oi,"color_candidate_index":ci,
                        "raw_image_region":key,"coordinate_hypothesis":hyp,
                        "status":"HOLD_NOT_OWN_OR_OPP_ROLE"])
                }
                if status != "HOLD_NEEDS_LABELED_UI_CALIBRATION" {rows=[];regions=[:];break}
                rows.append(["epoch":b.0,"frame_id":b.1,
                   "archive_png":b.3,"original_png_sha256":b.2,
                   "uncertified_regions":reviewed,
                   "role_assignment":"UNKNOWN_UNTIL_GAME_UI_CALIBRATED"])
            }
        }
        let report:[String:Any]=[
            "schema":"trueplan.r613-r616.integrated_readiness.v1",
            "status":status,"r613_frame_lineage":["frame_count":rows.count,"valid":status=="HOLD_NEEDS_LABELED_UI_CALIBRATION"],
            "r614_spatial_review":["raw_half_counts":regions,"coordinate_origin":"UNCALIBRATED"],
            "r615_own_opponent_role":["own":"UNKNOWN","opponent":"UNKNOWN","requires_ground_truth":true],
            "r616_scope_and_coverage":["target_field_count":79,"certified_field_count":0,
                 "missing_archive_members":missing,"archive_receipt_unsigned":true],
            "frame_rows":rows,"certified_for_battle":false,"owner_verified":false,
            "roi_verified":false,"mega_verified":false,"display_orientation_verified":false,
            "limitations":"Image location is not own/opponent identity, actual HP, Mega form or orientation."
        ]
        guard let data=try? JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),
              data.count<=80_000 else{return entries}
        return entries+[.init(name:memberName,bytes:data)]
    }
}
