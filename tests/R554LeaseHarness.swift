import Foundation

@main struct R554LeaseHarness {
    static func main() throws {
        let directory=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let reportURL=URL(fileURLWithPath:CommandLine.arguments[2])
        let a=String(repeating:"a",count:64),b=String(repeating:"b",count:64)
        var checks=0,receipts=[[String:Any]]()
        func check(_ condition: @autoclosure ()->Bool,_ message: String) {
            guard condition() else {fatalError("R554_CHECK_FAILED: "+message)};checks+=1
        }
        func json(_ object: Any) throws -> Data {try JSONSerialization.data(withJSONObject:object,options:[.sortedKeys,.withoutEscapingSlashes])}
        let lease=R554CandidateLease()
        check(lease.begin(session:"source-a",epoch:1,nowMs:1000),"new source scope")
        let first=lease.issue(frame:1,observedMs:1000,nowMs:1000)!
        check(lease.issue(frame:2,observedMs:1001,nowMs:1001)==nil,"single flight")
        check(lease.finish(first,imageSHA:a,admitted:true,nowMs:1100),"accept own ticket")
        check(lease.canPublish(first,nowMs:1100),"fresh receipt publication")
        receipts.append(lease.snapshot(nowMs:1100))
        check(!lease.begin(session:"same-epoch-restart",epoch:1,nowMs:1200),"same epoch cannot refresh")
        let second=lease.issue(frame:2,observedMs:1500,nowMs:1500)!
        check(!lease.finish(first,imageSHA:b,admitted:true,nowMs:1000),"old completion cannot reset clock or pending")
        check((lease.snapshot(nowMs:1500)["pending"] as? [String:Any])?["request_id"] as? Int64==second.request,"new pending survives")
        check(!lease.finish(second,imageSHA:a,admitted:true,nowMs:1510),"identical pixels do not renew")
        let duplicate=lease.snapshot(nowMs:1510);receipts.append(duplicate)
        check((duplicate["latest"] as? [String:Any])?["deadline_uptime_ms"] as? Int64==3000,"original deadline retained")
        check(lease.canPublish(first,nowMs:2999),"just before deadline")
        check(!lease.canPublish(first,nowMs:3000),"at deadline expired")
        let expired=lease.snapshot(nowMs:3000);receipts.append(expired)
        check(expired["view_status"] as? String=="EXPIRED","expired display")
        let third=lease.issue(frame:3,observedMs:3000,nowMs:3000)!
        check(lease.finish(third,imageSHA:b,admitted:true,nowMs:3010),"new pixels can renew")
        lease.invalidate(reason:"MEMORY_PRESSURE",nowMs:3020)
        check(!lease.canPublish(third,nowMs:3021),"memory warning invalidates")
        receipts.append(lease.snapshot(nowMs:3021))
        let fourth=lease.issue(frame:4,observedMs:3030,nowMs:3030)!
        check(!lease.finish(third,imageSHA:a,admitted:true,nowMs:1000),"old generation cannot unlock new")
        check(lease.finish(fourth,imageSHA:a,admitted:true,nowMs:3040),"replacement pending survives old result")
        lease.invalidate(reason:"SOURCE_STOPPED",nowMs:3050,stop:true)
        check(lease.issue(frame:5,observedMs:3051,nowMs:3051)==nil,"stopped source cannot offer")
        receipts.append(lease.snapshot(nowMs:3051))
        check(lease.begin(session:"source-b",epoch:2,nowMs:3060),"new scope after stop")
        let fresh=lease.issue(frame:1,observedMs:3060,nowMs:3060)!
        check(!lease.finish(fourth,imageSHA:a,admitted:true,nowMs:1),"retired source cannot affect current clock")
        check(lease.finish(fresh,imageSHA:b,admitted:true,nowMs:3070),"new source owns completion")
        check(lease.snapshot(nowMs:3000)["view_status"] as? String=="STOPPED","clock rewind withholds")
        receipts.append(lease.snapshot(nowMs:3000))

        for bad in [String(repeating:"A",count:64),"short",""] {
            let l=R554CandidateLease();_=l.begin(session:"invalid-sha",epoch:1,nowMs:100)
            let t=l.issue(frame:1,observedMs:100,nowMs:100)!
            check(!l.finish(t,imageSHA:bad,admitted:true,nowMs:101),"invalid SHA withheld")
        }
        let late=R554CandidateLease();_=late.begin(session:"late",epoch:1,nowMs:100)
        let lateTicket=late.issue(frame:1,observedMs:100,nowMs:100)!
        check(!late.finish(lateTicket,imageSHA:a,admitted:true,nowMs:2100),"late result at deadline withheld")
        check(late.snapshot(nowMs:2100)["latest"] is NSNull,"late result leaves no value")
        check(late.issue(frame:2,observedMs:100,nowMs:2100)==nil,"stale offer not issued")
        check(late.issue(frame:2,observedMs:2200,nowMs:2100)==nil,"future receipt withheld")
        let overflow=R554CandidateLease();_=overflow.begin(session:"overflow",epoch:1,nowMs:Int64.max-1000)
        check(overflow.issue(frame:1,observedMs:Int64.max-1000,nowMs:Int64.max-1000)==nil,"deadline overflow rejected")

        var gate=TP494AutoSampleGate()
        check(gate.offer(epoch:1,frame:1,observedMs:1000,width:1290,height:2796,background:true),"auto request")
        for frame in 2...32 {_=gate.offer(epoch:1,frame:Int64(frame),observedMs:1000+Int64(frame),width:1290,height:2796,background:true)}
        check(gate.finish(epoch:1,frame:2,observedMs:1000,startedMs:1010,completedMs:1200,succeeded:true)=="OLD_OR_INCONSISTENT_OCR" && gate.inFlight,"wrong frame cannot unlock gate")
        check(gate.finish(epoch:1,frame:1,observedMs:1001,startedMs:1010,completedMs:1200,succeeded:true)=="OLD_OR_INCONSISTENT_OCR" && gate.inFlight,"wrong receipt cannot unlock gate")
        let result=gate.finish(epoch:1,frame:1,observedMs:1000,startedMs:1010,completedMs:1200,succeeded:true)
        check(result=="SUPERSEDED_FRAME_RESEARCH_ONLY" && !gate.inFlight,"raw frames advancing is normal")
        var admission=TP495ObservationAdmission()
        check(admission.admit(result:result,epoch:1,frame:1,observedMs:1000,completedMs:1200,matchingSession:true),"bounded same-source research admission")
        check(!admission.admit(result:result,epoch:1,frame:1,observedMs:1000,completedMs:1200,matchingSession:true),"duplicate parsed frame rejected")
        check(!admission.admit(result:result,epoch:1,frame:2,observedMs:1001,completedMs:2600,matchingSession:true),"old source still rejected")
        check(!admission.admit(result:result,epoch:1,frame:2,observedMs:1001,completedMs:1200,matchingSession:false),"foreign source still rejected")
        check(!admission.admit(result:"HISTORICAL_FRAME_ONLY",epoch:1,frame:2,observedMs:1001,completedMs:1200,matchingSession:true),"historical-only still rejected")
        _=gate.offer(epoch:2,frame:1,observedMs:3000,width:1290,height:2796,background:true)
        check(gate.finish(epoch:1,frame:1,observedMs:1000,startedMs:1010,completedMs:1200,succeeded:true)=="OLD_OR_INCONSISTENT_OCR" && gate.inFlight,"old epoch cannot unlock gate")
        check(gate.finish(epoch:2,frame:1,observedMs:3000,startedMs:3010,completedMs:3100,succeeded:true)=="SAME_EPOCH_RESEARCH_ONLY","new epoch survives old completion")

        let racing=R554CandidateLease(ttlMs:30000)
        _=racing.begin(session:"concurrent",epoch:1)
        let observed=Int64(ProcessInfo.processInfo.systemUptime*1000),bagLock=NSLock()
        var issued=[R554CandidateLease.Ticket]()
        DispatchQueue.concurrentPerform(iterations:32) {index in
            if let ticket=racing.issue(frame:Int64(index+1),observedMs:observed) {bagLock.lock();issued.append(ticket);bagLock.unlock()}
        }
        check(issued.count==1,"exactly one of32 request issuers")
        var winners=0
        DispatchQueue.concurrentPerform(iterations:32) {_ in
            if racing.finish(issued[0],imageSHA:a,admitted:true) {bagLock.lock();winners+=1;bagLock.unlock()}
        }
        check(winners==1,"exactly one of32 completion owners")
        receipts.append(racing.snapshot())

        let stress=R554CandidateLease();_=stress.begin(session:"synthetic-stress",epoch:1,nowMs:1000)
        for index in 1...500 {
            let time=1000+Int64(index)*10
            let ticket=stress.issue(frame:Int64(index),observedMs:time,nowMs:time)!
            let digest=String(format:"%064x",index)
            check(stress.finish(ticket,imageSHA:digest,admitted:true,nowMs:time+1),"bounded synthetic reception sequence")
        }
        let bounded=stress.snapshot(nowMs:6001);receipts.append(bounded)
        let boundedBytes=try json(bounded)
        check(boundedBytes.count<4096,"diagnostic state stays bounded")
        check(bounded["current_state_eligible"] as? Bool==false,"receipt recency never authorizes game state")
        try json(receipts).write(to:reportURL)

        var selected=try JSONSerialization.jsonObject(with:Data(contentsOf:directory.appendingPathComponent("selected_evidence.json"))) as! [String:Any]
        selected["r554_candidate_leases"]=["automatic_full_frame":bounded,"paired_move_candidates":expired]
        var entries=[R548ResearchArchive.Entry(name:"selected_evidence.json",bytes:try json(selected))]
        for name in ["capture_manifest.json","frames/frame_17.png"] {entries.append(.init(name:name,bytes:try Data(contentsOf:directory.appendingPathComponent(name))))}
        entries=try R551EvidenceIntegrity.appendingIndex(entries,captureSessionID:"capture-test",frame:17,epoch:3,appVersion:"0.5.54",appBuild:"554")
        _=try R548ResearchArchive.write(entries,to:directory.appendingPathComponent("r554_lease.zip"))
        print("R554_NATIVE_LEASE_AND_INGRESS_CHECKS_PASS=\(checks)")
    }
}
