import Foundation

enum R548ResearchArchive {
    struct Entry {
        let name: String
        let bytes: Data
        init(name: String, bytes: Data) { self.name = name; self.bytes = bytes }
    }
    static let maximumMembers = 24
}

@main struct R602Harness {
    static var checks = 0
    static func check(_ yes: @autoclosure () -> Bool, _ msg: String) {
        guard yes() else { fatalError("R602: " + msg) }; checks += 1
    }
    static let png = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAT0lEQVR4nKXDiQ2AMAADsStQoPSbIfsPGYaIJQNytB" +
        "Q5yXHISc5TTnJdcpJa5ST3LSd5HjnJ+8pJWpOTfJ+cpHc5yRhykjnlJGvJSfaWkz9U5S8QboDItQAAAABJRU5ErkJggg=="
    )!
    static let manifest = Data(#"{"frame_count":12,"original":true}"#.utf8)
    static func input(
        verified: Bool = true,
        extractor: String = R596FormCatalogGate.extractorID,
        hash: String? = nil,
        orientation: String = "landscape-left",
        features: [Double] = Array(repeating: 0.2, count: 192)
    ) -> Data {
        let dict: [String: Any] = [
            "battleID": "B602", "epoch": 4, "frameID": 22,
            "actorToken": "actor001", "side": "own",
            "cropSHA256": hash ?? R598OneButtonFormAttachment.testDigest(png),
            "orientation": orientation, "roiLayoutID": "crop_602",
            "actorVerified": verified, "orientationVerified": verified,
            "extractorID": extractor, "features": features
        ]
        return try! JSONSerialization.data(withJSONObject: dict)
    }
    static func rows(
        _ data: Data = input(), pngBytes: Data = png
    ) -> [R548ResearchArchive.Entry] {
        [
            .init(name: R602OneTapFormArchive.inputName, bytes: data),
            .init(name: R602OneTapFormArchive.cropName, bytes: pngBytes),
            .init(name: R602OneTapFormArchive.manifestName, bytes: manifest)
        ]
    }
    static func same(_ a: [R548ResearchArchive.Entry], _ b: [R548ResearchArchive.Entry]) -> Bool {
        a.count == b.count && zip(a,b).allSatisfy { $0.name == $1.name && $0.bytes == $1.bytes }
    }
    static func main() {
        let original = rows()
        let out = R602OneTapFormArchive.beforeZip(original)
        check(out.count == 4, "verified source emits sidecar")
        check(same(Array(out.prefix(3)), original), "original member bytes unchanged")
        check(out[3].name == R602OneTapFormArchive.outputName, "stable archive member")
        let e = try! JSONDecoder().decode(R597EvidenceExport.self, from: out[3].bytes)
        check(e.certification == "NOT_CERTIFIED_FOR_LIVE_BATTLE", "no production certification")
        check(e.result.status == "hold", "without verified real references remains HOLD")
        check(e.cropSHA256 == R598OneButtonFormAttachment.testDigest(png), "pixel SHA bound")
        let noInput = original.filter { $0.name != R602OneTapFormArchive.inputName }
        check(same(R602OneTapFormArchive.beforeZip(noInput), noInput), "missing input untouched")
        let badOwner = rows(input(verified: false))
        check(same(R602OneTapFormArchive.beforeZip(badOwner), badOwner), "unverified actor rejected")
        let portrait = rows(input(orientation: "portrait"))
        check(same(R602OneTapFormArchive.beforeZip(portrait), portrait), "portrait rejected")
        let badHash = rows(input(hash: String(repeating: "a", count: 64)))
        check(same(R602OneTapFormArchive.beforeZip(badHash), badHash), "crop hash mismatch")
        let badExtractor = rows(input(extractor: "VNFeaturePrint"))
        check(same(R602OneTapFormArchive.beforeZip(badExtractor), badExtractor), "extractor mismatch")
        let badVector = rows(input(features: Array(repeating: 0.0, count: 191)))
        check(same(R602OneTapFormArchive.beforeZip(badVector), badVector), "feature count mismatch")
        let noCrop = original.filter { $0.name != R602OneTapFormArchive.cropName }
        check(same(R602OneTapFormArchive.beforeZip(noCrop), noCrop), "missing PNG untouched")
        let repeated = original + [original[0]]
        check(same(R602OneTapFormArchive.beforeZip(repeated), repeated), "duplicate member untouched")
        let preAttached = original + [.init(name: R602OneTapFormArchive.outputName, bytes: Data())]
        check(same(R602OneTapFormArchive.beforeZip(preAttached), preAttached), "duplicate evidence prevented")
        let corrupt = rows(pngBytes: Data("not PNG".utf8))
        check(same(R602OneTapFormArchive.beforeZip(corrupt), corrupt), "bad PNG untouched")
        let full = original + (0..<21).map { .init(name: "x\($0)", bytes: Data()) }
        check(same(R602OneTapFormArchive.beforeZip(full), full), "capacity never exceeded")
        check(same(R602OneTapFormArchive.beforeZip([]), []), "empty archive unchanged")
        check(same(R602OneTapFormArchive.beforeZip([.init(name:"manifest.json",bytes:manifest)]),
                   [.init(name:"manifest.json",bytes:manifest)]), "partial bundle unchanged")
        print("R602_SWIFT_\(checks)_PASS")
    }
}
