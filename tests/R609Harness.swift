import Foundation

enum R548ResearchArchive {
    struct Entry { let name:String; let bytes:Data }
    static let maximumMembers=24
}
enum R598OneButtonFormAttachment {
    static func testDigest(_ bytes:Data)->String {
        return bytes == Fixture.image ? Fixture.sha : "invalid"
    }
}
enum Fixture {
    static let image = Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAADAAAAAYCAIAAAAzn+mLAAAAM0lEQVR42mNgGAWjYBSMgoEFjFhFxT6Y0si+VwKn8StgGmwhNOqgUTAKRsEoGAWjYLgDAJOAAwjCGcRPAAAAAElFTkSuQmCC")!
    static let sha="6991a7eea5033953766c833ff3268128e860e42662c309e208221793bdbe1c60"
}

@main struct R609Harness {
    static func main() throws {
        func check(_ okay:Bool,_ what:String) { precondition(okay,what);print("PASS_R609",what) }
        let text:[String:Any] = ["x":0.1,"y":0.42,"width":0.2,"height":0.08]
        let pixel:[String:Any]=["x_norm":0.15,"y_norm":0.45,"width_norm":0.3,"height_norm":0.04]
        let pairs=R609VisionTextSpatialEvidence.spatialHypotheses(text:text,rawColor:pixel)
        check(pairs.count==2,"both_coordinate_hypotheses_preserved")
        check(pairs.allSatisfy{($0["spatial_relation"] as? String)=="UNVERIFIED_PROXIMITY_NOT_HUD_BINDING"},"no_roi_claim")
        var invalid=pixel;invalid["x_norm"] = 1.1
        check(R609VisionTextSpatialEvidence.spatialHypotheses(text:text,rawColor:invalid).isEmpty,"out_of_bounds_rejected")
        var invalidRect=text;invalidRect["width"] = Double.nan
        check(R609VisionTextSpatialEvidence.spatialHypotheses(text:invalidRect,rawColor:pixel).isEmpty,"nan_rejected")
        var far=pixel;far["x_norm"] = 0.75
        check(R609VisionTextSpatialEvidence.spatialHypotheses(text:text,rawColor:far).isEmpty,"no_x_overlap")
        func run(_ frames:[[String:Any]], includePNG:Bool=true, extra:[R548ResearchArchive.Entry]=[]) throws -> [String:Any] {
            let report:[String:Any]=[
                "schema":"trueplan.r608.raw_png_visual_evidence.v1",
                "certified_for_battle":false,
                "owner_verified":false,"roi_verified":false,
                "mega_verified":false,"frame_identity_verified":false,
                "display_orientation_verified":false,
                "status":"HOLD_VISUAL_OWNER_ROI_AND_ORIENTATION_UNCERTIFIED",
                "bindings":frames]
            let json=try JSONSerialization.data(withJSONObject:report)
            var entries:[R548ResearchArchive.Entry] = [.init(name:"r608_original_pixel_evidence.json",bytes:json)]
            if includePNG {entries.append(.init(name:"test.png",bytes:Fixture.image))}
            entries.append(contentsOf:extra)
            let output=R609VisionTextSpatialEvidence.beforeZip(entries)
            check(output.count==entries.count+1,"output_added")
            check(output.last?.name==R609VisionTextSpatialEvidence.memberName,"correct_member_name")
            return try JSONSerialization.jsonObject(with:output.last!.bytes) as! [String:Any]
        }
        let row:[String:Any]=["epoch":1,"frame_id":9,
            "original_png_sha256":Fixture.sha,"archive_png":"test.png",
            "png_ihdr_crc_verified":true,"decoded_pixels_verified":true,
            "owner_verified":false,"display_orientation_verified":false,
            "roi_verified":false,"mega_verified":false,
            "frame_identity_verified":false,
            "unverified_region_candidates":[pixel]]
        let doc=try run([row]); let rows=doc["bindings"] as! [[String:Any]]
        check(rows.count==1,"one_frame")
        check(doc["certified_for_battle"] as? Bool == false,"battle_certification_disabled")
        check(rows[0]["owner_verified"] as? Bool == false,"owner_disabled")
        check(rows[0]["mega_verified"] as? Bool == false,"mega_disabled")
        check(rows[0]["original_png_sha256"] as? String==Fixture.sha,"sha_preserved")
        #if canImport(Vision) && canImport(ImageIO) && canImport(CoreGraphics)
        check(rows[0]["ocr_request_orientation_assumption"] as? String=="UP_NOT_SCREEN_VERIFIED","explicit_orientation_assumption")
        #else
        check(rows[0]["status"] as? String=="HOLD_VISION_FRAMEWORK_UNAVAILABLE","nonapple_fail_closed")
        #endif
        let missing=try run([row],includePNG:false)
        let m=(missing["bindings"] as! [[String:Any]])[0]
        check(m["status"] as? String=="HOLD_ORIGINAL_PNG_OR_R608_BINDING_NOT_VERIFIED","missing_image_hold")
        var bad=row;bad["original_png_sha256"] = String(repeating:"f",count:64)
        let tampered=try run([bad]); let z=(tampered["bindings"] as! [[String:Any]])[0]
        check(z["status"] as? String=="HOLD_ORIGINAL_PNG_OR_R608_BINDING_NOT_VERIFIED","mismatched_hash_hold")
        let reused=try run([row,row]);check(reused["status"] as? String=="HOLD_DUPLICATE_FRAME_ID","reused_frame_fails_closed")
        var samePNGOtherFrame=row;samePNGOtherFrame["frame_id"]=10
        let same=try run([row,samePNGOtherFrame]);check(same["status"] as? String=="HOLD_REUSED_ARCHIVE_PNG","reused_image_cross_frame_hold")
        var claimedROI=row;claimedROI["roi_verified"]=true
        let inconsistent=try run([claimedROI]);let held=(inconsistent["bindings"] as! [[String:Any]])[0]
        check(held["status"] as? String=="HOLD_ORIGINAL_PNG_OR_R608_BINDING_NOT_VERIFIED","upstream_false_certification_rejected")
        let without=R609VisionTextSpatialEvidence.beforeZip([])
        check(without.count==1,"missing_evidence_generates_hold_receipt")
        let all=[R548ResearchArchive.Entry](repeating:.init(name:"foo",bytes:Data()),count:25)
        check(R609VisionTextSpatialEvidence.beforeZip(all).count==all.count,"oversized_archive_no_mutation")
        print("R609_STANDALONE_PASS_NOT_ACTOR_OR_HUD_OR_MEGA_CERTIFICATION")
    }
}
