import Foundation

// Captures the REAL, already-computed R594 luma grids in the one-tap ZIP.
// Side/actor identities remain unknown, and no crop/full-frame hash is conflated.
enum R604HistoricalFeatureArchive {
    static let name = "r604_r594_feature_snapshot.json"
    private static let schema = "trueplan.r594.historical-actor-appearance.v1"
    private static let regions = Set([
        "MEMORY_LEFT_ACTOR_HYPOTHESIS", "MEMORY_RIGHT_ACTOR_HYPOTHESIS"
    ])
    private static func validHash(_ value:String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
    static func beforeZip(_ entries:[R548ResearchArchive.Entry],
                          samples:[[String:Any]]) -> [R548ResearchArchive.Entry] {
        guard !samples.isEmpty, samples.count <= 8,
              entries.count < R548ResearchArchive.maximumMembers,
              Set(entries.map(\.name)).count == entries.count,
              !entries.contains(where:{$0.name == name}) else { return entries }
        var record=[[String:Any]](),seen=Set<String>()
        for s in samples {
            guard s["schema"] as? String == schema,
                  s["status"] as? String == "HISTORICAL_APPEARANCE_SAMPLES_ONLY",
                  s["owner_certified"] as? Bool == false,
                  s["mega_certified"] as? Bool == false,
                  let epoch=s["epoch"] as? Int64, epoch>0,
                  let frame=s["frame_id"] as? Int64, frame>0,
                  let ms=s["observed_ms_monotonic"] as? Int64,ms>0,
                  let hash=s["image_sha256"] as? String,validHash(hash),
                  let list=s["regions"] as? [[String:Any]] else {return entries}
            let key="\(epoch):\(frame)"
            guard seen.insert(key).inserted else {return entries}
            var values=[[String:Any]]()
            for r in list {
                guard let n=r["name"] as? String else {return entries}
                if !regions.contains(n) {continue}
                guard r["coordinate_space"] as? String == "RGBA_MEMORY_ROW_ORDER_UNVERIFIED",
                      r["grid_width"] as? Int == 16,
                      r["grid_height"] as? Int == 12,
                      let grid=r["luma_grid"] as? [Int],grid.count == 192,
                      grid.allSatisfy({(-1...255).contains($0)}),
                      r["transparent_samples"] as? Int == grid.filter({$0 == -1}).count else {
                    return entries
                }
                values.append(["region":n,"luma_grid":grid,
                               "valid_samples":grid.filter({$0>=0}).count])
            }
            guard values.count == 2, Set(values.compactMap{$0["region"] as? String}).count==2
                else {return entries}
            record.append(["epoch":epoch,"frame_id":frame,"monotonic_ms":ms,
                           "full_frame_sha256":hash,"regions":values])
        }
        let payload:[String:Any] = [
            "schema":"trueplan.r604.r594_exact_snapshot.v1",
            "status":"HOLD_OWNER_OR_ROI_AND_R595_MATCHER_PARITY",
            "source":"R594ActorAppearance.capture",
            "samples":record,
            "owner_verified":false,"form_verified":false,"mega_verified":false,
            "crop_sha256":NSNull(),
            "limitations":"Full-frame hash is not a crop hash. No live identity claim."
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let json=try? JSONSerialization.data(withJSONObject:payload,options:[.sortedKeys])
            else{return entries}
        return entries + [.init(name:name,bytes:json)]
    }
}
