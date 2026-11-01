import Foundation
import Vision
import CoreML
import CoreImage

/// Same image and recognition configuration for both bounded attempts.
enum R560VisionExecutor {
    enum Failure: Error {case cpuUnavailable,missingResults}
    private static let softwareContext=CIContext(options:[.useSoftwareRenderer:true,.cacheIntermediates:false])
    static func recognize(_ input: R559VisionInput.Prepared,template: VNRecognizeTextRequest,
                          work: R551EvidenceWork?=nil) throws -> R560OCRRecovery.Output<[VNRecognizedTextObservation]> {
        try R560OCRRecovery.execute(work:work) {mode,configuration in
            let request: VNRecognizeTextRequest
            var options=[VNImageOption:Any]()
            if mode == .frameworkDefault {request=template}
            else {
                request=VNRecognizeTextRequest()
                request.revision=template.revision
                request.recognitionLevel=template.recognitionLevel
                request.recognitionLanguages=template.recognitionLanguages
                request.usesLanguageCorrection=template.usesLanguageCorrection
                request.minimumTextHeight=template.minimumTextHeight
                request.regionOfInterest=template.regionOfInterest
                request.automaticallyDetectsLanguage=template.automaticallyDetectsLanguage
                request.customWords=template.customWords
                request.preferBackgroundProcessing=template.preferBackgroundProcessing
                guard #available(iOS 17.0,macOS 14.0,*) else {throw Failure.cpuUnavailable}
                let stages=try request.supportedComputeStageDevices
                configuration.supportedStages=stages.count
                configuration.mainStage=stages.keys.contains(.main)
                guard configuration.mainStage,(1...16).contains(stages.count) else {throw Failure.cpuUnavailable}
                var assignments=[(VNComputeStage,MLComputeDevice)]()
                for (stage,devices) in stages {
                    guard let cpu=devices.first(where:{device in if case .cpu = device {return true};return false}) else {
                        throw Failure.cpuUnavailable
                    }
                    assignments.append((stage,cpu))
                }
                // Validate all stages before making any partial assignment.
                for (stage,device) in assignments {request.setComputeDevice(device,for:stage)}
                configuration.assignedStages=assignments.count
                options[.ciContext]=softwareContext
                configuration.accepted=true
            }
            try work?.check()
            configuration.performed=true
            try VNImageRequestHandler(cvPixelBuffer:input.buffer,orientation:.up,options:options).perform([request])
            try work?.check()
            guard let observations=request.results else {throw Failure.missingResults}
            return observations
        }
    }
}
