# R664 — One-tap actual-signal audit (research only)

## Objective
Answer the user's question “how much can the shared battle screen actually be read?” with factual observable counts instead of attributing accuracy to CI or the existence of a 79-field schema. A new `r664_readout_scorecard` object is appended to the pre-existing live one-tap unified evidence `bundle` after R646, before R647, without changing any battle recommendation logic.

## Evidence contract
- Takes the **existing** R581 canonical 79 field inventory and R646 source-bound 79 field attempts from the **same source**.
- Requires image SHA, analysis SHA, source kind and 79-field order to match. Rejects certificate flags, mismatches, corrupt/incomplete data and alleged owners.
- Reports `fields_with_source_signal`, `fields_without_source_signal`, counts by stage and which fields have candidates. `source_signal_fraction_not_accuracy` is **not** a reading-accuracy estimate: the 79 includes capture metadata, and many battle effects are not simultaneously visible.
- `game_fields_certified=0`, `real_game_accuracy=NOT_MEASURED` and all battle-action/owner/form gates remain false.
- Uses no web access, permissions, paid services, invented labels, reference artwork or private data. No new ZIP entry or manual copy step.

## Verification
The Linux Swift test uses a local 79-name R581 stub only as a fixture. Actual Apple CI compiles against the repository's real R581. Do not ship the stub. Real-game precision requires an independently labeled gameplay set and a confusion matrix stratified by visibility, menu phase, owner, orientation, frame age, and Mega events.
