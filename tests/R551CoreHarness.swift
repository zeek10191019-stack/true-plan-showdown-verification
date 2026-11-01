import Foundation
import CryptoKit

@main struct R551CoreHarness {
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError("R551_CHECK_FAILED: " + message) }
            checks += 1
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let selectedURL = root.appendingPathComponent("selected_evidence.json")
        var selected = try JSONSerialization.jsonObject(with: Data(contentsOf:selectedURL)) as! [String:Any]
        let envelope = selected["research_candidate_envelope"] as! String
        let imageSHA = selected["png_sha256"] as! String
        let state = R551ScreenReadState.make(envelope:envelope,captureSessionID:"capture-test",frame:17,
            epoch:3,observedMs:1200,imageSHA:imageSHA,width:2,height:2)
        check(state["source_validation"] as? String == "PASS_FRAME_BINDING_ONLY", "same frame provenance")
        check(state["current_state_eligible"] as? Bool == false, "historical is never current")
        check(state["battle_id"] is NSNull, "capture is not game battle identity")
        check(state["turn"] is NSNull, "turn remains unknown")
        let rows = state["candidates"] as? [[String:Any]] ?? []
        check(rows.count == 1 && rows.first?["domain"] as? String == "hp_percent", "percent candidate")
        check(rows.first?["side"] as? String == "UNKNOWN_OWNER", "no side from a number")
        let own = state["own"] as! [String:Any]
        check((own["hp"] as? [String:Any])?["value"] is NSNull, "no owner leakage")
        let wrongFrame = R551ScreenReadState.make(envelope:envelope,captureSessionID:"capture-test",frame:18,
            epoch:3,observedMs:1200,imageSHA:imageSHA,width:2,height:2)
        check(wrongFrame["source_validation"] as? String == "HOLD", "reject other frame")
        let wrongSession = R551ScreenReadState.make(envelope:envelope,captureSessionID:"other",frame:17,
            epoch:3,observedMs:1200,imageSHA:imageSHA,width:2,height:2)
        check(wrongSession["source_validation"] as? String == "HOLD", "reject other capture")
        let corrupt = R551ScreenReadState.make(envelope:"{}",captureSessionID:"capture-test",frame:17,
            epoch:3,observedMs:1200,imageSHA:imageSHA,width:2,height:2)
        check(corrupt["source_validation"] as? String == "HOLD", "invalid envelope")
        for raw in ["148/197","81%","PP 5/10","どく","トリックルームあと3ターン","こうげき +1"] {
            check(!R551ScreenReadState.domains(raw).isEmpty,"literal candidate " + raw)
        }
        for raw in ["198/197","101%","-1/3","10/0","つばめがえし","こうげき +7"] {
            check(R551ScreenReadState.domains(raw).isEmpty,"reject ambiguous/invalid " + raw)
        }
        check(ResearchScreenClassifier.classify(["COMMAND","技の説明"]) == "move_selection_candidate", "legacy move UI")
        check(ResearchScreenClassifier.classify(["COMMAND","技の説明","威力"]) == "move_selection_with_move_details_overlay_candidate", "detail overlay")
        check(ResearchScreenClassifier.classify(["COMMAND","たたかう"]) == "normal_command_candidate", "normal commands")
        check(ResearchScreenClassifier.classify(["選出","決定"]) == "party_selection_candidate", "selection UI")
        check(ResearchScreenClassifier.classify(["相手のパーティ","選出時間"]) == "party_preview_candidate", "preview UI")
        check(ResearchScreenClassifier.classify(["交代先を選んでください","もどる"]) == "switch_selection_candidate", "switch UI")
        check(ResearchScreenClassifier.classify(["YOU WIN"]) == "battle_end_candidate", "end UI")
        check(ResearchScreenClassifier.classify(["COMMAND","技の説明","敗北"]) == "unknown", "conflicting UI")
        check(ResearchScreenClassifier.classify(["メガシンカ"]) == "animation_or_battle_message_candidate", "text is not activation")
        check(ResearchScreenClassifier.classify(["あめ"]) == "unknown", "weather alone not a screen")
        let work = R551EvidenceWork()
        check(!work.isCancelled,"initial cancellation state")
        work.cancel();check(work.isCancelled,"cooperative cancellation")
        do { try work.check();fatalError("cancelled work accepted") } catch { checks += 1 }

        selected["screen_read_state"] = state
        let selectedBytes = try JSONSerialization.data(withJSONObject:selected,options:[.sortedKeys,.withoutEscapingSlashes])
        let names = ["capture_manifest.json","frames/frame_17.png"]
        var entries = [R548ResearchArchive.Entry(name:"selected_evidence.json",bytes:selectedBytes)]
        entries += try names.map { .init(name:$0,bytes:try Data(contentsOf:root.appendingPathComponent($0))) }
        entries = try R551EvidenceIntegrity.appendingIndex(entries,captureSessionID:"capture-test",frame:17,epoch:3,
            appVersion:"0.5.51",appBuild:"551")
        let destination = root.appendingPathComponent("swift_written.zip")
        _ = try R548ResearchArchive.write(entries,to:destination)
        check(FileManager.default.fileExists(atPath:destination.path),"Swift writer produced archive")
        do { _ = try R548ResearchArchive.write(entries,to:destination);fatalError("existing overwritten") }
        catch R548ResearchArchive.Error.invalidArchive { checks += 1 }
        let racing = root.appendingPathComponent("exclusive_race.zip")
        let lock = NSLock()
        var won = 0, rejected = 0
        DispatchQueue.concurrentPerform(iterations:32) { _ in
            do {
                _ = try R548ResearchArchive.write(entries,to:racing)
                lock.lock();won += 1;lock.unlock()
            } catch { lock.lock();rejected += 1;lock.unlock() }
        }
        check(won == 1 && rejected == 31,"exactly one exclusive writer")
        let originals = Dictionary(uniqueKeysWithValues:entries.map {($0.name,$0.bytes)})
        let receipt = try R549ZipReadback.verify(archiveURL:racing,expectedFiles:originals)
        check(receipt.entryCount == entries.count,"racing winner remains readable")
        print("R551_NATIVE_CORE_CHECKS_PASS=\(checks)")
    }
}
