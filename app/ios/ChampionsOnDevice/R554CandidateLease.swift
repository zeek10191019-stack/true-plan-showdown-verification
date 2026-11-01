import Foundation

/// Thread-safe receipt freshness for automatic diagnostic display only.
/// Host receipt time is never an attested game-frame timestamp.
final class R554CandidateLease {
    struct Ticket: Equatable {
        let revision: Int64, request: Int64, epoch: Int64, frame: Int64, observedMs: Int64, deadlineMs: Int64
        let session: String
    }
    private let lock=NSLock()
    private let ttlMs: Int64
    // R570 opt-in: a later OCR request retires the previous display lease.
    // The last accepted digest remains available to reject unchanged pixels.
    private let retireOnNewRequest: Bool
    private var previousAdmittedSHA: String?
    private var revision: Int64=0, request: Int64=0, lastClockMs: Int64=0
    private var active=false
    private var session: String?
    private var epoch: Int64?
    private var lastFrame: Int64=0,lastObservedMs: Int64=0
    private var pending: Ticket?
    private var latest: (ticket: Ticket, sha: String)?
    private var reason="NOT_STARTED"
    private var accepted=0,rejected=0,duplicatePixels=0,invalidations=0

    init(ttlMs: Int64=2000,retireOnNewRequest: Bool=false) {
        precondition((1...30000).contains(ttlMs))
        self.ttlMs=ttlMs
        self.retireOnNewRequest=retireOnNewRequest
    }
    private func clear(_ why: String, stop: Bool) {
        if revision<Int64.max {revision+=1} else {active=false}
        pending=nil;latest=nil;previousAdmittedSHA=nil;reason=why;invalidations+=1
        if stop {active=false}
    }
    private func clock(_ nowMs: Int64) -> Bool {
        guard nowMs>0,nowMs>=lastClockMs else {
            clear("HOST_CLOCK_REWIND",stop:true);return false
        }
        lastClockMs=nowMs;return true
    }
    @discardableResult func begin(session newSession: String,epoch newEpoch: Int64,nowMs supplied: Int64?=nil) -> Bool {
        lock.lock();defer {lock.unlock()}
        let nowMs=supplied ?? Int64(ProcessInfo.processInfo.systemUptime*1000)
        guard !newSession.isEmpty,newSession.utf8.count<=128,newEpoch>0,
              epoch.map({newEpoch>$0}) ?? true,revision<Int64.max,clock(nowMs) else {rejected+=1;return false}
        clear("SOURCE_SCOPE_BEGAN",stop:false)
        session=newSession;epoch=newEpoch;lastFrame=0;lastObservedMs=0;active=true
        return true
    }
    func issue(frame: Int64,observedMs: Int64,nowMs supplied: Int64?=nil) -> Ticket? {
        lock.lock();defer {lock.unlock()}
        let nowMs=supplied ?? Int64(ProcessInfo.processInfo.systemUptime*1000)
        guard active,clock(nowMs),pending==nil,let session,let epoch,
              frame>lastFrame,observedMs>0,observedMs>=lastObservedMs,observedMs<=nowMs,
              nowMs-observedMs<ttlMs,observedMs<=Int64.max-ttlMs,request<Int64.max else {rejected+=1;return nil}
        request+=1;lastFrame=frame;lastObservedMs=observedMs
        // Prevent a new frame, such as a switch/animation, from coexisting
        // with an earlier frame's apparent "fresh" research candidates.
        if retireOnNewRequest { latest=nil }
        let ticket=Ticket(revision:revision,request:request,epoch:epoch,frame:frame,
            observedMs:observedMs,deadlineMs:observedMs+ttlMs,session:session)
        pending=ticket;reason="OCR_PENDING";return ticket
    }
    @discardableResult func finish(_ ticket: Ticket,imageSHA: String?,admitted: Bool,nowMs supplied: Int64?=nil) -> Bool {
        lock.lock();defer {lock.unlock()}
        let nowMs=supplied ?? Int64(ProcessInfo.processInfo.systemUptime*1000)
        // An old completion must not clear a newer pending request or clock.
        guard active,pending==ticket,ticket.revision==revision else {rejected+=1;return false}
        guard clock(nowMs) else {rejected+=1;return false}
        pending=nil
        guard admitted,let sha=imageSHA,sha.utf8.count==64,
              sha.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)}),
              nowMs>=ticket.observedMs,nowMs<ticket.deadlineMs else {
            latest=nil;reason="RESULT_REJECTED_OR_EXPIRED";rejected+=1;return false
        }
        if (retireOnNewRequest ? previousAdmittedSHA : latest?.sha)==sha {
            duplicatePixels+=1;reason="DUPLICATE_PIXELS_NO_REFRESH";return false
        }
        latest=(ticket,sha);previousAdmittedSHA=sha
        accepted+=1;reason="FRESH_HOST_RECEIPT_ONLY";return true
    }
    func canPublish(_ ticket: Ticket,nowMs supplied: Int64?=nil) -> Bool {
        lock.lock();defer {lock.unlock()}
        let nowMs=supplied ?? Int64(ProcessInfo.processInfo.systemUptime*1000)
        guard active,latest?.ticket==ticket,ticket.revision==revision else {return false}
        guard clock(nowMs) else {return false}
        return nowMs<ticket.deadlineMs
    }
    func invalidate(reason: String,nowMs supplied: Int64?=nil,stop: Bool=false) {
        lock.lock();defer {lock.unlock()}
        let nowMs=supplied ?? Int64(ProcessInfo.processInfo.systemUptime*1000)
        guard clock(nowMs) else {return}
        clear(reason,stop:stop)
    }
    private func describe(_ ticket: Ticket) -> [String:Any] {
        ["scope_revision":ticket.revision,"request_id":ticket.request,"capture_session_id":ticket.session,
         "epoch":ticket.epoch,"frame_id":ticket.frame,"receipt_uptime_ms":ticket.observedMs,"deadline_uptime_ms":ticket.deadlineMs]
    }
    func snapshot(nowMs supplied: Int64?=nil) -> [String:Any] {
        lock.lock();defer {lock.unlock()}
        let nowMs=supplied ?? Int64(ProcessInfo.processInfo.systemUptime*1000)
        _=clock(nowMs)
        let status: String
        if !active {status="STOPPED"}
        else if let latest {status=nowMs<latest.ticket.deadlineMs ? "FRESH_RECEIPT_ONLY" : "EXPIRED"}
        else {status=pending==nil ? "EMPTY" : "PENDING"}
        var latestObject: Any=NSNull()
        if let latest {
            var object=describe(latest.ticket);object["image_sha256"]=latest.sha;latestObject=object
        }
        return ["schema":"trueplan.screen-read.candidate-lease.v1","scope":"HOST_RECEIPT_DIAGNOSTICS_ONLY",
            "clock_basis":"UNCALIBRATED_HOST_RECEIPT_UPTIME","host_now_ms":max(0,nowMs),"last_clock_ms":lastClockMs,
            "ttl_ms":ttlMs,"active":active,"strict_retirement_on_new_request":retireOnNewRequest,
            "scope_revision":revision,"last_request_id":request,
            "capture_session_id":session.map {$0 as Any} ?? NSNull(),"epoch":epoch.map {$0 as Any} ?? NSNull(),
            "last_issued_frame_id":lastFrame,"last_issued_receipt_ms":lastObservedMs,
            "pending":pending.map {describe($0) as Any} ?? NSNull(),"latest":latestObject,
            "view_status":status,"last_reason":reason,"accepted_results":accepted,"rejected_operations":rejected,
            "duplicate_png_digests_not_refreshed":duplicatePixels,"invalidations":invalidations,
            "source_image_attached":false,"owner_certified":false,"current_state_eligible":false,
            "battle_advice_authorized":false,"battle_id":NSNull(),"turn":NSNull(),"capture_timestamp_ms":NSNull()]
    }
    static func display(_ snapshot: [String:Any]) -> String {
        switch snapshot["view_status"] as? String {
        case "FRESH_RECEIPT_ONLY":return "自動読取：受信期限内の研究候補（撮影時刻・現在状態は未認証）"
        case "EXPIRED":return "自動読取：受信期限切れ。古い候補の表示は停止しています"
        case "PENDING":return "自動読取：解析中。現在状態は未確認です"
        default:return "自動読取：新しい受信証拠待ち。現在状態は不明です"
        }
    }
}
