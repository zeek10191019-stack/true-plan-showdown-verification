import Foundation

@main
struct R599Tests {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        guard condition() else { fatalError("R599 TEST FAILED: \(label)") }
        checks += 1
    }
    static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAT0lEQVR4nKXDiQ2AMAADsStQoPSbIfsPGYaIJQNytBQ5yXHISc5TTnJdcpJa5ST3LSd5HjnJ+8pJWpOTfJ+cpHc5yRhykjnlJGvJSfaWkz9U5S8QboDItQAAAABJRU5ErkJggg==")!
    static let emptyCatalog = Data("{\"schema\":\"trueplan.r596.visual_catalog.v1\",\"references\":[]}".utf8)
    static func root() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        try! Data("{\"frame_count\":9,\"original\":true}".utf8).write(to: u.appendingPathComponent("manifest.json"))
        try! png.write(to: u.appendingPathComponent("crop.png"))
        return u
    }
    static func observation(sha: String? = nil, side: String = "own", verified: Bool = true) -> R597FrameObservation {
        R597FrameObservation(battleID: "battle-599", epoch: 2, frameID: 9, actorToken: "actor-1", captureSide: side,
           cropSHA256: sha ?? R598OneButtonFormAttachment.testDigest(png),
           extractorID: R596FormCatalogGate.extractorID,
           features: [Double](repeating: 0.2, count: 192), hasVerifiedActorBinding: verified,
           hasVerifiedOrientation: true)
    }
    static func main() throws {
        check(R599BoundOneButton.validPNG(png), "valid png")
        check(R598OneButtonFormAttachment.testDigest(png) == "d0a91a0220de2c782e8527567f025ec80cb3129d54752f5be9ba46673baf69fc", "png checksum")
        var wrong = png; wrong[60] ^= 1
        check(!R599BoundOneButton.validPNG(wrong), "crc corrupted")
        check(!R599BoundOneButton.validPNG(png.prefix(45)), "truncated png")
        check(!R599BoundOneButton.validPNG(Data("not png".utf8)), "wrong signature")
        var tooWide = png; tooWide[19] = 0x00; tooWide[18] = 0x80
        check(!R599BoundOneButton.validPNG(tooWide), "modified ihdr forbidden")
        var missingEnd = png; missingEnd.removeLast(12)
        check(!R599BoundOneButton.validPNG(missingEnd), "missing iend")
        var extra = png; extra.append(0)
        check(!R599BoundOneButton.validPNG(extra), "trailing bytes forbidden")
        let r = root(); defer { try? FileManager.default.removeItem(at: r) }
        let beforeCrop = try Data(contentsOf: r.appendingPathComponent("crop.png"))
        let receipt = R599BoundOneButton.attachBeforeZip(bundleRoot: r, cropRelativePath: "crop.png", observation: observation(), catalogData: emptyCatalog)
        check(receipt.emitted, "frame byte-binding attachment success")
        check(receipt.reason.contains("NOT_LIVE_CERTIFIED"), "not certified")
        check(receipt.sidecarPath?.hasPrefix("evidence/r598_form_2_9_") == true, "evidence path")
        let cropAfter = try Data(contentsOf: r.appendingPathComponent("crop.png"))
        check(cropAfter == beforeCrop, "original crop unchanged")
        let m = try JSONSerialization.jsonObject(with: Data(contentsOf: r.appendingPathComponent("manifest.json"))) as! [String:Any]
        check(m["original"] as? Bool == true && m["frame_count"] as? Int == 9, "manifest preserved")
        let e = m["r598_form_evidence"] as! [String:Any]
        check(e["certification"] as? String == "NOT_CERTIFIED_FOR_LIVE_BATTLE", "held certification")
        check(e["status"] as? String == "hold", "no catalog held")
        let content = try Data(contentsOf: r.appendingPathComponent(receipt.sidecarPath!))
        check(e["sha256"] as? String == R598OneButtonFormAttachment.testDigest(content), "sidecar digest")
        // Optional staged-directory fixture for cross-language real ZIP integrity audit.
        if let out = ProcessInfo.processInfo.environment["R599_STAGE_EXPORT"] {
            let destination = URL(fileURLWithPath: out, isDirectory: true)
            let before = destination.appendingPathComponent("before", isDirectory: true)
            let after = destination.appendingPathComponent("after", isDirectory: true)
            try FileManager.default.createDirectory(at: before, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: after, withIntermediateDirectories: true)
            try Data("{\"frame_count\":9,\"original\":true}".utf8).write(to: before.appendingPathComponent("manifest.json"))
            try png.write(to: before.appendingPathComponent("crop.png"))
            try FileManager.default.copyItem(at: r.appendingPathComponent("crop.png"), to: after.appendingPathComponent("crop.png"))
            try FileManager.default.copyItem(at: r.appendingPathComponent("manifest.json"), to: after.appendingPathComponent("manifest.json"))
            try FileManager.default.createDirectory(at: after.appendingPathComponent("evidence"), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: r.appendingPathComponent(receipt.sidecarPath!), to: after.appendingPathComponent(receipt.sidecarPath!))
        }
        let payload = try JSONDecoder().decode(R597EvidenceExport.self, from: content)
        check(payload.result.reason == "NO_INDEPENDENT_FORM_REFERENCES", "valid empty catalog hold")
        check(payload.frameID == 9 && payload.captureSide == "own", "side frame maintained")
        check(!R599BoundOneButton.attachBeforeZip(bundleRoot: r, cropRelativePath: "crop.png", observation: observation(), catalogData: emptyCatalog).emitted, "double attach refused")
        let wrongHash = root(); defer { try? FileManager.default.removeItem(at: wrongHash) }
        check(R599BoundOneButton.attachBeforeZip(bundleRoot: wrongHash, cropRelativePath: "crop.png", observation: observation(sha: String(repeating:"a",count:64)),catalogData: emptyCatalog).reason == "CROP_SHA256_NOT_BOUND_TO_FRAME", "sha mismatch")
        check(!FileManager.default.fileExists(atPath: wrongHash.appendingPathComponent("evidence").path), "sha mismatch never writes")
        check(R599BoundOneButton.attachBeforeZip(bundleRoot: wrongHash, cropRelativePath: "../crop.png", observation: observation(), catalogData: emptyCatalog).reason == "CROP_PATH_UNSAFE", "traversal")
        check(R599BoundOneButton.attachBeforeZip(bundleRoot: wrongHash, cropRelativePath: "/crop.png", observation: observation(), catalogData: emptyCatalog).reason == "CROP_PATH_UNSAFE", "absolute")
        check(R599BoundOneButton.attachBeforeZip(bundleRoot: wrongHash, cropRelativePath: "notexist.png", observation: observation(), catalogData: emptyCatalog).reason == "CROP_PNG_MISSING_OR_INVALID", "missing")
        check(R599BoundOneButton.attachBeforeZip(bundleRoot: wrongHash, cropRelativePath: "crop.png", observation: observation(side: "unknown"), catalogData: emptyCatalog).reason == "SOURCE_FRAME_OWNER_OR_ORIENTATION_HOLD", "unverified side")
        check(R599BoundOneButton.attachBeforeZip(bundleRoot: wrongHash, cropRelativePath: "crop.png", observation: observation(verified: false), catalogData: emptyCatalog).reason == "SOURCE_FRAME_OWNER_OR_ORIENTATION_HOLD", "unverified owner")
        let symlink = root(); defer { try? FileManager.default.removeItem(at: symlink) }
        try FileManager.default.removeItem(at: symlink.appendingPathComponent("crop.png"))
        try FileManager.default.createSymbolicLink(at: symlink.appendingPathComponent("crop.png"),withDestinationURL: wrongHash.appendingPathComponent("crop.png"))
        check(R599BoundOneButton.attachBeforeZip(bundleRoot: symlink, cropRelativePath: "crop.png", observation: observation(), catalogData: emptyCatalog).reason == "CROP_PNG_MISSING_OR_INVALID", "crop symlink refused")
        print("R599 SWIFT \(checks)/\(checks) PASS")
    }
}
