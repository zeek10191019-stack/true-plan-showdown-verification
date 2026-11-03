# R669: Source-bound HUD-adjacent status and boost text

Parent: R668 `5c87444b8153e06824f72844d683c0f4510b0e9c`.

Extends direct field reading beyond generic OCR keyword mentions.
Given the SAME selected frame and its R668 HP anchors, OCR tokens
near HUD anchors can produce field-specific, typed candidate records:

- Own-position and opponent-position major status (BRN/PAR/SLP/etc.)
- Own-position and opponent-position volatile status text
- Own-position and opponent-position signed boost stage text

Reject conflicting candidate statuses, invalid rectangles, stale
frame or image SHA, unknown source, and ambiguous orientation.
Fix R668 false species-name candidates for status/field words.

The positions are not independent actor identity or ownership
proof; no Mega identity, current state, turn or battle advice can
be certified. Unreadable status icons remain UNKNOWN. Synthetic
Swift tests are not validation on Pokémon Champions game images.

Full 79 field routes are NOT complete. This is incremental only.
