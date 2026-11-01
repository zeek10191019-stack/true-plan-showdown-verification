#!/usr/bin/env python3
"""Fail closed: connect Mega class safety gate to one-tap visual JSON."""
from pathlib import Path

p = Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
s = p.read_text(encoding='utf-8')
old = '''                        visualChanges["r650_megareference_registry_audit"] =
                            R650MegaReferenceBridge.audit(frames:actorAppearanceSamples,
                                references:r650LocalReferences)
'''
new = old + '''                        // R654: same-species BASE/X/Y/Z comparisons; class
                        // duplicates cannot substitute for negative controls.
                        // Output stays historical, not a live Mega assertion.
                        visualChanges["r654_megareference_class_safety"] =
                            R654MegaVisualClassGate.audit(
                                frames:actorAppearanceSamples,
                                references:r650LocalReferences)
'''
assert s.count(old) == 1, 'R654_CAPTURE_ANCHOR_DRIFT'
assert 'r654_megareference_class_safety' not in s
s = s.replace(old, new)
p.write_text(s, encoding='utf-8')
print('R654_VISUAL_CLASS_AUDIT_WIRED')
