#!/usr/bin/env python3
"""Attach R663 source-only residual diagnostics to existing one-tap ZIP."""
from pathlib import Path
p=Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
s=p.read_text(encoding='utf-8')
anchor='''                        let visualChangesData=try JSONSerialization.data(
                            withJSONObject:visualChanges,options:[.sortedKeys,.withoutEscapingSlashes])'''
assert 'r663_relative_motion_history' not in s, 'R663_ALREADY_PRESENT'
assert s.count(anchor)==1, 'R663_ANCHOR_MISMATCH'
for key in ('r659_auto_vision_timeline','r660_scene_registration',
            'r661_cross_modal_evidence','r662_region_track_history'):
    assert s.count('visualChanges["'+key+'"] =')==1, key+'_ASSIGNMENT_NOT_UNIQUE'
assert s.count('R662VisionRegionTracking.audit(')==1, 'R662_INTEGRATION_MISSING'
block='''                        // R663: two signed residual interpretations.
                        // Uncalibrated geometry: never promote to a battle fact.
                        let r663Tracks = visualChanges[
                            "r662_region_track_history"] as? [String:Any] ?? [:]
                        visualChanges["r663_relative_motion_history"] =
                            R663RelativeMotionAudit.audit(
                                feature:r661Feature,
                                joined:r662Join,
                                tracking:r663Tracks)
'''
s=s.replace(anchor,block+anchor)
assert s.count('visualChanges["r663_relative_motion_history"] =')==1
assert s.count('let visualChangesData=try JSONSerialization')==1
p.write_text(s,encoding='utf-8')
print('R663_ONE_TAP_RELATIVE_MOTION_INTEGRATED')
