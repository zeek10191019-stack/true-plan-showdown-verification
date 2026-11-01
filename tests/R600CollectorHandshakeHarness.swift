import Foundation
@main struct R600Harness {
    static var checks = 0
    static func check(_ ok: @autoclosure () -> Bool, _ why: String) {
        guard ok() else { fatalError("R600 FAIL: \(why)") }; checks += 1
    }
    static let png = Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAT0lEQVR4nKXDiQ2AMAADsStQoPSbIfsPGYaIJQNytBQ5yXHISc5TTnJdcpJa5ST3LSd5HjnJ+8pJWpOTfJ+cpHc5yRhykjnlJGvJSfaWkz9U5S8QboDItQAAAABJRU5ErkJggg==")!
    static let catalog = Data(#"{"schema":"trueplan.r596.visual_catalog.v1","references":[]}"#.utf8)
    static var hash: String { R598OneButtonFormAttachment.testDigest(png) }
    static func directory() -> URL {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: root,withIntermediateDirectories:true)
        try! png.write(to:root.appendingPathComponent("crop.png"))
        try! Data(#"{"original":true,"frame_count":9}"#.utf8).write(to:root.appendingPathComponent("manifest.json"))
        return root
    }
    static func frame(battle: String="b600", epoch:Int=3, id:Int=21, token:String="actor1",
                      side:String="own", crop:String="crop.png", sha:String?=nil,
                      orientation:String="landscape-left", roi:String="layoutA",
                      verified:Bool=true, orientationVerified:Bool=true) -> R600FrameStamp {
        R600FrameStamp(battleID:battle,epoch:epoch,frameID:id,actorToken:token,side:side,
           cropRelativePath:crop,cropSHA256:sha ?? hash,orientation:orientation,
           roiLayoutID:roi,actorVerified:verified,orientationVerified:orientationVerified)
    }
    static func producer(battle: String="b600", epoch:Int=3, id:Int=21, token:String="actor1",
                         side:String="own", sha:String?=nil, orientation:String="landscape-left",
                         roi:String="layoutA", extractor:String=R596FormCatalogGate.extractorID,
                         vector: [Double]=Array(repeating:0.2,count:192)) -> R600FeatureStamp {
        R600FeatureStamp(battleID:battle,epoch:epoch,frameID:id,actorToken:token,side:side,
          cropSHA256:sha ?? hash,orientation:orientation,roiLayoutID:roi,
          extractorID:extractor,features:vector)
    }
    static func stage(_ r:URL,_ f:R600FrameStamp=frame(),_ p:R600FeatureStamp=producer()) -> R600HandshakeReceipt {
        R600CollectorHandshake.stage(bundleRoot:r,frame:f,producer:p,catalogData:catalog)
    }
    static func main() throws {
        let good=directory();defer{try? FileManager.default.removeItem(at:good)}
        let before=try Data(contentsOf:good.appendingPathComponent("crop.png"))
        let success=stage(good)
        check(success.emitted,"complete handshake emits research sidecar")
        check(success.reason.contains("NOT_LIVE_CERTIFIED"),"cannot claim live certification")
        check(success.evidenceRelativePath?.hasPrefix("evidence/r598_form_3_21_")==true,"path identity")
        check(try! Data(contentsOf:good.appendingPathComponent("crop.png")) == before,"PNG bytes preserved")
        let manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:good.appendingPathComponent("manifest.json"))) as! [String:Any]
        check(manifest["original"] as? Bool == true,"manifest preexisting metadata intact")
        let side=manifest["r598_form_evidence"] as! [String:Any]
        check(side["status"] as? String == "hold","no real labels -> HOLD")
        check(side["certification"] as? String == "NOT_CERTIFIED_FOR_LIVE_BATTLE","not certified")
        let sideData=try Data(contentsOf:good.appendingPathComponent(success.evidenceRelativePath!))
        check(side["sha256"] as? String == R598OneButtonFormAttachment.testDigest(sideData),"sha correct")
        check(!stage(good).emitted,"double submit rejected")
        let bad=directory();defer{try? FileManager.default.removeItem(at:bad)}
        let original=try Data(contentsOf:bad.appendingPathComponent("manifest.json"))
        let cases: [(String,R600FrameStamp,R600FeatureStamp)] = [
           ("battle",frame(battle:"other"),producer()),
           ("epoch",frame(epoch:4),producer()),
           ("frame",frame(id:22),producer()),
           ("actor",frame(token:"actor2"),producer()),
           ("side",frame(side:"opponent"),producer()),
           ("hash",frame(sha:String(repeating:"a",count:64)),producer()),
           ("orientation",frame(orientation:"landscape-right"),producer()),
           ("roi",frame(roi:"layoutB"),producer()),
           ("bad feature shape",frame(),producer(vector:Array(repeating:0.2,count:191))),
           ("bad feature algorithm",frame(),producer(extractor:"vision-feature-print")),
           ("NaN",frame(),producer(vector:Array(repeating:Double.nan,count:192))),
           ("infinite",frame(),producer(vector:Array(repeating:Double.infinity,count:192))),
           ("overwide vector",frame(),producer(vector:Array(repeating:1000001.0,count:192))),
           ("unverified actor",frame(verified:false),producer()),
           ("unverified orientation",frame(orientationVerified:false),producer()),
           ("portrait",frame(orientation:"portrait"),producer(orientation:"portrait")),
           ("unsafe frame",frame(token:"../actor"),producer(token:"../actor")),
           ("negative epoch",frame(epoch:-1),producer(epoch:-1)),
           ("unrecognized side",frame(side:"other"),producer(side:"other")),
           ("bad sha format",frame(sha:String(repeating:"Z",count:64)),producer(sha:String(repeating:"Z",count:64))),
           ("relative escape",frame(crop:"../crop.png"),producer()),
           ("abs path",frame(crop:"/crop.png"),producer()),
           ("missing crop",frame(crop:"missing.png"),producer())
        ]
        for (name,f,p) in cases {
            check(!stage(bad,f,p).emitted,"must reject: \(name)")
            check(!FileManager.default.fileExists(atPath:bad.appendingPathComponent("evidence").path),"no partial write: \(name)")
        }
        check(try! Data(contentsOf:bad.appendingPathComponent("manifest.json")) == original,"failure leaves manifest identical")
        let mismatch=stage(bad,frame(sha:String(repeating:"a",count:64)),producer(sha:String(repeating:"a",count:64)))
        check(mismatch.reason == "CROP_SHA256_NOT_BOUND_TO_FRAME","byte association rejects shared wrong hash")
        let damaged=directory();defer{try? FileManager.default.removeItem(at:damaged)}
        var bytes=png;bytes[60] ^= 1
        try bytes.write(to:damaged.appendingPathComponent("crop.png"))
        check(!stage(damaged).emitted,"PNG CRC corruption refuses")
        check(!FileManager.default.fileExists(atPath:damaged.appendingPathComponent("evidence").path),"corruption no write")
        if let target=ProcessInfo.processInfo.environment["R600_STAGE_EXPORT"] {
            let dst=URL(fileURLWithPath:target,isDirectory:true)
            try FileManager.default.createDirectory(at:dst,withIntermediateDirectories:true)
            try FileManager.default.copyItem(at:good.appendingPathComponent("crop.png"),to:dst.appendingPathComponent("crop.png"))
            try FileManager.default.copyItem(at:good.appendingPathComponent("manifest.json"),to:dst.appendingPathComponent("manifest.json"))
            let ev=dst.appendingPathComponent("evidence",isDirectory:true)
            try FileManager.default.createDirectory(at:ev,withIntermediateDirectories:true)
            try FileManager.default.copyItem(at:good.appendingPathComponent(success.evidenceRelativePath!),to:dst.appendingPathComponent(success.evidenceRelativePath!))
        }
        print("R600 SWIFT \(checks)/\(checks) PASS")
    }
}
