import Foundation

// R602: actual pre-ZIP callsite adapter. Research evidence only.
// Never creates a verified actor, crop, or R595 feature vector by inference.
// Missing or conflicted input returns the original entries byte-for-byte.
private struct R602FormInput: Decodable {
    let battleID: String
    let epoch: Int
    let frameID: Int
    let actorToken: String
    let side: String
    let cropSHA256: String
    let orientation: String
    let roiLayoutID: String
    let actorVerified: Bool
    let orientationVerified: Bool
    let extractorID: String
    let features: [Double]
}

enum R602OneTapFormArchive {
    static let inputName = "r602_form_input.json"
    static let outputName = "r602_form_evidence.json"
    static let cropName = "crop.png"
    static let manifestName = "manifest.json"
    private static let emptyCatalog = Data(
        #"{"schema":"trueplan.r596.visual_catalog.v1","references":[]}"#.utf8
    )

    // Called immediately before R548ResearchArchive.write in the existing
    // CaptureCoordinator one-tap export path. No app UI redesign required.
    static func beforeZip(
        _ entries: [R548ResearchArchive.Entry]
    ) -> [R548ResearchArchive.Entry] {
        let original = entries
        guard entries.count < R548ResearchArchive.maximumMembers,
              Set(entries.map { $0.name }).count == entries.count,
              !entries.contains(where: { $0.name == outputName }) else {
            return original
        }
        let matches = [inputName, cropName, manifestName].map { key in
            entries.filter { $0.name == key }
        }
        guard matches.allSatisfy({ $0.count == 1 }),
              let input = try? JSONDecoder().decode(
                R602FormInput.self, from: matches[0][0].bytes
              ) else { return original }
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(
            "r602-" + UUID().uuidString, isDirectory: true
        )
        do { try fm.createDirectory(at: dir, withIntermediateDirectories: false) }
        catch { return original }
        defer { try? fm.removeItem(at: dir) }
        do {
            try matches[1][0].bytes.write(
                to: dir.appendingPathComponent(cropName), options: .atomic
            )
            try matches[2][0].bytes.write(
                to: dir.appendingPathComponent(manifestName), options: .atomic
            )
        } catch { return original }
        let stamp = R600FrameStamp(
            battleID: input.battleID, epoch: input.epoch,
            frameID: input.frameID, actorToken: input.actorToken,
            side: input.side, cropRelativePath: cropName,
            cropSHA256: input.cropSHA256, orientation: input.orientation,
            roiLayoutID: input.roiLayoutID,
            actorVerified: input.actorVerified,
            orientationVerified: input.orientationVerified
        )
        let feature = R600FeatureStamp(
            battleID: input.battleID, epoch: input.epoch,
            frameID: input.frameID, actorToken: input.actorToken,
            side: input.side, cropSHA256: input.cropSHA256,
            orientation: input.orientation, roiLayoutID: input.roiLayoutID,
            extractorID: input.extractorID, features: input.features
        )
        let catalog = entries.first(where: { $0.name == "r596_form_catalog.json" })?.bytes
            ?? emptyCatalog
        let receipt = R600CollectorHandshake.stage(
            bundleRoot: dir, frame: stamp,
            producer: feature, catalogData: catalog
        )
        guard receipt.emitted,
              let path = receipt.evidenceRelativePath,
              let data = try? Data(contentsOf: dir.appendingPathComponent(path)),
              let parsed = try? JSONDecoder().decode(R597EvidenceExport.self, from: data),
              parsed.certification == "NOT_CERTIFIED_FOR_LIVE_BATTLE",
              ["hold", "candidate_unverified"].contains(parsed.result.status) else {
            return original
        }
        // The R548 archive writer seals and CRC-protects this original-data-
        // preserving extra member. Do not mutate the existing manifest/index.
        return original + [R548ResearchArchive.Entry(name: outputName, bytes: data)]
    }
}
