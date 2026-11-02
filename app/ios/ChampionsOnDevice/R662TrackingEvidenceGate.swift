import Foundation
import CoreFoundation

/// Provenance/geometry fence for UNCALIBRATED region tracking.
/// No region is an identified Pokémon or certified owner.
enum R662TrackingEvidenceGate {
    static let schema = "trueplan.r662.region-track-fence.v1"
    struct Region {
        let name: String
        let x: Double        // top-left normalized
        let y: Double
        let width: Double
        let height: Double
    }
    static let seeds: [Region] = [
        .init(name: "LEFT_REGION_HYPOTHESIS", x: 0.10,
              y: 0.36, width: 0.31, height: 0.32),
        .init(name: "RIGHT_REGION_HYPOTHESIS", x: 0.60,
              y: 0.40, width: 0.22, height: 0.30)
    ]
    private static func int64(_ v: Any?) -> Int64? {
        guard let n = v as? NSNumber,
              CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let d = n.doubleValue
        guard d.isFinite, d.rounded() == d,
              d > -9.22e18, d < 9.22e18 else { return nil }
        return n.int64Value
    }
    static func geometry(_ regions: [Region]) -> String {
        guard regions.count == 2,
              regions.map({$0.name}) == seeds.map({$0.name}) else {
            return "HOLD_UNAPPROVED_REGION_SET"
        }
        for r in regions {
            guard [r.x,r.y,r.width,r.height].allSatisfy({$0.isFinite}),
                  r.x >= 0, r.y >= 0,
                  r.width >= 0.05, r.height >= 0.05,
                  r.x + r.width <= 1, r.y + r.height <= 1 else {
                return "HOLD_REGION_GEOMETRY"
            }
        }
        let a=regions[0], b=regions[1]
        let overlapX=max(0,min(a.x+a.width,b.x+b.width)-max(a.x,b.x))
        let overlapY=max(0,min(a.y+a.height,b.y+b.height)-max(a.y,b.y))
        guard overlapX*overlapY == 0 else {
            return "HOLD_OVERLAPPING_HYPOTHESES"
        }
        return "REGION_GEOMETRY_HYPOTHESIS_ONLY"
    }
    static func provenance(frameIDs: [Int64],
                           times: [Int64],
                           hashes: [String],
                           evidence: [String:Any]) -> String {
        guard frameIDs.count == 4, times.count == 4,
              hashes.count == 4 else {
            return "HOLD_FOUR_FRAME_PROVENANCE"
        }
        guard evidence["status"] as? String ==
                "HISTORICAL_CROSS_MODAL_EVIDENCE_ONLY",
              evidence["source_join_verified"] as? Bool == true,
              evidence["pairs_checked"] as? Int == 3,
              evidence["region_calibrated"] as? Bool == false,
              evidence["owner_certified"] as? Bool == false,
              evidence["species_certified"] as? Bool == false,
              evidence["mega_event_certified"] as? Bool == false,
              evidence["mega_form_certified"] as? Bool == false,
              evidence["current_state_eligible"] as? Bool == false,
              evidence["battle_advice_authorized"] as? Bool == false,
              evidence["held_out_accuracy"] as? String == "NOT_MEASURED",
              let pairs = evidence["pairs"] as? [[String:Any]],
              pairs.count == 3 else {
            return "HOLD_R661_JOIN_UNAVAILABLE"
        }
        guard frameIDs[0] > 0, times[0] > 0,
              Set(frameIDs).count == 4, Set(hashes).count == 4,
              zip(frameIDs,frameIDs.dropFirst()).allSatisfy({$0 < $1}),
              zip(times,times.dropFirst()).allSatisfy({$0 < $1}),
              hashes.allSatisfy({s in s.count == 64 && s.utf8.allSatisfy({
                  (48...57).contains($0) || (97...102).contains($0)
              })}) else {
            return "HOLD_TRACK_FRAME_ORDER"
        }
        for i in 0..<3 {
            let p=pairs[i]
            guard int64(p["from_frame_id"]) == frameIDs[i],
                  int64(p["to_frame_id"]) == frameIDs[i+1],
                  p["source_sha256_from"] as? String == hashes[i],
                  p["source_sha256_to"] as? String == hashes[i+1],
                  p["diagnostic_only"] as? Bool == true,
                  p["camera_or_actor_motion_distinguished"] as? Bool == false,
                  p["mega_event_confirmed"] as? Bool == false else {
                return "HOLD_TRACK_SOURCE_MISMATCH"
            }
        }
        return "TRACK_SOURCE_BOUND_RESEARCH_ONLY"
    }
    static func box(_ b: [Double]) -> String {
        guard b.count == 4, b.allSatisfy({$0.isFinite}),
              b[0]>=0, b[1]>=0, b[2]>0, b[3]>0,
              b[0]+b[2]<=1.000001,
              b[1]+b[3]<=1.000001 else {
            return "HOLD_TRACK_BOX_OUTSIDE_IMAGE"
        }
        return "NORMALIZED_BOX_DIAGNOSTIC_ONLY"
    }
}
