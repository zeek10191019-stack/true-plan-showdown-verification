from pathlib import Path
p=Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
s=p.read_text(encoding='utf-8')
old='''                        let ocrDeadline = ProcessInfo.processInfo.systemUptime + 6.0
                        for sample in retainedTimeline.prefix(8) {'''
new='''                        // R659: independent Vision evidence from retained frames.
                        // The model has no labels for Mega, owner or form.
                        var r659Frames = [R659AutoVisionTimeline.Frame]()
                        let ocrDeadline = ProcessInfo.processInfo.systemUptime + 6.0
                        for sample in retainedTimeline.prefix(8) {'''
assert s.count(old)==1, 'R659_INSERT_FRAME_DECLARATION_ANCHOR'
s=s.replace(old,new)
old='''                            let digest=SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()
                            let cached = ocrCache[digest]'''
new='''                            let digest=SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()
                            r659Frames.append(.init(epoch:sample.epoch,
                                frameID:sample.frame,observedMs:sample.observed,
                                image:sample.image,sha256:digest))
                            let cached = ocrCache[digest]'''
assert s.count(old)==1, 'R659_INSERT_PNG_BINDING_ANCHOR'
s=s.replace(old,new)
old='''                        let visualChangesData=try JSONSerialization.data(
                            withJSONObject:visualChanges,options:[.sortedKeys,.withoutEscapingSlashes])'''
new='''                        // R659: historical four-frame Vision, not a Mega event.
                        // Reuse the existing archive entry, never alter its count.
                        visualChanges["r659_auto_vision_timeline"] =
                            R659AutoVisionTimeline.audit(
                                frames:Array(r659Frames.suffix(4)),
                                budgetMs:1600)
                        let visualChangesData=try JSONSerialization.data(
                            withJSONObject:visualChanges,options:[.sortedKeys,.withoutEscapingSlashes])'''
assert s.count(old)==1,'R659_ONE_TAP_EVIDENCE_ANCHOR'
s=s.replace(old,new)
p.write_text(s,encoding='utf-8')
print('R659_ONE_TAP_REAL_FRAME_VISION_WIRING_PASS')
