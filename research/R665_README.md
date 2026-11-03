# R665 — One-tap Evidence Trace Audit

This is an *independent source-integrity audit* on the existing R581 → R646
→ R664 per-field one-tap report. It is NOT an object detector or a battle
value / accuracy certifier. No capture changes, network calls or cloud data.

- Binds canonical 79 field order to the same frame / epoch / capture
  session / raw image hash / analysis image hash.
- Independently recomputes R664 candidate counts and source-signal classes,
  rejects malformed counts, fake certifications and swapped field order.
- Resolves every R646 OCR evidence reference back to the actual same-frame
  OCR inventory; verifies literal, SHA, frame, epoch, session and ROI.
- Splits capture metadata and screen UI candidates from possible battle
  information; emits 79 field-specific diagnostic entries. Counts of signals
  are **not** correctness, coverage of visible items or accuracy.
- Conservative HOLD on mismatched or unverifiable data. Never populates
  battle state or claims own/opponent, Mega, turn or action authorization.
- The original R581/R646/R664 structures are unchanged. A new independent
  key `r665_evidence_trace_audit` is inserted after R664 in the existing
  one-tap output. No new button or app mode.

Quality gates: Swift pure safety harness, patch idempotency refusal,
full Swift parsing / generated project, iPhoneOS compilation on Apple CI,
source branch save after all gates pass. Synthetic tests do not establish
real-game accuracy; iPhone ground truth remains pending.

No Google Drive read; no new paid service. GitHub Actions owner-controlled.

R665 CI regression repair (2026-11-03):
- The original test fixture assigned CAPTURE_METADATA_ONLY to
  screen.ui_state, which the R665 safety gate correctly rejects.
- The fixture now uses actual canonical field types for
  screen.ui_state, capture.frame_id and own.hp.
- A negative test proves a mismatched capture/scene role HOLDs.
- Corrected Linux native Swift suite: 37/37 PASS.
- Apple CI and iPhoneOS build remain unverified until this
  workflow runs on the Apple runner.
