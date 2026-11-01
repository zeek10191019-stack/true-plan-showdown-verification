import Foundation
import CryptoKit

/// Uses the production snapshot/UI/archive path and fails in optimized builds too.
/// Synthetic OCR records test contracts; these are not game recognition samples.
@main struct R571SourceValueHarness {
    static func main() throws {
        let directory=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let reportURL=URL(fileURLWithPath:CommandLine.arguments[2])
        let appVersion=CommandLine.arguments.count>3 ? CommandLine.arguments[3] : "0.5.71"
        let appBuild=CommandLine.arguments.count>4 ? CommandLine.arguments[4] : "571"
        let selected=try JSONSerialization.jsonObject(with:Data(contentsOf:directory.appendingPathComponent("selected_evidence.json"))) as! [String:Any]
        let wrapper=try JSONSerialization.jsonObject(with:Data((selected["research_candidate_envelope"] as! String).utf8)) as! [String:Any]
        let original=try JSONSerialization.jsonObject(with:Data((wrapper["payload_json"] as! String).utf8)) as! [String:Any]
        let imageSHA=original["image_sha256"] as! String
        var checks=0
        func check(_ value:@autoclosure ()->Bool,_ reason:String) {
            guard value() else {fatalError("R571_CHECK_FAILED_"+reason)}
            checks+=1
        }
        func json(_ value:Any)throws->Data {
            try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys,.withoutEscapingSlashes])
        }
        func sha(_ bytes:Data)->String {SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()}
        var snapshots=[[String:Any]]()
        func scenario(_ id:String,_ edit:(inout [[String:Any]])->Void)throws {
            var packet=original,rows=original["readings"] as! [[String:Any]]
            edit(&rows);packet["readings"]=rows
            let payload=try json(packet)
            var envelope=wrapper;envelope["payload_json"]=String(data:payload,encoding:.utf8)!
            envelope["payload_sha256"]=sha(payload)
            let text=String(data:try json(envelope),encoding:.utf8)!
            let state=R551ScreenReadState.make(envelope:text,captureSessionID:"capture-test",frame:17,epoch:3,
                observedMs:1200,imageSHA:imageSHA,width:1000,height:462)
            check(state["source_validation"] as? String=="PASS_FRAME_BINDING_ONLY",id+"_frame")
            check(state["screen_read_engine_version"] as? String=="r571.snapshot.v1",id+"_version")
            let hintReport=state["owner_position_hints"] as! [String:Any]
            check(hintReport["schema"] as? String=="trueplan.screen-read.source-bound-hints.v2",id+"_schema")
            check(hintReport["owner_certified"] as? Bool==false,id+"_owner")
            check(hintReport["identity_certified"] as? Bool==false,id+"_identity")
            check(state["current_state_eligible"] as? Bool==false,id+"_historical")
            let hints=hintReport["hints"] as! [[String:Any]]
            if id=="ambiguous_pp" {
                check(hintReport["status"] as? String=="HOLD_AMBIGUOUS_OCR_VALUES",id+"_hold")
                check(hints.isEmpty,id+"_empty")
                check(!R551ScreenReadState.displayLines(state).contains(where:{$0.contains("自分側位置のHP候補：")}),id+"_UI_withheld")
            } else {
                check(hintReport["status"] as? String=="PROVISIONAL_SOURCE_BOUND_HINTS_NO_OWNER_CERTIFICATION",id+"_literal_gate")
                check(hints.count==12,id+"_twelve_fields")
                check(hintReport["literal_values_checked"] as? Bool==true,id+"_checked")
                check(hints[0]["literal_value"] as? [String:Int]==["current":100,"maximum":200],id+"_hp")
                check((hints[1]["literal_value"] as? NSNumber)?.doubleValue==81,id+"_opponent_percent")
                check(hints[2]["literal_value"] as? String=="ピカチュウ",id+"_name")
                check(hints[5]["literal_value"] as? [String:Int]==["current":4,"maximum":10],id+"_pp")
                check(R551ScreenReadState.displayLines(state).contains(where:{$0.contains("自分側位置のHP候補：100/200")}),id+"_UI_connected")
            }
            check(((state["own"] as! [String:Any])["hp"] as! [String:Any])["value"] is NSNull,id+"_no_own_promotion")
            check(((state["opponent"] as! [String:Any])["active_name"] as! [String:Any])["value"] is NSNull,id+"_no_identity_promotion")
            var output=selected
            output["research_candidate_envelope"]=text;output["screen_read_state"]=state
            var entries=[R548ResearchArchive.Entry(name:"selected_evidence.json",bytes:try json(output))]
            for name in ["capture_manifest.json","frames/frame_17.png"] {
                entries.append(.init(name:name,bytes:try Data(contentsOf:directory.appendingPathComponent(name))))
            }
            entries=try R551EvidenceIntegrity.appendingIndex(entries,captureSessionID:"capture-test",frame:17,epoch:3,
                appVersion:appVersion,appBuild:appBuild)
            let path=directory.appendingPathComponent("r571_"+id+".zip")
            _=try R548ResearchArchive.write(entries,to:path)
            let archive=try Data(contentsOf:path)
            snapshots.append(["id":id,"state":state,"packet":packet,
                "archive_base64":archive.base64EncodedString(),"archive_sha256":sha(archive)])
        }
        try scenario("baseline"){_ in}
        try scenario("split_alternatives"){rows in
            rows[7]["raw_text"]="4"
            rows[7]["ocr_alternatives"]=[["rank":0,"raw_text":"4","confidence":0.9],["rank":1,"raw_text":"04","confidence":0.8]]
            var lower=rows[7],rect=lower["roi_rect"] as! [String:Int]
            lower["raw_text"]="/10";rect["y"]=(rect["y"] ?? 0)+15;lower["roi_rect"]=rect
            lower["ocr_alternatives"]=[["rank":0,"raw_text":"/10","confidence":0.9],["rank":1,"raw_text":"/10","confidence":0.8]]
            rows.append(lower)
        }
        try scenario("ambiguous_pp"){rows in
            rows[7]["ocr_alternatives"]=[["rank":0,"raw_text":"4/10","confidence":0.9],["rank":1,"raw_text":"5/10","confidence":0.8]]
        }
        func site(_ reading:Int,_ text:String,_ rank:Int=0,_ y:Int64=10,_ x:Int64=300)->R553LayoutReading.Site {
            .init(reading:reading,rank:rank,text:text,confidence:0.9,
                reference:"payload_json.readings[\(reading)]"+(rank==0 ? "" : ".ocr_alternatives[\(rank)]"),
                roi:["x":x,"y":y,"width":20,"height":10])
        }
        let cases:[(String,[R553LayoutReading.Site],[String:Int]?)]=[
            ("whole",[site(0,"PP14/16")],["current":14,"maximum":16]),
            ("zero",[site(0,"0/16")],["current":0,"maximum":16]),
            ("split",[site(0,"14"),site(1,"/16",0,25)],["current":14,"maximum":16]),
            ("split_alts",[site(0,"14"),site(0,"１４",1),site(1,"/16",0,25),site(1,"／１６",1,25)],["current":14,"maximum":16]),
            ("numerator_conflict",[site(0,"14"),site(0,"13",1),site(1,"/16",0,25)],nil),
            ("denominator_conflict",[site(0,"14"),site(1,"/16",0,25),site(1,"/18",1,25)],nil),
            ("missing_primary",[site(0,"14",1),site(1,"/16",0,25)],nil),
            ("duplicate_rank",[site(0,"14"),site(0,"14"),site(1,"/16",0,25)],nil),
            ("changed_roi",[site(0,"14"),site(0,"14",1,10,301),site(1,"/16",0,25)],nil),
            ("overlap",[site(0,"14"),site(1,"/16",0,15)],nil),
            ("distant",[site(0,"14"),site(1,"/16",0,200)],nil),
            ("reversed",[site(0,"14",0,25),site(1,"/16")],nil),
            ("full_two_sources",[site(0,"14/16"),site(1,"14/16")],nil),
            ("same_observation",[site(0,"14"),site(0,"/16",1,25)],nil),
            ("over_max",[site(0,"17/16")],nil),
            ("hp_prefix",[site(0,"HP14/16")],nil)]
        var results=[[String:Any]]()
        for (id,sites,expected) in cases {
            let actual=R567EvidenceGroupFence.ppValue(sites:sites)
            check(actual==expected,id+"_literal")
            results.append(["id":id,"value":actual.map{$0 as Any} ?? NSNull()])
        }
        // NSNumber(0) must not masquerade as the false Boolean certification flag.
        let p=site(0,"100/200")
        let hint:[String:Any]=["role_hint":"own_hp","slot":NSNull(),"verification":"POSITION_ONLY_UNVERIFIED",
            "knowledge_state":"INFERRED","current_state_eligible":false,"evidence_refs":[p.reference],"rois":[p.roi]]
        var forged:[String:Any]=["status":"PROVISIONAL_POSITION_HINTS_NO_OWNER_CERTIFICATION",
            "capture_session_id":"capture-test","frame_id":Int64(17),"epoch":Int64(3),"image_sha256":imageSHA,
            "owner_certified":0,"current_state_eligible":false,"hints":[hint]]
        var rejected=R565SourceEvidenceFence.report(base:forged,sites:[p],session:"capture-test",frame:17,epoch:3,imageSHA:imageSHA)
        check(rejected["status"] as? String=="HOLD_R565_WRONG_FRAME_OR_BASE","numeric_false_rejected")
        check((rejected["hints"] as! [[String:Any]]).isEmpty,"numeric_false_clears")
        forged["owner_certified"]=false
        var badHint=hint;badHint["current_state_eligible"]=0;forged["hints"]=[badHint]
        rejected=R565SourceEvidenceFence.report(base:forged,sites:[p],session:"capture-test",frame:17,epoch:3,imageSHA:imageSHA)
        check(rejected["status"] as? String=="HOLD_R565_HINT_STRUCTURE_INVALID","numeric_hint_false_rejected")
        try json(["revision":"R"+appBuild,"checks":checks,"scope":"SYNTHETIC_SOURCE_VALUE_UI_AND_SWIFT_ZIP_ONLY",
            "pp_cases":results,"snapshots":snapshots,"game_accuracy_certified":false,
            "owner_certified":false,"identity_certified":false,"device_certified":false]).write(to:reportURL)
        print("R571_SOURCE_VALUE_UI_ARCHIVE_CHECKS_PASS=\(checks); SWIFT_ARCHIVES=\(snapshots.count); GAME_ACCURACY_UNVERIFIED")
    }
}
