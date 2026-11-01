import Foundation

// Research evidence only: this module NEVER certifies owner/HP/turn/form/orientation.
// It validates R609<->R610 candidate lineage and exposes calibrated-data-needed
// location hypotheses across at most three archived frames of the same epoch.
enum R611TemporalHUDReview {
    static let memberName = "r611_temporal_hud_review.json"
    static let maxReport = 160_000
    private static func digest(_ s:String) -> Bool {
        s.count == 64 && s.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func filename(_ s:String) -> Bool {
        !s.isEmpty && s.utf8.count <= 160 && !s.hasPrefix("/") &&
        !s.contains("..") && !s.contains("\\") && !s.contains("//") && s.hasSuffix(".png")
    }
    private static func integer(_ v:Any?) -> Int64? {
        if let n=v as? Int64 { return n }
        return nil
    }
    private static func box(_ o:[String:Any]) -> (Double,Double,Double,Double)? {
        guard let r=o["rect_norm_bottom_left"] as? [String:Any],
              let x=r["x"] as? Double,let y=r["y"] as? Double,
              let w=r["width"] as? Double,let h=r["height"] as? Double,
              [x,y,w,h].allSatisfy({$0.isFinite}),x>=0,y>=0,w>0,h>0,
              x+w<=1.000001,y+h<=1.000001 else {return nil}
        return (x,y,w,h)
    }
    static func normalizedRawRowRect(_ o:[String:Any], hypothesis:String) -> [String:Double]? {
        guard let (x,y,w,h)=box(o),
              ["RAW_ROW_EQUALS_VISION_BOTTOM","RAW_ROW_FLIPPED_VERTICALLY"].contains(hypothesis) else {return nil}
        let yy = hypothesis == "RAW_ROW_EQUALS_VISION_BOTTOM" ? y : 1-y-h
        guard yy>=0, yy+h<=1.000001 else {return nil}
        return ["x":x,"y":yy,"width":w,"height":h]
    }
    private static func uncertified(_ doc:[String:Any]) -> Bool {
        for key in ["certified_for_battle","owner_verified","roi_verified",
                    "display_orientation_verified","mega_verified"] {
            guard doc[key] as? Bool == false else {return false}
        }
        return true
    }
    static func beforeZip(_ entries:[R548ResearchArchive.Entry]) -> [R548ResearchArchive.Entry] {
        let names=entries.map(\.name)
        guard entries.count<R548ResearchArchive.maximumMembers,
              names.count==Set(names).count,!names.contains(memberName) else {return entries}
        var status="HOLD_UPSTREAM_MISSING_OR_INVALID"
        var rows=[[String:Any]]()
        var tracking=[[String:Any]]()
        if let rc=entries.first(where:{$0.name=="r610_hud_cross_evidence_candidates.json"}),
           let rt=entries.first(where:{$0.name=="r609_vision_text_spatial_evidence.json"}),
           rc.bytes.count<=maxReport,rt.bytes.count<=maxReport,
           let c=(try? JSONSerialization.jsonObject(with:rc.bytes)) as? [String:Any],
           let t=(try? JSONSerialization.jsonObject(with:rt.bytes)) as? [String:Any],
           c["schema"] as? String == "trueplan.r610.hud_cross_evidence.v1",
           t["schema"] as? String == "trueplan.r609.vision_text_spatial_evidence.v1",
           c["status"] as? String == "HOLD_REVIEW_UNCERTIFIED_HUD_CANDIDATES",
           t["status"] as? String == "HOLD_OCR_AND_SPATIAL_RELATIONS_NOT_CALIBRATED",
           uncertified(c),uncertified(t),
           let cs=c["bindings"] as? [[String:Any]],cs.count<=3,
           let ts=t["bindings"] as? [[String:Any]],ts.count==cs.count {
            status="HOLD_UNCERTIFIED_VISUAL_LOCATION_HYPOTHESES"
            var seen=Set<String>()
            var seenFiles=Set<String>()
            var seenSHA=Set<String>()
            var previous:[String:[String:Any]]=[:]
            var lastFrameByEpoch=[Int64:Int64]()
            for (i,row) in cs.enumerated() {
                let source=ts[i]
                guard let epoch=integer(row["epoch"]),epoch>0,
                      let frame=integer(row["frame_id"]),frame>0,
                      let sourceEpoch=integer(source["epoch"]),sourceEpoch==epoch,
                      let sourceFrame=integer(source["frame_id"]),sourceFrame==frame,
                      let sha=row["original_png_sha256"] as? String,digest(sha),
                      sha==source["original_png_sha256"] as? String,
                      let name=row["archive_png"] as? String,filename(name),
                      name==source["archive_png"] as? String,
                      let count=row["candidate_count"] as? Int,count>=0,count<=24,
                      let cc=row["unverified_hp_shape_proximity_candidates"] as? [[String:Any]],cc.count==count,
                      let ocr=source["ocr_observations"] as? [[String:Any]],ocr.count<=32,
                      row["owner_verified"] as? Bool == false,
                      row["certified_for_battle"] as? Bool == false,
                      source["owner_verified"] as? Bool == false,
                      seen.insert("\(epoch):\(frame)").inserted,
                      seenFiles.insert(name).inserted,
                      seenSHA.insert(sha).inserted,
                      let png=entries.first(where:{$0.name==name}),
                      png.bytes.count<=8_000_000,
                      R598OneButtonFormAttachment.testDigest(png.bytes)==sha,
                      (lastFrameByEpoch[epoch] ?? -1)<frame else {
                    status="HOLD_FRAME_LINEAGE_OR_ORDER_CONTRADICTION";rows=[];tracking=[];break
                }
                lastFrameByEpoch[epoch]=frame
                var candidates=[[String:Any]]()
                var keys=Set<String>()
                for v in cc {
                    guard let index=v["ocr_index"] as? Int,index>=0,index<ocr.count,
                          let color=v["color_candidate_index"] as? Int,color>=0,color<12,
                          let hyp=v["coordinate_hypothesis"] as? String,
                          let shape=v["visual_shape"] as? String,
                          let raw=ocr[index]["text"] as? String,
                          shape==R610CrossEvidenceCandidate.visualShape(raw),
                          v["verification"] as? String=="HOLD_HUD_ROLE_AND_COORDINATES_NOT_CALIBRATED",
                          let score=v["review_priority_score_not_probability"] as? Double,
                          score.isFinite,score>=0,score<=1.000001,
                          let rect=normalizedRawRowRect(ocr[index],hypothesis:hyp),
                          keys.insert("\(index):\(color):\(hyp)").inserted else {
                        status="HOLD_CANDIDATE_POSITION_OR_SHAPE_CONTRADICTION";break
                    }
                    let centerX=(rect["x"] ?? 0)+(rect["width"] ?? 0)/2
                    let centerY=(rect["y"] ?? 0)+(rect["height"] ?? 0)/2
                    let groupKey="\(epoch):\(shape):\(hyp):\(color)"
                    // A location continuity label only. NOT a Pokémon identity or same-value assertion.
                    var near=false
                    if let prior=previous[groupKey],let px=prior["x"] as? Double,
                       let py=prior["y"] as? Double,
                       let pf=prior["frame"] as? Int64,pf<frame {
                        near=abs(px-centerX)<=0.04 && abs(py-centerY)<=0.04
                    }
                    previous[groupKey]=["x":centerX,"y":centerY,"frame":frame]
                    if near {tracking.append([
                        "epoch":epoch,"from_previous_frame_location_only":true,
                        "frame_id":frame,"group_key":groupKey,
                        "status":"HOLD_NOT_SAME_ACTOR_OR_HP_CERTIFICATION"
                    ])}
                    candidates.append([
                        "ocr_index":index,"color_candidate_index":color,
                        "visual_shape":shape,"coordinate_hypothesis":hyp,
                        "uncertified_raw_row_rect":rect,
                        "location_consistent_with_previous_candidate":near,
                        "status":"HOLD_OWNER_HP_AND_ORIENTATION_UNVERIFIED"
                    ])
                }
                if status != "HOLD_UNCERTIFIED_VISUAL_LOCATION_HYPOTHESES" {rows=[];tracking=[];break}
                rows.append([
                    "epoch":epoch,"frame_id":frame,"archive_png":name,
                    "original_png_sha256":sha,
                    "candidate_count":candidates.count,"candidates":candidates,
                    "owner_verified":false,"roi_verified":false,
                    "certified_for_battle":false
                ])
            }
            if rows.count != cs.count && status=="HOLD_UNCERTIFIED_VISUAL_LOCATION_HYPOTHESES" {
                status="HOLD_INCOMPLETE_FRAME_COVERAGE";rows=[];tracking=[]
            }
        }
        let report:[String:Any]=[
            "schema":"trueplan.r611.temporal_hud_review.v1",
            "status":status,"bindings":rows,"location_continuity_hypotheses":tracking,
            "owner_verified":false,"roi_verified":false,"mega_verified":false,
            "display_orientation_verified":false,"certified_for_battle":false,
            "limitations":"Pixel/OCR geometry tracking across at most three frames is not UI/actor identity, HP value, or orientation calibration."
        ]
        guard let data=try? JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),
              data.count<=maxReport else {return entries}
        return entries+[.init(name:memberName,bytes:data)]
    }
}
