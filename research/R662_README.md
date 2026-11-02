# R662 | Apple Vision hypothesis-region tracking

Parent: R661 first-party evidence join. Add R662-only research fields to
historical_visual_region_changes.json, with no new archive entries or buttons.

Apple VNTrackObjectRequest / VNSequenceRequestHandler track TWO presumed
visual regions for three consecutive frame transitions. Seed regions are
unnamed *hypotheses*, not detections of an actor. The geometry uses explicit
top-left-to-Vision-bottom-left conversion and assumes orientation UP without
claiming it has been calibrated. Track confidence is only a raw diagnostic.

Input is exactly the four R659 retained frames; R661 successful cross-modal
source join is a precondition. Each tracked sample retains both frame IDs,
source SHA-256 and observation timestamps. Any absence, bad geometry,
identity upgrade, mismatch, timeout or Vision failure produces HOLD.

The output cannot be interpreted as Pokémon detection, owner assignment,
Mega evolution, Mega form or camera-vs-actor separation. No strategy
recommendations; live game recognition 0/79 certified unless separately
proven. Calibrate full-frame landscape orientation/ROI from real gameplay,
then independent labeled evaluation before any certification.

References:
- https://developer.apple.com/documentation/vision/vntrackobjectrequest
- https://developer.apple.com/documentation/vision/vnsequencerequesthandler
- https://developer.apple.com/documentation/vision/vndetectedobjectobservation

Apple CI: compile real iPhoneOS app and run native Vision synthetic smoke
with conservative HOLD allowed. It is not a device accuracy benchmark.

## R662-R repair of first CI failure
The original R662 workflow failed before native Vision compilation.
The patch counted every reference to the existing evidence keys.
R661 correctly also reads those keys, so the count was >1.
This repair verifies exactly one assignment per upstream key,
then inserts the same R662 research-only tracking call.
Do not interpret a guard PASS or a valid HOLD from Vision
as measured tracking accuracy or Mega identification.

## R662 typed-observation CI repair (d.yml)
The c.yml Apple CI compiler rejected property access and assignment on a generic VNObservation. This revision requires `as? VNDetectedObjectObservation` before accessing the bounding box, confidence and reseeding the specific tracker. Failed cast yields HOLD_TRACK_NO_VALID_OBSERVATION. This is not device accuracy certification.
