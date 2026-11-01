import Foundation

@main struct R594ActorAppearanceHarness {
 static func main() {
  var n=0
  func check(_ value:Bool,_ name:String) {guard value else {fatalError("R594_\(name)")};n+=1}
  let w=512,h=256,s1=String(repeating:"a",count:64),s2=String(repeating:"b",count:64)
  func image()->[UInt8] {var a=[UInt8](repeating:0,count:w*h*4);for i in stride(from:3,to:a.count,by:4){a[i]=255};return a}
  func fill(_ a:inout [UInt8],_ x0:Int,_ x1:Int,_ y0:Int,_ y1:Int,_ c:UInt8) {
   for y in y0..<y1 {for x in x0..<x1 {let j=(y*w+x)*4;a[j]=c;a[j+1]=c;a[j+2]=c}}
  }
  func actorStripes(_ a:inout [UInt8],left:Bool,invert:Bool=false) {
   let x0=left ? 50:315,x1=left ? 300:385
   for x in stride(from:x0,to:x1,by:18) {fill(&a,x,min(x1,x+9),100,185,invert ? 30:225)}
  }
  func record(_ img:[UInt8],_ id:Int64,ms:Int64=100,ep:Int64=1,sha:String=s1)->[String:Any] {
   R594ActorAppearance.capture(pixels:img,width:w,height:h,rowBytes:w*4,epoch:ep,frame:id,ms:ms,sha:sha)
  }
  let empty=image()
  let hold=R594ActorAppearance.capture(pixels:[],width:w,height:h,rowBytes:w*4,epoch:1,frame:1,ms:100,sha:s1)
  check(hold["status"] as? String=="HOLD_RASTER_UNAVAILABLE","raster_hold")
  check(hold["mega_certified"] as? Bool==false,"raster_no_mega")
  var a=empty;actorStripes(&a,left:true);actorStripes(&a,left:false)
  let first=record(a,1)
  check(first["schema"] as? String==R594ActorAppearance.schema,"schema")
  check(first["status"] as? String=="HISTORICAL_APPEARANCE_SAMPLES_ONLY","status")
  check(first["owner_certified"] as? Bool==false,"no_owner")
  check(first["species_certified"] as? Bool==false,"no_species")
  check(first["mega_certified"] as? Bool==false,"no_mega")
  check(first["automatic_upload"] as? Bool==false,"no_auto_upload")
  let regions=first["regions"] as? [[String:Any]] ?? []
  check(regions.count==3,"three_regions")
  check(regions.allSatisfy{($0["luma_grid"] as? [Int])?.count==192},"grid_size")
  check(regions.allSatisfy{$0["grid_width"] as? Int==16},"grid_width")
  check(regions.allSatisfy{$0["grid_height"] as? Int==12},"grid_height")
  check(regions.allSatisfy{$0["transparent_samples"] as? Int==0},"opaque")
  let same=R594ActorAppearance.timeline([first,record(a,2,ms:200,sha:s2)])
  check(same["pair_count"] as? Int==1,"one_pair")
  let row=(same["pairs"] as? [[String:Any]])?.first ?? [:]
  check(row["status"] as? String=="UNCERTIFIED_APPEARANCE_CANDIDATES","compare")
  let actors=row["actors"] as? [[String:Any]] ?? []
  check(actors.count==2,"two_actors")
  check(actors.allSatisfy{$0["status"] as? String=="APPEARANCE_SIMILARITY_CANDIDATE"},"similar")
  check(actors.allSatisfy{$0["mega_confirmed"] == nil},"no_mega_in_actors")
  check(row["mega_confirmed"] as? Bool==false,"pair_no_mega")
  check(row["switch_confirmed"] as? Bool==false,"pair_no_switch")
  check(row["owner"] as? String=="UNKNOWN","pair_owner_unknown")
  var change=a
  fill(&change,50,300,100,185,30)
  let changed=R594ActorAppearance.timeline([first,record(change,2,ms:200,sha:s2)])
  let changedActors=((changed["pairs"] as? [[String:Any]])?.first?["actors"] as? [[String:Any]]) ?? []
  let left=changedActors.first{$0["region"] as? String=="MEMORY_LEFT_ACTOR_HYPOTHESIS"} ?? [:]
  let right=changedActors.first{$0["region"] as? String=="MEMORY_RIGHT_ACTOR_HYPOTHESIS"} ?? [:]
  check(left["status"] as? String=="APPEARANCE_DIFFERENCE_CANDIDATE","left_change")
  check(right["status"] as? String=="APPEARANCE_SIMILARITY_CANDIDATE","right_stable")
  check((left["brightness_normalized_distance"] as? Int ?? 0)>=19,"distance")
  check(left["is_species_identity"] as? Bool==false,"actor_not_identity")
  check(left["is_mega_evidence"] as? Bool==false,"actor_not_mega")
  var camera=change;fill(&camera,190,350,9,54,200)
  let bg=R594ActorAppearance.timeline([record(change,1),record(camera,2,ms:200,sha:s2)])
  check(((bg["pairs"] as? [[String:Any]])?.first?["status"] as? String)=="HOLD_BACKGROUND_OR_CAMERA_CHANGE","camera_hold")
  let bgActors=((bg["pairs"] as? [[String:Any]])?.first?["actors"] as? [[String:Any]]) ?? []
  check(bgActors.allSatisfy{$0["status"] as? String=="HOLD_BACKGROUND_OR_CAMERA_CHANGE"},"camera_actor_hold")
  let flat=R594ActorAppearance.timeline([record(empty,1),record(empty,2,ms:200,sha:s2)])
  let flatActors=((flat["pairs"] as? [[String:Any]])?.first?["actors"] as? [[String:Any]]) ?? []
  check(flatActors.allSatisfy{$0["status"] as? String=="HOLD_LOW_TEXTURE"},"low_texture")
  check(R594ActorAppearance.timeline([first,first])["status"] as? String=="HOLD_INVALID_SEQUENCE","duplicate")
  check(R594ActorAppearance.timeline([record(a,2),first])["status"] as? String=="HOLD_INVALID_SEQUENCE","reverse_order")
  check(R594ActorAppearance.timeline([first,record(a,2,ms:99)])["status"] as? String=="HOLD_INVALID_SEQUENCE","reverse_time")
  let cross=R594ActorAppearance.timeline([first,record(a,1,ms:200,ep:2,sha:s2)])
  check(((cross["pairs"] as? [[String:Any]])?.first?["status"] as? String)=="HOLD_CROSS_EPOCH_OR_MISSING_RASTER","cross_epoch")
  let skip=R594ActorAppearance.timeline([first,R594ActorAppearance.unavailable(epoch:1,frame:2,ms:200,sha:s2,reason:"TEST")])
  check(((skip["pairs"] as? [[String:Any]])?.first?["status"] as? String)=="HOLD_CROSS_EPOCH_OR_MISSING_RASTER","missing_pixels")
  check(R594ActorAppearance.timeline(Array(repeating:first,count:9))["status"] as? String=="HOLD_INVALID_SEQUENCE","max8")
  check(R594ActorAppearance.timeline([])["pair_count"] as? Int==0,"zero")
  check(record(a,0)["status"] as? String=="HOLD_RASTER_UNAVAILABLE","bad_frame")
  check(record(a,1,ms:0)["status"] as? String=="HOLD_RASTER_UNAVAILABLE","bad_clock")
  check(record(a,1,ms:100,ep:0)["status"] as? String=="HOLD_RASTER_UNAVAILABLE","bad_epoch")
  check(record(a,1,ms:100,ep:1,sha:"BAD")["status"] as? String=="HOLD_RASTER_UNAVAILABLE","bad_sha")
  var bad=record(a,2,ms:200,sha:s2)
  bad["mega_certified"]=true
  check(R594ActorAppearance.timeline([first,bad])["status"] as? String=="HOLD_INVALID_SEQUENCE","fake_cert")
  bad=record(a,2,ms:200,sha:s2)
  bad["regions"]=[["name":"invalid","luma_grid":[0]]]
  check(R594ActorAppearance.timeline([first,bad])["status"] as? String=="HOLD_INVALID_SEQUENCE","malformed_grid")
  var transparent=a
  transparent[(120*w+150)*4+3]=0
  let t=record(transparent,1)
  check((t["regions"] as? [[String:Any]])?.count==3,"transparent_bounded")
  let json=try! JSONSerialization.data(withJSONObject:same)
  check(json.count<120_000,"bounded_json")
  print("R594_ACTOR_APPEARANCE_TESTS_\(n)_PASS")
 }
}
