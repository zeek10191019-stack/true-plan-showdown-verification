#!/usr/bin/env python3
"""Wire form-label contradiction guard into one-button evidence (fail closed)."""
from pathlib import Path
p = Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
s = p.read_text(encoding='utf-8')
old = '''                        visualChanges["r654_megareference_class_safety"] =
                            R654MegaVisualClassGate.audit(
                                frames:actorAppearanceSamples,
                                references:r650LocalReferences)
'''
new = '''                        // R655: detect contradictory Mega labels in the local
                        // 16x12 reference catalog before class comparisons.
                        // The catalog's labels are still NOT ground truth.
                        let r655Integrity=R655MegaReferenceConflictGate.audit(
                            references:r650LocalReferences)
                        visualChanges["r655_reference_integrity"] = r655Integrity
                        if r655Integrity["status"] as? String ==
                            "REVIEWED_LABEL_CONSISTENCY_ONLY" {
                            visualChanges["r654_megareference_class_safety"] =
                                R654MegaVisualClassGate.audit(
                                    frames:actorAppearanceSamples,
                                    references:r650LocalReferences)
                        } else {
                            visualChanges["r654_megareference_class_safety"] = [
                                "schema":R654MegaVisualClassGate.schema,
                                "status":"HOLD_R655_REFERENCE_INTEGRITY",
                                "owner_certified":false,
                                "mega_event_certified":false,
                                "mega_form_certified":false,
                                "current_state_eligible":false,
                                "battle_advice_authorized":false
                            ] as [String:Any]
                        }
'''
assert s.count(old) == 1, 'R655_SOURCE_ANCHOR_MISMATCH'
assert 'r655_reference_integrity' not in s, 'R655_ALREADY_PRESENT'
s = s.replace(old,new)
p.write_text(s,encoding='utf-8')
print('R655_ONE_TAP_FAIL_CLOSED_WIRING_PASS')
