#!/usr/bin/env python3
"""Add R662 to existing one-tap evidence; never change app decisions."""
from pathlib import Path
p=Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
s=p.read_text('utf-8')
anchor='''                        let visualChangesData=try JSONSerialization.data(
                            withJSONObject:visualChanges,options:[.sortedKeys,.withoutEscapingSlashes])'''
assert 'r662_region_track_history' not in s,'R662_ALREADY_PRESENT'
assert s.count(anchor)==1,'R662_BAD_ANCHOR'
for tag in ('r659_auto_vision_timeline','r660_scene_registration',
            'r661_cross_modal_evidence'):
    assert s.count('visualChanges["'+tag+'"] =')==1,tag+'_ASSIGNMENT_NOT_UNIQUE'
new='''                        // R662: follow unverified regions across the SAME
                        // four retained frames. Never promote identity.
                        let r662Join=visualChanges[
                            "r661_cross_modal_evidence"] as? [String:Any] ?? [:]
                        visualChanges["r662_region_track_history"] =
                            R662VisionRegionTracking.audit(
                                frames:Array(r659Frames.suffix(4)),
                                evidence:r662Join,budgetMs:1600)
'''
s=s.replace(anchor,new+anchor)
assert s.count('r662_region_track_history')==1
p.write_text(s,'utf-8')
print('R662_ONE_TAP_TRACKING_DIAGNOSTIC_INTEGRATED')
