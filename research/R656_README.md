# R656 – real Apple Vision feature-print measurement (research only)

Parent: R655 research save commit, pinned exactly by workflow.

## Purpose

Existing R594/R595 relies on a 16×12 luminance grid and unverified actor ROIs. R656 adds an **actual iOS Vision feature-print** pairwise comparison from two locally imported PNGs. The original PNGs never appear in exported JSON and are not uploaded. The user chooses the supposed Mega form from the 81-entry frozen M-C registry and explicitly controls manual review.

Output includes SHA-256 hashes of each image, source dimensions, and uncalibrated Vision distances for whole frame, left/right hypotheses, and background. Distance scores are not transformed into percentages or probabilities. No Mega activation, species, ownership, turn, legal move or battle advice can become certified by this feature.

## Known limitations and immediate follow-up

- Actual two-frame source image quality, geometrical calibration, camera matching and owner identity are not proven.
- This measures image change, not Mega classification. In particular, motion/camera/scene effects can dominate.
- Compare only user-consented private local screenshots; no copyrighted Pokémon sprite files are bundled.
- The supplied labels are claims, not independent ground truth.
- The macOS CI harness uses synthetic PNGs to execute Vision and validate output contracts; it does not measure accuracy on real Champions screenshots.
- R656 should be followed by actual captured frame calibration, image mask/segmentation research, multi-angle reference sampling, and held-out confusion-matrix evaluation for all 81 forms, with X/Y/Z and sex variants covered.

## Current workflow contract

The GitHub workflow runs on push when `.github/workflows/de.yml` is uploaded to `main`. The checkout is pinned to the exact R655 source commit, and the output is committed to a new research branch only after test and iPhoneOS build succeed. No automatic push into main, no external billing API or image downloads. If branch exists it stops instead of overwriting.
