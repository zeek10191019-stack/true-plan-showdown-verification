import Foundation
import CryptoKit
import CoreFoundation
import Darwin

/// Offline PNG -> the actual shared app OCR -> snapshot -> production ZIP writer.
/// It accepts label-free manifests, never annotations, and never certifies live state.
@main struct R574PNGReplay {
    enum Failure: Error {case rejected}
    static func require(_ ok:Bool)throws {if !ok {throw Failure.rejected}}
    static func sha(_ data:Data)->String {SHA256.hash(data:data).map {String(format:"%02x",$0)}.joined()}
    static func json(_ value:Any)throws->Data {try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys,.withoutEscapingSlashes])}
    static func integer(_ value:Any?)->Int? {
        guard let n=value as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),
              !["f","d"].contains(String(cString:n.objCType)),n.int64Value>=0,n.int64Value<=Int64(Int.max) else {return nil}
        return n.intValue
    }
    static func main() {
        do {try run()} catch {fputs("PNG_REPLAY_REJECTED_SEE_REPORT_IF_CREATED\n",stderr);exit(1)}
    }
    static func run()throws {
        try require(CommandLine.arguments.count==7)
        let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true).standardizedFileURL.resolvingSymlinksInPath()
        let manifestURL=URL(fileURLWithPath:CommandLine.arguments[2])
        let output=URL(fileURLWithPath:CommandLine.arguments[3],isDirectory:true)
        let reportURL=URL(fileURLWithPath:CommandLine.arguments[4])
        let version=CommandLine.arguments[5],build=CommandLine.arguments[6]
        try require(!version.isEmpty && version.utf8.count<=64 && build.range(of:#"^[1-9][0-9]{0,8}$"#,options:.regularExpression) != nil)
        let manifestBytes=try Data(contentsOf:manifestURL);try require(manifestBytes.count<=2_000_000)
        guard let manifest=try JSONSerialization.jsonObject(with:manifestBytes) as? [String:Any],
              Set(manifest.keys)==Set(["schema","samples"]),manifest["schema"] as? String=="trueplan.screen-read.png-replay-inputs.v1",
              let samples=manifest["samples"] as? [[String:Any]] else {throw Failure.rejected}
        try require((1...64).contains(samples.count) && !FileManager.default.fileExists(atPath:output.path) && !FileManager.default.fileExists(atPath:reportURL.path))
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        var results=[[String:Any]](),ids=Set<String>(),hashes=Set<String>(),paths=Set<String>()
        func save()throws {
            try json(["status":"EXPORTED_UNVERIFIED_OFFLINE_PNGS","scope":"EXACT_PNG_SHARED_APP_READER_OFFLINE_ONLY",
                "app_version":version,"app_build":build,"results":results,"expected_inputs":samples.count,
                "game_accuracy_certified":false,"device_certified":false,"iOS_runtime_executed":false]).write(to:reportURL,options:.atomic)
        }
        try save()
        let session="offline-png-"+UUID().uuidString
        var allSucceeded=true
        for (index,input) in samples.enumerated() {
            let sampleID=input["sample_id"] as? String ?? "INVALID"
            do {
                try require(Set(input.keys)==Set(["sample_id","path","sha256","bytes","width","height"]))
                guard let name=input["path"] as? String,let digest=input["sha256"] as? String,
                      let bytes=integer(input["bytes"]),let width=integer(input["width"]),let height=integer(input["height"]) else {throw Failure.rejected}
                try require(sampleID.range(of:#"^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$"#,options:.regularExpression) != nil && ids.insert(sampleID).inserted)
                try require(name.range(of:#"^[A-Za-z0-9_./-]{1,120}\.png$"#,options:.regularExpression) != nil &&
                    !name.hasPrefix("/") && name.split(separator:"/",omittingEmptySubsequences:false).allSatisfy {!$0.isEmpty && $0 != "." && $0 != ".."} && paths.insert(name.lowercased()).inserted)
                let path=root.appendingPathComponent(name).standardizedFileURL
                let resolved=path.resolvingSymlinksInPath()
                let properties=try path.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
                try require(properties.isRegularFile==true && properties.isSymbolicLink != true && resolved.path.hasPrefix(root.path+"/") && properties.fileSize==bytes && bytes>0 && bytes<=12_000_000)
                let png=try Data(contentsOf:resolved)
                try require(png.count==bytes && sha(png)==digest && hashes.insert(digest).inserted)
                let decoded=try R558FullFrameOCR.decodePNG(png)
                try require(decoded.image.width==width && decoded.image.height==height && decoded.sha256==digest)
                let frame=Int64(index+1),epoch:Int64=1,observed=max(1,Int64(ProcessInfo.processInfo.systemUptime*1000))
                let image:[String:Any]=["width":width,"height":height,"png_bytes":bytes,"png_sha256":digest,"image_png_base64":png.base64EncodedString()]
                var selected:[String:Any]=["schema":"trueplan.r27441.manual-frame-evidence.v2","source":"offline_exact_png_replay",
                    "capture_session_id":session,"battle_id":NSNull(),"frame_id":frame,"epoch":epoch,"observed_ms_monotonic":observed,
                    "image_width":width,"image_height":height,"png_bytes":bytes,"png_sha256":digest,"image_png_base64":png.base64EncodedString(),
                    "analysis_image":image,"research_candidate_envelope":NSNull(),"screen_read_state":NSNull(),
                    "verified_game_screen":false,"observed_turn":NSNull(),"production_enabled":false,"battle_advice_authorized":false]
                let started=ProcessInfo.processInfo.systemUptime
                var status="SUCCESS"
                var requestElapsed=0.0,requestFinished=false
                do {
                    let batch=try R558FullFrameOCR.inspect(decoded:decoded,session:session,frame:frame,epoch:epoch,observedMs:observed)
                    requestElapsed=(ProcessInfo.processInfo.systemUptime-started)*1000;requestFinished=true
                    let bound=batch.tokens.filter {$0.rect != nil}
                    let kind=R557ScreenEvidence.decide(primary:bound.map(\.text),allVariants:bound.flatMap {$0.alternatives.map(\.raw_text)}).kind
                    var packet=ResearchBattlePacket(battle_id:session,epoch:Int(epoch),frame_id:Int(frame),turn:nil,observed_at_ms:observed,
                        received_at_ms:max(observed,Int64(ProcessInfo.processInfo.systemUptime*1000)),image_sha256:digest,
                        source_ref:"offline-exact-png-replay",screen_kind:kind,readings:batch.readings)
                    packet.ocr_engine_version=R558FullFrameOCR.engineVersion;packet.ocr_request_audit=batch.audit
                    let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys,.withoutEscapingSlashes]
                    let payload=try encoder.encode(packet)
                    let envelope=String(data:try json(["schema":"trueplan.mobile-envelope.v1","payload_json":String(data:payload,encoding:.utf8)!,"payload_sha256":sha(payload)]),encoding:.utf8)!
                    selected["research_candidate_envelope"]=envelope
                    selected["screen_read_state"]=R551ScreenReadState.make(envelope:envelope,captureSessionID:session,frame:frame,epoch:epoch,
                        observedMs:observed,imageSHA:digest,width:width,height:height)
                } catch {
                    if !requestFinished {requestElapsed=(ProcessInfo.processInfo.systemUptime-started)*1000}
                    status="FAILED";allSucceeded=false
                    selected["r559_ocr_failure"]=R559OCRFailure.report(error,session:session,frame:frame,epoch:epoch,observedMs:observed,png:png,width:width,height:height)
                }
                selected["png_replay"]=["schema":"trueplan.screen-read.png-replay.v1","policy_id":"EXACT_PNG_SHARED_READER_OFFLINE_V1",
                    "reader_policy_version":"r574.png-replay.v1",
                    "sample_id":sampleID,"source_kind":"OFFLINE_EXACT_PNG","input_sha256":digest,"input_png_bytes":bytes,
                    "image_width":width,"image_height":height,"app_version":version,"app_build":build,"status":status,
                    "processing_time":["clock_basis":"HOST_MONOTONIC_ELAPSED","scope":"OCR_REQUEST","elapsed_ms":requestElapsed],
                    "capture_time_calibrated":false,"owner_certified":false,"identity_certified":false,"current_state_eligible":false,
                    "battle_advice_authorized":false,"game_accuracy_certified":false,"device_certified":false]
                let rotation:[String:Any]=["schema":"trueplan.r551.rotation-ocr-evidence.v1","image_sha256":digest,"mega_certified":false,"own_opponent":"UNKNOWN",
                    "megascene_observed":NSNull(),"mega_event_status":"UNKNOWN","visual_form_certified":false,"orientation_certified":false,
                    "rotations_completed":[Int](),"rotations_failed":[Int](),"rotations_skipped":[0,90,180,270],"orientation_evidence":[[String:Any]]()]
                let framePath="frames/frame_\(frame).png"
                let retained:[String:Any]=["file":framePath,"frame_id":frame,"epoch":epoch,"observed_ms_monotonic":observed,"png_sha256":digest,
                    "png_bytes":bytes,"width":width,"height":height,"own_opponent_certified":false,"mega_form_visual_certified":false,"mega_scene_ocr_hints":rotation]
                let capture:[String:Any]=["schema":"trueplan.r548.single-share-capture-package.v1","selected_frame_id":frame,"selected_epoch":epoch,
                    "capture_session_id":session,"battle_id":NSNull(),"battle_advice_authorized":false,"captured_frame_count":1,"frames":[retained],
                    "omissions":[String](),"capture_sample_spacing_ms":NSNull(),"source":"OFFLINE_EXACT_PNG_NO_CAPTURE_TIMING"]
                let selectedBytes=try json(selected);try require(selectedBytes.count<=FrameEvidenceExportGate.maximumJSONBytes)
                var entries=[R548ResearchArchive.Entry(name:"selected_evidence.json",bytes:selectedBytes),
                    .init(name:"capture_manifest.json",bytes:try json(capture)),.init(name:framePath,bytes:png)]
                entries=try R551EvidenceIntegrity.appendingIndex(entries,captureSessionID:session,frame:frame,epoch:epoch,appVersion:version,appBuild:build)
                let filename="replay_\(index+1).zip",archive=output.appendingPathComponent(filename)
                _=try R548ResearchArchive.write(entries,to:archive)
                let data=try Data(contentsOf:archive)
                results.append(["sample_id":sampleID,"status":status,"archive_file":filename,"archive_sha256":sha(data)])
            } catch {
                allSucceeded=false
                results.append(["sample_id":sampleID,"status":"INPUT_OR_EXPORT_REJECTED","reason":"INPUT_BINDING_DECODE_OR_EXPORT_FAILURE"])
            }
            try save()
        }
        print("R574_OFFLINE_PNG_REPLAY_EXPORTED=\(results.count); GAME_AND_DEVICE_UNVERIFIED")
        if !allSucceeded {throw Failure.rejected}
    }
}
