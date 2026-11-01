import Foundation

@main
struct Harness {
    static var count = 0
    static func check(_ test: @autoclosure () -> Bool, _ label: String) {
        guard test() else { fatalError("R598 FAIL: \(label)") }
        count += 1
    }
    static func observation(_ hash: String = String(repeating: "a", count: 64),
                            _ epoch: Int = 1, _ frame: Int = 8) -> R597FrameObservation {
        R597FrameObservation(battleID: "battle-1", epoch: epoch, frameID: frame, actorToken: "own-actor",
                             captureSide: "own", cropSHA256: hash,
                             extractorID: R596FormCatalogGate.extractorID,
                             features: Array(repeating: 0.4, count: 192),
                             hasVerifiedActorBinding: true, hasVerifiedOrientation: true)
    }
    static func emptyCatalog() -> Data { Data("{\"schema\":\"trueplan.r596.visual_catalog.v1\",\"references\":[]}".utf8) }
    static func temp() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static func makeBundle(_ url: URL, _ manifest: Data = Data("{\"legacy\":{\"source\":\"captured\"},\"frames\":[\"original.png\"]}".utf8)) {
        try! manifest.write(to: url.appendingPathComponent("manifest.json"))
        try! Data("frame immutable".utf8).write(to: url.appendingPathComponent("original.png"))
    }
    static func main() throws {
        check(R598OneButtonFormAttachment.testDigest(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256 empty")
        check(R598OneButtonFormAttachment.testDigest(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256 abc")
        check(R598OneButtonFormAttachment.testDigest(Data(repeating: 0x61, count: 1000)) == "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3", "sha256 1000 a")
        let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
        makeBundle(root)
        let originalFrame = try Data(contentsOf: root.appendingPathComponent("original.png"))
        let receipt = R598OneButtonFormAttachment.attach(bundleRoot: root, observation: observation(), catalogData: emptyCatalog())
        check(receipt.attached, "first attach works")
        check(receipt.reason == "RESEARCH_EVIDENCE_ATTACHED_NOT_CERTIFIED", "research only")
        check(receipt.relativePath?.hasPrefix("evidence/r598_form_1_8_") == true, "safe relative path")
        check((receipt.evidenceSHA256?.count ?? 0) == 64, "sha256 present")
        let frameAfter = try Data(contentsOf: root.appendingPathComponent("original.png"))
        check(frameAfter == originalFrame, "original unchanged")
        let metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("manifest.json"))) as! [String: Any]
        check(((metadata["legacy"] as? [String: String])?["source"]) == "captured", "legacy JSON preserved")
        check((metadata["frames"] as? [String]) == ["original.png"], "frame list preserved")
        let extensionObj = metadata["r598_form_evidence"] as? [String: Any]
        check(extensionObj?["certification"] as? String == "NOT_CERTIFIED_FOR_LIVE_BATTLE", "cannot certify")
        check(extensionObj?["status"] as? String == "hold", "empty catalog holds")
        let ev = try Data(contentsOf: root.appendingPathComponent(receipt.relativePath!))
        check((extensionObj?["bytes"] as? Int) == ev.count, "byte count matches")
        check((extensionObj?["sha256"] as? String) == R598OneButtonFormAttachment.testDigest(ev), "evidence SHA matches")
        let payload = try JSONDecoder().decode(R597EvidenceExport.self, from: ev)
        check(payload.result.reason == "NO_INDEPENDENT_FORM_REFERENCES", "hold reason exported")
        check(payload.captureSide == "own", "side preserved")
        check(payload.frameID == 8 && payload.epoch == 1, "frame binding preserved")
        check(!R598OneButtonFormAttachment.attach(bundleRoot: root, observation: observation(), catalogData: emptyCatalog()).attached, "duplicate blocked")
        check(R598OneButtonFormAttachment.attach(bundleRoot: root, manifestName: "../manifest.json", observation: observation(), catalogData: emptyCatalog()).reason == "UNRECOGNIZED_MANIFEST_NAME", "manifest traversal blocked")

        let noManifest = temp(); defer { try? FileManager.default.removeItem(at: noManifest) }
        check(R598OneButtonFormAttachment.attach(bundleRoot: noManifest, observation: observation(), catalogData: emptyCatalog()).reason == "MANIFEST_MISSING_OR_SYMLINK", "missing manifest holds")
        let malformed = temp(); defer { try? FileManager.default.removeItem(at: malformed) }
        makeBundle(malformed, Data("not-json".utf8))
        check(R598OneButtonFormAttachment.attach(bundleRoot: malformed, observation: observation(), catalogData: emptyCatalog()).reason == "MANIFEST_NOT_JSON_OBJECT", "invalid manifest holds")
        let invalidFrame = temp(); defer { try? FileManager.default.removeItem(at: invalidFrame) }
        makeBundle(invalidFrame)
        check(R598OneButtonFormAttachment.attach(bundleRoot: invalidFrame, observation: observation("bad"), catalogData: emptyCatalog()).reason == "FRAME_IDENTITY_INVALID", "bad hash holds")
        check(!FileManager.default.fileExists(atPath: invalidFrame.appendingPathComponent("evidence").path), "bad hash does not mutate")
        let unsafe = temp(); defer { try? FileManager.default.removeItem(at: unsafe) }
        makeBundle(unsafe)
        try FileManager.default.createSymbolicLink(at: unsafe.appendingPathComponent("evidence"), withDestinationURL: noManifest)
        check(R598OneButtonFormAttachment.attach(bundleRoot: unsafe, observation: observation(), catalogData: emptyCatalog()).reason == "EVIDENCE_DIRECTORY_UNSAFE", "symlink evidence directory holds")
        let mLink = temp(); defer { try? FileManager.default.removeItem(at: mLink) }
        try FileManager.default.createSymbolicLink(at: mLink.appendingPathComponent("manifest.json"), withDestinationURL: root.appendingPathComponent("manifest.json"))
        check(R598OneButtonFormAttachment.attach(bundleRoot: mLink, observation: observation(), catalogData: emptyCatalog()).reason == "MANIFEST_MISSING_OR_SYMLINK", "symlink manifest holds")
        print("R598 SWIFT \(count)/\(count) PASS")
    }
}
