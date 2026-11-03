import Foundation
enum R674ActorHUDLink {
static let schema = "trueplan.r674.actor-hud-position-link.v1"
private static func hash(_ s: String) -> Bool {
s.utf8.count == 64 && s.utf8.allSatisfy {
(48...57).contains($0) || (97...102).contains($0)
}
}
private static func hold(_ why: String) -> [String: Any] {
["schema": schema, "status": why, "pairs": [[String: Any]](),
"pair_count": 0, "owner_certified": false,
"mega_form_certified": false, "hp_percent_certified": false,
"current_state_eligible": false, "battle_advice_authorized": false]
}
static func link(sprite: [String: Any], hp: [String: Any]) -> [String: Any] {
guard sprite["schema"] as? String == R673OrientedSpriteReader.schema,
hp["schema"] as? String == R672PixelHPFillReader.schema,
let frame = sprite["frame_id"] as? Int64, frame > 0,
let epoch = sprite["epoch"] as? Int64, epoch > 0,
let sha = sprite["raw_image_sha256"] as? String, hash(sha),
hp["frame_id"] as? Int64 == frame,
hp["epoch"] as? Int64 == epoch,
hp["raw_image_sha256"] as? String == sha,
sprite["owner_certified"] as? Bool == false,
sprite["mega_form_certified"] as? Bool == false,
hp["owner_certified"] as? Bool == false,
hp["hp_percent_certified"] as? Bool == false,
sprite["current_state_eligible"] as? Bool == false,
hp["current_state_eligible"] as? Bool == false,
let sprites = sprite["candidates"] as? [[String: Any]],
let bars = hp["tracks"] as? [[String: Any]],
sprites.count <= 2, bars.count <= 16,
sprite["candidate_count"] as? Int == sprites.count,
hp["track_count"] as? Int == bars.count else {
return hold("HOLD_SOURCE_OR_SCHEMA_CONFLICT")
}
guard sprite["status"] as? String ==
"VISUAL_FORM_CANDIDATES_NOT_CERTIFIED",
hp["status"] as? String ==
"PARTIAL_BAR_FILL_TRACKS_UNVERIFIED" else {
return hold("HOLD_NOT_BOTH_VISIBLE")
}
var proposals = [[String: Any]]()
var keys = Set<String>()
for actor in sprites {
guard let region = actor["region"] as? String,
let angle = actor["rotation_hypothesis_degrees"] as? Int,
[0,90,180,270].contains(angle),
let flip = actor["raster_y_flip_hypothesis"] as? Bool,
let species = actor["species_token_claim"] as? String,
let form = actor["form_token_claim"] as? String,
!species.isEmpty, !form.isEmpty,
actor["source_image_sha256"] as? String == sha,
actor["owner"] as? String == "UNKNOWN",
actor["mega_confirmed"] as? Bool == false,
actor["mega_form_certified"] as? Bool == false else {
return hold("HOLD_INVALID_SPRITE_CANDIDATE")
}
let expectedBar: String
switch region {
case "LEFT_ACTOR_POSITION_ONLY":
expectedBar = "LOWER_LEFT_HUD_POSITION_ONLY"
case "RIGHT_ACTOR_POSITION_ONLY":
expectedBar = "UPPER_RIGHT_HUD_POSITION_ONLY"
default:
return hold("HOLD_UNKNOWN_ACTOR_REGION")
}
let rowOrigin = flip ? "BOTTOM_FIRST" : "TOP_FIRST"
for bar in bars where
bar["position_hint"] as? String == expectedBar &&
bar["rotation_hypothesis_degrees"] as? Int == angle &&
bar["raw_row_origin_hypothesis"] as? String == rowOrigin {
guard let fraction = bar["fill_percentage_candidate_not_hp"]
as? Double, fraction.isFinite,
fraction >= 8, fraction <= 92,
bar["owner"] as? String == "UNKNOWN",
bar["hp_percent_certified"] as? Bool == false else {
return hold("HOLD_INVALID_HP_BAR_CANDIDATE")
}
let key = "\(region):\(angle):\(rowOrigin)"
if !keys.insert(key).inserted {
return hold("HOLD_DUPLICATE_SIDE_OR_ORIENTATION")
}
proposals.append([
"actor_region": region, "hud_region": expectedBar,
"image_rotation_degrees": angle,
"raster_row_origin": rowOrigin,
"species_candidate": species, "form_candidate": form,
"fill_percentage_candidate_not_hp": fraction,
"position_correspondence_only": true,
"owner": "UNKNOWN", "mega_confirmed": false,
"hp_percent_certified": false,
"current_state_eligible": false
])
}
}
guard !proposals.isEmpty else {
return hold("HOLD_NO_COMPATIBLE_SAME_FRAME_GEOMETRY")
}
guard Set(proposals.compactMap {
$0["image_rotation_degrees"] as? Int
}).count == 1 else {
return hold("HOLD_MULTIPLE_ROTATION_HYPOTHESES")
}
return ["schema": schema,
"status": "SAME_FRAME_POSITION_PAIRS_NOT_CERTIFIED",
"frame_id": frame, "epoch": epoch,
"raw_image_sha256": sha, "pair_count": proposals.count,
"pairs": proposals, "owner_certified": false,
"mega_form_certified": false, "hp_percent_certified": false,
"current_state_eligible": false, "battle_advice_authorized": false,
"accuracy": "NOT_MEASURED"]
}
}
