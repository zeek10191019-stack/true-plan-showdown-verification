import Foundation

func check(_ condition: @autoclosure () -> Bool, _ tag: String) {
    precondition(condition(), "R596_TEST_FAILED:\(tag)")
}

func item(_ id: String, _ form: String = "mega", _ session: String = "s1", _ source: String = "champions-screen-capture", _ extractor: String = R596FormCatalogGate.extractorID, _ n: Int = 192, _ evidence: String = "human-confirmed") -> R596VisualReference {
    let hex = String(repeating: "0", count: 63) + String(id.last ?? "1")
    return R596VisualReference(referenceID: id, speciesID: "gyarados", formID: form, captureSide: "opponent", sessionID: session, frameID: 42, sourceKind: source, labelEvidence: evidence, extractorID: extractor, imageSHA256: hex, features: Array(repeating: 0.2, count: n))
}
func encode(_ refs: [R596VisualReference], schema: String = R596FormCatalogGate.schema) -> Data {
    return try! JSONEncoder().encode(R596VisualReferenceCatalog(schema: schema, references: refs))
}
func rejects(_ data: Data) -> Bool { do { _ = try R596FormCatalogGate.load(data); return false } catch { return true } }

@main
struct R596Tests {
 static func main() throws {
  let empty = try R596FormCatalogGate.load(encode([]))
  check(!empty.productionReady && empty.holdReasons.contains("NO_REAL_GAME_REFERENCES"), "EMPTY_HOLDS")
  let single = try R596FormCatalogGate.load(encode([item("ref1")]))
  check(!single.productionReady && single.readyFormKeys.isEmpty, "SINGLE_SESSION_HOLDS")
  let twin = try R596FormCatalogGate.load(encode([item("ref1"), item("ref2", "mega", "s2")]))
  check(twin.readyFormKeys.contains("gyarados/mega"), "INDEPENDENT_SESSIONS_ADMIT")
  check(!twin.productionReady, "NO_REAL_GAME_CERTIFICATION")
  check(rejects(encode([item("ref1"),item("ref1", "normal", "s2")])), "DUPLICATE_ID_REJECT")
  check(rejects(encode([item("ref1"),item("alt1", "normal", "s2")])), "DUPLICATE_CROP_REJECT")
  check(rejects(encode([item("ref1", "ultra")])), "FORM_REJECT")
  check(rejects(encode([item("ref1", "mega", "s1", "synthetic")])), "SYNTHETIC_REJECT")
  check(rejects(encode([item("ref1", "mega", "s1", "champions-screen-capture", "other")])), "EXTRACTOR_REJECT")
  check(rejects(encode([item("ref1", "mega", "s1", "champions-screen-capture", R596FormCatalogGate.extractorID, 191)])), "FEATURES_REJECT")
  check(rejects(encode([item("ref1", "mega", "s1", "champions-screen-capture", R596FormCatalogGate.extractorID, 192, "model-inferred")])), "GUESSED_LABEL_REJECT")
  check(rejects(encode([], schema: "other")), "SCHEMA_REJECT")
  print("R596_FORM_CATALOG_12_TESTS_PASS; REAL_GAME_CATALOG_EMPTY; LIVE_RECOGNITION_UNCERTIFIED")
 }
}
