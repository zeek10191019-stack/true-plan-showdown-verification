import Foundation

/// Research-only class-level comparison of local, reviewed image descriptors.
/// Rejects unbalanced reference libraries: duplicate images of a form are
/// not independent counterexamples; missing BASE/X/Y/Z controls force HOLD.
enum R654MegaVisualClassGate {
    static let schema = "trueplan.r654.mega-visual-class-gate.v1"
    struct Decision {
        let status: String
        let species: String?
        let form: String?
        let best: Int?
        let competing: Int?
        let distinctClasses: Int
        let referenceCount: Int
        var candidate: Bool { status == "VISUAL_FORM_CANDIDATE_ONLY" }
        let ownerCertified = false
        let megaCertified = false
        let battleAdviceAuthorized = false
    }
    private static func hold(_ status: String, _ classes: Int = 0,
                             _ count: Int = 0, _ first: Int? = nil,
                             _ second: Int? = nil) -> Decision {
        Decision(status: status, species: nil, form: nil,
                 best: first, competing: second,
                 distinctClasses: classes, referenceCount: count)
    }
    private static func formToken(_ variant: String) -> String {
        variant == "N" ? "MEGA" : "MEGA_" + variant
    }
    /// Input: score, species-token, form-token, human-reviewed label.
    /// The score must come from the same ROI and a single valid frame.
    static func adjudicate(_ scores: [(Int, String, String)],
                           expected: [String: Set<String>]) -> Decision {
        guard scores.count <= 512 else {
            return hold("HOLD_CAPACITY")
        }
        guard !scores.isEmpty else {
            return hold("HOLD_NO_REFERENCES")
        }
        var byClass = [String: Int]()
        var all = [String: Set<String>]()
        for (score, species, form) in scores {
            guard (0...255).contains(score),
                  let permitted = expected[species],
                  permitted.contains(form) else {
                return hold("HOLD_UNREGISTERED_FORM")
            }
            let key = species + "|" + form
            if let previous = byClass[key] {
                byClass[key] = min(previous, score)
            } else {
                byClass[key] = score
            }
            all[species, default: []].insert(form)
        }
        let ranked = byClass.sorted {
            if $0.value != $1.value { return $0.value < $1.value }
            return $0.key < $1.key
        }
        guard let top = ranked.first else { return hold("HOLD_NO_REFERENCES") }
        let components = top.key.split(separator: "|", omittingEmptySubsequences: false)
        guard components.count == 2 else { return hold("HOLD_CLASS_KEY") }
        let species = String(components[0]), form = String(components[1])
        let best = top.value
        guard all[species] == expected[species] else {
            return hold("HOLD_MISSING_SAME_SPECIES_FORMS",
                        byClass.count, scores.count, best)
        }
        guard best <= 12 else {
            return hold("HOLD_NO_CLOSE_MATCH", byClass.count,
                        scores.count, best)
        }
        guard ranked.count > 1 else {
            return hold("HOLD_NO_NEGATIVE_CONTROL", byClass.count,
                        scores.count, best)
        }
        let second = ranked[1].value
        guard second - best >= 8 else {
            return hold("HOLD_CLASS_AMBIGUITY", byClass.count,
                        scores.count, best, second)
        }
        return Decision(status: "VISUAL_FORM_CANDIDATE_ONLY",
                        species: species, form: form,
                        best: best, competing: second,
                        distinctClasses: byClass.count,
                        referenceCount: scores.count)
    }
    private static func table() -> [String: Set<String>]? {
        guard R649MegaRegistryAudit.validCatalog(),
              R649MegaRegistryAudit.entries.count == 81 else { return nil }
        var map = [String: Set<String>]()
        for r in R649MegaRegistryAudit.entries {
            let species = r.species.uppercased()
            map[species, default: ["BASE"]].insert(formToken(r.variant))
        }
        return map
    }
    private static func lumaScore(_ a: [Int], _ b: [Int]) -> Int? {
        guard a.count == 192, b.count == 192 else { return nil }
        let pairs = zip(a,b).filter { $0.0 >= 0 && $0.1 >= 0 }
        guard pairs.count >= 180 else { return nil }
        let meanA = Double(pairs.reduce(0) { $0 + $1.0 }) / Double(pairs.count)
        let meanB = Double(pairs.reduce(0) { $0 + $1.1 }) / Double(pairs.count)
        let loss = pairs.reduce(0.0) { $0 + abs(Double($1.0)-meanA-Double($1.1)+meanB) }
        return Int((loss / Double(pairs.count)).rounded())
    }
    private static func fail(_ reason: String, _ count: Int = 0) -> [String:Any] {
        ["schema": schema, "status": reason, "frames": [[String:Any]](),
         "frame_count": count, "eligible_mega_forms": 81,
         "owner_certified": false, "mega_event_certified": false,
         "species_certified": false, "mega_form_certified": false,
         "current_state_eligible": false, "battle_advice_authorized": false]
    }
    static func audit(frames: [[String:Any]], references: [[String:Any]]) -> [String:Any] {
        guard let expected = table() else { return fail("HOLD_REGISTRY") }
        guard frames.count <= 8, references.count <= 512 else {
            return fail("HOLD_CAPACITY")
        }
        // Reuse R595's full provenance, grid and reviewed-reference validator.
        let upstream = R595FormReferenceMatcher.audit(frames, references: references)
        guard upstream["schema"] as? String == R595FormReferenceMatcher.schema else {
            return fail("HOLD_UPSTREAM_SCHEMA")
        }
        let status = upstream["status"] as? String ?? ""
        guard status == "HISTORICAL_REFERENCE_FORM_CANDIDATES_ONLY" else {
            return fail("HOLD_UPSTREAM_" + status, frames.count)
        }
        var rows = [[String:Any]]()
        for frame in frames {
            guard let regions = frame["regions"] as? [[String:Any]],
                  let sha = frame["image_sha256"] as? String,
                  let epoch = frame["epoch"] as? Int64,
                  let id = frame["frame_id"] as? Int64 else {
                return fail("HOLD_FRAME_PROVENANCE")
            }
            var candidates = [[String:Any]]()
            for region in regions where
                (region["name"] as? String ?? "").hasPrefix("MEMORY_") &&
                region["name"] as? String != "MEMORY_BACKGROUND_REFERENCE" {
                guard let side = region["name"] as? String,
                      let grid = region["luma_grid"] as? [Int] else {
                    return fail("HOLD_INVALID_REGION_GRID")
                }
                var scores = [(Int,String,String)]()
                for reference in references where reference["region"] as? String == side {
                    guard let species = reference["species_token"] as? String,
                          let form = reference["form_token"] as? String,
                          let luma = reference["luma_grid"] as? [Int],
                          let score = lumaScore(grid,luma) else { continue }
                    scores.append((score,species,form))
                }
                let d = adjudicate(scores, expected: expected)
                var row: [String:Any] = [
                    "region": side, "status": d.status,
                    "reference_count": d.referenceCount,
                    "distinct_form_classes": d.distinctClasses,
                    "owner": "UNKNOWN", "mega_confirmed": false,
                    "species_certified": false, "mega_form_certified": false]
                if let x = d.best { row["best_distance"] = x }
                if let x = d.competing { row["competitor_distance"] = x }
                if d.candidate, let s = d.species, let f = d.form {
                    row["species_claim"] = s
                    row["form_claim"] = f
                    row["label_is_ground_truth"] = false
                }
                candidates.append(row)
            }
            rows.append(["epoch": epoch, "frame_id": id,
                         "image_sha256": sha, "regions": candidates,
                         "provenance_certified": false])
        }
        return ["schema": schema,
                "status": "HISTORICAL_FORM_CLASS_CANDIDATES_ONLY",
                "eligible_mega_forms": 81,
                "frame_count": rows.count, "frames": rows,
                "owner_certified": false, "mega_event_certified": false,
                "species_certified": false, "mega_form_certified": false,
                "current_state_eligible": false, "battle_advice_authorized": false,
                "limitations": "Luminance-only, 16x12 guessed ROIs, no game-image calibration"]
    }
}
