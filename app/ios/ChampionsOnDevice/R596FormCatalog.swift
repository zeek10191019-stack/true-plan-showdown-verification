import Foundation

// R596: strict admission control for R595 16x12 visual-form references.
// This module does not label a live opponent or claim real-game recognition.
struct R596VisualReference: Codable {
    let referenceID: String
    let speciesID: String
    let formID: String
    let captureSide: String
    let sessionID: String
    let frameID: Int
    let sourceKind: String
    let labelEvidence: String
    let extractorID: String
    let imageSHA256: String
    let features: [Double]
}

struct R596VisualReferenceCatalog: Codable {
    let schema: String
    let references: [R596VisualReference]
}

enum R596CatalogError: Error, CustomStringConvertible {
    case invalid(String)
    var description: String {
        switch self { case .invalid(let reason): return "R596_CATALOG_REJECT: \(reason)" }
    }
}

struct R596CatalogReport {
    let validReferences: [R596VisualReference]
    let readyFormKeys: Set<String>
    let holdReasons: [String]
    var productionReady: Bool { return !readyFormKeys.isEmpty && holdReasons.isEmpty }
}

struct R596FormCatalogGate {
    static let schema = "trueplan.r596.visual_catalog.v1"
    static let extractorID = "R595-16x12-unverified-scale"
    static let featureCount = 16 * 12
    static let minIndependentSessions = 2
    private static let hex = CharacterSet(charactersIn: "0123456789abcdef")
    private static let safeID = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_-.:")

    static func load(_ data: Data) throws -> R596CatalogReport {
        let catalog: R596VisualReferenceCatalog
        do { catalog = try JSONDecoder().decode(R596VisualReferenceCatalog.self, from: data) }
        catch { throw R596CatalogError.invalid("JSON_OR_SCHEMA_INVALID") }
        guard catalog.schema == schema else { throw R596CatalogError.invalid("SCHEMA_MISMATCH") }
        var seenIDs = Set<String>()
        var seenHashes = Set<String>()
        var forms: [String: Set<String>] = [:]
        var holds: [String] = []
        for ref in catalog.references {
            for (key, value) in [("referenceID", ref.referenceID), ("speciesID", ref.speciesID), ("formID", ref.formID), ("sessionID", ref.sessionID)] {
                guard !value.isEmpty && value.count <= 96 && value.unicodeScalars.allSatisfy({ safeID.contains($0) }) else {
                    throw R596CatalogError.invalid("INVALID_\(key)")
                }
            }
            guard ["normal", "mega", "mega-x", "mega-y", "mega-z"].contains(ref.formID) else {
                throw R596CatalogError.invalid("FORM_NOT_ALLOWLISTED")
            }
            guard ["own", "opponent"].contains(ref.captureSide) else {
                throw R596CatalogError.invalid("SIDE_UNVERIFIED")
            }
            guard ref.frameID >= 0 else { throw R596CatalogError.invalid("FRAME_ID_INVALID") }
            guard ref.sourceKind == "champions-screen-capture" && ref.labelEvidence == "human-confirmed" else {
                throw R596CatalogError.invalid("UNVERIFIED_IMAGE_OR_FORM_LABEL")
            }
            guard ref.extractorID == extractorID else {
                throw R596CatalogError.invalid("FEATURE_EXTRACTOR_CONTRACT_MISMATCH")
            }
            guard ref.imageSHA256.count == 64 && ref.imageSHA256.unicodeScalars.allSatisfy({ hex.contains($0) }) else {
                throw R596CatalogError.invalid("IMAGE_SHA256_INVALID")
            }
            guard ref.features.count == featureCount && ref.features.allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }) else {
                throw R596CatalogError.invalid("FEATURE_VECTOR_INVALID")
            }
            guard !seenIDs.contains(ref.referenceID) else { throw R596CatalogError.invalid("REFERENCE_ID_DUPLICATE") }
            guard !seenHashes.contains(ref.imageSHA256) else { throw R596CatalogError.invalid("CROP_IMAGE_REUSED") }
            seenIDs.insert(ref.referenceID)
            seenHashes.insert(ref.imageSHA256)
            let formKey = ref.speciesID + "/" + ref.formID
            forms[formKey, default: []].insert(ref.sessionID)
        }
        var ready = Set<String>()
        for (key, sessions) in forms {
            if sessions.count >= minIndependentSessions { ready.insert(key) }
            else { holds.append("INSUFFICIENT_INDEPENDENT_CAPTURE_SESSIONS:\(key)") }
        }
        if catalog.references.isEmpty { holds.append("NO_REAL_GAME_REFERENCES") }
        // Admission approval is separate from live classification. Do not silently
        // convert any candidate into a confirmed Mega/species/side verdict.
        holds.append("REAL_GAME_HELDOUT_ACCURACY_UNVERIFIED")
        holds.append("R595_RUNTIME_ADAPTER_UNVERIFIED")
        return R596CatalogReport(validReferences: catalog.references, readyFormKeys: ready, holdReasons: holds.sorted())
    }
}
