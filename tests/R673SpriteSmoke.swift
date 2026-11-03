import Foundation
@main struct R673SpriteSmoke {
static func main() {
let w=800,h=400,hash=String(repeating:"a",count:64)
var pixels=[UInt8](repeating:100,count:w*h*4)
for y in 0..<h {for x in 0..<w {
let idx=(y*w+x)*4
let v=UInt8(min(250,40+x*120/w+y*100/h))
pixels[idx]=v;pixels[idx+1]=v;pixels[idx+2]=v;pixels[idx+3]=255
}}
for y in 0..<h {for x in 0..<w {
if Double(x)/Double(w)<0.06 || Double(x)/Double(w)>0.30 ||
Double(y)/Double(h)<0.60 || Double(y)/Double(h)>0.80 {
let idx=(y*w+x)*4
pixels[idx]=100;pixels[idx+1]=100;pixels[idx+2]=100
}
}}
func sample()->[Int] {
var g=[Int]()
for j in 0..<12 {for i in 0..<16 {
let x=Int(Double(w)*(0.06+0.24*(Double(i)+0.5)/16))
let y=Int(Double(h)*(0.60+0.20*(Double(j)+0.5)/12))
g.append(Int(pixels[(y*w+x)*4]))
}}
return g
}
let g=sample();precondition(g.count==192)
let alt=g.map{255-$0}
func ref(_ id:String,_ form:String,_ grid:[Int])->[String:Any] {
["reference_id":id,"species_token":"GYARADOS",
"form_token":form,"region":"MEMORY_LEFT_ACTOR_HYPOTHESIS",
"reference_image_sha256":String(repeating:id=="base" ? "b":"c",count:64),
"human_label_reviewed":true,"certified_as_game_state":false,
"coordinate_space":"RGBA_MEMORY_ROW_ORDER_UNVERIFIED",
"luma_grid":grid]
}
let refs=[ref("base","BASE",g),ref("mega","MEGA",alt)]
let expect=["GYARADOS":Set(["BASE","MEGA"])]
func run(_ refs:[[String:Any]],_ exp:[String:Set<String>]=expect,_ sha:String=hash)->[String:Any] {
R673OrientedSpriteReader.inspect(pixels:pixels,width:w,height:h,
rowBytes:w*4,epoch:1,frame:2,sha:sha,
references:refs,expected:exp)
}
let result=run(refs)
precondition(result["status"] as? String == "VISUAL_FORM_CANDIDATES_NOT_CERTIFIED",String(describing:result))
let candidates=result["candidates"] as! [[String:Any]]
precondition(candidates.count==1)
precondition(candidates[0]["form_token_claim"] as? String == "BASE")
precondition(candidates[0]["owner"] as? String == "UNKNOWN")
precondition(result["mega_form_certified"] as? Bool == false)
print("R673_SPRITE_TEST_BASE_CANDIDATE_PASS")
precondition(run([])["status"] as? String=="HOLD_NO_REVIEWED_REFERENCES")
precondition(run(refs,[:])["status"] as? String=="HOLD_REFERENCE_CONFLICT")
precondition(run(refs,expect,String(repeating:"!",count:64))["status"] as? String=="HOLD_INVALID_RGBA")
precondition(run([refs[0],refs[0]])["status"] as? String=="HOLD_REFERENCE_CONFLICT")
var selfRef=refs[0];selfRef["reference_image_sha256"]=hash
precondition(run([selfRef,refs[1]])["status"] as? String=="HOLD_REFERENCE_CONFLICT")
var illegal=refs[0];illegal["form_token"]="MEGA_Z"
precondition(run([illegal,refs[1]])["status"] as? String=="HOLD_REFERENCE_CONFLICT")
precondition(run([refs[0]])["candidate_count"] as? Int==0)
precondition(run(refs,["GYARADOS":Set(["BASE","MEGA","MEGA_Z"])])["candidate_count"] as? Int==0)
precondition(run(refs).description.contains("NOT_CERTIFIED"))
var rotated=[UInt8](repeating:0,count:pixels.count)
for y in 0..<h {for x in 0..<w {
let src=(y*w+x)*4
let dst=((w-1-x)*h+y)*4
for c in 0..<4 {rotated[dst+c]=pixels[src+c]}
}}
let turn=R673OrientedSpriteReader.inspect(pixels:rotated,
width:h,height:w,rowBytes:h*4,epoch:1,frame:3,sha:hash,
references:refs,expected:expect)
precondition(turn["status"] as? String == "VISUAL_FORM_CANDIDATES_NOT_CERTIFIED",String(describing:turn))
let rotatedMatch=turn["candidates"] as! [[String:Any]]
precondition(rotatedMatch.count==1)
precondition(rotatedMatch[0]["rotation_hypothesis_degrees"] as? Int==90)
print("R673_SPRITE_SMOKE_PASS 12")
}
}
