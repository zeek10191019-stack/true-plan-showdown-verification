import Foundation

/// sampleQueue owns this slot. Epoch changes never release a running worker.
struct R562ReadWorkSlot {
    private var lastTicket:Int64=0
    private var activeTicket:Int64?
    var isAvailable:Bool {activeTicket==nil && lastTicket<Int64.max}
    func isLatest(_ ticket:Int64) -> Bool {ticket>0 && ticket==lastTicket}
    mutating func begin() -> Int64? {
        guard isAvailable else {return nil}
        lastTicket+=1;activeTicket=lastTicket;return lastTicket
    }
    @discardableResult mutating func finish(_ ticket:Int64) -> Bool {
        guard activeTicket==ticket else {return false}
        activeTicket=nil;return true
    }
    var object:[String:Any] {
        ["schema":"trueplan.screen-read.live-work-slot.v1","scope":"ONE_LIVE_OCR_WORKER_ACROSS_CAPTURE_EPOCHS",
         "capacity":1,"active_requests":activeTicket==nil ? 0:1,"last_ticket":lastTicket,
         "active_ticket":activeTicket.map {$0 as Any} ?? NSNull(),"available":isAvailable,
         "current_state_eligible":false,"owner_certified":false,"battle_advice_authorized":false]
    }
}
