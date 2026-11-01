import Foundation

/// Validates R595 image-match suggestions against the season registry.
/// Never certifies species, role, Mega activation or a strategic set.
/// This bridge is fully offline; no remote or bundled Pokémon images.
enum R650MegaReferenceBridge {
 static let schema = "trueplan.r650.mega-reference-bridge.v1"
 private static func form(_ r:R649MegaEntry)->String {
  if r.variant == "N" { return "MEGA" }
  return "MEGA_" + r.variant
 }
 private static func allowed(_ species:String,_ form:String,
                             _ mega:Bool)->Bool {
  if form == "BASE" && !mega {
   return R649MegaRegistryAudit.entries.contains {
    $0.species.uppercased() == species
   }
  }
  if !mega {return false}
  return R649MegaRegistryAudit.entries.contains {
   $0.species.uppercased() == species && self.form($0) == form
  }
 }
 private static func hold(_ reason:String,refs:Int=0)->[String:Any] {
  return ["schema":schema,"status":reason,
   "reference_count":refs,"eligible_mega_forms":81,
   "bounded_image_matches":0,"unverified_form_candidates":0,
   "owner_verified":false,"species_certified":false,
   "mega_event_certified":false,"mega_form_certified":false,
   "current_state_eligible":false,"battle_advice_authorized":false,
   "limitations":"No independent 3D game model calibration"]
 }
 static func audit(frames:[[String:Any]],references:[[String:Any]])
  ->[String:Any] {
  guard R649MegaRegistryAudit.validCatalog() else {
   return hold("HOLD_REGISTRY_INTEGRITY")
  }
  guard references.count<=512,frames.count<=8 else {
   return hold("HOLD_BOUNDED_INPUT")
  }
  // A reference's human label is a claim, not an assertion of truth.
  for r in references {
   guard let species=r["species_token"] as? String,
    let form=r["form_token"] as? String,
    let mega=r["mega_label_claim"] as? Bool,
    allowed(species,form,mega),
    r["certified_as_game_state"] as? Bool == false
   else {return hold("HOLD_FOREIGN_OR_CONFLICTING_LABEL")}
  }
  guard !references.isEmpty else {
   return hold("HOLD_NO_GAME_REFERENCES")
  }
  let visual=R595FormReferenceMatcher.audit(frames,
                                           references:references)
  guard visual["schema"] as? String ==
         R595FormReferenceMatcher.schema,
        visual["status"] as? String ==
         "HISTORICAL_REFERENCE_FORM_CANDIDATES_ONLY",
        let rows=visual["frames"] as? [[String:Any]],
        rows.count == frames.count,
        let transitions=visual["possible_form_transitions"]
         as? [[String:Any]]
  else {return hold("HOLD_UPSTREAM_REFERENCE_GATE")}
  var matches=0,unverified=[[String:Any]]()
  for (i,row) in rows.enumerated() {
   guard let frame=frames[i]["frame_id"] as? Int64,
    let epoch=frames[i]["epoch"] as? Int64,
    let sha=frames[i]["image_sha256"] as? String,
    row["frame_id"] as? Int64 == frame,
    row["epoch"] as? Int64 == epoch,
    row["image_sha256"] as? String == sha,
    let regions=row["regions"] as? [[String:Any]]
   else {return hold("HOLD_FRAME_BINDING_MISMATCH")}
   for region in regions {
    guard region["status"] as? String ==
            "VISUAL_FORM_REFERENCE_MATCH_CANDIDATE" else {continue}
    guard let species=region["species_token"] as? String,
     let form=region["form_token"] as? String,
     let mega=region["mega_label_claim"] as? Bool,
     allowed(species,form,mega) else {
     return hold("HOLD_UNREGISTERED_VISUAL_CANDIDATE")
    }
    matches += 1
    unverified.append(["frame_id":frame,"epoch":epoch,
       "image_sha256":sha,"region":region["region"] ?? "UNKNOWN",
       "species_claim":species,"form_claim":form,
       "mega_claim":mega,"owner":"UNKNOWN",
       "visual_match_is_confirmation":false])
   }
  }
  // R595 transitions remain suggestions only. Never convert a
  // BASE->MEGA similarity result into a confirmed on-field event.
  guard transitions.allSatisfy({
   $0["mega_confirmed"] as? Bool == false &&
   $0["owner"] as? String == "UNKNOWN"
  }) else {return hold("HOLD_UNAUTHORIZED_TRANSITION_PROMOTION")}
  return ["schema":schema,
   "status":"HISTORICAL_IMAGE_CANDIDATES_NOT_CERTIFICATION",
   "reference_count":references.count,
   "eligible_mega_forms":81,"bounded_image_matches":matches,
   "unverified_form_candidates":unverified.count,
   "candidates":unverified,
   "possible_transition_count":transitions.count,
   "owner_verified":false,"species_certified":false,
   "mega_event_certified":false,"mega_form_certified":false,
   "current_state_eligible":false,"battle_advice_authorized":false,
   "limitations":"Unknown owner and geometry calibration; art is not 3D frame"]
 }
}
