# R661｜R659 / R660 historical evidence cross-check

Base: R660 Apple CI verified source commit
`27e58008ecc61a0478a376746357df7ced416efd`.

## Scope

Integrate an additive field `r661_cross_modal_evidence` into the
existing one-button historical-visual JSON. Verify the R659 9
feature-distance samples and R660 3 translation samples refer to the
same four retained frame IDs, monotonic times and 64-digit SHA-256
references. Validate expected region coverage, normalized translation,
and that neither upstream channel has promoted an unknown owner / form
or a Mega event to a certified label.

If the join is internally consistent, report research-only measurements.
Otherwise HOLD with a reason code, preserving no-proof flags. No new
capture, network, permissions, raw image exports, UI buttons or archive
entries. The existing evidence ZIP entry count does not change.

## Limitations

This validates data lineage and joint inspectability, NOT the claim that
translation equals camera motion. A static background cannot be assumed.
Actor ROI geometry remains an unverified hypothesis. Neither Pokémon
species, team ownership, Mega form nor Mega activation is recognized by
this feature; all real-game 79-field certification gates remain unchanged.
Synthetic tests cannot demonstrate gameplay recognition accuracy.

## CI

Pinned R660 source; Linux Swift Foundation harness tests the pure gate.
Apple Xcode 27 run compiles the complete iPhoneOS target and runs existing
native/source-guard regressions. The CI writes only a new research branch.
No IPA distribution, no device test, no formal promotion.
