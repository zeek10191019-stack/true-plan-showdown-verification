import Foundation

// R603: one-tap diagnostic, not a Pokémon identity or Mega confirmation.
// This uses only archive member existence; absence must never be guessed away.
enum R603FormReadiness {
    static let receiptName = "r603_form_readiness.json"
    static let requiredNames = [
        "r602_form_input.json", "crop.png", "manifest.json"
    ]

    static func beforeZip(
        _ entries: [R548ResearchArchive.Entry]
    ) -> [R548ResearchArchive.Entry] {
        let names = entries.map(\.name)
        // On any ambiguous or capacity-overflow case, keep the old export unchanged.
        guard entries.count < R548ResearchArchive.maximumMembers,
              Set(names).count == names.count,
              !names.contains(receiptName),
              names.allSatisfy({ safeName($0) }) else {
            return entries
        }
        let present = requiredNames.filter { key in
            entries.contains { $0.name == key && !$0.bytes.isEmpty }
        }
        let missing = requiredNames.filter { !present.contains($0) }
        let hasCandidate = entries.contains {
            $0.name == "r602_form_evidence.json" && !$0.bytes.isEmpty
        }
        let status: String
        if !missing.isEmpty {
            status = "HOLD_MISSING_CAPTURE_EVIDENCE"
        } else if !hasCandidate {
            status = "HOLD_NO_FORM_EVIDENCE"
        } else {
            status = "UNVERIFIED_EVIDENCE_PRESENT"
        }
        let payload: [String: Any] = [
            "schema": "trueplan.r603.form_readiness.v1",
            "status": status,
            "certification": "NOT_CERTIFIED_FOR_LIVE_BATTLE",
            "required": requiredNames,
            "present": present,
            "missing": missing,
            "evidence_present": hasCandidate,
            "reference_catalog_certified": false,
            "actor_identity_certified": false,
            "numeric_parity_certified": false,
            "disclaimer": "Archive-member inventory only; not a vision result"
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.sortedKeys]
        ) else { return entries }
        return entries + [R548ResearchArchive.Entry(
            name: receiptName, bytes: data
        )]
    }

    private static func safeName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 160 &&
        !name.hasPrefix("/") && !name.contains("\\") &&
        !name.contains("..") && !name.contains("//") &&
        name.utf8.allSatisfy { $0 >= 32 && $0 != 127 }
    }
}
