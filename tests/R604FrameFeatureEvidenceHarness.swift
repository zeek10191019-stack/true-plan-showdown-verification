import Foundation

@main struct Main {
 static func main() {
   let png=Data(base64Encoded:
   "iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEUlEQVR4nGM44SCAFTEMLQkAiF1GAYJRm+sAAAAASUVORK5CYII=")!
   let seed=[R548ResearchArchive.Entry(name:"manifest.json",bytes:Data("{}".utf8))]
   let sha=R598OneButtonFormAttachment.testDigest(png)
   let full=String(repeating:"a",count:64)
   let grid=Array(0..<192).map{$0 % 256}
   func observation(_ fid:Int64=101,_ missing:Bool=false)->[String:Any]{
     ["schema":"trueplan.r594.historical-actor-appearance.v1",
      "status":"HISTORICAL_APPEARANCE_SAMPLES_ONLY","epoch":Int64(3),
      "frame_id":fid,"observed_ms_monotonic":Int64(1000),
      "image_sha256":full,"owner_certified":false,"mega_certified":false,
      "regions":[["name":"MEMORY_LEFT_ACTOR_HYPOTHESIS",
                  "coordinate_space":"RGBA_MEMORY_ROW_ORDER_UNVERIFIED",
                  "grid_width":16,"grid_height":12,
                  "transparent_samples":missing ? 1 : 0,
                  "luma_grid":missing ? [-1]+Array(grid.dropFirst()) : grid]]]
   }
   func crop(_ verified:Bool=true,_ reg:String="MEMORY_LEFT_ACTOR_HYPOTHESIS",
             _ appearance:[String:Any]?=nil,_ src:String?=nil)->R604ProvenancedCrop{
      R604ProvenancedCrop(battleID:"B0",epoch:3,frameID:101,actorToken:"ACTOR",
          side:"own",orientation:"landscape-left",roiLayoutID:"roi:v1",
          actorVerified:verified,orientationVerified:true,
          sourceFrameSHA256:src ?? full,cropPNG:png,cropSHA256:sha,
          appearance:appearance ?? observation(),appearanceRegion:reg)
   }
   func ck(_ c:Bool,_ n:String){precondition(c,n);print("PASS",n)}
   ck(R599BoundOneButton.validPNG(png),"valid PNG fixture")
   ck(!R604FrameFeatureEvidence.stage(seed,candidate:nil).appended,"missing real source HOLD")
   ck(!R604FrameFeatureEvidence.stage(seed,candidate:crop(false)).appended,"owner unverified HOLD")
   ck(!R604FrameFeatureEvidence.stage(seed,candidate:crop(true,"BACKGROUND")).appended,"background ROI rejected")
   ck(!R604FrameFeatureEvidence.stage(seed,candidate:crop(true,"MEMORY_LEFT_ACTOR_HYPOTHESIS",observation(102))).appended,"frame id mismatch")
   ck(!R604FrameFeatureEvidence.stage(seed,candidate:crop(true,"MEMORY_LEFT_ACTOR_HYPOTHESIS",observation(101,true))).appended,"transparent samples HOLD")
   ck(!R604FrameFeatureEvidence.stage(seed,candidate:crop(true,"MEMORY_LEFT_ACTOR_HYPOTHESIS",nil,String(repeating:"b",count:64))).appended,"full-frame hash mismatch")
   ck(!R604FrameFeatureEvidence.stage(seed+[seed[0]],candidate:crop()).appended,"duplicate archive HOLD")
   let out=R604FrameFeatureEvidence.stage(seed,candidate:crop())
   ck(out.appended && out.entries.count==4,"R594 original grid staged")
   let json=try! JSONSerialization.jsonObject(with:out.entries[2].bytes) as! [String:Any]
   ck((json["features"] as! [Double])==grid.map(Double.init),"byte-identical R594 luma grid numeric")
   ck(json["cropSHA256"] as? String==sha,"exact PNG SHA recorded")
   let proof=try! JSONSerialization.jsonObject(with:out.entries[3].bytes) as! [String:Any]
   ck(proof["r595_numeric_matching_parity_verified"] as? Bool==false,"R595 parity remains HOLD")
 }
}
