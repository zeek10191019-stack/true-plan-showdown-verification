import Foundation
import CryptoKit

/// Synthetic menu contract and adversarial source/ROI tests. No game accuracy claim.
@main struct R553LayoutHarness {
    static func main() throws {
        let directory=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        var selected=try JSONSerialization.jsonObject(with:Data(contentsOf:directory.appendingPathComponent("selected_evidence.json"))) as! [String:Any]
        let expected=selected["screen_read_state"] as! [String:Any]
        let wrapper=try JSONSerialization.jsonObject(with:Data((selected["research_candidate_envelope"] as! String).utf8)) as! [String:Any]
        let baseline=try JSONSerialization.jsonObject(with:Data((wrapper["payload_json"] as! String).utf8)) as! [String:Any]
        let imageSHA=baseline["image_sha256"] as! String
        var checks=0,lastEnvelope=""
        func check(_ condition: @autoclosure ()->Bool,_ message: String) {
            guard condition() else {fatalError("R553_CHECK_FAILED: "+message)};checks+=1
        }
        func data(_ value: Any) -> Data {try! JSONSerialization.data(withJSONObject:value,options:[.sortedKeys,.withoutEscapingSlashes])}
        func build(width: Int=1000,height: Int=462,_ transform: ((inout [[String:Any]])->Void)?=nil) -> [String:Any] {
            var packet=baseline,rows=packet["readings"] as! [[String:Any]]
            transform?(&rows);packet["readings"]=rows
            let payload=data(packet)
            let envelope:[String:Any]=["schema":"trueplan.mobile-envelope.v1","payload_json":String(data:payload,encoding:.utf8)!,
                "payload_sha256":SHA256.hash(data:payload).map {String(format:"%02x",$0)}.joined()]
            lastEnvelope=String(data:data(envelope),encoding:.utf8)!
            return R551ScreenReadState.make(envelope:lastEnvelope,captureSessionID:"capture-test",frame:17,epoch:3,
                observedMs:1200,imageSHA:imageSHA,width:width,height:height)
        }
        func layout(_ state: [String:Any]) -> [String:Any] {state["layout_candidates"] as? [String:Any] ?? [:]}
        func associations(_ state: [String:Any]) -> [[String:Any]] {layout(state)["associations"] as? [[String:Any]] ?? []}
        func status(_ state: [String:Any]) -> String {layout(state)["status"] as? String ?? "MISSING"}
        let original=build()
        check(data(layout(original))==data(expected["layout_candidates"]!),"hand-authored independent layout contract")
        check(status(original)=="PROVISIONAL_PROFILE_MATCH_ONLY","three anchors")
        check(associations(original).count==12,"two HPs, two labels, four move names and PP slots")
        check(layout(original)["owner_certified"] as? Bool==false,"owner remains uncertified")
        check(layout(original)["calibration_certified"] as? Bool==false,"profile remains uncertified")
        check(original["current_state_eligible"] as? Bool==false,"never live from historical layout")
        check(((original["own"] as! [String:Any])["hp"] as! [String:Any])["value"] is NSNull,"no own current adoption")
        check(associations(original).allSatisfy {$0["side"] as? String=="UNKNOWN_OWNER"},"hints are not certified sides")
        check(R553LayoutReading.displayLines(layout(original)).contains(where:{$0.contains("技枠1")}),"slot candidates reach Japanese display")
        for (field,value) in [("source_epoch",4 as Any),("source_frame_id",18 as Any),
                              ("source_image_sha256",String(repeating:"0",count:64) as Any)] {
            let foreign=build {$0[0][field]=value}
            check(foreign["source_validation"] as? String=="HOLD" && associations(foreign).isEmpty,"foreign source halts layout: "+field)
        }
        check(status(build {$0[0]["confidence"]=0.2})=="HOLD_MISSING_ANCHORS","weak anchor")
        check(status(build {$0.append($0[0])})=="HOLD_AMBIGUOUS_ANCHORS","duplicate anchor")
        let portrait=build(width:462,height:1000)
        check(["HOLD_UNSUPPORTED_GEOMETRY","HOLD_UNSUPPORTED_SCREEN"].contains(status(portrait)) && associations(portrait).isEmpty,"portrait cannot assign a layout")
        check(status(build(width:1200,height:462))=="HOLD_UNSUPPORTED_GEOMETRY","unmodeled letterbox unknown")
        let overlay=build { rows in
            rows.append(["raw_text":"威力","confidence":0.9,"reason":"FULL_FRAME_TEXT_OWNER_AND_TURN_UNBOUND"])
        }
        check(status(overlay)=="PROVISIONAL_PROFILE_MATCH_ONLY" && overlay["screen_kind"] as? String=="move_selection_candidate","unlocated panel text cannot change the bound screen class")
        let ambiguous=build {rows in
            rows[0]["ocr_alternatives"]=[["rank":0,"raw_text":"100/200","confidence":0.9],["rank":1,"raw_text":"101/200","confidence":0.8]]
        }
        check(status(ambiguous)=="HOLD_AMBIGUOUS_ANCHORS","differing numeric alternative blocks association")
        check(ambiguous["knowledge_state"] as? String=="CONFLICT","numeric alternatives propagate conflict")
        let contradictoryName=build {rows in
            rows[4]["ocr_alternatives"]=[["rank":0,"raw_text":"ピカチュウ","confidence":0.9],["rank":1,"raw_text":"ライチュウ","confidence":0.8]]
        }
        check(associations(contradictoryName)[2]["knowledge_state"] as? String=="CONFLICT","name variants not silently selected")
        check(contradictoryName["knowledge_state"] as? String=="CONFLICT","name conflict is visible at root")
        let unknownName=build {rows in
            rows[4]["ocr_alternatives"]=[["rank":0,"raw_text":"ピカチュウ","confidence":0.9],["rank":1,"raw_text":"?","confidence":0.8]]
        }
        check(associations(unknownName)[2]["knowledge_state"] as? String=="UNKNOWN","uninterpretable alternative withholds name")
        func split(_ rows: inout [[String:Any]], slash: Bool=true, offset: Int=15) {
            rows[7]["raw_text"]="4"
            var lower=rows[7],rect=lower["roi_rect"] as! [String:Int]
            lower["raw_text"]=slash ? "/10" : "10";rect["y"]=(rect["y"] ?? 0)+offset
            lower["roi_rect"]=rect;rows.append(lower)
        }
        let splitState=build {split(&$0)}
        check(associations(splitState)[5]["value"] as? [String:Int]==["current":4,"maximum":10],"explicit split fraction")
        check((associations(splitState)[5]["evidence_refs"] as? [String])?.count==2,"both PP fragments retained")
        check(associations(build {split(&$0,slash:false)})[5]["knowledge_state"] as? String=="UNKNOWN","no slash no PP")
        check(associations(build {split(&$0,offset:-10)})[5]["knowledge_state"] as? String=="UNKNOWN","reversed fragments unknown")
        check(associations(build {split(&$0,offset:55)})[5]["knowledge_state"] as? String=="UNKNOWN","cross-slot fragments unknown")
        let both=build {rows in
            rows[1]["ocr_alternatives"]=[["rank":0,"raw_text":"81%","confidence":0.9],["rank":1,"raw_text":"82%","confidence":0.8],["rank":2,"raw_text":"83%","confidence":0.7]]
        }
        let percent=(both["candidates"] as! [[String:Any]]).filter {$0["domain"] as? String=="hp_percent"}
        check(percent.count==3,"all three numeric interpretations retained")
        check(percent[2]["evidence_ref"] as? String=="payload_json.readings[1].ocr_alternatives[2]","ranked source ref")
        let badAlternatives: [[[String:Any]]] = [
            [["rank":true,"raw_text":"100/200","confidence":0.9]],
            [["rank":0,"raw_text":"100/200","confidence":0.9],["rank":1,"raw_text":"101/200","confidence":1.0]],
            [["rank":0,"raw_text":"999/999","confidence":0.9]],
            (0..<4).map {["rank":$0,"raw_text":"100/200","confidence":0.9] as [String:Any]}
        ]
        for bad in badAlternatives {
            let malformed=build {$0[0]["ocr_alternatives"]=bad}
            check(malformed["source_validation"] as? String=="HOLD","malformed alternative envelope")
        }
        var wire=ResearchReading(key:nil,value:.null,raw_text:"81%",confidence:0.9,reason:"FULL_FRAME_TEXT_OWNER_AND_TURN_UNBOUND")
        wire.ocr_alternatives=[.init(rank:0,raw_text:"81%",confidence:0.9),.init(rank:1,raw_text:"82%",confidence:0.8)]
        let encoded=try JSONEncoder().encode(wire)
        let decoded=try JSONDecoder().decode(ResearchReading.self,from:encoded)
        check(decoded==wire,"wire codec retains alternatives")

        let final=build()
        selected["research_candidate_envelope"]=lastEnvelope;selected["screen_read_state"]=final
        var entries=[R548ResearchArchive.Entry(name:"selected_evidence.json",bytes:data(selected))]
        for name in ["capture_manifest.json","frames/frame_17.png"] {
            entries.append(.init(name:name,bytes:try Data(contentsOf:directory.appendingPathComponent(name))))
        }
        entries=try R551EvidenceIntegrity.appendingIndex(entries,captureSessionID:"capture-test",frame:17,epoch:3,appVersion:"0.5.53",appBuild:"553")
        _=try R548ResearchArchive.write(entries,to:directory.appendingPathComponent("r553_layout.zip"))
        try data(final).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
        print("R553_NATIVE_LAYOUT_ALTERNATIVE_CHECKS_PASS=\(checks)")
    }
}
