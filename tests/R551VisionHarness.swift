import Foundation

@main struct R551VisionHarness {
    static func main() throws {
        let png = try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
        let skipped = R548MegaSceneProbe.inspect(png,budgetMs:0)
        guard (skipped["rotations_skipped"] as? [Int]) == [0,90,180,270],
              skipped["mega_certified"] as? Bool == false else {fatalError("ZERO_BUDGET_FAILURE")}
        let work = R551EvidenceWork();work.cancel()
        let cancelled = R548MegaSceneProbe.inspect(png,budgetMs:6000,work:work)
        guard cancelled["state"] as? String == "CANCELLED",
              (cancelled["rotations_completed"] as? [Int])?.isEmpty == true else {fatalError("CANCEL_FAILURE")}
        let invalid = R548MegaSceneProbe.inspect(Data())
        guard invalid["state"] as? String == "INVALID_IMAGE_SIZE" else {fatalError("EMPTY_FAILURE")}
        // Synthetic pixels exercise Vision invocation/limits only, never game accuracy.
        let result = R548MegaSceneProbe.inspect(png,budgetMs:3500)
        guard result["mega_certified"] as? Bool == false,
              result["megascene_observed"] is NSNull,
              result["own_opponent"] as? String == "UNKNOWN" else {fatalError("FALSE_MEGA_CERTIFICATION")}
        let data = try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys])
        try data.write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
        print("R551_VISION_SYNTHETIC_CASES_PASS=4; GAME_ACCURACY_UNVERIFIED")
    }
}
