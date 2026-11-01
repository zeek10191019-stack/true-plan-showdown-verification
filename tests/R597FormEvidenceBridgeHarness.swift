import Foundation

func expect(_ p: @autoclosure () -> Bool, _ tag: String) {
    precondition(p(), "R597_TEST_FAILED:\(tag)")
}

func ref(_ id: String, _ form: String, _ sess: String, _ value: Double,
         _ species: String = "gyarados") -> R596VisualReference {
    let sha = String(repeating: "0", count: 63) + id.suffix(1)
    return R596VisualReference(referenceID: id, speciesID: species, formID: form,
                               captureSide: "opponent", sessionID: sess, frameID: 5,
                               sourceKind: "champions-screen-capture", labelEvidence: "human-confirmed",
                               extractorID: R596FormCatalogGate.extractorID,
                               imageSHA256: sha, features: Array(repeating: value, count: 192))
}
func catalog(_ refs: [R596VisualReference]) -> Data {
    try! JSONEncoder().encode(R596VisualReferenceCatalog(schema: R596FormCatalogGate.schema, references: refs))
}
func obs(_ val: Double = 0.2, side: String = "opponent", verified: Bool = true,
         extractor: String = R596FormCatalogGate.extractorID, sha: String = String(repeating: "f", count: 64),
         values: [Double]? = nil) -> R597FrameObservation {
    R597FrameObservation(battleID: "b1", epoch: 1, frameID: 100, actorToken: "actor-1",
                         captureSide: side, cropSHA256: sha, extractorID: extractor,
                         features: values ?? Array(repeating: val, count: 192),
                         hasVerifiedActorBinding: verified, hasVerifiedOrientation: verified)
}
@main
struct Tests {
 static func main() throws {
    let refs = catalog([ref("ref1", "mega", "s1", 0.20), ref("ref2", "mega", "s2", 0.21),
                        ref("ref3", "normal", "s3", 0.85), ref("ref4", "normal", "s4", 0.86)])
    let good = R597FormEvidenceBridge.propose(obs(), catalogData: refs)
    expect(good.status == "candidate_unverified", "CANDIDATE_UNVERIFIED")
    expect(good.speciesID == "gyarados" && good.formID == "mega", "CANDIDATE_FORM")
    expect(good.supportingSessions == 2, "TWO_SESSIONS")
    expect(R597FormEvidenceBridge.propose(obs(side: "unknown"), catalogData: refs).reason == "SIDE_OR_ORIENTATION_UNVERIFIED", "SIDE_HOLD")
    expect(R597FormEvidenceBridge.propose(obs(verified: false), catalogData: refs).status == "hold", "ACTOR_HOLD")
    expect(R597FormEvidenceBridge.propose(obs(extractor: "modified-extractor"), catalogData: refs).reason == "R595_EXTRACTOR_CONTRACT_UNVERIFIED", "EXTRACTOR_HOLD")
    expect(R597FormEvidenceBridge.propose(obs(sha: String(repeating: "0", count: 63)+"1"), catalogData: refs).reason == "TRAINING_CROP_REPLAY", "LEAKAGE_HOLD")
    expect(R597FormEvidenceBridge.propose(obs(0.5), catalogData: refs).reason == "DISTANCE_TOO_LARGE", "DISTANCE_HOLD")
    let short = catalog([ref("ref1","mega","s1",0.2)])
    expect(R597FormEvidenceBridge.propose(obs(), catalogData: short).reason == "NO_INDEPENDENT_FORM_REFERENCES", "SINGLE_HOLD")
    let ambiguous = catalog([ref("ref1","mega","s1",0.2),ref("ref2","mega","s2",0.2),
                              ref("ref3","normal","s3",0.21),ref("ref4","normal","s4",0.21)])
    expect(R597FormEvidenceBridge.propose(obs(), catalogData: ambiguous).reason == "FORM_AMBIGUITY", "AMBIGUITY_HOLD")
    expect(R597FormEvidenceBridge.propose(obs(values:[Double.nan]+Array(repeating:0.2,count:191)), catalogData: refs).status == "hold", "NAN_HOLD")
    expect(R597FormEvidenceBridge.propose(obs(values:Array(repeating:0.2,count:191)), catalogData: refs).status == "hold", "SHORT_VECTOR_HOLD")
    expect(R597FormEvidenceBridge.propose(obs(), catalogData: Data("{}".utf8)).reason == "REFERENCE_CATALOG_INVALID", "BAD_CATALOG_HOLD")
    let exported = try R597FormEvidenceBridge.export(obs(), catalogData: refs)
    let decoded = try JSONDecoder().decode(R597EvidenceExport.self, from: exported)
    expect(decoded.schema == R597FormEvidenceBridge.exportSchema, "EXPORT_SCHEMA")
    expect(decoded.result.status == "candidate_unverified", "EXPORT_NOT_CONFIRMED")
    expect(decoded.certification == "NOT_CERTIFIED_FOR_LIVE_BATTLE", "CERTIFICATION_STAYS_HOLD")
    let lopsided = catalog([ref("ref1","mega","s1",0.2),ref("ref2","mega","s2",0.8),
                            ref("ref3","normal","s3",0.8),ref("ref4","normal","s4",0.8)])
    expect(R597FormEvidenceBridge.propose(obs(),catalogData:lopsided).status == "hold", "SECOND_SESSION_MUST_MATCH")
    let splitSides = catalog([ref("ref1","mega","s1",0.2), ref("ref2","mega","s2",0.2)])
    // R596 readiness is species/form keyed; R597 must also require side-consistent independent sessions.
    let otherSide = R597FrameObservation(battleID: "b1", epoch: 1, frameID: 100,
        actorToken: "actor-1", captureSide: "own", cropSHA256: String(repeating: "f", count: 64),
        extractorID: R596FormCatalogGate.extractorID, features: Array(repeating: 0.2, count: 192),
        hasVerifiedActorBinding: true, hasVerifiedOrientation: true)
    expect(R597FormEvidenceBridge.propose(otherSide, catalogData: splitSides).reason == "NO_COMPARABLE_REFERENCES", "SIDE_REFERENCES_SEPARATED")
    let sameBattle = R597FrameObservation(battleID: "s1", epoch: 1, frameID: 100,
        actorToken: "actor-1", captureSide: "opponent", cropSHA256: String(repeating: "f", count: 64),
        extractorID: R596FormCatalogGate.extractorID, features: Array(repeating: 0.2, count: 192),
        hasVerifiedActorBinding: true, hasVerifiedOrientation: true)
    expect(R597FormEvidenceBridge.propose(sameBattle, catalogData: splitSides).status == "hold", "SAME_BATTLE_SESSION_NOT_USED")
    print("R597_FORM_EVIDENCE_BRIDGE_19_CHECKS_PASS; NO_LIVE_CERTIFICATION")
 }
}
