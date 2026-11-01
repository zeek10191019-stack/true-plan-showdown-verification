import Foundation

// Evidence receipt for the newly appended audit modules. This is not a signed
// attestation, nor an assertion that the captured image shows a battle UI.
enum R612ArchiveEvidenceClosure {
    static let memberName="r612_archive_evidence_closure.json"
    private static let subjects=[
        "r608_original_pixel_evidence.json",
        "r609_vision_text_spatial_evidence.json",
        "r610_hud_cross_evidence_candidates.json",
        "r611_temporal_hud_review.json"
    ]
    static func beforeZip(_ entries:[R548ResearchArchive.Entry]) -> [R548ResearchArchive.Entry] {
        let names=entries.map(\.name)
        guard entries.count<R548ResearchArchive.maximumMembers,
              names.count==Set(names).count,!names.contains(memberName) else {return entries}
        var records=[[String:Any]]()
        var missing=[String]()
        var contradiction=false
        for name in subjects {
            guard let entry=entries.first(where:{$0.name==name}),entry.bytes.count<=160_000,
                  let json=(try? JSONSerialization.jsonObject(with:entry.bytes)) as? [String:Any],
                  json["certified_for_battle"] as? Bool == false,
                  json["owner_verified"] as? Bool == false,
                  json["roi_verified"] as? Bool == false,
                  json["mega_verified"] as? Bool == false else {
                missing.append(name);continue
            }
            if json["display_orientation_verified"] as? Bool != false {contradiction=true}
            records.append([
                "archive_member":name,"byte_count":entry.bytes.count,
                "sha256":R598OneButtonFormAttachment.testDigest(entry.bytes),
                "upstream_status":json["status"] as? String ?? "UNKNOWN",
                "certified_for_battle":false
            ])
        }
        let report:[String:Any]=[
            "schema":"trueplan.r612.research_evidence_closure.v1",
            "status":!missing.isEmpty ? "HOLD_MISSING_OR_INVALID_RESEARCH_EVIDENCE" :
                (contradiction ? "HOLD_UNEXPECTED_ORIENTATION_PROMOTION" :
                "HOLD_COMPLETE_UNCERTIFIED_RESEARCH_RECEIPTS"),
            "checked_members":records,"missing_or_invalid":missing,
            "member_count_before_closure":entries.count,
            "certified_for_battle":false,"owner_verified":false,
            "roi_verified":false,"mega_verified":false,
            "display_orientation_verified":false,
            "limitations":"SHA-256 receipts are reproducibility metadata, not proof of image truth, identity, form or calibration."
        ]
        guard let bytes=try? JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),
              bytes.count<=16_000 else {return entries}
        return entries+[.init(name:memberName,bytes:bytes)]
    }
}
