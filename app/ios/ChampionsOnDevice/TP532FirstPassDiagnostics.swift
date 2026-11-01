import Foundation

/// Real first-pass ROI diagnostics. Counts only; no raw OCR, pixel or Battle State.
/// Measurements are collected only after current epoch/frame admission succeeds.
enum TP532FirstPassDiagnostics {
    struct Snapshot {
        let frames: Int
        let acceptedRects: Int
        let rejectedRects: Int
        let failedFrames: Int
        let measuredLatency: [Int]
        let epoch: Int?
        let latestFrame: Int64?
        var redacted: [String:Any] {
            let sorted = measuredLatency.sorted()
            let p95 = sorted.isEmpty ? nil : sorted[(95 * sorted.count + 99)/100 - 1]
            return [
                "schema":"R532_FIRST_PASS_DIAGNOSTIC_V1",
                "scope":"CURRENT_EPOCH_RESEARCH_ONLY",
                "frames":frames,
                "first_pass_rects_retained":acceptedRects,
                "first_pass_rects_rejected":rejectedRects,
                "ocr_failed_frames":failedFrames,
                "p95_research_inspection_elapsed_ms": p95 as Any? ?? NSNull(),
                "latency_window_samples":sorted.count,
                "over_budget_samples_last_32":sorted.filter{$0>1500}.count,
                "auto_ocr_policy":"ONE_FULL_FRAME_REQUEST_WITH_JA_SUPPORTED_FAST_FALLBACK",
                "manual_ocr_policy":"EXTRA_HP_GENDER_CROPS_RESEARCH_ONLY",
                "latest_epoch":epoch as Any? ?? NSNull(),
                "latest_frame_id":latestFrame as Any? ?? NSNull(),
                "vision_publication_limit_per_frame":96,
                "owner_certified":false,
                "recognition_certified":false,
                "decision_eligible":false,
                "image_bytes_included":false,
                "ocr_text_included":false,
                "image_hash_included":false,
                "battle_id_included":false
            ]
        }
    }
    private static let lock=NSLock()
    private static var sessionID:String?=nil
    private static var epoch:Int?=nil
    private static var lastFrame:Int64?=nil
    private static var frames=0
    private static var accepted=0
    private static var rejected=0
    private static var failures=0
    private static var latency:[Int]=[]

    static func resetForTests() {
        lock.lock();defer{lock.unlock()}
        sessionID=nil;epoch=nil;lastFrame=nil;frames=0;accepted=0;rejected=0;failures=0;latency=[]
    }
    @discardableResult
    static func record(battleID:String,epoch ep:Int,frameID id:Int64,retained:Int,rejected removed:Int,
                       elapsedMs:Int,result:String)->Bool {
        guard !battleID.isEmpty,battleID.utf8.count<=128,ep>=0,id>0,(0...96).contains(retained),(0...96).contains(removed),
              retained+removed<=96,(0...120_000).contains(elapsedMs),
              result.utf8.count<=96 else{return false}
        lock.lock();defer{lock.unlock()}
        if sessionID != battleID {
            sessionID=battleID;epoch=nil
        }
        if let old=epoch,ep<old {return false}
        if epoch != ep {
            epoch=ep;lastFrame=nil;frames=0;accepted=0;rejected=0;failures=0;latency=[]
        }
        if let prev=lastFrame,id<=prev{return false}
        lastFrame=id;frames+=1;accepted+=retained;rejected+=removed
        if result=="NO_OCR_RESULT" { failures+=1 }
        latency.append(elapsedMs)
        if latency.count>32 {latency.removeFirst(latency.count-32)}
        return true
    }
    static func snapshot()->Snapshot {
        lock.lock();defer{lock.unlock()}
        return Snapshot(frames:frames,acceptedRects:accepted,rejectedRects:rejected,
                        failedFrames:failures,measuredLatency:latency,epoch:epoch,
                        latestFrame:lastFrame)
    }
    /// Add first-pass diagnostics to the R528 one-tap JSON; original 3 sources remain unchanged.
    /// This never assigns an own/opp identity or authorizes a battle decision.
    static func attach(to original:Data) throws -> Data {
        guard var packet=try JSONSerialization.jsonObject(with:original) as? [String:Any],
              var sources=packet["sources"] as? [String:Any],
              var scopes=packet["source_scopes"] as? [String:String] else {
            throw NSError(domain:"R532FirstPassExport",code:1)
        }
        guard sources["r532_first_pass"] == nil else {
            throw NSError(domain:"R532FirstPassExport",code:2)
        }
        sources["r532_first_pass"]=snapshot().redacted
        scopes["r532_first_pass"]="CURRENT_EPOCH_RESEARCH_ONLY"
        packet["sources"]=sources
        packet["source_scopes"]=scopes
        packet["source_count"]=sources.count
        packet["schema"]="R532_ONE_TAP_FOUR_SOURCE_DIAGNOSTICS_V1"
        packet["all_sources_same_frame_certified"]=false
        packet["owner_certified"]=false
        packet["recognition_certified"]=false
        packet["battle_advice_authorized"]=false
        return try JSONSerialization.data(withJSONObject:packet,options:[.sortedKeys])
    }
}
