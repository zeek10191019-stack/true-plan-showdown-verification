# R663 | Historical two-sign residual motion diagnostics

## Parent and scope

R662 Apple CI SUCCESS pinned commit `f7d141b4ee837062657b2842f70fa4a6c71a167a`.
Additive research-only code for the existing one-button diagnostic archive.
No new network, permission, payment, image upload or IPA distribution.

## Purpose

Compare the 2 hypothetical R662 tracked regions (3 successive pairs)
with the R661 scene translation. R659 frame IDs, times and SHA-256
must match every R662 sample and R661 pair. Validate history, geometry,
confidence, disjoint named tracks, source status, and all no-proof flags.
The R662 regions are NOT validated Pokémon bounding boxes.

## Important coordinate limitation

R660 image-registration translation direction is not calibrated against
R662 Vision bottom-left normalized coordinates or app capture orientation.
Report two values per region and pair: `residual_if_scene_subtracted`
and `residual_if_scene_added`. Never select a sign, declare a camera
motion or an actor motion, conclude a mega event, assign ownership,
or authorize live battle advice. Any mismatch becomes HOLD.

## Validation / next action

Linux Swift gate harness exercises positive and adversarial input.
Apple CI must compile the full iPhoneOS app and run retained regressions.
Real game/holdout recognition accuracy and 79 fields remain uncertified.
The following study requires labeled iPhone capture and verified ROI
coordinate mapping, ideally with scenes including both camera panning
and Pokémon movement. No empirical threshold is claimed here.
