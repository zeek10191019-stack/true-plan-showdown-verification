import Foundation

/// R582 automatic delivery/retention audit, not a classifier or real-time state.
/// Queue confinement: use only on CaptureCoordinator.sampleQueue.
/// All memory is bounded; historical omissions must remain explicit.
struct R582AutoCaptureCoverage {
    static let schema = "trueplan.r582.auto-frame-coverage.v1"
    static let maxRecords = 1024
    static let exportRecordLimit = 128
    private(set) var totalObserved = 0
    private(set) var droppedRecords = 0
    private var records = [Record]()
    private struct Record {
        let epoch:Int64
        let frame:Int64
        let observedMs:Int64
        let width:Int
        let height:Int
        let background:Bool
        let clockAccepted:Bool
        var retained:Bool
        var pngSHA:String?
    }
    mutating func reset() {
        totalObserved = 0;droppedRecords = 0;records.removeAll(keepingCapacity:false)
    }
    @discardableResult mutating func observe(epoch:Int64,frame:Int64,observedMs:Int64,
                                            width:Int,height:Int,background:Bool,
                                            clockAccepted:Bool)->Bool {
        guard epoch>=0,frame>0,observedMs>0,width>0,height>0,
              width<=16384,height<=16384 else{return false}
        if let last=records.last {
            // Epoch is a capture scope, not a game/battle turn.
            guard epoch>last.epoch || (epoch==last.epoch && frame>last.frame && observedMs>=last.observedMs) else {return false}
        }
        totalObserved += 1
        records.append(Record(epoch:epoch,frame:frame,observedMs:observedMs,
                        width:width,height:height,background:background,
                        clockAccepted:clockAccepted,retained:false,pngSHA:nil))
        if records.count>Self.maxRecords {
            records.removeFirst(records.count-Self.maxRecords)
            droppedRecords=totalObserved-records.count
        }
        return true
    }
    @discardableResult mutating func markRetained(epoch:Int64,frame:Int64,pngSHA:String)->Bool {
        guard pngSHA.utf8.count==64,pngSHA.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)}),
              let idx=records.lastIndex(where:{$0.epoch==epoch && $0.frame==frame}),
              records[idx].retained==false else {return false}
        records[idx].retained=true;records[idx].pngSHA=pngSHA
        return true
    }
    func snapshot(epoch:Int64)->[String:Any] {
        let epochRows=records.filter{$0.epoch==epoch}
        let emitted=Array(epochRows.suffix(Self.exportRecordLimit))
        let first=epochRows.first
        let last=epochRows.last
        // This structure is an audit of DELIVERY, not proof that every event or
        // pixel was recorded. Even a complete retained log is not battle truth.
        return ["schema":Self.schema,"epoch":epoch,
                "total_accepted_deliveries_all_epochs":totalObserved,
                "ring_evicted_all_epochs":droppedRecords,
                "in_memory_records_for_epoch":epochRows.count,
                "exported_records_for_epoch":emitted.count,
                "omitted_from_epoch_report":epochRows.count-emitted.count,
                "stored_png_samples_within_ring":epochRows.filter{$0.retained}.count,
                "unretained_deliveries_within_ring":epochRows.filter{ !$0.retained }.count,
                "earliest_retained_frame_id":first?.frame as Any? ?? NSNull(),
                "latest_retained_frame_id":last?.frame as Any? ?? NSNull(),
                "full_session_history_guaranteed":false,
                "every_frame_pixels_archived":false,
                "game_state_certified":false,"mega_form_certified":false,
                "automatic_collection":"FRAME_DELIVERY_METADATA_ONLY_NO_UPLOAD",
                "records":emitted.map { r in
                    ["frame_id":r.frame,"epoch":r.epoch,"observed_ms_monotonic":r.observedMs,
                     "width":r.width,"height":r.height,"is_background":r.background,
                     "clock_allows_ocr":r.clockAccepted,"png_sample_retained":r.retained,
                     "png_sha256":r.pngSHA as Any? ?? NSNull()] as [String:Any]
                }]
    }
}
