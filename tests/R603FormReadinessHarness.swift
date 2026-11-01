import Foundation

// Minimal archive stub: production references the existing R548 writer's Entry.
enum R548ResearchArchive {
    static let maximumMembers = 24
    struct Entry {
        let name: String
        let bytes: Data
    }
}

@main struct Test {
    static var checks = 0
    static func check(_ ok: Bool, _ label: String) {
        precondition(ok, label); checks += 1
    }
    static func member(_ n: String, _ b: String = "a") -> R548ResearchArchive.Entry {
        .init(name: n, bytes: Data(b.utf8))
    }
    static func report(_ a: [R548ResearchArchive.Entry]) -> [String: Any]? {
        guard let b = a.first(where: { $0.name == R603FormReadiness.receiptName })?.bytes
        else { return nil }
        return try? JSONSerialization.jsonObject(with: b) as? [String: Any]
    }
    static func main() {
        let blank = R603FormReadiness.beforeZip([])
        check(blank.count == 1, "empty adds receipt")
        check(report(blank)?["status"] as? String == "HOLD_MISSING_CAPTURE_EVIDENCE", "empty HOLD")
        check((report(blank)?["missing"] as? [String])?.count == 3, "all missing")
        let e = [member("r602_form_input.json"), member("crop.png"), member("manifest.json")]
        let complete = R603FormReadiness.beforeZip(e)
        check(complete.count == 4, "complete ready inventory")
        check(report(complete)?["status"] as? String == "HOLD_NO_FORM_EVIDENCE", "no vector HOLD")
        check((report(complete)?["missing"] as? [String])?.isEmpty == true, "no names missing")
        let e2 = e + [member("r602_form_evidence.json")]
        let withEvidence = R603FormReadiness.beforeZip(e2)
        check(report(withEvidence)?["status"] as? String == "UNVERIFIED_EVIDENCE_PRESENT", "no certified result")
        check(report(withEvidence)?["numeric_parity_certified"] as? Bool == false, "no invented parity")
        check(report(withEvidence)?["actor_identity_certified"] as? Bool == false, "no invented owner")
        check(report(withEvidence)?["reference_catalog_certified"] as? Bool == false, "no invented refs")
        let bad = [member("a"), member("a")]
        check(R603FormReadiness.beforeZip(bad).count == 2, "duplicate original")
        let hazardous = [member("../evil")]
        check(R603FormReadiness.beforeZip(hazardous).count == 1, "path danger")
        check(R603FormReadiness.beforeZip([member("/root")]).count == 1, "absolute path")
        check(R603FormReadiness.beforeZip([member("sub\\back")]).count == 1, "backslash")
        check(R603FormReadiness.beforeZip([member("r603_form_readiness.json")]).count == 1, "duplicate receipt")
        let full = (0..<24).map { member("input_\($0)") }
        check(R603FormReadiness.beforeZip(full).count == 24, "capacity")
        let emptyRequired = e.enumerated().map {
            $0.offset == 0 ? member($0.element.name, "") : $0.element
        }
        check((report(R603FormReadiness.beforeZip(emptyRequired))?["missing"] as? [String]) == ["r602_form_input.json"], "empty input absent")
        let untouched = R603FormReadiness.beforeZip(e)
        check(untouched.prefix(3).map(\.name) == e.map(\.name), "original member names")
        check(untouched.prefix(3).map(\.bytes) == e.map(\.bytes), "original member bytes")
        let once = R603FormReadiness.beforeZip(e)
        check(once.last!.bytes == untouched.last!.bytes, "receipt deterministic")
        check(R603FormReadiness.beforeZip(once).count == once.count, "second pass rejected")
        print("R603_FORM_READINESS_TESTS \(checks)/\(checks) PASS")
    }
}
