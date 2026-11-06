import Foundation

// Match real PNG-backed R680 reference drafts to OCR species names in the
// SAME image HUD. This is a label suggestion, never a Mega-form assertion.
enum R681MegaSeedOCRHints {
    static let schema = "trueplan.r681.png-ocr-species-hints.v1"
    private static let left = "MEMORY_LEFT_ACTOR_HYPOTHESIS"
    private static let right = "MEMORY_RIGHT_ACTOR_HYPOTHESIS"
    private static func sha(_ s:String)->Bool {
        s.utf8.count==64 && s.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
    private static func hold(_ why:String)->[String:Any] {
        ["schema":schema,"status":why,"suggestion_count":0,
         "draft_count":0,"records":[[String:Any]](),
         "owner_certified":false,"species_certified":false,
         "mega_form_certified":false,"current_state_eligible":false,
         "battle_advice_authorized":false]
    }
    private static func rect(_ raw:Any?)->(Double,Double)? {
        guard let d=raw as? [String:Any],
              let x=d["x"] as? Double,let y=d["y"] as? Double,
              let w=d["width"] as? Double,let h=d["height"] as? Double,
              [x,y,w,h].allSatisfy({$0.isFinite}),
              x>=0,y>=0,w>0,h>0,x+w<=1.000001,y+h<=1.000001
        else {return nil}
        return (x+w/2,y+h/2)
    }
    private static func speciesText(_ raw:String)->String {
        raw.precomposedStringWithCompatibilityMapping
          .replacingOccurrences(of:"　",with:"")
          .replacingOccurrences(of:" ",with:"")
          .replacingOccurrences(of:"♀",with:"")
          .replacingOccurrences(of:"♂",with:"")
          .trimmingCharacters(in:.whitespacesAndNewlines)
    }
    static func make(draftReport:[String:Any],spatial:[String:Any],
                     registry:[(species:String,jp:String)])->[String:Any] {
        guard draftReport["schema"] as? String ==
                "trueplan.r680.real-png-form-reference-drafts.v1",
              ["UNLABELED_REFERENCE_DRAFTS_FOR_HUMAN_REVIEW",
               "NO_REVIEWABLE_ACTOR_DRAFTS"].contains(
                draftReport["status"] as? String ?? ""),
              draftReport["human_label_reviewed"] as? Bool == false,
              draftReport["catalog_auto_installed"] as? Bool == false,
              let drafts=draftReport["drafts"] as? [[String:Any]],
              let count=draftReport["draft_count"] as? Int,
              drafts.count==count,drafts.count<=16,
              spatial["schema"] as? String ==
                "trueplan.r585.historical-spatial-ocr-candidates.v1",
              spatial["status"] as? String ==
                "HISTORICAL_GEOMETRY_CANDIDATES_ONLY",
              spatial["current_state_eligible"] as? Bool == false,
              spatial["display_orientation_certified"] as? Bool == false,
              spatial["roi_owner_certified"] as? Bool == false,
              spatial["truncated_by_limit"] as? Bool == false,
              let ocr=spatial["candidates"] as? [[String:Any]],
              let ocrCount=spatial["candidate_count"] as? Int,
              ocr.count==ocrCount,ocr.count<=256,
              registry.count<=128,!registry.isEmpty
        else {return hold("HOLD_INVALID_SOURCE_OR_INCOMPLETE_OCR")}
        var lookup=[String:String](),knownSpecies=Set<String>()
        for entry in registry {
            let japanese=speciesText(entry.jp)
            guard !japanese.isEmpty,!entry.species.isEmpty,
                  entry.species.utf8.count<=64,
                  !entry.jp.isEmpty else {return hold("HOLD_BAD_REGISTRY")}
            if let other=lookup[japanese],other != entry.species {
                return hold("HOLD_REGISTRY_LABEL_COLLISION")
            }
            lookup[japanese]=entry.species
            knownSpecies.insert(entry.species)
        }
        guard !knownSpecies.isEmpty else{return hold("HOLD_EMPTY_REGISTRY")}
        var sightings=[String:[(String,String,Int)]]()
        for row in ocr {
            guard row["status"] as? String ==
                     "UNVERIFIED_ORIENTATION_SPATIAL_OCR_CANDIDATE",
                  row["owner"] as? String == "UNKNOWN",
                  row["pokemon_identity"] as? String == "UNKNOWN",
                  row["current_state_eligible"] as? Bool == false,
                  let frame=row["frame_id"] as? Int64,frame>0,
                  let epoch=row["epoch"] as? Int64,epoch>0,
                  let hash=row["image_sha256"] as? String,sha(hash),
                  let ref=row["evidence_ref"] as? String,!ref.isEmpty,
                  let angle=row["rotation_degrees"] as? Int,
                  [0,90,180,270].contains(angle),
                  let text=row["text"] as? String,!text.isEmpty,
                  let (x,y)=rect(row["nominal_source_bottom_left_roi"])
            else {return hold("HOLD_CORRUPT_OCR_PROVENANCE")}
            guard let token=lookup[speciesText(text)] else{continue}
            let region:String
            if x>=0.04 && x<=0.50 && y<=0.30 {region=left}
            else if x>=0.68 && x<=1.00 && y>=0.72 {region=right}
            else {continue}
            let key="\(epoch):\(frame):\(hash):\(region)"
            sightings[key,default:[]].append((token,ref,angle))
        }
        var seen=Set<String>(),records=[[String:Any]](),hitCount=0
        for draft in drafts {
            guard let id=draft["reference_id"] as? String,!id.isEmpty,
                  seen.insert(id).inserted,
                  let region=draft["region"] as? String,
                  region==left || region==right,
                  let epoch=draft["source_epoch"] as? Int64,epoch>0,
                  let frame=draft["source_frame_id"] as? Int64,frame>0,
                  let hash=draft["reference_image_sha256"] as? String,
                  sha(hash),
                  draft["source_png_file"] as? String ==
                    "frames/frame_\(epoch)_\(frame).png",
                  draft["human_label_reviewed"] as? Bool == false,
                  draft["needs_form_token"] as? Bool == true,
                  draft["must_review_actual_png"] as? Bool == true
            else {return hold("HOLD_INVALID_PNG_REFERENCE_DRAFT")}
            let key="\(epoch):\(frame):\(hash):\(region)"
            let options=sightings[key] ?? []
            let names=Set(options.map{$0.0})
            let angles=Set(options.map{$0.2})
            var rec:[String:Any]=[
                "reference_id":id,"region":region,
                "source_image_sha256":hash,"source_frame_id":frame,
                "source_epoch":epoch,"owner":"UNKNOWN",
                "form_token":"UNKNOWN","mega_form_certified":false,
                "species_certified":false,"human_label_reviewed":false,
                "must_review_actual_png":true,
                "current_state_eligible":false]
            if names.count==1 && angles.count==1 && options.count==1,
               let match=options.first {
                rec["species_token_suggestion"]=match.0
                rec["ocr_evidence_ref"]=match.1
                rec["rotation_hypothesis_degrees"]=match.2
                rec["status"]="SOURCE_BOUND_SPECIES_TEXT_SUGGESTION_ONLY"
                hitCount+=1
            } else {
                rec["status"]=options.isEmpty ?
                    "NO_SAME_FRAME_HUD_SPECIES_TEXT" :
                    "HOLD_AMBIGUOUS_HUD_SPECIES_TEXT"
            }
            records.append(rec)
        }
        return ["schema":schema,"status":"HISTORICAL_SPECIES_HINTS_NOT_FORM_LABELS",
            "draft_count":drafts.count,"suggestion_count":hitCount,
            "records":records,"owner_certified":false,
            "species_certified":false,"mega_form_certified":false,
            "catalog_auto_installed":false,"human_label_reviewed":false,
            "current_state_eligible":false,"battle_advice_authorized":false,
            "accuracy":"NOT_MEASURED"]
    }
}
