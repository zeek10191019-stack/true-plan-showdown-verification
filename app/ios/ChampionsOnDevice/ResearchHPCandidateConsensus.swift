import Foundation

// Treat multiple OCR passes as *independent diagnostic candidates*, never as
// permission to assign own/opp. Divergence must be reported, not silently chosen.
enum ResearchHPCandidateConsensus {
    struct Result {
        let readings: [ResearchReading]
        let status: String
    }
    static func inspect(_ passes:[String], side:String) -> Result {
        guard side=="own" || side=="opp" else {
            return Result(readings:[],status:"INVALID_SIDE_HOLD")
        }
        let distinct = Array(Set(passes.map { $0.precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in:.whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        let valid = distinct.filter { !ResearchLiteralParser.hp($0,side:side).isEmpty }
        var observations=[ResearchReading]()
        for raw in valid { observations += ResearchOwnerGate.unverified(ResearchLiteralParser.hp(raw,side:side),side:side) }
        let status:String
        if valid.isEmpty { status = "NO_VALID_HP_HOLD" }
        else if valid.count > 1 { status = "OCR_HP_DISAGREEMENT_HOLD" }
        else if passes.count > 1 && passes.filter({ !$0.isEmpty }).count == passes.count &&
                distinct.count == 1 { status = "TWO_PASS_SAME_LITERAL_UNVERIFIED" }
        else { status = "SINGLE_HP_LITERAL_UNVERIFIED" }
        return Result(readings:observations,status:status)
    }
}
