import Foundation

/// R525 research component. It cannot certify an image classifier or unlock battle advice.
/// Mega appearance is persistent evidence; the transformation animation is NOT required.
/// An opponent can be tracked after switching only when the same roster identity is verified.
public enum R525Side: String, Codable { case own, opponent }
public struct R525Identity: Hashable, Codable {
    public let battleID: String
    public let epoch: Int
    public let side: R525Side
    public let rosterIdentity: String
    public init(battleID: String, epoch: Int, side: R525Side, rosterIdentity: String) {
        self.battleID = battleID; self.epoch = epoch
        self.side = side; self.rosterIdentity = rosterIdentity
    }
}
public enum R525Signal: String, Codable {
    case transformationEvent, persistentMegaSprite, persistentMegaUI
    case speciesNameOCR, sandstorm, uncheckedSprite, manualGroundTruth
}
public enum R525MegaVerdict: String, Codable {
    case unknown, candidate, confirmed, conflict
}
public struct R525MegaObservation: Codable {
    public let identity: R525Identity
    public let frameID: Int
    public let imageSHA256: String
    public let signal: R525Signal
    public let claimsMega: Bool
    public let ownerCertified: Bool
    public let currentFrameCertified: Bool
    public let orientationCertified: Bool
    public let signalDetectorCertified: Bool
    public let confidence: Double
    public init(identity: R525Identity, frameID: Int, imageSHA256: String,
                signal: R525Signal, claimsMega: Bool,
                ownerCertified: Bool, currentFrameCertified: Bool,
                orientationCertified: Bool, signalDetectorCertified: Bool,
                confidence: Double) {
        self.identity = identity; self.frameID = frameID
        self.imageSHA256 = imageSHA256; self.signal = signal
        self.claimsMega = claimsMega; self.ownerCertified = ownerCertified
        self.currentFrameCertified = currentFrameCertified
        self.orientationCertified = orientationCertified
        self.signalDetectorCertified = signalDetectorCertified
        self.confidence = confidence
    }
    public var eligible: Bool {
        guard frameID >= 0, imageSHA256.count == 64,
              imageSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              ownerCertified, currentFrameCertified, orientationCertified,
              signalDetectorCertified, confidence.isFinite, confidence >= 0.95,
              !identity.battleID.isEmpty, identity.epoch >= 0,
              !identity.rosterIdentity.isEmpty else { return false }
        switch signal {
        case .transformationEvent, .persistentMegaSprite, .persistentMegaUI: return true
        case .speciesNameOCR, .sandstorm, .uncheckedSprite, .manualGroundTruth: return false
        }
    }
}

public final class R525MegaEvidenceLedger {
    private var storage: [R525Identity: [R525MegaObservation]] = [:]
    public private(set) var rejectedCount = 0
    public private(set) var researchCount = 0
    public init() {}
    @discardableResult
    public func ingest(_ o: R525MegaObservation, activeBattleID: String, activeEpoch: Int,
                       activeFrameID: Int) -> Bool {
        guard o.identity.battleID == activeBattleID,
              o.identity.epoch == activeEpoch,
              o.frameID == activeFrameID else {
            rejectedCount += 1; return false
        }
        if !o.eligible { researchCount += 1; return false }
        // Repeated reports for the SAME frame/hash/signal are not independent evidence.
        var observations = storage[o.identity, default: []]
        guard !observations.contains(where: {
            $0.frameID == o.frameID && $0.imageSHA256 == o.imageSHA256 && $0.signal == o.signal
        }) else { return false }
        observations.append(o)
        storage[o.identity] = observations
        return true
    }
    public func status(_ id: R525Identity) -> R525MegaVerdict {
        let accepted = storage[id, default: []]
        if accepted.isEmpty { return .unknown }
        let conclusive = accepted.filter { $0.claimsMega &&
            ($0.signal == .transformationEvent || $0.signal == .persistentMegaUI) }
        let sprites = accepted.filter { $0.claimsMega && $0.signal == .persistentMegaSprite }
        // A certified base form BEFORE activation is expected, not a conflict.
        if let first = conclusive.map(\.frameID).min() {
            if accepted.contains(where: { !$0.claimsMega && $0.frameID >= first }) {
                return .conflict
            }
            return .confirmed
        }
        guard let firstSprite = sprites.map(\.frameID).min() else { return .unknown }
        if accepted.contains(where: { !$0.claimsMega && $0.frameID >= firstSprite }) {
            return .conflict
        }
        let uniqueImages = Set(sprites.map(\.imageSHA256))
        let uniqueFrames = Set(sprites.map(\.frameID))
        return uniqueImages.count >= 2 && uniqueFrames.count >= 2 ? .confirmed : .candidate
    }
    public func resetAll() { storage.removeAll(); rejectedCount = 0; researchCount = 0 }
    public func acceptedCount(_ id: R525Identity) -> Int { storage[id]?.count ?? 0 }
    public func isBattlePhysicsMegaEligible(_ id: R525Identity) -> Bool {
        // An independent identity/side/appearance gate must still pass upstream.
        status(id) == .confirmed
    }
}
