import Foundation
@main struct R674Smoke {
static func main() {
let w=800,h=400,sha=String(repeating:"a",count:64)
var pixels=[UInt8](repeating:0,count:w*h*4)
for y in 0..<h {for x in 0..<w {
let k=(y*w+x)*4
let v=UInt8(45+(x*17+y*31+(x/13)*37+(y/19)*29)%175)
pixels[k]=v;pixels[k+1]=v;pixels[k+2]=v;pixels[k+3]=255
}}
func r594Reference()->[Int] {
var out=[Int]()
for y in 0..<12 {for x in 0..<16 {
let u=0.06+(0.60-0.06)*(Double(x)+0.5)/16
let v=0.30+(0.80-0.30)*(Double(y)+0.5)/12
let xx=min(w-1,max(0,Int(Double(w)*u)))
let yy=min(h-1,max(0,Int(Double(h)*v)))
let i=(yy*w+xx)*4
out.append((77*Int(pixels[i])+150*Int(pixels[i+1])+29*Int(pixels[i+2]))>>8)
}}
return out
}
let refgrid=r594Reference()
precondition(refgrid.count==192)
func makeRef(_ id:String,_ form:String,_ grid:[Int])->[String:Any] {
["reference_id":id,"species_token":"GYARADOS",
"form_token":form,"region":"MEMORY_LEFT_ACTOR_HYPOTHESIS",
"reference_image_sha256":String(repeating:id=="base" ? "b":"c",count:64),
"human_label_reviewed":true,"certified_as_game_state":false,
"coordinate_space":"RGBA_MEMORY_ROW_ORDER_UNVERIFIED","luma_grid":grid]
}
let base=makeRef("base","BASE",refgrid)
let mega=makeRef("mega","MEGA",refgrid.map{255-$0})
let sprite=R673OrientedSpriteReader.inspect(
pixels:pixels,width:w,height:h,rowBytes:w*4,
epoch:1,frame:2,sha:sha,references:[base,mega],
expected:["GYARADOS":Set(["BASE","MEGA"])])
precondition(sprite["status"] as? String ==
"VISUAL_FORM_CANDIDATES_NOT_CERTIFIED",String(describing:sprite))
let candidates=sprite["candidates"] as! [[String:Any]]
precondition(candidates.count==1,String(describing:candidates))
precondition(candidates[0]["best_distance"] as? Int==0)
precondition(candidates[0]["rotation_hypothesis_degrees"] as? Int==0)
precondition(candidates[0]["raster_y_flip_hypothesis"] as? Bool==false)
precondition(candidates[0]["form_token_claim"] as? String=="BASE")
print("R674_R594_REFERENCE_ROI_ROUNDTRIP_PASS")
let bar:[String:Any]=[
"position_hint":"LOWER_LEFT_HUD_POSITION_ONLY",
"rotation_hypothesis_degrees":0,
"raw_row_origin_hypothesis":"TOP_FIRST",
"fill_percentage_candidate_not_hp":65.0,
"owner":"UNKNOWN","hp_percent_certified":false]
func hp(_ bars:[[String:Any]])->[String:Any] {
["schema":R672PixelHPFillReader.schema,
"status":"PARTIAL_BAR_FILL_TRACKS_UNVERIFIED",
"frame_id":Int64(2),"epoch":Int64(1),
"raw_image_sha256":sha,"owner_certified":false,
"hp_percent_certified":false,"current_state_eligible":false,
"tracks":bars,"track_count":bars.count]
}
let paired=R674ActorHUDLink.link(sprite:sprite,hp:hp([bar]))
precondition(paired["status"] as? String ==
"SAME_FRAME_POSITION_PAIRS_NOT_CERTIFIED",String(describing:paired))
precondition(paired["pair_count"] as? Int==1)
let item=(paired["pairs"] as! [[String:Any]])[0]
precondition(item["species_candidate"] as? String=="GYARADOS")
precondition(item["form_candidate"] as? String=="BASE")
precondition(item["owner"] as? String=="UNKNOWN")
precondition(item["fill_percentage_candidate_not_hp"] as? Double==65)
precondition(paired["owner_certified"] as? Bool==false)
precondition(paired["hp_percent_certified"] as? Bool==false)
var mismatch=hp([bar]);mismatch["frame_id"]=Int64(3)
precondition((R674ActorHUDLink.link(sprite:sprite,hp:mismatch)["status"] as? String)=="HOLD_SOURCE_OR_SCHEMA_CONFLICT")
mismatch=hp([bar]);mismatch["raw_image_sha256"]=String(repeating:"f",count:64)
precondition((R674ActorHUDLink.link(sprite:sprite,hp:mismatch)["status"] as? String)=="HOLD_SOURCE_OR_SCHEMA_CONFLICT")
var wrongBar=bar;wrongBar["rotation_hypothesis_degrees"]=90
precondition((R674ActorHUDLink.link(sprite:sprite,hp:hp([wrongBar]))["status"] as? String)=="HOLD_NO_COMPATIBLE_SAME_FRAME_GEOMETRY")
wrongBar=bar;wrongBar["position_hint"]="UPPER_RIGHT_HUD_POSITION_ONLY"
precondition((R674ActorHUDLink.link(sprite:sprite,hp:hp([wrongBar]))["status"] as? String)=="HOLD_NO_COMPATIBLE_SAME_FRAME_GEOMETRY")
wrongBar=bar;wrongBar["raw_row_origin_hypothesis"]="BOTTOM_FIRST"
precondition((R674ActorHUDLink.link(sprite:sprite,hp:hp([wrongBar]))["status"] as? String)=="HOLD_NO_COMPATIBLE_SAME_FRAME_GEOMETRY")
precondition((R674ActorHUDLink.link(sprite:sprite,hp:hp([bar,bar]))["status"] as? String)=="HOLD_DUPLICATE_SIDE_OR_ORIENTATION")
wrongBar=bar;wrongBar["fill_percentage_candidate_not_hp"]=Double.nan
precondition((R674ActorHUDLink.link(sprite:sprite,hp:hp([wrongBar]))["status"] as? String)=="HOLD_INVALID_HP_BAR_CANDIDATE")
var badSprite=sprite;badSprite["owner_certified"]=true
precondition((R674ActorHUDLink.link(sprite:badSprite,hp:hp([bar]))["status"] as? String)=="HOLD_SOURCE_OR_SCHEMA_CONFLICT")
var badHP=hp([bar]);badHP["hp_percent_certified"]=true
precondition((R674ActorHUDLink.link(sprite:sprite,hp:badHP)["status"] as? String)=="HOLD_SOURCE_OR_SCHEMA_CONFLICT")
precondition((R674ActorHUDLink.link(sprite:sprite,hp:hp([]))["status"] as? String)=="HOLD_NO_COMPATIBLE_SAME_FRAME_GEOMETRY")
print("R674_SAME_FRAME_ACTOR_HUD_SMOKE_PASS 11")
}
}
