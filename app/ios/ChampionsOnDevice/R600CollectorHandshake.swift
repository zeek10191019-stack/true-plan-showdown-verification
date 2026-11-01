import Foundation

// R600 - a deterministic pre-ZIP handoff that correlates the original frame
// and the R595-style feature producer. This does not patch the app's button.
// Unverified ROI/actor/orientation remain HOLD, never a LIVE_COACH signal.
struct R600FrameStamp {
    let battleID: String
    let epoch: Int
    let frameID: Int
    let actorToken: String
    let side: String
    let cropRelativePath: String
    let cropSHA256: String
    let orientation: String
    let roiLayoutID: String
    let actorVerified: Bool
    let orientationVerified: Bool
}

struct R600FeatureStamp {
    let battleID: String
    let epoch: Int
    let frameID: Int
    let actorToken: String
    let side: String
    let cropSHA256: String
    let orientation: String
    let roiLayoutID: String
    let extractorID: String
    let features: [Double]
}

struct R600HandshakeReceipt {
    let emitted: Bool
    let reason: String
    let evidenceRelativePath: String?
}

enum R600CollectorHandshake {
    private static let allowedOrientation: Set<String> = ["landscape-left", "landscape-right"]
    private static func fail(_ reason: String) -> R600HandshakeReceipt {
        R600HandshakeReceipt(emitted: false, reason: reason, evidenceRelativePath: nil)
    }
    private static func safeToken(_ x: String, max: Int = 96) -> Bool {
        !x.isEmpty && x.count <= max && x.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) ||
            (97...122).contains($0) || $0 == 95 || $0 == 45 || $0 == 46 || $0 == 58
        }
    }
    // Must be invoked within an existing one-button bundle stage *before* ZIP
    // closure. No filename guessing and no automatic enrolment in the form DB.
    static func stage(bundleRoot: URL, frame: R600FrameStamp,
                      producer: R600FeatureStamp, catalogData: Data,
                      manifestName: String = "manifest.json") -> R600HandshakeReceipt {
        guard safeToken(frame.battleID), safeToken(frame.actorToken),
              safeToken(frame.roiLayoutID), frame.epoch >= 0, frame.frameID >= 0,
              ["own", "opponent"].contains(frame.side) else {
            return fail("FRAME_STAMP_NOT_TRUSTWORTHY")
        }
        guard frame.actorVerified && frame.orientationVerified &&
              allowedOrientation.contains(frame.orientation) else {
            return fail("OWNER_OR_ORIENTATION_UNVERIFIED")
        }
        guard producer.battleID == frame.battleID,
              producer.epoch == frame.epoch, producer.frameID == frame.frameID,
              producer.actorToken == frame.actorToken, producer.side == frame.side,
              producer.cropSHA256 == frame.cropSHA256,
              producer.orientation == frame.orientation,
              producer.roiLayoutID == frame.roiLayoutID else {
            return fail("FRAME_FEATURE_PROVENANCE_MISMATCH")
        }
        guard producer.extractorID == R596FormCatalogGate.extractorID,
              producer.features.count == R596FormCatalogGate.featureCount,
              producer.features.allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }) else {
            return fail("FEATURE_EXTRACTOR_CONTRACT_UNVERIFIED")
        }
        guard frame.cropSHA256.count == 64 &&
              frame.cropSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            return fail("CROP_SHA256_MALFORMED")
        }
        let observation = R597FrameObservation(
            battleID: frame.battleID, epoch: frame.epoch, frameID: frame.frameID,
            actorToken: frame.actorToken, captureSide: frame.side,
            cropSHA256: frame.cropSHA256, extractorID: producer.extractorID,
            features: producer.features, hasVerifiedActorBinding: frame.actorVerified,
            hasVerifiedOrientation: frame.orientationVerified)
        let result = R599BoundOneButton.attachBeforeZip(
            bundleRoot: bundleRoot, cropRelativePath: frame.cropRelativePath,
            observation: observation, catalogData: catalogData, manifestName: manifestName)
        return R600HandshakeReceipt(emitted: result.emitted, reason: result.reason,
                                     evidenceRelativePath: result.sidecarPath)
    }
}
