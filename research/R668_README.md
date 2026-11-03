# R668 | plain HUD OCR geometry (research-only)

Parent: R667 7142d0db7ed04800a88de3e1ce312edf366c4e08.

Actual OCR tokens from one selected frame are associated by normalized
pixel position, including image orientation hypotheses 0/90/180/270:
- Plain move text paired with PP fractions (without needing "技:")
- HUD species name text near own-position and opponent-position HP
- On-screen gender glyph and HH:MM-style timer candidates
- HP numerator/denominator and opponent HP percent

No owner, orientation, actor, species, Mega form or turn proof.
Outputs only for anchored, unambiguous layout hypotheses.
No new screen capture, upload, permissions, app controls or network calls.

Unknown/unmatched/multiple candidates remain HOLD or missing.
Synthetic tests are not actual Pokemon Champions held-out game truth.
The full 79 real-field paths are NOT complete. R668 is incremental.
