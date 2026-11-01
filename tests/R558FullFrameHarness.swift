import Foundation
import AppKit
import CryptoKit
import Vision
import Darwin

/// Render independent literal probes, then run the exact app OCR engine.
/// These are not game screenshots or device recognition certification.
@main struct R558FullFrameHarness {
    enum ProbeFailure: Error {case failed(String)}
    @MainActor static func main() {
        do {try execute()} catch {
            fputs("FULLFRAME_PROBE_FAILED_SEE_NATIVE_JSON\n",stderr)
            exit(1)
        }
    }
    @MainActor static func execute() throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let reportURL=URL(fileURLWithPath:CommandLine.arguments[2])
        let appVersion=CommandLine.arguments.count>3 ? CommandLine.arguments[3] : "0.5.60"
        let appBuild=CommandLine.arguments.count>4 ? CommandLine.arguments[4] : "560"
        var checks=0
        func check(_ condition:@autoclosure ()->Bool,_ reason:String)throws {
            guard condition() else {throw ProbeFailure.failed(reason)};checks+=1
        }
        func sha(_ data:Data)->String {SHA256.hash(data:data).map {String(format:"%02x",$0)}.joined()}
        func json(_ value:Any)throws->Data {try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys,.withoutEscapingSlashes])}
        func object<T:Encodable>(_ value:T)throws->Any {try JSONSerialization.jsonObject(with:JSONEncoder().encode(value))}
        @MainActor func render(_ text:String)throws->Data {
            guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1200,pixelsHigh:180,bitsPerSample:8,
                samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),
                let context=NSGraphicsContext(bitmapImageRep:bitmap) else {throw R558FullFrameOCR.Failure.invalidPNG}
            bitmap.size=NSSize(width:1200,height:180)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current=context
            defer {NSGraphicsContext.restoreGraphicsState()}
            NSColor.white.setFill();NSBezierPath(rect:NSRect(x:0,y:0,width:1200,height:180)).fill()
            (text as NSString).draw(at:NSPoint(x:40,y:50),withAttributes:[.font:NSFont.systemFont(ofSize:64),.foregroundColor:NSColor.black])
            context.cgContext.flush()
            guard let png=bitmap.representation(using:.png,properties:[:]) else {throw R558FullFrameOCR.Failure.invalidPNG}
            return png
        }
        func compact(_ text:String)->String {text.precomposedStringWithCompatibilityMapping.filter {!$0.isWhitespace}.uppercased()}
        func envelope(_ batch:R558FullFrameOCR.Batch)throws->String {
            let bound=batch.tokens.filter {$0.rect != nil}
            let kind=R557ScreenEvidence.decide(primary:bound.map(\.text),allVariants:bound.flatMap {$0.alternatives.map(\.raw_text)}).kind
            var packet=ResearchBattlePacket(battle_id:"capture-test",epoch:3,frame_id:17,turn:nil,observed_at_ms:1200,
                received_at_ms:1250,image_sha256:batch.audit.image_sha256,source_ref:"ci-synthetic:appkit-literal-probe",
                screen_kind:kind,readings:batch.readings)
            packet.ocr_engine_version=R558FullFrameOCR.engineVersion;packet.ocr_request_audit=batch.audit
            let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys,.withoutEscapingSlashes]
            let payload=try encoder.encode(packet)
            let wire=try json(["schema":"trueplan.mobile-envelope.v1","payload_json":String(data:payload,encoding:.utf8)!,"payload_sha256":sha(payload)])
            return String(data:wire,encoding:.utf8)!
        }
        var phase="SETUP",probeID="NONE",currentPNG:Data?,currentImage:CGImage?
        var currentTexts=[String]()
        func controls(_ image:CGImage,_ png:Data)->[[String:Any]] {
            // Only after a failed probe, compare the old CGImage and PNG routes.
            // These are diagnostics, not app retries or substitutes for the gate.
            ["CGIMAGE_UP","EXACT_PNG_UP"].map {name in
                let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate
                request.usesLanguageCorrection=false;request.recognitionLanguages=["ja-JP","en-US"]
                do {
                    let handler = name == "CGIMAGE_UP" ? VNImageRequestHandler(cgImage:image,orientation:.up,options:[:])
                        : VNImageRequestHandler(data:png,orientation:.up,options:[:])
                    try handler.perform([request])
                    return ["handler":name,"status":"PERFORM_RETURNED","revision":Int(request.revision),
                        "observation_count":request.results?.count ?? 0]
                } catch {return ["handler":name,"status":"PERFORM_FAILED","error_codes":R559OCRFailure.codes(error)]}
            }
        }
        let cases:[(String,String,String,Any)]=[
            ("literal_hp_ascii","HP148/197","hp",["current":148,"maximum":197]),
            ("literal_percent_ascii","81%","hp_percent",81),
            ("literal_pp_ascii","PP5/10","pp",["current":5,"maximum":10]),
            ("literal_remaining_japanese","トリックルーム残り3ターン","room",
                ["label":"トリックルーム","remaining_turns":3,"duration_semantics":"EXPLICIT_REMAINING_CANDIDATE"] as [String:Any])]
        var results=[[String:Any]](),firstPNG:Data?,firstWire:String?,firstState:[String:Any]?
        do {
        for (index,probe) in cases.enumerated() {
            probeID=probe.0;phase="RENDER";currentTexts=[];currentPNG=nil;currentImage=nil
            print("FULLFRAME_PROBE_BEGIN=\(probeID)");fflush(stdout)
            let png=try render(probe.1);currentPNG=png;currentImage=nil;phase="DECODE"
            let decoded=try R558FullFrameOCR.decodePNG(png);currentImage=decoded.image;phase="VISION_PERFORM"
            try check(decoded.image.width==1200 && decoded.image.height==180 && decoded.sha256==sha(png),"actual PNG dimensions and hash")
            let requestStarted=ProcessInfo.processInfo.systemUptime
            let batch=try R558FullFrameOCR.inspect(decoded:decoded,session:"capture-test",frame:17,epoch:3,observedMs:1200,speedPriority:index==3)
            let requestElapsedMs=(ProcessInfo.processInfo.systemUptime-requestStarted)*1000
            currentTexts=batch.tokens.map(\.text)
            phase="LITERAL_AND_WIRE_CHECKS"
            try check(batch.audit.image_sha256==sha(png) && batch.audit.emitted_region_count==batch.readings.count,"same decoded PNG reaches wire rows")
            try check(Set(["ja-JP","en-US"]).isSubset(of:Set(batch.audit.effective_supported_languages)),"both required languages are supported")
            let exact=batch.tokens.contains {compact($0.text)==compact(probe.1)}
            try check(exact,"clear synthetic primary literal: "+probe.0)
            try check(!batch.readings.isEmpty && batch.readings.allSatisfy {$0.key==nil && $0.ocr_observation_index != nil && $0.source_image_sha256==sha(png)},"no owner/current keys and complete source indices")
            let wire=try envelope(batch)
            let state=R551ScreenReadState.make(envelope:wire,captureSessionID:"capture-test",frame:17,epoch:3,observedMs:1200,
                imageSHA:sha(png),width:1200,height:180)
            try check(state["source_validation"] as? String=="PASS_FRAME_BINDING_ONLY","real OCR packet source reaches snapshot")
            let expected=try json(["value":probe.3])
            var matched=false
            for candidate in state["candidates"] as? [[String:Any]] ?? [] where candidate["domain"] as? String==probe.2 {
                if let value=candidate["value"],try json(["value":value])==expected {matched=true}
            }
            try check(matched,"real primary literal reaches structured candidate: "+probe.0)
            try check(state["current_state_eligible"] as? Bool==false && batch.audit.ocr_accuracy_certified==false,"synthetic probe never certifies game or live state")
            results.append(["probe_id":probe.0,"rendered_literal":probe.1,"expected_domain":probe.2,"expected_value":probe.3,
                "rendered_png_base64":png.base64EncodedString(),"rendered_png_sha256":sha(png),
                "processing_time":["clock_basis":"HOST_MONOTONIC_ELAPSED","scope":"OCR_REQUEST","elapsed_ms":requestElapsedMs],
                "primary_texts":batch.tokens.map(\.text),"primary_literal_match":exact,"structured_candidate_match":matched,
                "request_audit":try object(batch.audit),"game_accuracy_certified":false])
            if index==0 {firstPNG=png;firstWire=wire;firstState=state}
        }
        phase="ADVERSARIAL_AND_ARCHIVE_CHECKS"
        guard let png=firstPNG,let wire=firstWire,let state=firstState else {throw ProbeFailure.failed("MISSING_PROBE")}
        let cancelled=R551EvidenceWork();cancelled.cancel()
        do {_=try R558FullFrameOCR.inspect(png,session:"capture-test",frame:17,epoch:3,observedMs:1200,work:cancelled);throw ProbeFailure.failed("CANCELLED_OCR_ACCEPTED")}
        catch R551EvidenceWork.Failure.cancelled {checks+=1}
        for invalid in [Data(),Data(png.prefix(30)),Data("not a PNG".utf8),Data(png.dropLast()),png+Data([0])] {
            do {_=try R558FullFrameOCR.decodePNG(invalid);throw ProbeFailure.failed("INVALID_PNG_ACCEPTED")}
            catch R558FullFrameOCR.Failure.invalidPNG {checks+=1}
        }
        var huge=png;huge.replaceSubrange(16..<20,with:[0x7f,0xff,0xff,0xff])
        do {_=try R558FullFrameOCR.decodePNG(huge);throw ProbeFailure.failed("OVERSIZE_HEADER_ACCEPTED")}
        catch R558FullFrameOCR.Failure.invalidPNG {checks+=1}
        do {_=try R558FullFrameOCR.inspect(png,session:"capture-test",frame:0,epoch:3,observedMs:1200);throw ProbeFailure.failed("INVALID_FRAME_ACCEPTED")}
        catch R558FullFrameOCR.Failure.invalidFrame {checks+=1}
        var selected=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("selected_evidence.json"))) as! [String:Any]
        selected["image_width"]=1200;selected["image_height"]=180;selected["image_png_base64"]=png.base64EncodedString()
        selected["png_bytes"]=png.count;selected["png_sha256"]=sha(png)
        selected["analysis_image"]=["width":1200,"height":180,"image_png_base64":png.base64EncodedString(),"png_bytes":png.count,"png_sha256":sha(png)]
        selected["research_candidate_envelope"]=wire;selected["screen_read_state"]=state
        var manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("capture_manifest.json"))) as! [String:Any]
        var frames=manifest["frames"] as! [[String:Any]]
        frames[0]["width"]=1200;frames[0]["height"]=180;frames[0]["png_bytes"]=png.count;frames[0]["png_sha256"]=sha(png)
        var rotation=frames[0]["mega_scene_ocr_hints"] as! [String:Any];rotation["image_sha256"]=sha(png);frames[0]["mega_scene_ocr_hints"]=rotation
        manifest["frames"]=frames
        var entries=[R548ResearchArchive.Entry(name:"selected_evidence.json",bytes:try json(selected)),
            .init(name:"capture_manifest.json",bytes:try json(manifest)),.init(name:"frames/frame_17.png",bytes:png)]
        entries=try R551EvidenceIntegrity.appendingIndex(entries,captureSessionID:"capture-test",frame:17,epoch:3,appVersion:appVersion,appBuild:appBuild)
        let archiveURL=root.appendingPathComponent("r558_fullframe.zip")
        _=try R548ResearchArchive.write(entries,to:archiveURL)
        let archiveBytes=try Data(contentsOf:archiveURL)
        try json(["status":"PASS","checks":checks,"synthetic_literal_probes":results,"scope":"APPKIT_SYNTHETIC_PRIMITIVES_ONLY",
            "app_version":appVersion,"app_build":appBuild,"archive_base64":archiveBytes.base64EncodedString(),"archive_sha256":sha(archiveBytes),
            "shared_app_OCR_implementation_executed_on_macos":true,"real_game_images_used":false,"game_accuracy_certified":false,
            "device_certified":false]).write(to:reportURL)
        print("R558_NATIVE_FULLFRAME_CHECKS_PASS=\(checks); SYNTHETIC_LITERAL_PROBES=\(results.count); GAME_ACCURACY_UNVERIFIED")
        } catch {
            var failed:[String:Any] = ["status":"FAIL","phase":phase,"probe_id":probeID,"completed_checks":checks,
                "completed_probes":results,"failure_type":String(reflecting:type(of:error)),
                "error_codes":(error as? R559OCRFailure.RequestFailure)?.codes ?? R559OCRFailure.codes(error),
                "primary_texts":currentTexts,
                "game_accuracy_certified":false,"device_certified":false]
            if let failure=error as? ProbeFailure,case .failed(let reason)=failure {failed["failed_assertion"]=reason}
            if let execution=(error as? R559OCRFailure.RequestFailure)?.execution,let value=try? object(execution) {failed["execution_audit"]=value}
            if let png=currentPNG {
                failed["attempted_png_base64"]=png.base64EncodedString()
                failed["attempted_png_sha256"]=sha(png)
            }
            // Preserve the first failure before optional control handlers run.
            try? json(failed).write(to:reportURL)
            if let png=currentPNG,let image=currentImage {
                failed["image_info"]=["png_sha256":sha(png),"width":image.width,"height":image.height,
                    "bits_per_component":image.bitsPerComponent,"bits_per_pixel":image.bitsPerPixel,
                    "bytes_per_row":image.bytesPerRow,"alpha_info":image.alphaInfo.rawValue]
                failed["control_handlers"]=controls(image,png)
            }
            try? json(failed).write(to:reportURL)
            throw error
        }
    }
}
