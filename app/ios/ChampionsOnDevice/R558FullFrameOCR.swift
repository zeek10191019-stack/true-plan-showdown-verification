import Foundation
import CoreGraphics
import ImageIO
import Vision
import CryptoKit

/// The same bounded Vision path is used by the iOS app and macOS CI.
/// Source identity is declared by the caller; the PNG bytes/hash are checked here.
enum R558FullFrameOCR {
    static let engineVersion="r560.full-frame.v3"
    static let maximumRegions=96
    static let maximumCandidates=3
    static let requiredLanguages=["ja-JP","en-US"]
    struct DecodedPNG {
        let image: CGImage
        let sha256: String
        fileprivate init(image: CGImage,sha256: String) {self.image=image;self.sha256=sha256}
    }
    struct Token {
        let text: String
        let confidence: Float
        let rect: TP530VisionRect.Rect?
        let alternatives: [ResearchTextAlternative]
        let observationIndex: Int
    }
    struct ImageResult {
        let execution: ResearchOCRExecutionAudit
        let visionInput: ResearchOCRVisionInput
        let tokens: [Token]
        let effectiveLevel: String
        let supportedLanguages: [String]
        let fastCheck: String
        let fastLanguages: [String]
        let requestRevision: Int
        let rawCount: Int
        let examinedCount: Int
        let omissions: [ResearchOCROmission]
    }
    struct Batch {
        let tokens: [Token]
        let readings: [ResearchReading]
        let audit: ResearchOCRRequestAudit
    }
    enum Failure: Error,LocalizedError {
        case invalidPNG,invalidFrame,unsupportedLanguages
        var errorDescription: String? {
            switch self {
            case .invalidPNG:return "画像の形式または寸法が一致せず、文字認識を保留しました"
            case .invalidFrame:return "画像のフレーム情報が不足しているため、文字認識を保留しました"
            case .unsupportedLanguages:return "日本語と英語に対応する文字認識を利用できません"
            }
        }
    }
    static func decodePNG(_ png: Data,work: R551EvidenceWork?=nil) throws -> DecodedPNG {
        try work?.check()
        guard png.count>=45,png.count<=FrameEvidenceExportGate.maximumPNGBytes,
              Array(png.suffix(12))==[0,0,0,0,73,69,78,68,174,66,96,130] else {throw Failure.invalidPNG}
        let header=Array(png.prefix(33))
        guard Array(header[0..<8])==[137,80,78,71,13,10,26,10],
              Array(header[8..<12])==[0,0,0,13],Array(header[12..<16])==Array("IHDR".utf8) else {throw Failure.invalidPNG}
        func u32(_ offset: Int)->Int {header[offset..<offset+4].reduce(0) {($0<<8)|Int($1)}}
        let width=u32(16),height=u32(20)
        guard FrameEvidenceExportGate.permitted(width:width,height:height) else {throw Failure.invalidPNG}
        guard let decoder=CGImageSourceCreateWithData(png as CFData,[kCGImageSourceShouldCache as String:false] as CFDictionary),
              CGImageSourceGetCount(decoder)==1,let kind=CGImageSourceGetType(decoder),kind as String=="public.png",
              let image=CGImageSourceCreateImageAtIndex(decoder,0,nil),image.width==width,image.height==height,
              CGImageSourceGetStatus(decoder) == .statusComplete,
              CGImageSourceGetStatusAtIndex(decoder,0) == .statusComplete else {throw Failure.invalidPNG}
        let digest=SHA256.hash(data:png).map {String(format:"%02x",$0)}.joined()
        try work?.check()
        return DecodedPNG(image:image,sha256:digest)
    }
    static func recognizeImage(_ image: CGImage,speedPriority: Bool=false,
                               work: R551EvidenceWork?=nil) throws -> ImageResult {
        try work?.check()
        guard FrameEvidenceExportGate.permitted(width:image.width,height:image.height) else {throw Failure.invalidPNG}
        let request=VNRecognizeTextRequest()
        request.usesLanguageCorrection=false
        var fastCheck="NOT_REQUESTED",fastLanguages=[String](),supported=[String]()
        if speedPriority {
            request.recognitionLevel = .fast
            do {
                fastLanguages=Array(Set(try request.supportedRecognitionLanguages())).sorted()
                fastCheck=requiredLanguages.allSatisfy {fastLanguages.contains($0)} ? "SUPPORTED" : "UNSUPPORTED"
            } catch {fastCheck="QUERY_FAILED"}
        }
        if speedPriority && fastCheck=="SUPPORTED" {
            supported=fastLanguages
        } else {
            request.recognitionLevel = .accurate
            guard let languages=try? request.supportedRecognitionLanguages() else {throw Failure.unsupportedLanguages}
            supported=Array(Set(languages)).sorted()
        }
        guard requiredLanguages.allSatisfy({supported.contains($0)}) else {throw Failure.unsupportedLanguages}
        request.recognitionLanguages=requiredLanguages
        try work?.check()
        let input=try R559VisionInput.prepare(image,work:work)
        try work?.check()
        let execution=try R560VisionExecutor.recognize(input,template:request,work:work)
        // Cooperative cancellation cannot interrupt perform(); reject its result
        // if cancellation arrived while Vision was running.
        try work?.check()
        let observations=execution.value
        var tokens=[Token](),omissions=[ResearchOCROmission]()
        for (index,observation) in observations.prefix(maximumRegions).enumerated() {
            try work?.check()
            let candidates=observation.topCandidates(maximumCandidates)
            guard let first=candidates.first else {
                omissions.append(.init(observation_index:index,reason:"NO_TEXT_CANDIDATE"));continue
            }
            let valid=candidates.count<=maximumCandidates && candidates.allSatisfy {
                !$0.string.isEmpty && $0.string.unicodeScalars.count<=256 && $0.string.utf8.count<=1024 &&
                $0.confidence.isFinite && (0...1).contains($0.confidence)
            }
            guard valid else {omissions.append(.init(observation_index:index,reason:"INVALID_TEXT_OR_CONFIDENCE"));continue}
            let sorted=zip(candidates,candidates.dropFirst()).allSatisfy {$0.0.confidence >= $0.1.confidence}
            guard sorted else {omissions.append(.init(observation_index:index,reason:"INVALID_ALTERNATIVE_ORDER"));continue}
            let alternatives=candidates.enumerated().map {
                ResearchTextAlternative(rank:$0.offset,raw_text:$0.element.string,confidence:Double($0.element.confidence))
            }
            let box=observation.boundingBox
            let rect=TP530VisionRect.convert(minX:Double(box.minX),minY:Double(box.minY),maxX:Double(box.maxX),maxY:Double(box.maxY),width:image.width,height:image.height)
            tokens.append(.init(text:first.string,confidence:first.confidence,rect:rect,alternatives:alternatives,observationIndex:index))
        }
        try work?.check()
        return ImageResult(execution:execution.audit,visionInput:input.audit,tokens:tokens,effectiveLevel:request.recognitionLevel == .fast ? "fast" : "accurate",
            supportedLanguages:supported,fastCheck:fastCheck,fastLanguages:fastLanguages,requestRevision:Int(request.revision),
            rawCount:observations.count,examinedCount:min(observations.count,maximumRegions),omissions:omissions)
    }
    static func inspect(_ png: Data,session: String,frame: Int64,epoch: Int64,observedMs: Int64,
                        speedPriority: Bool=false,work: R551EvidenceWork?=nil) throws -> Batch {
        guard !session.isEmpty,session.utf8.count<=256,frame>0,epoch>0,observedMs>0 else {throw Failure.invalidFrame}
        return try inspect(decoded:decodePNG(png,work:work),session:session,frame:frame,epoch:epoch,observedMs:observedMs,
                    speedPriority:speedPriority,work:work)
    }
    static func inspect(decoded: DecodedPNG,session: String,frame: Int64,epoch: Int64,observedMs: Int64,
                        speedPriority: Bool=false,work: R551EvidenceWork?=nil) throws -> Batch {
        guard !session.isEmpty,session.utf8.count<=256,frame>0,epoch>0,observedMs>0 else {throw Failure.invalidFrame}
        let result=try recognizeImage(decoded.image,speedPriority:speedPriority,work:work)
        let readings=result.tokens.map {token -> ResearchReading in
            var row=ResearchReading(key:nil,value:.null,raw_text:token.text,confidence:Double(token.confidence),
                reason:"FULL_FRAME_TEXT_OWNER_AND_TURN_UNBOUND")
            row.ocr_alternatives=token.alternatives;row.ocr_observation_index=token.observationIndex
            row.source_frame_id=frame;row.source_epoch=Int(epoch);row.source_image_sha256=decoded.sha256
            row.roi_owner_certified=false
            if let rect=token.rect {row.roi_rect=rect.dictionary;row.roi_source=TP530VisionRect.source}
            return row
        }
        var audit=ResearchOCRRequestAudit(schema:"trueplan.ocr.request-audit.v1",engine_version:engineVersion,
            scope:"PROVISIONAL_TEXT_REQUEST_ONLY",input_binding:"EXACT_PNG_BYTES_DECODED_UP",execution_attestation:"SELF_REPORTED_NO_SIGNATURE",
            capture_session_id:session,frame_id:frame,epoch:epoch,receipt_uptime_ms:observedMs,timestamp_basis:"UNCALIBRATED_HOST_RECEIPT_UPTIME",
            image_sha256:decoded.sha256,image_width:decoded.image.width,image_height:decoded.image.height,
            requested_mode:speedPriority ? "AUTOMATIC_SPEED_PRIORITY" : "MANUAL_ACCURATE",effective_recognition_level:result.effectiveLevel,
            requested_languages:requiredLanguages,effective_supported_languages:result.supportedLanguages,
            fast_language_check:result.fastCheck,fast_supported_languages:result.fastLanguages,request_revision:result.requestRevision,
            uses_language_correction:false,maximum_regions:maximumRegions,maximum_candidates_per_region:maximumCandidates,
            raw_region_count:result.rawCount,examined_region_count:result.examinedCount,emitted_region_count:result.tokens.count,
            truncated_region_count:result.rawCount-result.examinedCount,omitted_observations:result.omissions,
            unbound_roi_count:result.tokens.filter {$0.rect==nil}.count,ocr_accuracy_certified:false,device_certified:false,
            owner_certified:false,current_state_eligible:false,battle_advice_authorized:false)
        audit.vision_input=result.visionInput
        audit.execution_audit=result.execution
        try work?.check()
        return Batch(tokens:result.tokens,readings:readings,audit:audit)
    }
}
