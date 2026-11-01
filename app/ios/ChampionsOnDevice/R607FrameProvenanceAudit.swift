import Foundation

// R607: cross-check the R604 snapshot, R605 content hash index and actual
// archived PNG bytes. An identical image is NOT proof of its frame identity,
// left/right owner, on-screen orientation, species or Mega form.
enum R607FrameProvenanceAudit {
    static let memberName = "r607_frame_provenance_audit.json"
    private static let sourceName = "r604_r594_feature_snapshot.json"
    private static let bindingName = "r605_exact_frame_binding.json"

    private static func validHash(_ s: String) -> Bool {
        s.utf8.count == 64 && s.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
    private static func validName(_ s: String) -> Bool {
        !s.isEmpty && s.utf8.count <= 160 && !s.hasPrefix("/") &&
        !s.contains("..") && !s.contains("\\") && !s.contains("//") &&
        s.utf8.allSatisfy { $0 >= 32 && $0 != 127 }
    }
    private static func read(_ bytes: Data) -> [String: Any]? {
        guard bytes.count <= 96*1024 else {return nil}
        return (try? JSONSerialization.jsonObject(with:bytes)) as? [String:Any]
    }
    private static func receipt(_ status: String,
                                _ rows: [[String:Any]],
                                _ reason: String) -> Data? {
        let doc: [String:Any] = [
            "schema":"trueplan.r607.byte_provenance_audit.v1",
            "status":status, "reason":reason,
            "certified_for_battle":false,
            "owner_verified":false,"orientation_verified":false,
            "roi_verified":false,"species_verified":false,"mega_verified":false,
            "full_frame_identity_verified":false,
            "reference_image_count":0,
            "bindings":rows,
            "limits":"SHA equality proves content only; frame/actor identity requires independent evidence"
        ]
        return try? JSONSerialization.data(withJSONObject:doc,options:[.sortedKeys])
    }
    static func beforeZip(_ entries: [R548ResearchArchive.Entry])
        -> [R548ResearchArchive.Entry] {
        let names=entries.map(\.name)
        guard entries.count < R548ResearchArchive.maximumMembers,
              names.count == Set(names).count,
              names.allSatisfy({validName($0)}),
              !names.contains(memberName) else {return entries}

        var status="HOLD_EVIDENCE_MISSING"
        var reason="R604_OR_R605_REPORT_NOT_PRESENT"
        var rows=[[String:Any]]()
        if let e4=entries.first(where:{$0.name==sourceName}),
           let e5=entries.first(where:{$0.name==bindingName}),
           let r4=read(e4.bytes),let r5=read(e5.bytes) {
            status="HOLD_REPORT_INCONSISTENT"
            reason="R604_R605_CONTRACT_OR_DIGEST_MISMATCH"
            if r4["schema"] as? String=="trueplan.r604.r594_exact_snapshot.v1",
               r4["status"] as? String=="HOLD_OWNER_OR_ROI_AND_R595_MATCHER_PARITY",
               r5["schema"] as? String=="trueplan.r605.exact_fullframe_binding.v1",
               r5["certification"] as? String=="NOT_CERTIFIED_FOR_LIVE_BATTLE",
               r5["original_r604_snapshot_sha256"] as? String ==
                 R598OneButtonFormAttachment.testDigest(e4.bytes),
               let samples=r4["samples"] as? [[String:Any]],
               let claims=r5["frame_bindings"] as? [[String:Any]],
               !samples.isEmpty,samples.count<=8,samples.count==claims.count {
                var pngs=[String:[String]]()
                for entry in entries where entry.name.lowercased().hasSuffix(".png") {
                    guard entry.bytes.count>=33,entry.bytes.count<=16*1024*1024,
                          entry.bytes.starts(with:[137,80,78,71,13,10,26,10]) else {continue}
                    let digest=R598OneButtonFormAttachment.testDigest(entry.bytes)
                    pngs[digest,default:[]].append(entry.name)
                }
                let allHashes=samples.compactMap{$0["full_frame_sha256"] as? String}
                var seen=Set<String>()
                var valid=true
                var output=[[String:Any]]()
                for i in samples.indices {
                    let s=samples[i],c=claims[i]
                    guard let frame=s["frame_id"] as? Int64,frame>0,
                          let epoch=s["epoch"] as? Int64,epoch>0,
                          let ms=s["monotonic_ms"] as? Int64,ms>0,
                          let hash=s["full_frame_sha256"] as? String,validHash(hash),
                          let cf=c["frame_id"] as? Int64,cf==frame,
                          let ce=c["epoch"] as? Int64,ce==epoch,
                          let ch=c["full_frame_sha256"] as? String,ch==hash,
                          let n=c["matches"] as? Int,n>=0,
                          let reported=c["status"] as? String,
                          c["actor_verified"] as? Bool == false,
                          c["orientation_verified"] as? Bool == false,
                          c["crop_verified"] as? Bool == false,
                          c["mega_verified"] as? Bool == false,
                          seen.insert("\(epoch):\(frame)").inserted,
                          let regions=s["regions"] as? [[String:Any]],regions.count==2,
                          Set(regions.compactMap({$0["region"] as? String})) == Set([
                            "MEMORY_LEFT_ACTOR_HYPOTHESIS",
                            "MEMORY_RIGHT_ACTOR_HYPOTHESIS"]),
                          regions.allSatisfy({r in
                              guard let grid=r["luma_grid"] as? [Int],grid.count==192,
                                    let count=r["valid_samples"] as? Int,
                                    count==grid.filter({$0>=0}).count else{return false}
                              return grid.allSatisfy({(-1...255).contains($0)})
                          }) else {valid=false;break}
                    let matches=pngs[hash] ?? []
                    let expected = matches.isEmpty ? "HOLD_ORIGINAL_PNG_NOT_IN_ARCHIVE" :
                        (matches.count>1 ? "HOLD_DUPLICATE_IDENTICAL_PNG" :
                         "EXACT_SOURCE_PNG_BYTES_MATCHED_RESEARCH_ONLY")
                    let linked=c["matched_archive_png"] as? String
                    guard n==matches.count,reported==expected,
                          linked == (matches.count==1 ? matches[0] : nil) else {
                        valid=false;break
                    }
                    let collision=allHashes.filter({$0==hash}).count>1
                    let verdict: String = matches.isEmpty ? "HOLD_PNG_BYTES_MISSING" :
                        (matches.count>1 ? "HOLD_DUPLICATE_ARCHIVE_PNG" :
                         (collision ? "HOLD_SHARED_BYTES_ACROSS_FRAME_IDS" :
                          "CONTENT_HASH_MATCH_ONLY_NEEDS_FRAME_AND_OWNER_PROOF"))
                    output.append([
                        "epoch":epoch,"frame_id":frame,"monotonic_ms":ms,
                        "source_png_sha256":hash,
                        "archive_png":matches.count==1 ? matches[0] as Any : NSNull(),
                        "status":verdict,
                        "frame_identity_verified":false,"actor_verified":false,
                        "mega_verified":false
                    ])
                }
                if valid {
                    rows=output
                    status="HOLD_FRAME_OWNER_ROI_ORIENTATION"
                    reason="CONTENT_HASH_AUDIT_PASS_IDENTITY_UNVERIFIED"
                }
            }
        }
        guard let bytes=receipt(status,rows,reason) else{return entries}
        return entries + [.init(name:memberName,bytes:bytes)]
    }
}
