import Foundation

/// Offline, bounded FORM MATCH CANDIDATES from the existing R594 luminance raster.
/// References are NOT bundled: a separate labeled, independently verified reference
/// library is required. Neither label metadata nor score certifies Mega/owner/species.
enum R595FormReferenceMatcher {
    static let schema = "trueplan.r595.reference-form-matcher.v1"
    static let catalogSchema = "trueplan.r595.manual-form-reference-library.v1"
    private static let regions = ["MEMORY_LEFT_ACTOR_HYPOTHESIS", "MEMORY_RIGHT_ACTOR_HYPOTHESIS"]
    private static let cellCount = 192
    private static func validHash(_ s: String) -> Bool {
        s.utf8.count == 64 && s.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func token(_ s: String) -> Bool {
        !s.isEmpty && s.utf8.count <= 64 && s.utf8.allSatisfy {
            (65...90).contains($0) || (48...57).contains($0) || $0 == 95 || $0 == 45
        }
    }
    private static func validGrid(_ a: [Int]) -> Bool {
        guard a.count == cellCount, a.allSatisfy({ (-1...255).contains($0) }) else { return false }
        let eligible = a.filter { $0 >= 0 }
        return eligible.count >= 180 && (eligible.max() ?? 0) - (eligible.min() ?? 0) >= 25
    }
    private static func status(_ reason: String, count: Int = 0) -> [String: Any] {
        ["schema":schema,"status":reason,"frame_count":count,
         "frames":[[String:Any]](),"possible_form_transitions":[[String:Any]](),
         "owner_certified":false,"species_certified":false,"mega_certified":false,
         "current_state_eligible":false,"automatic_upload":false]
    }
    /// Strictly read a *local* reference file. Invalid or missing catalog -> no refs.
    /// The label is a supplied claim, not independent proof of a form or Pokémon.
    static func loadLocalCatalog(at url: URL?) -> [[String:Any]] {
        guard let url=url, url.isFileURL,
              let data=try? Data(contentsOf:url,options:.mappedIfSafe),data.count<=262_144,
              let obj=try? JSONSerialization.jsonObject(with:data) as? [String:Any],
              obj["schema"] as? String == catalogSchema,
              let refs=obj["references"] as? [[String:Any]] else { return [] }
        return validate(refs) ? refs : []
    }
    private static func validate(_ refs:[[String:Any]]) -> Bool {
        guard refs.count<=64 else { return false }
        var ids=Set<String>()
        for row in refs {
            guard let id=row["reference_id"] as? String,token(id),ids.insert(id).inserted,
                  let side=row["region"] as? String,regions.contains(side),
                  let species=row["species_token"] as? String,token(species),
                  let form=row["form_token"] as? String,token(form),
                  let mega=row["mega_label_claim"] as? Bool,
                  let verified=row["human_label_reviewed"] as? Bool,verified,
                  let hash=row["reference_image_sha256"] as? String,validHash(hash),
                  let vals=row["luma_grid"] as? [Int],validGrid(vals),
                  row["coordinate_space"] as? String == "RGBA_MEMORY_ROW_ORDER_UNVERIFIED",
                  row["certified_as_game_state"] as? Bool == false,
                  !mega || form.hasPrefix("MEGA")
            else { return false }
        }
        return true
    }
    private static func score(_ sample:[Int],_ reference:[Int]) -> Int? {
        let good=zip(sample,reference).filter { $0.0>=0 && $0.1>=0 }
        guard good.count>=180 else {return nil}
        let mean1=Double(good.reduce(0){$0+$1.0})/Double(good.count)
        let mean2=Double(good.reduce(0){$0+$1.1})/Double(good.count)
        let total=good.reduce(0.0) { $0 + abs((Double($1.0)-mean1)-(Double($1.1)-mean2)) }
        return Int((total / Double(good.count)).rounded())
    }
    /// All returned matches are historical *reference comparisons*, never a live
    /// state assertion. Default empty library explicitly marks missing templates.
    static func audit(_ frames:[[String:Any]],references:[[String:Any]]) -> [String:Any] {
        guard frames.count<=8,validate(references) else { return status("HOLD_INVALID_INPUT_OR_CATALOG") }
        guard !references.isEmpty else { return status("HOLD_NO_LABELED_FORM_REFERENCES",count:frames.count) }
        var lastEpoch:Int64=0,lastId:Int64=0,lastMs:Int64=0
        var identities=Set<String>()
        var output=[[String:Any]](), previous:[String:[String:Any]]?=nil
        var transitionRows=[[String:Any]]()
        for f in frames {
            guard f["schema"] as? String==R594ActorAppearance.schema,
                  f["status"] as? String=="HISTORICAL_APPEARANCE_SAMPLES_ONLY",
                  let epoch=f["epoch"] as? Int64,epoch>0,
                  let id=f["frame_id"] as? Int64,id>0,
                  let ms=f["observed_ms_monotonic"] as? Int64,ms>0,
                  let hash=f["image_sha256"] as? String,validHash(hash),
                  identities.insert("\(epoch):\(id)").inserted,
                  (epoch>lastEpoch || (epoch==lastEpoch && id>lastId && ms>lastMs)),
                  f["owner_certified"] as? Bool==false,
                  f["species_certified"] as? Bool==false,
                  f["mega_certified"] as? Bool==false,
                  f["current_state_eligible"] as? Bool==false,
                  let rows=f["regions"] as? [[String:Any]],rows.count==3
            else { return status("HOLD_INVALID_FRAME_PROVENANCE") }
            lastEpoch=epoch;lastId=id;lastMs=ms
            var byName=[String:[Int]]()
            for row in rows {
                guard let name=row["name"] as? String,
                      (regions+["MEMORY_BACKGROUND_REFERENCE"]).contains(name),byName[name]==nil,
                      row["grid_width"] as? Int==16,row["grid_height"] as? Int==12,
                      row["coordinate_space"] as? String=="RGBA_MEMORY_ROW_ORDER_UNVERIFIED",
                      let vals=row["luma_grid"] as? [Int],vals.count==cellCount,
                      vals.allSatisfy({(-1...255).contains($0)})
                else {return status("HOLD_INVALID_FRAME_GRID")}
                byName[name]=vals
            }
            guard byName.count==3 else {return status("HOLD_MISSING_REGION")}
            var candidates=[[String:Any]](),found=[String:[String:Any]]()
            for name in regions {
                let values=byName[name]!
                var distances=[(Int,[String:Any])]()
                if validGrid(values) {
                    for ref in references where ref["region"] as? String==name {
                        if let error=score(values,ref["luma_grid"] as! [Int]) {distances.append((error,ref))}
                    }
                }
                distances.sort { $0.0 == $1.0 ? ($0.1["reference_id"] as! String)<($1.1["reference_id"] as! String):$0.0<$1.0 }
                let first=distances.first?.0,runner=distances.dropFirst().first?.0
                var result:[String:Any] = ["region":name,"status":"HOLD_INSUFFICIENT_REFERENCE_OR_TEXTURE",
                     "owner":"UNKNOWN","species_certified":false,"mega_certified":false]
                if let best=first {
                    result["best_distance"] = best
                    result["runner_up_distance"] = runner ?? -1
                    result["candidate_margin"] = runner.map{$0-best} ?? -1
                    if best<=12 && (runner==nil || runner!-best>=8) {
                        let ref=distances[0].1
                        result["status"]="VISUAL_FORM_REFERENCE_MATCH_CANDIDATE"
                        for key in ["reference_id","species_token","form_token","mega_label_claim"] {
                            result[key]=ref[key]
                        }
                        result["reference_image_sha256"]=ref["reference_image_sha256"]
                        found[name]=result
                    } else {
                        result["status"]=best>12 ? "HOLD_NO_CLOSE_FORM_REFERENCE" : "HOLD_COMPETING_FORM_REFERENCES"
                    }
                }
                candidates.append(result)
            }
            if let previous=previous,epoch==output.last?["epoch"] as? Int64 {
                for name in regions {
                    if let before=previous[name],let after=found[name],
                       let species=before["species_token"] as? String,
                       species==after["species_token"] as? String,
                       before["mega_label_claim"] as? Bool == false,
                       after["mega_label_claim"] as? Bool == true {
                        transitionRows.append(["region":name,"from_frame_id":output.last!["frame_id"]!,
                             "to_frame_id":id,"species_token_claim":species,
                             "status":"BASE_TO_MEGA_REFERENCE_SEQUENCE_CANDIDATE",
                             "mega_confirmed":false,"switch_confirmed":false,
                             "owner":"UNKNOWN","requires_event_and_actor_verification":true])
                    }
                }
            }
            output.append(["epoch":epoch,"frame_id":id,"observed_ms_monotonic":ms,
                           "image_sha256":hash,"regions":candidates])
            previous=found
        }
        return ["schema":schema,"status":"HISTORICAL_REFERENCE_FORM_CANDIDATES_ONLY",
                "frame_count":output.count,"reference_count":references.count,
                "frames":output,"possible_form_transitions":transitionRows,
                "owner_certified":false,"species_certified":false,"mega_certified":false,
                "current_state_eligible":false,"automatic_upload":false,
                "limitations":"UNVERIFIED_IMAGE_ROTATION; LABELS_ARE_SUPPLIED_CLAIMS; NO_MEGA_OR_SWITCH_PROOF"]
    }
}
