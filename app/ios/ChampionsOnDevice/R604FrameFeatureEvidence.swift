import Foundation

// R604: use EXACT R594 output (not a second, incompatible 16x12 sampler).
// These are research candidates, not verified owner/species/Mega information.
struct R604ProvenancedCrop {
    let battleID: String
    let epoch: Int
    let frameID: Int
    let actorToken: String
    let side: String
    let orientation: String
    let roiLayoutID: String
    let actorVerified: Bool
    let orientationVerified: Bool
    let sourceFrameSHA256: String
    let cropPNG: Data
    let cropSHA256: String
    let appearance: [String: Any]
    let appearanceRegion: String
}

struct R604CropStageResult {
    let entries: [R548ResearchArchive.Entry]
    let status: String
    let appended: Bool
}

enum R604FrameFeatureEvidence {
    static let inputName = "r602_form_input.json"
    static let cropName = "crop.png"
    static let provenanceName = "r604_form_provenance.json"
    private static let maxNewMembers = 5 // crop + input + provenance + R602 + R603
    private static let idChars = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.:"
    )
    private static func token(_ x: String, limit: Int = 96) -> Bool {
        !x.isEmpty && x.count <= limit && x.unicodeScalars.allSatisfy { idChars.contains($0) }
    }
    private static func hex(_ x: String) -> Bool {
        x.utf8.count == 64 && x.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
    private static func hold(_ entries: [R548ResearchArchive.Entry], _ reason: String)
    -> R604CropStageResult {
        R604CropStageResult(entries: entries, status: reason, appended: false)
    }

    // The caller supplies its actual R594 capture result and a crop from the
    // SAME original frame. Never derive confirmed actor/ROI/orientation flags.
    static func stage(_ entries: [R548ResearchArchive.Entry],
                      candidate: R604ProvenancedCrop?) -> R604CropStageResult {
        guard let c = candidate else { return hold(entries, "HOLD_R594_SOURCE_NOT_WIRED") }
        let names = entries.map(\.name)
        guard names.count == Set(names).count,
              !names.contains(inputName), !names.contains(cropName),
              !names.contains(provenanceName), names.contains("manifest.json"),
              entries.count <= R548ResearchArchive.maximumMembers - maxNewMembers else {
            return hold(entries, "HOLD_ARCHIVE_CAPACITY_OR_MEMBER_COLLISION")
        }
        guard token(c.battleID), token(c.actorToken), token(c.roiLayoutID),
              c.epoch > 0, c.frameID > 0, ["own", "opponent"].contains(c.side),
              c.actorVerified, c.orientationVerified,
              ["landscape-left", "landscape-right"].contains(c.orientation) else {
            return hold(entries, "HOLD_UNVERIFIED_ACTOR_OR_COORDINATES")
        }
        guard hex(c.sourceFrameSHA256), hex(c.cropSHA256),
              R599BoundOneButton.validPNG(c.cropPNG),
              R598OneButtonFormAttachment.testDigest(c.cropPNG) == c.cropSHA256 else {
            return hold(entries, "HOLD_SOURCE_FRAME_OR_CROP_BYTES")
        }
        let a=c.appearance
        guard a["schema"] as? String == "trueplan.r594.historical-actor-appearance.v1",
              a["status"] as? String == "HISTORICAL_APPEARANCE_SAMPLES_ONLY",
              a["epoch"] as? Int64 == Int64(c.epoch),
              a["frame_id"] as? Int64 == Int64(c.frameID),
              (a["observed_ms_monotonic"] as? Int64 ?? 0) > 0,
              a["image_sha256"] as? String == c.sourceFrameSHA256,
              a["owner_certified"] as? Bool == false,
              a["mega_certified"] as? Bool == false,
              a["regions"] is [[String:Any]] else {
            return hold(entries, "HOLD_R594_OBSERVATION_MISMATCH")
        }
        guard ["MEMORY_LEFT_ACTOR_HYPOTHESIS",
               "MEMORY_RIGHT_ACTOR_HYPOTHESIS"].contains(c.appearanceRegion),
              let regions=a["regions"] as? [[String:Any]],
              regions.filter({ $0["name"] as? String == c.appearanceRegion }).count == 1,
              let region=regions.first(where: {
                  $0["name"] as? String == c.appearanceRegion
              }), region["coordinate_space"] as? String ==
                "RGBA_MEMORY_ROW_ORDER_UNVERIFIED",
              region["grid_width"] as? Int == 16,
              region["grid_height"] as? Int == 12,
              let grid=region["luma_grid"] as? [Int], grid.count == 192,
              grid.allSatisfy({(-1...255).contains($0)}),
              region["transparent_samples"] as? Int == grid.filter({$0 == -1}).count,
              !grid.contains(-1) else {
            return hold(entries, "HOLD_R594_GRID_OR_REGION_NOT_COMPARABLE")
        }
        // No recomputation: the 192 values are copied EXACTLY from R594 output.
        // Numeric parity of R595's matching policy is still not certified.
        let input: [String:Any] = [
            "battleID":c.battleID,"epoch":c.epoch,"frameID":c.frameID,
            "actorToken":c.actorToken,"side":c.side,"cropSHA256":c.cropSHA256,
            "orientation":c.orientation,"roiLayoutID":c.roiLayoutID,
            "actorVerified":c.actorVerified,"orientationVerified":c.orientationVerified,
            "extractorID":R596FormCatalogGate.extractorID,
            "features":grid.map(Double.init)
        ]
        let provenance: [String:Any] = [
            "schema":"trueplan.r604.r594_provenance.v1",
            "status":"RESEARCH_ONLY_NOT_MEGA_CERTIFIED",
            "source_frame_sha256":c.sourceFrameSHA256,
            "crop_sha256":c.cropSHA256,"r594_region":c.appearanceRegion,
            "r594_schema":a["schema"]!,"epoch":c.epoch,"frame_id":c.frameID,
            "r595_numeric_matching_parity_verified":false,
            "owner_certification_from_r594":false
        ]
        guard JSONSerialization.isValidJSONObject(input),
              JSONSerialization.isValidJSONObject(provenance),
              let data=try? JSONSerialization.data(
                withJSONObject:input,options:[.sortedKeys]),
              let proof=try? JSONSerialization.data(
                withJSONObject:provenance,options:[.sortedKeys]) else {
            return hold(entries,"HOLD_EVIDENCE_ENCODING")
        }
        return R604CropStageResult(entries:entries+[
            .init(name:cropName,bytes:c.cropPNG),
            .init(name:inputName,bytes:data),
            .init(name:provenanceName,bytes:proof)
        ],status:"R594_GRID_BYTE_COPIED_SOURCE_CROP_UNVERIFIED_FOR_LIVE",appended:true)
    }
}
