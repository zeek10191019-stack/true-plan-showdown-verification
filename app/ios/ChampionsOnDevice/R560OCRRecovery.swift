import Foundation

/// A failed framework execution may retry once; text content never triggers it.
enum R560OCRRecovery {
    enum Mode: String {case frameworkDefault="FRAMEWORK_DEFAULT",cpuSoftware="CPU_SOFTWARE"}
    struct Configuration {
        var accepted: Bool
        var performed=false
        var supportedStages=0
        var mainStage=false
        var assignedStages=0
        let softwareContext: Bool
        init(_ mode: Mode) {accepted=mode == .frameworkDefault;softwareContext=mode == .cpuSoftware}
    }
    struct Output<Value> {let value: Value;let audit: ResearchOCRExecutionAudit}
    enum Failure: Error {case invalidConfiguration}
    static func codes(_ error: Error)->[ResearchOCRErrorCode] {
        R559OCRFailure.codes(error).compactMap {row in
            guard let domain=row["domain"] as? String,let code=row["code"] as? Int else {return nil}
            return .init(domain:domain,code:code)
        }
    }
    static func retryable(_ errors: [ResearchOCRErrorCode])->Bool {
        errors.contains {$0.domain=="TextRecognition.CRImageReaderError" && $0.code==9}
    }
    static func audit(_ attempts: [ResearchOCRExecutionAttempt],succeeded: Bool)->ResearchOCRExecutionAudit {
        .init(schema:"trueplan.ocr.execution.v1",policy_id:"DEFAULT_THEN_CPU_SOFTWARE_ON_IMAGE_ERROR_9_V1",
            status:succeeded ? "SUCCEEDED" : "FAILED",attempt_count:attempts.count,attempts:attempts,
            same_input_reused:true,configuration_only:true,compute_execution_attested:false,
            ocr_accuracy_certified:false,owner_certified:false,current_state_eligible:false,battle_advice_authorized:false)
    }
    static func execute<Value>(work: R551EvidenceWork?=nil,
        perform: (Mode,inout Configuration)throws->Value) throws -> Output<Value> {
        var attempts=[ResearchOCRExecutionAttempt]()
        for mode in [Mode.frameworkDefault,.cpuSoftware] {
            try work?.check()
            var configuration=Configuration(mode)
            do {
                let result=try perform(mode,&configuration)
                try work?.check()
                guard configuration.accepted,configuration.performed,
                      mode == .frameworkDefault || (configuration.mainStage && configuration.supportedStages>0 &&
                        configuration.supportedStages<=16 && configuration.assignedStages==configuration.supportedStages) else {
                    throw Failure.invalidConfiguration
                }
                attempts.append(attempt(mode,configuration,"SUCCEEDED",[]))
                return Output(value:result,audit:audit(attempts,succeeded:true))
            } catch {
                // Never admit a result or retry once its caller has cancelled.
                try work?.check()
                let errors=codes(error)
                let outcome=configuration.performed ? "REQUEST_FAILED" : "CONFIGURATION_FAILED"
                attempts.append(attempt(mode,configuration,outcome,errors))
                if mode == .frameworkDefault && configuration.performed && retryable(errors) {continue}
                let all=attempts.flatMap(\.error_codes).prefix(4).map {["domain":$0.domain,"code":$0.code] as [String:Any]}
                throw R559OCRFailure.RequestFailure(codes:all,execution:audit(attempts,succeeded:false))
            }
        }
        throw Failure.invalidConfiguration
    }
    private static func attempt(_ mode: Mode,_ config: Configuration,_ outcome: String,
                                _ errors:[ResearchOCRErrorCode])->ResearchOCRExecutionAttempt {
        .init(mode:mode.rawValue,outcome:outcome,configuration_accepted:config.accepted,
            request_performed:config.performed,supported_stage_count:config.supportedStages,
            main_stage_present:config.mainStage,cpu_assigned_stage_count:config.assignedStages,
            software_context_requested:config.softwareContext,error_codes:errors)
    }
}
