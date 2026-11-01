import Foundation

// R597: an evidence-preserving bridge from R596 admitted vectors to an exportable
// R595-style candidate. Does not bypass R596's production HOLD or certify Mega.
struct R597FrameObservation: Codable {
    let battleID: String
    let epoch: Int
    let frameID: Int
    let actorToken: String
    let captureSide: String
    let cropSHA256: String
    let extractorID: String
    let features: [Double]
    let hasVerifiedActorBinding: Bool
    let hasVerifiedOrientation: Bool
}

struct R597FormCandidate: Codable {
    let speciesID: String?
    let formID: String?
    let status: String
    let reason: String
    let bestDistance: Double?
    let secondDistance: Double?
    let supportingSessions: Int
}

struct R597EvidenceExport: Codable {
    let schema: String
    let battleID: String
    let epoch: Int
    let frameID: Int
    let actorToken: String
    let captureSide: String
    let cropSHA256: String
    let result: R597FormCandidate
    let certification: String
}

struct R597FormEvidenceBridge {
    static let exportSchema = "trueplan.r597.form_evidence.v1"
    // Research-only bounds. Not calibrated against game screenshots.
    static let maximumDistance = 0.10
    static let minimumMargin = 0.05

    private static func hold(_ reason: String, support: Int = 0) -> R597FormCandidate {
        R597FormCandidate(speciesID: nil, formID: nil, status: "hold", reason: reason,
                         bestDistance: nil, secondDistance: nil, supportingSessions: support)
    }

    static func propose(_ obs: R597FrameObservation, catalogData: Data) -> R597FormCandidate {
        guard !obs.battleID.isEmpty && !obs.actorToken.isEmpty && obs.epoch >= 0 && obs.frameID >= 0
        else { return hold("ACTOR_OR_FRAME_MISSING") }
        guard obs.hasVerifiedActorBinding && obs.hasVerifiedOrientation &&
              ["own", "opponent"].contains(obs.captureSide) else {
            return hold("SIDE_OR_ORIENTATION_UNVERIFIED")
        }
        guard obs.cropSHA256.count == 64 && obs.cropSHA256.allSatisfy({ $0.isHexDigit }) else {
            return hold("OBSERVATION_CROP_SHA_INVALID")
        }
        guard obs.extractorID == R596FormCatalogGate.extractorID &&
              obs.features.count == R596FormCatalogGate.featureCount &&
              obs.features.allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }) else {
            return hold("R595_EXTRACTOR_CONTRACT_UNVERIFIED")
        }
        let report: R596CatalogReport
        do { report = try R596FormCatalogGate.load(catalogData) }
        catch { return hold("REFERENCE_CATALOG_INVALID") }
        guard !report.readyFormKeys.isEmpty else { return hold("NO_INDEPENDENT_FORM_REFERENCES") }
        // Do not compare to the exact same crop used for registration.
        guard !report.validReferences.contains(where: { $0.imageSHA256 == obs.cropSHA256 }) else {
            return hold("TRAINING_CROP_REPLAY")
        }
        // Require all comparison references to be from valid independently sourced sessions.
        var byForm: [String: [(String, Double)]] = [:]
        for ref in report.validReferences where report.readyFormKeys.contains(ref.speciesID + "/" + ref.formID) && ref.captureSide == obs.captureSide && ref.sessionID != obs.battleID {
            let distance = zip(ref.features, obs.features).reduce(0.0) { partial, item in
                let d = item.0 - item.1
                return partial + d * d
            }
            guard distance.isFinite else { return hold("FEATURE_DISTANCE_OVERFLOW") }
            let rms = sqrt(distance / Double(R596FormCatalogGate.featureCount))
            byForm[ref.speciesID + "/" + ref.formID, default: []].append((ref.sessionID, rms))
        }
        // Aggregate per independent capture session, then by form. Prevent a
        // prolific single-session sample from overwhelming rarer forms.
        var distances: [(key: String, distance: Double, sessions: Int)] = []
        for (key, rows) in byForm {
            var bestBySession: [String: Double] = [:]
            for (session, distance) in rows {
                bestBySession[session] = min(bestBySession[session] ?? .infinity, distance)
            }
            guard bestBySession.count >= R596FormCatalogGate.minIndependentSessions else { continue }
            let values = bestBySession.values.sorted()
            // Conservative: second-best independent session must also be close.
            distances.append((key, values[1], bestBySession.count))
        }
        distances.sort { $0.distance == $1.distance ? $0.key < $1.key : $0.distance < $1.distance }
        guard let best = distances.first else { return hold("NO_COMPARABLE_REFERENCES") }
        guard best.distance <= maximumDistance else { return hold("DISTANCE_TOO_LARGE", support: best.sessions) }
        let second = distances.dropFirst().first?.distance
        guard second == nil || (second! - best.distance) >= minimumMargin else {
            return hold("FORM_AMBIGUITY", support: best.sessions)
        }
        let parts = best.key.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return hold("FORM_KEY_INVALID") }
        return R597FormCandidate(speciesID: String(parts[0]), formID: String(parts[1]),
                                 status: "candidate_unverified", reason: "REAL_GAME_HELDOUT_NOT_CERTIFIED",
                                 bestDistance: best.distance, secondDistance: second, supportingSessions: best.sessions)
    }

    static func export(_ obs: R597FrameObservation, catalogData: Data) throws -> Data {
        let candidate = propose(obs, catalogData: catalogData)
        let record = R597EvidenceExport(schema: exportSchema, battleID: obs.battleID,
                                        epoch: obs.epoch, frameID: obs.frameID,
                                        actorToken: obs.actorToken, captureSide: obs.captureSide,
                                        cropSHA256: obs.cropSHA256, result: candidate,
                                        certification: "NOT_CERTIFIED_FOR_LIVE_BATTLE")
        return try JSONEncoder().encode(record)
    }
}
