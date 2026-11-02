# R660 | Historical camera-registration evidence

## Base
R659 successful GitHub CI commit SHA pinned in the workflow. This artifact is an additive research-only patch, not a replacement for the R659 capture or battle state pipeline.

## Work
Use the genuine 4 retained frames already recorded in `r659Frames` by `CaptureCoordinator.prepareUnifiedEvidenceFile`. Run Apple Vision `VNTranslationalImageRegistrationRequest` on each adjacent pair (1→2, 2→3, 3→4) and store frame IDs, SHA-256 hashes, timestamps, translation pixels, and image-normalized translation in the existing `historical_visual_region_changes.json` as `r660_scene_registration`.

## Limits
This estimates translation of the WHOLE SCENE, not a Pokémon model, camera motion alone, or a Mega evolution. UI, animation, unrelated scene changes or viewpoint transformations can affect alignment. NO alignment correction or classification is attempted. Failure / out-of-budget / mixed epochs / duplicates / unsupported geometry => HOLD. No raw images are newly uploaded. No owner, species, form, Mega activation, battle state or strategy certification. No new system permissions, paid APIs or network access.

## Evidence and gates
All decision fields remain false; accuracy is NOT_MEASURED. `R660CameraMotionGate` bounds invalid translations and preserves normalized values without inventing learned thresholds. Device source geometry and actor ROIs remain uncalibrated. 79 real-device screen-reading fields remain unaccredited. Mac-only Vision integration must pass Apple CI; Linux checks are only syntax + pure gate test.

## Next
Collect labeled first-party gameplay footage with one-tap evidence and independently annotate geometry/owner/Mega before measuring real-world precision; then validate the translation model against camera rotation, pan and scene cuts. No automatic Battle AI recommendation before gates.
