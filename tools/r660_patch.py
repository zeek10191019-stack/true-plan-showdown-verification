#!/usr/bin/env python3
"""Integrate non-certifying Vision translation into R659 one-button ZIP."""
from pathlib import Path
p=Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
s=p.read_text('utf-8')
old='''                        let visualChangesData=try JSONSerialization.data(
                            withJSONObject:visualChanges,options:[.sortedKeys,.withoutEscapingSlashes])'''
new='''                        // R660: camera/scene translation only, on the exact
                        // four frames already bound and used by R659.
                        // No owner, Pokémon identity, or Mega claim.
                        visualChanges["r660_scene_registration"] =
                            R660CameraMotionRegistration.audit(
                                frames:Array(r659Frames.suffix(4)),
                                budgetMs:1200)
                        let visualChangesData=try JSONSerialization.data(
                            withJSONObject:visualChanges,options:[.sortedKeys,.withoutEscapingSlashes])'''
assert s.count('visualChanges["r659_auto_vision_timeline"]')==1, 'R659_MISSING'
assert s.count('r660_scene_registration')==0,'R660_ALREADY_PRESENT'
assert s.count(old)==1,'R660_INSERTION_ANCHOR_MISMATCH'
s=s.replace(old,new)
p.write_text(s,'utf-8')
assert s.count('visualChanges["r659_auto_vision_timeline"]')==1
assert s.count('visualChanges["r660_scene_registration"]')==1
print('R660_ONE_TAP_VISION_REGISTRATION_INTEGRATED')
