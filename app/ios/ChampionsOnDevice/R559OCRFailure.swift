import Foundation
import CryptoKit

/// Bounded error codes only. No localized messages, paths or NSError userInfo.
enum R559OCRFailure {
    struct RequestFailure: Error,LocalizedError {
        let codes: [[String:Any]]
        var execution: ResearchOCRExecutionAudit? = nil
        var errorDescription: String? {"文字認識を完了できませんでした。画像と診断を保存して再試行できます"}
    }
    static func codes(_ error: Error)->[[String:Any]] {
        let allowed:Set<String>=["com.apple.Vision","VNErrorDomain","NSCocoaErrorDomain","NSOSStatusErrorDomain",
            "NSPOSIXErrorDomain","TextRecognition.CRImageReaderError","OTHER_ERROR_DOMAIN"]
        var result=[[String:Any]](),current: NSError?=error as NSError
        for _ in 0..<4 {
            guard let value=current else {break}
            // Unknown domains can themselves contain paths or user text.
            result.append(["domain":allowed.contains(value.domain) ? value.domain : "OTHER_ERROR_DOMAIN","code":value.code])
            current=value.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return result
    }
    static func report(_ error: Error,session: String,frame: Int64,epoch: Int64,observedMs: Int64,
                       png: Data?,width: Int,height: Int)->[String:Any] {
        let digest=png.map {SHA256.hash(data:$0).map {String(format:"%02x",$0)}.joined()}
        var report:[String:Any] = ["schema":"trueplan.ocr.failure.v1","status":"OCR_FAILED_NO_RESULT","capture_session_id":session,
            "frame_id":frame,"epoch":epoch,"receipt_uptime_ms":observedMs,
            "attempted_image_sha256":digest.map {$0 as Any} ?? NSNull(),"attempted_image_width":png == nil ? 0 : width,
            "attempted_image_height":png == nil ? 0 : height,
            "error_codes":(error as? RequestFailure)?.codes ?? codes(error),
            "execution_attestation":"SELF_REPORTED_NO_SIGNATURE","automatic_retry_count":max(0,((error as? RequestFailure)?.execution?.attempt_count ?? 1)-1),
            "raw_error_messages_included":false,"current_state_eligible":false,"owner_certified":false,
            "ocr_accuracy_certified":false,"battle_advice_authorized":false]
        if let audit=(error as? RequestFailure)?.execution,
           let data=try? JSONEncoder().encode(audit),let value=try? JSONSerialization.jsonObject(with:data) {
            report["recovery_audit"]=value
        }
        return report
    }
}
