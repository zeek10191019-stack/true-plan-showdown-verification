import Foundation
import CryptoKit

/// Production snapshot/projection code, synthetic packets and real Swift ZIPs.
/// No Vision request or real game/device certification is performed here.
@main struct R561SourceGuardHarness {
    static func main() throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let output=URL(fileURLWithPath:CommandLine.arguments[2])
        let appVersion=CommandLine.arguments.count>3 ? CommandLine.arguments[3]:"0.5.61"
        let appBuild=CommandLine.arguments.count>4 ? CommandLine.arguments[4]:"561"
        let original=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("selected_evidence.json"))) as! [String:Any]
        let wrapper=try JSONSerialization.jsonObject(with:Data((original["research_candidate_envelope"] as! String).utf8)) as! [String:Any]
        let baseline=try JSONSerialization.jsonObject(with:Data((wrapper["payload_json"] as! String).utf8)) as! [String:Any]
        let image=baseline["image_sha256"] as! String
        var checks=0,cases=[[String:Any]](),archives=[[String:Any]](),projections=[[String:Any]]()
        func check(_ value:@autoclosure ()->Bool,_ why:String) {
            guard value() else {fatalError("R561_SOURCE_CHECK_FAILED: "+why)};checks+=1
        }
        func json(_ value:Any)->Data {try! JSONSerialization.data(withJSONObject:value,options:[.sortedKeys,.withoutEscapingSlashes])}
        func hash(_ data:Data)->String {SHA256.hash(data:data).map {String(format:"%02x",$0)}.joined()}
        let fields=["source_frame_id","source_epoch","source_image_sha256"]
        func packet(explicit:Bool=true,roi:Bool=false)->[String:Any] {
            var packet=baseline,rows=baseline["readings"] as! [[String:Any]]
            for index in rows.indices {
                for key in fields {rows[index].removeValue(forKey:key)}
                rows[index].removeValue(forKey:"roi_rect")
                if explicit {
                    rows[index]["source_frame_id"]=17;rows[index]["source_epoch"]=3
                    rows[index]["source_image_sha256"]=image
                    if roi {rows[index]["roi_rect"]=["x":0,"y":0,"width":2,"height":2]}
                }
            }
            packet["readings"]=rows;return packet
        }
        func exercise(_ id:String,_ packet:[String:Any],valid:Bool,
                      wrapperSchema:Any="trueplan.mobile-envelope.v1",floatFrame:Bool=false) throws {
            var payload=String(data:json(packet),encoding:.utf8)!
            if floatFrame {payload=payload.replacingOccurrences(of:"\"source_frame_id\":17",with:"\"source_frame_id\":17.0")}
            let envelope=String(data:json(["schema":wrapperSchema,"payload_json":payload,
                "payload_sha256":hash(Data(payload.utf8))]),encoding:.utf8)!
            let state=R551ScreenReadState.make(envelope:envelope,captureSessionID:"capture-test",frame:17,epoch:3,
                observedMs:1200,imageSHA:image,width:2,height:2)
            check(state["source_validation"] as? String==(valid ? "PASS_FRAME_BINDING_ONLY":"HOLD"),id+" source decision")
            check(state["current_state_eligible"] as? Bool==false && state["battle_advice_authorized"] as? Bool==false,id+" no current/advice")
            if valid {
                check((state["candidates"] as? [[String:Any]])?.count==1,id+" provisional percent retained")
                var selected=original;selected["research_candidate_envelope"]=envelope;selected["screen_read_state"]=state
                var entries=[R548ResearchArchive.Entry(name:"selected_evidence.json",bytes:json(selected))]
                for name in ["capture_manifest.json","frames/frame_17.png"] {
                    entries.append(.init(name:name,bytes:try Data(contentsOf:root.appendingPathComponent(name))))
                }
                entries=try R551EvidenceIntegrity.appendingIndex(entries,captureSessionID:"capture-test",frame:17,epoch:3,appVersion:appVersion,appBuild:appBuild)
                let destination=root.appendingPathComponent("r561_"+id+".zip")
                _=try R548ResearchArchive.write(entries,to:destination)
                let bytes=try Data(contentsOf:destination)
                archives.append(["id":id,"archive_sha256":hash(bytes),"archive_base64":bytes.base64EncodedString()])
            } else {
                check((state["candidates"] as? [[String:Any]])?.isEmpty==true,id+" all candidates withheld")
                check(state["screen_classification"]==nil && state["layout_candidates"]==nil,id+" no partial publication")
                check(R551ScreenReadState.displayLines(state).contains(where:{$0.contains("採用できません")}),id+" UI rejection")
            }
            cases.append(["id":id,"expected_valid":valid,"envelope":envelope,"state":state])
        }
        try exercise("legacy_packet_only",packet(explicit:false),valid:true)
        try exercise("explicit_no_roi",packet(),valid:true)
        try exercise("explicit_roi",packet(roi:true),valid:true)
        for (field,value) in [("source_frame_id",18 as Any),("source_epoch",4 as Any),
                              ("source_image_sha256",String(repeating:"0",count:64) as Any),
                              ("source_frame_id",true as Any),("source_frame_id",NSNull() as Any),
                              ("source_epoch","3" as Any),("source_epoch",3.5 as Any)] {
            var valuePacket=packet(),rows=valuePacket["readings"] as! [[String:Any]]
            rows[0][field]=value;valuePacket["readings"]=rows
            try exercise("invalid_\(cases.count)_"+field,valuePacket,valid:false)
        }
        for mask in 1..<7 {
            var valuePacket=packet(),rows=valuePacket["readings"] as! [[String:Any]]
            for (index,key) in fields.enumerated() where mask & (1<<index)==0 {rows[0].removeValue(forKey:key)}
            valuePacket["readings"]=rows
            try exercise("partial_\(mask)",valuePacket,valid:false)
        }
        try exercise("float_integer_frame",packet(),valid:false,floatFrame:true)
        var late=packet(),rows=late["readings"] as! [[String:Any]]
        var foreign=rows[0];foreign["source_frame_id"]=18;rows.append(foreign);late["readings"]=rows
        try exercise("late_foreign_discards_earlier_candidates",late,valid:false)
        for (index,value) in [NSNull() as Any,true as Any,"foreign.v1" as Any].enumerated() {
            try exercise("wrapper_schema_\(index)",packet(),valid:false,wrapperSchema:value)
            var wrong=packet();wrong["schema"]=value
            try exercise("packet_schema_\(index)",wrong,valid:false)
            let payload=json(packet())
            let envelope=String(data:json(["schema":value,"payload_json":String(data:payload,encoding:.utf8)!,"payload_sha256":hash(payload)]),encoding:.utf8)!
            let projection=R556AnalysisProjection.report(plan:.init(rawWidth:2,rawHeight:2,crop:.init(x:0,y:0,width:2,height:2),quarterTurnsCCW:0),
                envelope:envelope,session:"capture-test",frame:17,epoch:3,observedMs:1200,rawSHA:image,analysisSHA:image)
            check(projection["status"] as? String=="HOLD","projection rejects unknown wrapper schema")
            projections.append(projection)
        }
        try json(["scope":"SYNTHETIC_SOURCE_GUARD_ONLY","checks":checks,"cases":cases,"valid_archives":archives,"rejected_projections":projections,
            "Vision_executed":false,"game_accuracy_certified":false,"device_certified":false,"native_CI_certified":false]).write(to:output)
        print("R561_NATIVE_SOURCE_GUARD_CHECKS_PASS=\(checks); SYNTHETIC_PACKETS_ONLY")
    }
}
