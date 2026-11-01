# R658 | Four-frame Mega temporal Vision audit

Parent: exact, passing R657 research branch commit, pinned in workflow.

## Implementation
- New 4-PNG import panel: two manually labeled frames from before,
  two manually labeled frames from after an alleged Mega change.
- Reuses R656's real Apple Vision feature-print computation four times,
  including two within-state controls and two cross-state comparisons.
- Per region, records `cross_min - within_max`, checks whether
  both actor regions changed, and whether background motion dominates.
- Invalidates stale work on any imported file, label, or form change.
- Rejects non-distinct PNGs, mismatched form IDs, broken SHA bindings,
  non-finite distances, malicious schema, missing regions and false
  certification status.
- JSON exports SHA256, distances and HOLD reason, never PNG binaries.
- Candidate flags mean appearance differences only, not Mega evolution.

## Tests and limitations
- Local Linux Swift: R658 pure adjudication synthetic regression suite.
- Apple CI macOS: links against actual Vision through R656 comparison,
  plus full iPhoneOS project and existing regression checks.
- All ROI geometry uncalibrated; comparing images shot in differing
  camera locations/turns may produce false change candidates.
- No actual Pokémon Champions source PNGs in CI. No ownership, species,
  Mega-form identification, turn, or real-time battle advice certified.
- Never uploads images or incurs external AI API usage.

Source API: https://developer.apple.com/documentation/vision/vnfeatureprintobservation
