# R657 — Mega Vision pair control and image orientation audit

Parent: R656 saved branch (pinned source SHA in the GitHub workflow).

## Changes

1. ImageIO orientation metadata is checked before Apple Vision processes CGImage. Non-up EXIF orientation, invalid orientation data, and unsupported pixel geometry halt before any distance is produced. The raw CGImage crop coordinates are not orientation-corrected, so rejecting the unsupported case prevents misleading left/right regions.
2. If a user imports another PNG or clears a pair while the worker is busy, `busy` is reset. The old worker's epoch can no longer publish an obsolete report.
3. Changing the selected Mega form or manual review switch invalidates previous output and any in-flight work. Manual review is required to start the compare but remains an *unverified* claim.
4. JSON explicitly records scaling, image orientation assumption, and absence of independent frame provenance. No new form-certification path, no owner assertion, no Battle AI recommendation.

## Tests and limitations

- Linux Swift standalone metadata gate validates orientation values, pixel limits, and file limits. CI additionally compiles the whole iPhoneOS app and runs the existing synthetic Apple Vision feature-print harness.
- This is **not** a Champions game-screen accuracy measurement, does not supply labeled Mega images, and does not certify any of the 79 real-screen fields.
- Images are user-selected and kept local; no copyrighted image is saved to the repository.
- Note: orientation metadata absent defaults to CGImage pixel-native orientation, as before. Camera geometry and game HUD orientation remain uncalibrated.
