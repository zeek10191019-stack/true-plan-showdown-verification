import Foundation

/// Injected runner failures exercise the actual production policy, not Vision.
@main struct R560RecoveryHarness {
    enum ProbeFailure: Error {case failed(String)}
    static func main() throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let reportURL=URL(fileURLWithPath:CommandLine.arguments[2])
        var checks=0,calls=0,audits=[ResearchOCRExecutionAudit]()
        func check(_ v:@autoclosure ()->Bool,_ reason:String)throws {
            guard v() else {throw ProbeFailure.failed(reason)};checks+=1
        }
        func json(_ v:Any)throws->Data {try JSONSerialization.data(withJSONObject:v,options:[.sortedKeys,.withoutEscapingSlashes])}
        func object<T:Encodable>(_ v:T)throws->Any {try JSONSerialization.jsonObject(with:JSONEncoder().encode(v))}
        func configured(_ mode:R560OCRRecovery.Mode,_ c:inout R560OCRRecovery.Configuration) {
            if mode == .cpuSoftware {c.accepted=true;c.supportedStages=2;c.mainStage=true;c.assignedStages=2}
            c.performed=true
        }
        let known=NSError(domain:"TextRecognition.CRImageReaderError",code:9)
        let unknown=NSError(domain:"NSCocoaErrorDomain",code:640)
        let direct=try R560OCRRecovery.execute {mode,c -> [String] in
            calls+=1;configured(mode,&c);return []
        }
        try check(calls==1 && direct.value.isEmpty && direct.audit.attempt_count==1,"empty successful result never triggers another attempt")
        audits.append(direct.audit)
        calls=0
        let recovered=try R560OCRRecovery.execute {mode,c -> [String] in
            calls+=1;configured(mode,&c)
            if mode == .frameworkDefault {throw known};return ["SYNTHETIC_RUNNER_VALUE"]
        }
        try check(calls==2 && recovered.value==["SYNTHETIC_RUNNER_VALUE"] && recovered.audit.attempts[0].outcome=="REQUEST_FAILED" &&
            recovered.audit.attempts[1].mode=="CPU_SOFTWARE","one known execution error retries exactly once")
        try check(!recovered.audit.ocr_accuracy_certified && !recovered.audit.compute_execution_attested,"configuration is not hardware/accuracy attestation")
        audits.append(recovered.audit)
        calls=0
        do {
            let _:R560OCRRecovery.Output<Int>=try R560OCRRecovery.execute {mode,c in calls+=1;configured(mode,&c);throw unknown}
            throw ProbeFailure.failed("unrelated failure accepted")
        } catch let error as R559OCRFailure.RequestFailure {
            try check(calls==1 && error.execution?.attempt_count==1,"unrelated error never retries")
            audits.append(error.execution!)
        }
        calls=0
        var finalFailure:R559OCRFailure.RequestFailure?
        do {
            let _:R560OCRRecovery.Output<Int>=try R560OCRRecovery.execute {mode,c in calls+=1;configured(mode,&c);throw known}
            throw ProbeFailure.failed("double failure accepted")
        } catch let error as R559OCRFailure.RequestFailure {
            try check(calls==2 && error.execution?.attempt_count==2 && error.execution?.status=="FAILED","no third attempt or empty success")
            finalFailure=error;audits.append(error.execution!)
        }
        calls=0
        do {
            let _:R560OCRRecovery.Output<Int>=try R560OCRRecovery.execute {mode,c in
                calls+=1
                if mode == .frameworkDefault {configured(mode,&c);throw known}
                c.supportedStages=2;c.mainStage=true;throw unknown
            }
            throw ProbeFailure.failed("unsupported CPU accepted")
        } catch let error as R559OCRFailure.RequestFailure {
            try check(calls==2 && error.execution?.attempts[1].outcome=="CONFIGURATION_FAILED" &&
                error.execution?.attempts[1].request_performed==false,"CPU configuration failure cannot run a request")
            audits.append(error.execution!)
        }
        for failFirst in [true,false] {
            calls=0;let work=R551EvidenceWork()
            do {
                let _:R560OCRRecovery.Output<Int>=try R560OCRRecovery.execute(work:work) {mode,c in
                    calls+=1;configured(mode,&c);work.cancel()
                    if failFirst {throw known};return 3
                }
                throw ProbeFailure.failed("cancelled result accepted")
            } catch R551EvidenceWork.Failure.cancelled {
                try check(calls==1,"cancelled first completion neither publishes nor retries")
            }
        }
        let cancelled=R551EvidenceWork();cancelled.cancel();calls=0
        do {
            let _:R560OCRRecovery.Output<Int>=try R560OCRRecovery.execute(work:cancelled) {mode,c in calls+=1;return 3}
            throw ProbeFailure.failed("already cancelled accepted")
        } catch R551EvidenceWork.Failure.cancelled {try check(calls==0,"pre-cancel avoids all requests")}
        for error in [NSError(domain:"NSCocoaErrorDomain",code:9),NSError(domain:"TextRecognition.CRImageReaderError",code:8),
                      NSError(domain:"TextRecognition.CRImageReaderError",code:10)] {
            calls=0
            do {
                let _:R560OCRRecovery.Output<Int>=try R560OCRRecovery.execute {mode,c in calls+=1;configured(mode,&c);throw error}
                throw ProbeFailure.failed("non-signature error accepted")
            } catch let failed as R559OCRFailure.RequestFailure {
                try check(calls==1 && failed.execution?.attempt_count==1,"only the exact observed signature retries")
                audits.append(failed.execution!)
            }
        }
        let png=try Data(contentsOf:root.appendingPathComponent("frames/frame_17.png"))
        let failure=R559OCRFailure.report(finalFailure!,session:"capture-test",frame:17,epoch:3,observedMs:1200,png:png,width:2,height:2)
        try check(failure["automatic_retry_count"] as? Int==1 && failure["recovery_audit"] is [String:Any],"failed retry reaches exported diagnostic")
        var selected=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("selected_evidence.json"))) as! [String:Any]
        selected["research_candidate_envelope"]=NSNull();selected["screen_read_state"]=NSNull();selected["r559_ocr_failure"]=failure
        var entries=[R548ResearchArchive.Entry(name:"selected_evidence.json",bytes:try json(selected))]
        for name in ["capture_manifest.json","frames/frame_17.png"] {entries.append(.init(name:name,bytes:try Data(contentsOf:root.appendingPathComponent(name))))}
        entries=try R551EvidenceIntegrity.appendingIndex(entries,captureSessionID:"capture-test",frame:17,epoch:3,appVersion:"0.5.60",appBuild:"560")
        _=try R548ResearchArchive.write(entries,to:root.appendingPathComponent("r560_recovery_failure.zip"))
        try json(["scope":"INJECTED_RUNNER_POLICY_ONLY","checks":checks,"audits":try audits.map {try object($0)},
            "failure":failure,"Vision_executed":false,"game_accuracy_certified":false]).write(to:reportURL)
        print("R560_NATIVE_RECOVERY_CHECKS_PASS=\(checks); INJECTED_RUNNER_ONLY")
    }
}
