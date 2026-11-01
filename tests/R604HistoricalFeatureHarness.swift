import Foundation
@main struct Main {
 static func main() {
    let original=[R548ResearchArchive.Entry(name:"manifest.json",bytes:Data("{}".utf8))]
    let grid=Array(0..<192).map { $0 % 256 }
    func sample(_ frame:Int64=2,_ wrong:Bool=false)->[String:Any] {
      ["schema":"trueplan.r594.historical-actor-appearance.v1",
       "status":"HISTORICAL_APPEARANCE_SAMPLES_ONLY",
       "owner_certified":false,"mega_certified":false,
       "epoch":Int64(1),"frame_id":frame,"observed_ms_monotonic":Int64(3100),
       "image_sha256":String(repeating:"a",count:64),
       "regions":["MEMORY_LEFT_ACTOR_HYPOTHESIS","MEMORY_RIGHT_ACTOR_HYPOTHESIS"].map{ name in
         ["name":name,"coordinate_space": "RGBA_MEMORY_ROW_ORDER_UNVERIFIED",
          "grid_width":16,"grid_height":12,"transparent_samples":0,
          "luma_grid":wrong ? [12,20] : grid] as [String:Any]
       }]
    }
    func check(_ b:Bool,_ n:String){precondition(b,n);print("PASS",n)}
    check(R604HistoricalFeatureArchive.beforeZip(original,samples:[]).count==1,"no snapshots untouched")
    check(R604HistoricalFeatureArchive.beforeZip(original,samples:[sample(2,true)]).count==1,"bad dimensions reject")
    check(R604HistoricalFeatureArchive.beforeZip(original,samples:[sample(),sample()]).count==1,"duplicate frame reject")
    let added=R604HistoricalFeatureArchive.beforeZip(original,samples:[sample()])
    check(added.count==2,"original+new snapshot")
    check(added[0].bytes==original[0].bytes,"original member byte identical")
    let object=try! JSONSerialization.jsonObject(with:added[1].bytes) as! [String:Any]
    let samples=object["samples"] as! [[String:Any]]
    let regions=samples[0]["regions"] as! [[String:Any]]
    check((regions[0]["luma_grid"] as! [Int])==grid,"R594 numerical grid unchanged")
    check(object["mega_verified"] as? Bool==false,"Mega remains HOLD")
    check(object["crop_sha256"] is NSNull,"crop not invented")
 }
}
