import Foundation

// Export real retained-frame descriptors as UNLABELED form-reference drafts.
// A draft cannot be used by R595 until a human reviews the actual image.
enum R680MegaReferenceSeeds {
    static let schema = "trueplan.r680.real-png-form-reference-drafts.v1"
    private static let actorRegions = [
        "MEMORY_LEFT_ACTOR_HYPOTHESIS",
        "MEMORY_RIGHT_ACTOR_HYPOTHESIS"]
    private static func hash(_ s: String) -> Bool {
        s.utf8.count == 64 && s.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
    private static func held(_ reason: String) -> [String:Any] {
        ["schema":schema,"status":reason,"draft_count":0,
         "drafts":[[String:Any]](),"human_label_reviewed":false,
         "owner_certified":false,"species_certified":false,
         "mega_form_certified":false,"current_state_eligible":false,
         "battle_advice_authorized":false]
    }
    private static func validGrid(_ a: [Int]) -> Bool {
        guard a.count == 192,
              a.allSatisfy({(-1...255).contains($0)}) else {return false}
        let good=a.filter{$0>=0}
        return good.count>=180 && (good.max() ?? 0)-(good.min() ?? 0)>=25
    }
    static func make(frames:[[String:Any]],snapshots:[[String:Any]])->[String:Any] {
        guard frames.count==snapshots.count,frames.count<=8 else {
            return held("HOLD_FRAME_COUNT_OR_CAPACITY")
        }
        var seenFrames=Set<String>(),seenImages=Set<String>()
        var drafts=[[String:Any]](),skipped=[[String:Any]]()
        for i in frames.indices {
            let frame=frames[i],snap=snapshots[i]
            guard frame["schema"] as? String ==
                        "trueplan.r594.historical-actor-appearance.v1",
                  let status=frame["status"] as? String,
                  ["HISTORICAL_APPEARANCE_SAMPLES_ONLY",
                   "HOLD_RASTER_UNAVAILABLE"].contains(status),
                  let epoch=frame["epoch"] as? Int64,epoch>0,
                  let id=frame["frame_id"] as? Int64,id>0,
                  let sha=frame["image_sha256"] as? String,hash(sha),
                  snap["epoch"] as? Int64==epoch,
                  snap["frame_id"] as? Int64==id,
                  snap["png_sha256"] as? String==sha,
                  let file=snap["file"] as? String,
                  file=="frames/frame_\(epoch)_\(id).png",
                  seenFrames.insert("\(epoch):\(id)").inserted,
                  frame["owner_certified"] as? Bool==false,
                  frame["species_certified"] as? Bool==false,
                  frame["mega_certified"] as? Bool==false,
                  frame["current_state_eligible"] as? Bool==false else {
                return held("HOLD_PNG_SNAPSHOT_OR_SOURCE_PROVENANCE")
            }
            if status=="HOLD_RASTER_UNAVAILABLE" {
                skipped.append(["frame_id":id,"reason":"RGBA_UNAVAILABLE"])
                continue
            }
            guard let width=frame["image_width"] as? Int,
                  let height=frame["image_height"] as? Int,
                  width>=256,height>=192,width<=4096,height<=4096,
                  snap["width"] as? Int==width,
                  snap["height"] as? Int==height,
                  let regions=frame["regions"] as? [[String:Any]],
                  regions.count==3 else {
                return held("HOLD_RASTER_GEOMETRY_OR_REGIONS")
            }
            var used=Set<String>()
            for region in regions {
                guard let name=region["name"] as? String,
                      used.insert(name).inserted,
                      (actorRegions+["MEMORY_BACKGROUND_REFERENCE"]).contains(name),
                      region["grid_width"] as? Int==16,
                      region["grid_height"] as? Int==12,
                      region["coordinate_space"] as? String == "RGBA_MEMORY_ROW_ORDER_UNVERIFIED",
                      let grid=region["luma_grid"] as? [Int],
                      grid.count==192,
                      grid.allSatisfy({(-1...255).contains($0)}),
                      let missing=region["transparent_samples"] as? Int,
                      missing==grid.filter({$0 == -1}).count else {
                    return held("HOLD_INVALID_ACTOR_GRID")
                }
                if name=="MEMORY_BACKGROUND_REFERENCE" {continue}
                guard validGrid(grid) else {
                    skipped.append(["frame_id":id,"region":name,
                                    "reason":"LOW_TEXTURE_OR_MISSING_PIXELS"])
                    continue
                }
                let key=sha+":"+name
                if !seenImages.insert(key).inserted {continue}
                let side=name==actorRegions[0] ? "L":"R"
                drafts.append([
                    "reference_id":"SEED_"+String(sha.prefix(24)).uppercased()+"_"+side,
                    "region":name,"luma_grid":grid,
                    "reference_image_sha256":sha,
                    "source_png_file":file,"source_epoch":epoch,
                    "source_frame_id":id,
                    "coordinate_space":"RGBA_MEMORY_ROW_ORDER_UNVERIFIED",
                    "human_label_reviewed":false,
                    "certified_as_game_state":false,
                    "needs_species_token":true,
                    "needs_form_token":true,
                    "needs_mega_label_claim":true,
                    "needs_region_orientation_review":true,
                    "must_review_actual_png":true])
            }
            guard used.count==3 else {return held("HOLD_MISSING_ACTOR_REGION")}
        }
        return ["schema":schema,
                "status":drafts.isEmpty ? "NO_REVIEWABLE_ACTOR_DRAFTS" :
                          "UNLABELED_REFERENCE_DRAFTS_FOR_HUMAN_REVIEW",
                "draft_count":drafts.count,"drafts":drafts,
                "skipped":skipped,
                "source_kind":"RETAINED_FRAME_PNG_WITH_SHA256",
                "target_catalog_schema":
                    "trueplan.r595.manual-form-reference-library.v1",
                "required_review_fields":["species_token","form_token",
                                          "mega_label_claim","human_label_reviewed"],
                "catalog_auto_installed":false,
                "human_label_reviewed":false,
                "owner_certified":false,"species_certified":false,
                "mega_form_certified":false,"current_state_eligible":false,
                "battle_advice_authorized":false,
                "limitations":"16x12 whole-ROI luminance; no labels, " +
                   "orientation or form calibration; do not train without review"]
    }
}
