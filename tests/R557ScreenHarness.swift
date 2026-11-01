import Foundation
import CryptoKit

/// Actual Swift snapshot -> ZIP -> independent PC verification; synthetic only.
@main struct R557ScreenHarness {
    static func main() throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let reportURL=URL(fileURLWithPath:CommandLine.arguments[2])
        var selected=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("selected_evidence.json"))) as! [String:Any]
        let expected=selected["screen_read_state"] as! [String:Any]
        let wrapper=try JSONSerialization.jsonObject(with:Data((selected["research_candidate_envelope"] as! String).utf8)) as! [String:Any]
        let baseline=try JSONSerialization.jsonObject(with:Data((wrapper["payload_json"] as! String).utf8)) as! [String:Any]
        let image=baseline["image_sha256"] as! String
        var count=0,lastEnvelope=""
        func check(_ value:@autoclosure ()->Bool,_ why:String) {
            guard value() else {fatalError("R557_CHECK_FAILED: "+why)};count+=1
        }
        func json(_ value:Any)->Data {try! JSONSerialization.data(withJSONObject:value,options:[.sortedKeys,.withoutEscapingSlashes])}
        func build(declared:Any?=nil,_ transform:((inout [[String:Any]])->Void)?=nil)->[String:Any] {
            var packet=baseline,rows=baseline["readings"] as! [[String:Any]]
            transform?(&rows);packet["readings"]=rows
            if let declared {packet["screen_kind"]=declared}
            let payload=json(packet)
            lastEnvelope=String(data:json(["schema":"trueplan.mobile-envelope.v1",
                "payload_json":String(data:payload,encoding:.utf8)!,
                "payload_sha256":SHA256.hash(data:payload).map {String(format:"%02x",$0)}.joined()]),encoding:.utf8)!
            return R551ScreenReadState.make(envelope:lastEnvelope,captureSessionID:"capture-test",frame:17,epoch:3,
                observedMs:1200,imageSHA:image,width:1000,height:462)
        }
        func screen(_ value:[String:Any])->[String:Any] {value["screen_classification"] as? [String:Any] ?? [:]}
        func layout(_ value:[String:Any])->[String:Any] {value["layout_candidates"] as? [String:Any] ?? [:]}
        func kind(_ value:[String:Any])->String {value["screen_kind"] as? String ?? "MISSING"}
        let first=build()
        check(json(screen(first))==json(expected["screen_classification"]!),"literal independent classification report")
        check(json(layout(first))==json(expected["layout_candidates"]!),"literal two-panel-anchor layout contract")
        check(kind(first)=="move_selection_with_move_details_overlay_candidate","overlay kind retained")
        check((layout(first)["anchors"] as? [[String:Any]])?.count==5,"three UI anchors plus two panel anchors")
        check((layout(first)["associations"] as? [[String:Any]])?.count==12,"two HPs, two names and four move/PP slots")
        check(screen(first)["owner_certified"] as? Bool==false && first["current_state_eligible"] as? Bool==false,"no ownership or live promotion")
        check((screen(first)["evaluated_evidence_refs"] as? [String])?.count==16,"every bound source is indexed")
        for token in ["COMMANDER","XCOMMAND","記録COMMAND","COMMAND-1","COMMAND1000"] {
            check(ResearchScreenClassifier.classify([token,"技の説明"])=="unknown","substring cannot enable command UI: "+token)
        }
        for token in ["COMMAND","COMMAND 32","COMMAND:32","ＣＯＭＭＡＮＤ　３２"] {
            check(ResearchScreenClassifier.classify([token,"技の説明"])=="move_selection_candidate","exact command with optional timer")
        }
        check(ResearchScreenClassifier.classify(["COMMAND","技の説明はありません"])=="unknown","description prose not a button")
        check(ResearchScreenClassifier.classify(["COMMAND","技の説明","威力は80"])=="move_selection_candidate","prose not a panel label")
        for field in ["source_frame_id","source_epoch","source_image_sha256"] {
            let foreign=build {rows in rows[2][field]=field=="source_image_sha256" ? String(repeating:"0",count:64) as Any : 999 as Any}
            check(foreign["source_validation"] as? String=="HOLD","foreign source packet withheld")
            check((foreign["candidates"] as? [[String:Any]])?.isEmpty==true,"no candidates relabeled as packet source")
        }
        let boolean=build {$0[2]["source_frame_id"]=true}
        check(boolean["source_validation"] as? String=="HOLD","boolean is not a frame number")
        let missing=build(declared:"move_selection_candidate") {rows in
            rows[14].removeValue(forKey:"roi_rect");rows[15].removeValue(forKey:"roi_rect")
        }
        check(kind(missing)=="move_selection_candidate","unlocated overlay labels ignored")
        check((screen(missing)["omitted_reading_refs"] as? [String])?.count==2,"missing geometry accounted")
        let conflict=build(declared:"unknown") {rows in
            rows[3]["ocr_alternatives"]=[["rank":0,"raw_text":"技の説明","confidence":0.9],["rank":1,"raw_text":"勝利","confidence":0.8]]
        }
        check(screen(conflict)["status"] as? String=="HOLD_OCR_SCREEN_CONFLICT","alternative screen family vetoes primary")
        check(kind(conflict)=="unknown" && conflict["knowledge_state"] as? String=="CONFLICT","screen conflict reaches root")
        check((layout(conflict)["associations"] as? [[String:Any]])?.isEmpty==true,"screen conflict cannot assign slots")
        check(R551ScreenReadState.displayLines(conflict).contains(where:{$0.contains("保留")}),"screen conflict visible in UI")
        let alternativeOnly=build(declared:"unknown") {rows in
            rows[3]["raw_text"]="不明"
            rows[3]["ocr_alternatives"]=[["rank":0,"raw_text":"不明","confidence":0.9],["rank":1,"raw_text":"技の説明","confidence":0.8]]
        }
        check(screen(alternativeOnly)["status"] as? String=="HOLD_UNKNOWN_PRIMARY" && kind(alternativeOnly)=="unknown","alternative alone cannot promote screen")
        let right=build {rows in
            for index in [14,15] {var rect=rows[index]["roi_rect"] as! [String:Int];rect["x"]=750;rows[index]["roi_rect"]=rect}
        }
        check(layout(right)["status"] as? String=="HOLD_UNSUPPORTED_OVERLAY","right panel cannot reuse left panel layout")
        check(R553LayoutReading.displayLines(layout(right)).contains(where:{$0.contains("保留")}),"unsupported panel shown to user")
        let one=build {rows in rows.removeLast()}
        check(layout(one)["status"] as? String=="HOLD_UNSUPPORTED_OVERLAY","one panel label is insufficient")
        let duplicate=build {rows in rows.append(rows[15])}
        check(layout(duplicate)["status"] as? String=="HOLD_AMBIGUOUS_OVERLAY","duplicate panel label withheld")
        let panelConflict=build {rows in
            rows[14]["ocr_alternatives"]=[["rank":0,"raw_text":"技分類","confidence":0.9],["rank":1,"raw_text":"別の文字","confidence":0.8]]
        }
        check(layout(panelConflict)["status"] as? String=="HOLD_AMBIGUOUS_OVERLAY","panel-label alternatives must agree")
        let falsePacket=build(declared:"battle_end_candidate")
        check(kind(falsePacket)=="unknown" && screen(falsePacket)["status"] as? String=="HOLD_PACKET_KIND_DISAGREEMENT","packet claim cannot override source")
        check(screen(build(declared:true))["status"] as? String=="HOLD_MALFORMED_PACKET_KIND","malformed screen declaration withheld")
        let final=build()
        selected["screen_read_state"]=final;selected["research_candidate_envelope"]=lastEnvelope
        var entries=[R548ResearchArchive.Entry(name:"selected_evidence.json",bytes:json(selected))]
        for name in ["capture_manifest.json","frames/frame_17.png"] {entries.append(.init(name:name,bytes:try Data(contentsOf:root.appendingPathComponent(name))))}
        entries=try R551EvidenceIntegrity.appendingIndex(entries,captureSessionID:"capture-test",frame:17,epoch:3,appVersion:"0.5.57",appBuild:"557")
        _=try R548ResearchArchive.write(entries,to:root.appendingPathComponent("r557_screen.zip"))
        try json(["checks":count,"screen_classification":screen(final),"layout":layout(final),
            "scope":"SYNTHETIC_SCREEN_CONTRACT_ONLY","Vision_real_game_OCR_executed":false,
            "game_accuracy_certified":false,"device_certified":false]).write(to:reportURL)
        print("R557_NATIVE_SCREEN_CHECKS_PASS=\(count); SYNTHETIC_SCREEN_ONLY")
    }
}
