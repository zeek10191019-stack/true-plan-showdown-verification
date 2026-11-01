import Foundation

// Do not allow an uncalibrated ROI to assign own/opp ownership.
// This operation does not prove that the numeric candidate is correct.
enum ResearchOwnerGate {
    static func unverified(_ candidates: [ResearchReading], side: String) -> [ResearchReading] {
        guard side == "own" || side == "opp" else { return [] }
        return candidates.map { candidate in
            ResearchReading(key:nil, value:candidate.value, raw_text:candidate.raw_text,
                            confidence:nil, reason:"UNVERIFIED_ROI_OWNER_" + side.uppercased())
        }
    }
}
