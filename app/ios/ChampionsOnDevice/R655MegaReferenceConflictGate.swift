import Foundation

/// Rejects contradictory human labels on the same historical image or
/// indistinguishable 16x12 appearance. This is NOT recognition or proof of Mega.
enum R655MegaReferenceConflictGate {
    static let schema = "trueplan.r655.mega-reference-conflict-gate.v1"
    private static let regions: Set<String> = [
        "MEMORY_LEFT_ACTOR_HYPOTHESIS", "MEMORY_RIGHT_ACTOR_HYPOTHESIS"
    ]
    private static func token(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.count <= 64 && text.utf8.allSatisfy {
            (65...90).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }
    }
    private static func hash(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
    private static func hold(_ code: String, _ count: Int) -> [String: Any] {
        ["schema":schema,"status":code,"reference_count":count,
         "owner_certified":false,"mega_event_certified":false,
         "mega_form_certified":false,"species_certified":false,
         "current_state_eligible":false,"battle_advice_authorized":false,
         "verified_image_source":false,"integrity_approved":false]
    }
    private static func expected() -> [String: Set<String>]? {
        guard R649MegaRegistryAudit.validCatalog(),
              R649MegaRegistryAudit.entries.count == 81 else { return nil }
        var result: [String: Set<String>] = [:]
        for form in R649MegaRegistryAudit.entries {
            let species = form.species.uppercased()
            let name = form.variant == "N" ? "MEGA" : "MEGA_" + form.variant
            result[species,default:["BASE"]].insert(name)
        }
        return result
    }
    static func audit(references: [[String:Any]]) -> [String:Any] {
        guard let validForms = expected() else {
            return hold("HOLD_REGISTRY_INVALID", references.count)
        }
        guard references.count <= 512 else {
            return hold("HOLD_REFERENCE_CAPACITY", references.count)
        }
        guard !references.isEmpty else {
            return hold("HOLD_NO_LOCAL_REFERENCES",0)
        }
        var imageRegionLabel: [String:String] = [:]
        var imageRegionGrid: [String:[Int]] = [:]
        var gridLabel: [String:String] = [:]
        var ids=Set<String>()
        var forms=Set<String>()
        for ref in references {
            guard let id=ref["reference_id"] as? String,token(id),
                  ids.insert(id).inserted,
                  let region=ref["region"] as? String,regions.contains(region),
                  let species=ref["species_token"] as? String,token(species),
                  let form=ref["form_token"] as? String,token(form),
                  validForms[species]?.contains(form) == true,
                  let mega=ref["mega_label_claim"] as? Bool,
                  mega == (form != "BASE"),
                  ref["human_label_reviewed"] as? Bool == true,
                  ref["certified_as_game_state"] as? Bool == false,
                  let sha=ref["reference_image_sha256"] as? String,hash(sha),
                  ref["coordinate_space"] as? String == "RGBA_MEMORY_ROW_ORDER_UNVERIFIED",
                  let pixels=ref["luma_grid"] as? [Int],pixels.count == 192,
                  pixels.allSatisfy({ (-1...255).contains($0) }),
                  pixels.filter({$0 >= 0}).count >= 180
            else { return hold("HOLD_INVALID_REFERENCE", references.count) }
            let visible=pixels.filter{$0 >= 0}
            guard (visible.max() ?? 0)-(visible.min() ?? 0) >= 25 else {
                return hold("HOLD_FLAT_IMAGE_GRID",references.count)
            }
            let key=region+"|"+sha
            let label=species+"|"+form
            if let previous=imageRegionLabel[key], previous != label {
                return hold("HOLD_SAME_IMAGE_CONTRADICTORY_FORM",references.count)
            }
            imageRegionLabel[key]=label
            if let previous=imageRegionGrid[key], previous != pixels {
                return hold("HOLD_SAME_IMAGE_CONTRADICTORY_PIXELS",references.count)
            }
            imageRegionGrid[key]=pixels
            // Same 16x12 samples cannot independently discriminate
            // competing form labels, even across different source PNGs.
            let signature=region+"|"+pixels.map(String.init).joined(separator:",")
            if let previous=gridLabel[signature], previous != label {
                return hold("HOLD_IDENTICAL_GRID_DIFFERENT_FORM",references.count)
            }
            gridLabel[signature]=label
            forms.insert(label)
        }
        return ["schema":schema,
                "status":"REVIEWED_LABEL_CONSISTENCY_ONLY",
                "reference_count":references.count,
                "distinct_form_classes":forms.count,
                "distinct_source_roi_pairs":imageRegionLabel.count,
                "owner_certified":false,"mega_event_certified":false,
                "mega_form_certified":false,"species_certified":false,
                "current_state_eligible":false,"battle_advice_authorized":false,
                "verified_image_source":false,"integrity_approved":true,
                "limitations":"No RGB or geometry; labels are manually supplied claims"]
    }
}
