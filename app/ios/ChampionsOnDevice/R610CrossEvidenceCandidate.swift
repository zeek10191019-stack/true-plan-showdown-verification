import Foundation

// R610: candidate generation ONLY. No ownership, HP, ROI, turn, orientation
// or Mega authentication. Cross-validate immutable PNG + R608 + R609 receipts.
enum R610CrossEvidenceCandidate {
    static let memberName = "r610_hud_cross_evidence_candidates.json"
    static let maxInputBytes = 160_000
    static let maxRows = 3
    static let maxCandidatesPerFrame = 24

    private static func validName(_ s:String) -> Bool {
        !s.isEmpty && s.utf8.count <= 160 && !s.hasPrefix("/") &&
        !s.contains("..") && !s.contains("\\") && !s.contains("//") &&
        s.utf8.allSatisfy { $0 >= 32 && $0 != 127 }
    }
    private static func validDigest(_ s:String) -> Bool {
        s.utf8.count == 64 && s.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func frameKey(_ row:[String:Any]) -> String? {
        guard let epoch=row["epoch"] as? Int64,epoch>0,
              let frame=row["frame_id"] as? Int64,frame>0 else {return nil}
        return "\(epoch):\(frame)"
    }
    private static func sameIdentity(_ a:[String:Any], _ b:[String:Any]) -> Bool {
        guard let ak=frameKey(a),let bk=frameKey(b),ak==bk,
              let ah=a["original_png_sha256"] as? String,
              let bh=b["original_png_sha256"] as? String,
              validDigest(ah), ah==bh,
              let an=a["archive_png"] as? String,
              let bn=b["archive_png"] as? String,
              validName(an), an.hasSuffix(".png"),an==bn else {return false}
        return true
    }
    private static func isUncertified(_ value:[String:Any]) -> Bool {
        for k in ["certified_for_battle","owner_verified","roi_verified",
                  "mega_verified","display_orientation_verified","frame_identity_verified"] {
            if let b=value[k] as? Bool, b != false {return false}
        }
        return value["owner_verified"] as? Bool == false &&
               value["roi_verified"] as? Bool == false &&
               value["mega_verified"] as? Bool == false &&
               value["display_orientation_verified"] as? Bool == false
    }
    static func visualShape(_ source:String) -> String? {
        let s=source.replacingOccurrences(of:" ",with:"")
                    .replacingOccurrences(of:"\u{3000}",with:"")
        let chars=Array(s)
        func digits(_ a:ArraySlice<Character>) -> Int? {
            guard a.count>=1 && a.count<=4,
                  a.allSatisfy({$0 >= "0" && $0 <= "9"}) else {return nil}
            return Int(String(a))
        }
        if let slash=chars.firstIndex(of:"/"), chars.filter({$0=="/"}).count==1,
           let cur=digits(chars[..<slash]), let full=digits(chars[(slash+1)...]),
           full>0 && cur<=full {return "NUMERIC_FRACTION_SHAPE_UNVERIFIED"}
        if chars.last == "%",chars.count>=2 && chars.count<=4,
           let p=digits(chars.dropLast()),p<=100 {
            return "PERCENTAGE_SHAPE_UNVERIFIED"
        }
        return nil
    }
    private static func validRects(_ observation:[String:Any]) -> Bool {
        guard let c=observation["confidence"] as? Double,c.isFinite,c>=0,c<=1,
              let name=observation["text"] as? String,
              name.utf8.count>0,name.utf8.count<=384,
              let box=observation["rect_norm_bottom_left"] as? [String:Any],
              let x=box["x"] as? Double, let y=box["y"] as? Double,
              let w=box["width"] as? Double,let h=box["height"] as? Double,
              [x,y,w,h].allSatisfy({$0.isFinite}),
              x>=0,y>=0,w>0,h>0,x+w<=1.000001,y+h<=1.000001 else {return false}
        return true
    }
    private static func rect(_ v:[String:Any], prefix:String="") -> (Double,Double,Double,Double)? {
        let keys=prefix.isEmpty ? ["x","y","width","height"] :
                   ["x_norm","y_norm","width_norm","height_norm"]
        guard let x=v[keys[0]] as? Double,let y=v[keys[1]] as? Double,
              let w=v[keys[2]] as? Double,let h=v[keys[3]] as? Double,
              [x,y,w,h].allSatisfy({$0.isFinite}),
              x>=0,y>=0,w>0,h>0,x+w<=1.000001,y+h<=1.000001 else {return nil}
        return (x,y,w,h)
    }
    private static func spatialRecheck(_ rel:[String:Any],
                 ocr:[String:Any],rawColor:[String:Any],model:String,
                 overlap:Double,delta:Double)->Bool {
        guard let box=ocr["rect_norm_bottom_left"] as? [String:Any],
              let t=rect(box),let c=rect(rawColor,prefix:"raw") else {return false}
        let xOverlap=max(0,min(t.0+t.2,c.0+c.2)-max(t.0,c.0))
        let fraction=xOverlap/min(t.2,c.2)
        let colorY=model=="RAW_ROW_EQUALS_VISION_BOTTOM" ? c.1+c.3/2 : 1-c.1-c.3/2
        let difference=abs(t.1+t.3/2-colorY)
        return fraction>=0.15 && difference<=0.12 &&
               abs(overlap-fraction)<=0.000001 && abs(delta-difference)<=0.000001
    }
    private static func candidates(_ row:[String:Any],colors:[[String:Any]]) -> [[String:Any]]? {
        guard let ocr=row["ocr_observations"] as? [[String:Any]],ocr.count<=32,
              let relations=row["text_color_associations"] as? [[String:Any]],
              relations.count<=32 else {return nil}
        for o in ocr {if !validRects(o) {return nil}}
        var result=[[String:Any]](),used=Set<String>()
        for rel in relations {
            guard let oi=rel["ocr_index"] as? Int,oi>=0,oi<ocr.count,
                  let bi=rel["color_candidate_index"] as? Int,bi>=0,bi<colors.count,
                  let model=rel["coordinate_hypothesis"] as? String,
                  ["RAW_ROW_EQUALS_VISION_BOTTOM","RAW_ROW_FLIPPED_VERTICALLY"].contains(model),
                  rel["spatial_relation"] as? String == "UNVERIFIED_PROXIMITY_NOT_HUD_BINDING",
                  let overlap=rel["horizontal_overlap_fraction"] as? Double,
                  overlap.isFinite,overlap>=0.15,overlap<=1.000001,
                  let delta=rel["vertical_center_delta_normalized"] as? Double,
                  delta.isFinite,delta>=0,delta<=0.120001,
                  spatialRecheck(rel,ocr:ocr[oi],rawColor:colors[bi],
                                 model:model,overlap:overlap,delta:delta) else {return nil}
            guard let text=ocr[oi]["text"] as? String,
                  let shape=visualShape(text) else {continue}
            let id="\(oi):\(bi):\(model)"
            guard used.insert(id).inserted else {return nil}
            // Ranking is for human review only; the score is NOT a posterior probability.
            let rank=(overlap * max(0,1-delta/0.12))
            result.append([
                "ocr_index":oi,"color_candidate_index":bi,
                "coordinate_hypothesis":model,"visual_shape":shape,
                "review_priority_score_not_probability":rank,
                "verification":"HOLD_HUD_ROLE_AND_COORDINATES_NOT_CALIBRATED"
            ])
        }
        return Array(result.sorted {
            ($0["review_priority_score_not_probability"] as! Double) >
            ($1["review_priority_score_not_probability"] as! Double)
        }.prefix(maxCandidatesPerFrame))
    }
    static func beforeZip(_ entries:[R548ResearchArchive.Entry]) -> [R548ResearchArchive.Entry] {
        let names=entries.map(\.name)
        guard entries.count < R548ResearchArchive.maximumMembers,
              names.count==Set(names).count,
              names.allSatisfy({validName($0)}),
              !names.contains(memberName) else {return entries}
        var status="HOLD_R608_R609_SOURCE_EVIDENCE_MISSING_OR_INVALID"
        var output=[[String:Any]]()
        var truncated=false
        if let r8=entries.first(where:{$0.name=="r608_original_pixel_evidence.json"}),
           let r9=entries.first(where:{$0.name=="r609_vision_text_spatial_evidence.json"}),
           r8.bytes.count<=maxInputBytes, r9.bytes.count<=maxInputBytes,
           let a=(try? JSONSerialization.jsonObject(with:r8.bytes)) as? [String:Any],
           let b=(try? JSONSerialization.jsonObject(with:r9.bytes)) as? [String:Any],
           a["schema"] as? String == "trueplan.r608.raw_png_visual_evidence.v1",
           b["schema"] as? String == "trueplan.r609.vision_text_spatial_evidence.v1",
           a["status"] as? String == "HOLD_VISUAL_OWNER_ROI_AND_ORIENTATION_UNCERTIFIED",
           b["status"] as? String == "HOLD_OCR_AND_SPATIAL_RELATIONS_NOT_CALIBRATED",
           a["certified_for_battle"] as? Bool == false,
           b["certified_for_battle"] as? Bool == false,
           isUncertified(a),isUncertified(b),
           let frames8=a["bindings"] as? [[String:Any]],frames8.count<=8,
           let frames9=b["bindings"] as? [[String:Any]],frames9.count<=maxRows,
           b["frames_truncated"] as? Bool == (frames8.count>maxRows) {
            status="HOLD_REVIEW_UNCERTIFIED_HUD_CANDIDATES"
            truncated=frames8.count>maxRows
            var map8=[String:[String:Any]](),seen9=Set<String>(),seenImage=Set<String>()
            for row in frames8 {
                guard let key=frameKey(row),map8[key]==nil,
                      isUncertified(row),
                      row["frame_identity_verified"] as? Bool == false else {status="HOLD_R608_FRAME_DUPLICATE_OR_FALSE_CERT";break}
                map8[key]=row
            }
            if status == "HOLD_REVIEW_UNCERTIFIED_HUD_CANDIDATES" {
              for row9 in frames9 {
                guard let key=frameKey(row9),seen9.insert(key).inserted,
                      let row8=map8[key],sameIdentity(row8,row9),
                      isUncertified(row9),
                      let file=row9["archive_png"] as? String,
                      seenImage.insert(file).inserted,
                      let original=entries.first(where:{$0.name==file}),
                      let sha=row9["original_png_sha256"] as? String,
                      original.bytes.count<=8_000_000,
                      R598OneButtonFormAttachment.testDigest(original.bytes)==sha,
                      row8["png_ihdr_crc_verified"] as? Bool == true,
                      row8["decoded_pixels_verified"] as? Bool == true,
                      row9["png_ihdr_crc_verified"] == nil,
                      let colors=row8["unverified_region_candidates"] as? [[String:Any]],
                      colors.count<=12,
                      let cand=candidates(row9,colors:colors) else {
                    status="HOLD_R608_R609_FRAME_OR_COORDINATE_CONTRADICTION";output=[];break
                }
                output.append([
                  "epoch":row9["epoch"]!,"frame_id":row9["frame_id"]!,
                  "original_png_sha256":sha,"archive_png":file,
                  "candidate_count":cand.count,"unverified_hp_shape_proximity_candidates":cand,
                  "owner_verified":false,"roi_verified":false,
                  "display_orientation_verified":false,"mega_verified":false,
                  "certified_for_battle":false,
                  "status":"HOLD_ACTOR_ROI_AND_DISPLAY_CALIBRATION_REQUIRED"
                ])
              }
            }
            if status == "HOLD_REVIEW_UNCERTIFIED_HUD_CANDIDATES" && output.count != frames9.count {
                status="HOLD_R609_FRAME_COVERAGE_MISMATCH";output=[]
            }
        }
        let report:[String:Any]=[
          "schema":"trueplan.r610.hud_cross_evidence.v1",
          "status":status,"certified_for_battle":false,
          "owner_verified":false,"roi_verified":false,
          "display_orientation_verified":false,"mega_verified":false,
          "species_verified":false,"frame_identity_verified":false,
          "bindings":output,"truncated_input_frames":truncated,
          "limitations":"Only numeric-text and saturated-color proximity hypotheses. No actor, HP value, UI ROI, device rotation, Pokemon or Mega identity certification."
        ]
        guard let json=try? JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),
              json.count<=maxInputBytes else {return entries}
        return entries+[.init(name:memberName,bytes:json)]
    }
}
