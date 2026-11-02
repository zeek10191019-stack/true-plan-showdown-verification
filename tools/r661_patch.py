#!/usr/bin/env python3
"""R661 additive evidence join; no inference or old-source replacement."""
from pathlib import Path
p = Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
s = p.read_text(encoding='utf-8')
needle = '''                        let visualChangesData=try JSONSerialization.data(
                            withJSONObject:visualChanges,options:[.sortedKeys,.withoutEscapingSlashes])'''
assert s.count(needle)==1, 'R661_UNIQUE_INSERTION_ANCHOR_REQUIRED'
assert s.count('r660_scene_registration')==1, 'R660_BASE_INVALID'
assert s.count('r659_auto_vision_timeline')==1, 'R659_BASE_INVALID'
assert 'r661_cross_modal_evidence' not in s, 'R661_ALREADY_PRESENT'
insert = '''                        // R661: join ONLY evidence with matching IDs,
                        // timestamps and source hashes; never grant advice.
                        let r661Feature = visualChanges[
                            "r659_auto_vision_timeline"] as? [String:Any] ?? [:]
                        let r661Motion = visualChanges[
                            "r660_scene_registration"] as? [String:Any] ?? [:]
                        visualChanges["r661_cross_modal_evidence"] =
                            R661CrossModalEvidenceGate.audit(
                                feature:r661Feature,
                                registration:r661Motion)
'''
s = s.replace(needle,insert+needle)
assert s.count('r661_cross_modal_evidence')==1
p.write_text(s,encoding='utf-8')
print('R661_ONE_TAP_CROSS_MODAL_EVIDENCE_JOIN_INTEGRATED')
