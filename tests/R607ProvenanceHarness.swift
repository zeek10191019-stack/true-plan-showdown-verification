import Foundation

@main struct R607ProvenanceHarness {
    static func main() throws {
        func check(_ ok: Bool,_ name:String) {precondition(ok,name);print("PASS_R607",name)}
        func entry(_ n:String,_ d:Data)->R548ResearchArchive.Entry {
            .init(name:n,bytes:d)
        }
        let png=Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEUlEQVR4nGM44SCAFTEMLQkAiF1GAYJRm+sAAAAASUVORK5CYII=")!
        let hash=R598OneButtonFormAttachment.testDigest(png)
        let names=["MEMORY_LEFT_ACTOR_HYPOTHESIS","MEMORY_RIGHT_ACTOR_HYPOTHESIS"]
        let regions=names.map{["region":$0,"luma_grid":Array(repeating:25,count:192),
            "valid_samples":192] as [String:Any]}
        func snapshot(_ hashes:[String],_ ids:[Int64]?=nil)->Data {
            let samples=hashes.enumerated().map { index,digest in
                ["epoch":Int64(2),"frame_id":ids?[index] ?? Int64(index+1),
                 "monotonic_ms":Int64(500+index),"full_frame_sha256":digest,
                 "regions":regions] as [String:Any]
            }
            let data:[String:Any]=[
                "schema":"trueplan.r604.r594_exact_snapshot.v1",
                "status":"HOLD_OWNER_OR_ROI_AND_R595_MATCHER_PARITY",
                "owner_verified":false,"mega_verified":false,"samples":samples
            ]
            return try! JSONSerialization.data(withJSONObject:data,options:[.sortedKeys])
        }
        func make(_ hashes:[String],_ pngs:[(String,Data)],_ ids:[Int64]?=nil)
            ->[R548ResearchArchive.Entry] {
            var a=[entry("manifest.json",Data("{}".utf8)),
                   entry("r604_r594_feature_snapshot.json",snapshot(hashes,ids))]
            for (n,data) in pngs {a.append(entry(n,data))}
            return R605ExactFrameBinding.beforeZip(a)
        }
        func report(_ archive:[R548ResearchArchive.Entry])->[String:Any] {
            let out=R607FrameProvenanceAudit.beforeZip(archive)
            check(out.count == archive.count+1,"receipt appended")
            return (try! JSONSerialization.jsonObject(with:out.last!.bytes)) as! [String:Any]
        }
        let original=make([hash],[ ("frame.png",png) ])
        let a=report(original)
        check(a["status"] as? String=="HOLD_FRAME_OWNER_ROI_ORIENTATION","identity remains hold")
        let aa=a["bindings"] as! [[String:Any]]
        check(aa.count==1,"one frame")
        check(aa[0]["archive_png"] as? String=="frame.png","bytes match")
        check(aa[0]["status"] as? String=="CONTENT_HASH_MATCH_ONLY_NEEDS_FRAME_AND_OWNER_PROOF","no promotion")
        check(a["mega_verified"] as? Bool==false,"mega unverified")
        check(a["full_frame_identity_verified"] as? Bool==false,"frame identity unverified")
        let missing=report(make([hash],[]))["bindings"] as! [[String:Any]]
        check(missing[0]["status"] as? String=="HOLD_PNG_BYTES_MISSING","PNG missing")
        let dup=report(make([hash],[ ("a.png",png),("b.png",png) ]))["bindings"] as! [[String:Any]]
        check(dup[0]["status"] as? String=="HOLD_DUPLICATE_ARCHIVE_PNG","duplicate PNG")
        let shared=report(make([hash,hash],[("frame.png",png)]))["bindings"] as! [[String:Any]]
        check(shared.count==2 && shared.allSatisfy({$0["status"] as? String ==
            "HOLD_SHARED_BYTES_ACROSS_FRAME_IDS"}),"reused image not same frame")
        var tampered=original
        let r5=original.first(where:{$0.name=="r605_exact_frame_binding.json"})!
        var claim=(try JSONSerialization.jsonObject(with:r5.bytes)) as! [String:Any]
        var rows=claim["frame_bindings"] as! [[String:Any]]
        rows[0]["matched_archive_png"]="other.png"
        claim["frame_bindings"]=rows
        tampered=tampered.map{$0.name==r5.name ? entry(r5.name,try! JSONSerialization.data(
            withJSONObject:claim,options:[.sortedKeys])):$0}
        let t=report(tampered)
        check(t["status"] as? String=="HOLD_REPORT_INCONSISTENT","tampered link hold")
        let originalAfter=R607FrameProvenanceAudit.beforeZip(original)
        check(R607FrameProvenanceAudit.beforeZip(originalAfter).count==originalAfter.count,"idempotent")
        var full=original
        while full.count < 24 {full.append(entry("pad\(full.count)",Data()))}
        check(R607FrameProvenanceAudit.beforeZip(full).count==24,"capacity preserved")
        let unsafe=original+[entry("../unsafe",Data())]
        check(R607FrameProvenanceAudit.beforeZip(unsafe).count==unsafe.count,"unsafe filename rejected")
        let oldOnly=original.filter{$0.name != "r605_exact_frame_binding.json"}
        let notPresent=report(oldOnly)
        check(notPresent["status"] as? String=="HOLD_EVIDENCE_MISSING","no fabricated source")
        print("R607_STANDALONE_TESTS_SUCCESS")
    }
}
