import Foundation
enum R673OrientedSpriteReader {
static let schema = "trueplan.r673.oriented-sprite-reference.v1"
private static let zones:[(String,Double,Double,Double,Double)] = [
("LEFT_ACTOR_POSITION_ONLY",0.06,0.30,0.60,0.80),
("RIGHT_ACTOR_POSITION_ONLY",0.60,0.35,0.78,0.82)]
private static func validSHA(_ s:String)->Bool {
s.utf8.count==64 && s.utf8.allSatisfy {
(48...57).contains($0) || (97...102).contains($0)
}
}
private static func base(_ why:String,epoch:Int64,frame:Int64,sha:String)
->[String:Any] {
["schema":schema,"status":why,"frame_id":frame,"epoch":epoch,
"raw_image_sha256":sha,"candidates":[[String:Any]](),
"candidate_count":0,"owner_certified":false,
"mega_form_certified":false,"species_certified":false,
"battle_advice_authorized":false,"current_state_eligible":false]
}
static func unavailable(epoch:Int64,frame:Int64,sha:String)->[String:Any] {
base("HOLD_RGBA_UNAVAILABLE",epoch:epoch,frame:frame,sha:sha)
}
private static func uv(_ x:Double,_ y:Double,angle:Int,flip:Bool)
->(Double,Double) {
let a:(Double,Double)
switch angle {
case 90:a=(y,1-x)
case 180:a=(1-x,1-y)
case 270:a=(1-y,x)
default:a=(x,y)
}
return (a.0,flip ? 1-a.1 : a.1)
}
private static func features(_ pixels:[UInt8],_ w:Int,_ h:Int,
_ rb:Int,_ zone:(String,Double,Double,Double,Double),
_ angle:Int,_ flip:Bool)->[Int] {
var grid=[Int]();grid.reserveCapacity(192)
for j in 0..<12 {for i in 0..<16 {
let u=zone.1+(zone.2-zone.1)*(Double(i)+0.5)/16
let v=zone.3+(zone.4-zone.3)*(Double(j)+0.5)/12
let (x,y)=uv(u,v,angle:angle,flip:flip)
let xx=max(0,min(w-1,Int(Double(w)*x)))
let yy=max(0,min(h-1,Int(Double(h)*y)))
let idx=yy*rb+xx*4
if pixels[idx+3]<160 {grid.append(-1)}
else {
let lum=77*Int(pixels[idx]) + 150*Int(pixels[idx+1]) + 29*Int(pixels[idx+2])
grid.append(lum>>8)
}
}}
return grid
}
private static func score(_ a:[Int],_ b:[Int])->Int? {
guard a.count==192,b.count==192 else {return nil}
let pairs=zip(a,b).filter{$0.0>=0 && $0.1>=0}
guard pairs.count>=180 else {return nil}
let avg1=Double(pairs.reduce(0){$0+$1.0})/Double(pairs.count)
let avg2=Double(pairs.reduce(0){$0+$1.1})/Double(pairs.count)
let d=pairs.reduce(0.0){$0+abs(Double($1.0)-avg1-Double($1.1)+avg2)}
return Int((d/Double(pairs.count)).rounded())
}
static func inspect(pixels:[UInt8],width:Int,height:Int,rowBytes:Int,
epoch:Int64,frame:Int64,sha:String,
references:[[String:Any]],
expected:[String:Set<String>])->[String:Any] {
guard width>=256,height>=192,width<=4096,height<=4096,
rowBytes>=width*4,rowBytes<=width*4+4096,
rowBytes<=64*1024*1024/height,pixels.count==rowBytes*height,
epoch>0,frame>0,validSHA(sha) else {
return base("HOLD_INVALID_RGBA",epoch:epoch,frame:frame,sha:sha)
}
guard references.count<=512,!references.isEmpty else {
return base("HOLD_NO_REVIEWED_REFERENCES",epoch:epoch,frame:frame,sha:sha)
}
struct Ref {let id:String,species:String,form:String,region:String,grid:[Int]}
var refs=[Ref](),ids=Set<String>()
for r in references {
guard let id=r["reference_id"] as? String,!id.isEmpty,
ids.insert(id).inserted,
let species=r["species_token"] as? String,
let form=r["form_token"] as? String,
let region=r["region"] as? String,
let allowed=expected[species],allowed.contains(form),
r["human_label_reviewed"] as? Bool == true,
r["certified_as_game_state"] as? Bool == false,
let refSHA=r["reference_image_sha256"] as? String,
validSHA(refSHA),refSHA != sha,
let grid=r["luma_grid"] as? [Int],grid.count==192,
grid.allSatisfy({(-1...255).contains($0)}),
["MEMORY_LEFT_ACTOR_HYPOTHESIS",
"MEMORY_RIGHT_ACTOR_HYPOTHESIS"].contains(region),
r["coordinate_space"] as? String ==
"RGBA_MEMORY_ROW_ORDER_UNVERIFIED" else {
return base("HOLD_REFERENCE_CONFLICT",epoch:epoch,frame:frame,sha:sha)
}
refs.append(Ref(id:id,species:species,form:form,region:region,grid:grid))
}
let rw=Double(width)/Double(height)
var candidates=[[String:Any]]()
for angle in [0,90,180,270] {
let aspect=angle%180==0 ? rw : 1/rw
guard (1.65...2.35).contains(aspect) else{continue}
for flip in [false,true] {
for (index,zone) in zones.enumerated() {
let memoryRegion=index==0 ?
"MEMORY_LEFT_ACTOR_HYPOTHESIS":
"MEMORY_RIGHT_ACTOR_HYPOTHESIS"
let g=features(pixels,width,height,rowBytes,zone,angle,flip)
let visible=g.filter{$0>=0}
guard visible.count>=180,
(visible.max() ?? 0)-(visible.min() ?? 0)>=25 else{continue}
let compatible=refs.filter{$0.region==memoryRegion}
var byForm=[String:(Int,Ref)]()
for ref in compatible {
guard let s=score(g,ref.grid) else{continue}
let key=ref.species+"|"+ref.form
if let prev=byForm[key],prev.0<=s {continue}
byForm[key]=(s,ref)
}
let ordered=byForm.values.sorted{$0.0<$1.0}
guard let best=ordered.first else{continue}
let needed=expected[best.1.species] ?? []
let available=Set(compatible.filter{$0.species==best.1.species}.map{$0.form})
guard needed.count>=2,available==needed,
ordered.count>=2,
best.0<=12,ordered[1].0-best.0>=8 else {continue}
candidates.append([
"region":zone.0,"rotation_hypothesis_degrees":angle,
"raster_y_flip_hypothesis":flip,
"species_token_claim":best.1.species,
"form_token_claim":best.1.form,
"reference_id":best.1.id,
"best_distance":best.0,"runner_up_distance":ordered[1].0,
"source_image_sha256":sha,
"owner":"UNKNOWN","mega_confirmed":false,
"mega_form_certified":false,"species_certified":false,
"current_state_eligible":false])
}
}
}
let statuses=Set(candidates.compactMap{$0["rotation_hypothesis_degrees"] as? Int})
let ambiguous=statuses.count>1 || candidates.count>2
var out=base(ambiguous ? "HOLD_MULTIPLE_ORIENTATIONS" :
(candidates.isEmpty ? "NO_UNAMBIGUOUS_FORM_MATCH" :
"VISUAL_FORM_CANDIDATES_NOT_CERTIFIED"),
epoch:epoch,frame:frame,sha:sha)
out["candidates"]=ambiguous ? []:candidates
out["candidate_count"]=ambiguous ? 0:candidates.count
out["evaluated_reference_count"]=refs.count
out["evaluated_rotation_hypotheses"]=4
out["real_game_accuracy"]="NOT_MEASURED"
return out
}
}
