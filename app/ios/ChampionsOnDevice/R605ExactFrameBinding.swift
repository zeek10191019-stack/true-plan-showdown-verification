import Foundation

// R605: byte-exact linkage of a saved full-frame PNG to R594's original
// 16x12 luminance samples. This is NOT an actor, ROI, or Mega identity proof.
enum R605ExactFrameBinding {
    static let memberName = "r605_exact_frame_binding.json"
    private static let sourceName = "r604_r594_feature_snapshot.json"
    private static let sourceSchema = "trueplan.r604.r594_exact_snapshot.v1"
    private static let maxPNGBytes = 16 * 1024 * 1024
    private static func isHash(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
    private static func safeName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 160 && !name.hasPrefix("/") &&
        !name.contains("..") && !name.contains("\\") &&
        !name.contains("//") &&
        name.utf8.allSatisfy { $0 >= 32 && $0 != 127 }
    }
    static func beforeZip(_ entries: [R548ResearchArchive.Entry])
        -> [R548ResearchArchive.Entry] {
        let names=entries.map(\.name)
        guard entries.count < R548ResearchArchive.maximumMembers,
              names.count == Set(names).count, names.allSatisfy({safeName($0)}),
              !names.contains(memberName),
              let source=entries.first(where:{$0.name == sourceName}),
              source.bytes.count <= 96 * 1024,
              let object=(try? JSONSerialization.jsonObject(with:source.bytes)) as? [String:Any],
              object["schema"] as? String == sourceSchema,
              object["status"] as? String == "HOLD_OWNER_OR_ROI_AND_R595_MATCHER_PARITY",
              object["owner_verified"] as? Bool == false,
              object["mega_verified"] as? Bool == false,
              let samples=object["samples"] as? [[String:Any]],
              !samples.isEmpty && samples.count <= 8 else { return entries }
        // Only the original bytes of archive PNGs are eligible. A separately
        // resized/re-encoded crop is not interchangeable with the source frame.
        var pngHashes=[String:[String]]()
        for e in entries where e.name.lowercased().hasSuffix(".png") {
            guard e.bytes.count >= 33, e.bytes.count <= maxPNGBytes,
                  e.bytes.starts(with:[137,80,78,71,13,10,26,10]) else {continue}
            let digest=R598OneButtonFormAttachment.testDigest(e.bytes)
            pngHashes[digest,default:[]].append(e.name)
        }
        var output=[[String:Any]](),seen=Set<String>()
        for s in samples {
            guard let epoch=s["epoch"] as? Int64,epoch>0,
                  let frame=s["frame_id"] as? Int64,frame>0,
                  let ms=s["monotonic_ms"] as? Int64,ms>0,
                  let hash=s["full_frame_sha256"] as? String,isHash(hash),
                  let regions=s["regions"] as? [[String:Any]],regions.count==2,
                  Set(regions.compactMap({$0["region"] as? String})) == Set([
                    "MEMORY_LEFT_ACTOR_HYPOTHESIS","MEMORY_RIGHT_ACTOR_HYPOTHESIS"]),
                  regions.allSatisfy({r in
                      guard let grid=r["luma_grid"] as? [Int],grid.count==192,
                            let valid=r["valid_samples"] as? Int,
                            valid == grid.filter({$0>=0}).count else {return false}
                      return grid.allSatisfy({(-1...255).contains($0)})
                  }), seen.insert("\(epoch):\(frame)").inserted
            else {return entries}
            let paths=pngHashes[hash] ?? []
            let status: String
            if paths.isEmpty {status="HOLD_ORIGINAL_PNG_NOT_IN_ARCHIVE"}
            else if paths.count != 1 {status="HOLD_DUPLICATE_IDENTICAL_PNG"}
            else {status="EXACT_SOURCE_PNG_BYTES_MATCHED_RESEARCH_ONLY"}
            output.append([
                "epoch":epoch,"frame_id":frame,"monotonic_ms":ms,
                "full_frame_sha256":hash,"matched_archive_png":paths.count==1 ? paths[0]:NSNull(),
                "matches":paths.count,"status":status,
                "feature_grid_count":2,"feature_count_per_grid":192,
                "actor_verified":false,"orientation_verified":false,
                "crop_verified":false,"mega_verified":false
            ])
        }
        let result: [String:Any] = [
            "schema":"trueplan.r605.exact_fullframe_binding.v1",
            "certification":"NOT_CERTIFIED_FOR_LIVE_BATTLE",
            "source":"R594_CAPTURED_GRID_PLUS_ARCHIVED_ORIGINAL_PNG_ONLY",
            "original_r604_snapshot_sha256":R598OneButtonFormAttachment.testDigest(source.bytes),
            "frame_bindings":output,
            "limits":"Full-frame SHA equality does not certify actor ROI, rotation, crop, or form"
        ]
        guard let json=try? JSONSerialization.data(withJSONObject:result,options:[.sortedKeys])
        else{return entries}
        return entries + [.init(name:memberName,bytes:json)]
    }
}
