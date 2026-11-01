import Foundation

// Standalone test doubles of the archive contract, for platform tests only.
enum R548ResearchArchive {
    struct Entry { let name:String; let bytes:Data }
    static let maximumMembers=24
}
enum R598OneButtonFormAttachment {
    static func testDigest(_ bytes:Data)->String {
        // Test fixture with known PNG SHA is supplied by Python at build time.
        let hex=bytes.map {String(format:"%02x",$0)}.joined()
        return hex == PNGData.fixtureHex ? PNGData.fixtureSHA : "no-match"
    }
}
enum PNGData {
    static let fixtureHex="89504e470d0a1a0a0000000d4948445200000030000000180802000000339fe98b000000334944415478da63601805a360148c8281058c5845c53e98d2c8be5702a7f12b601a6c2134eaa051300a46c1281805a360b8030093800308c219c44f0000000049454e44ae426082"
    static let fixtureSHA="6991a7eea5033953766c833ff3268128e860e42662c309e208221793bdbe1c60"
}
@main struct R608Harness {
    static func main() throws {
        func check(_ v:Bool,_ label:String) {precondition(v,label);print("PASS_R608",label)}
        let img=Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAADAAAAAYCAIAAAAzn+mLAAAAM0lEQVR42mNgGAWjYBSMgoEFjFhFxT6Y0si+VwKn8StgGmwhNOqgUTAKRsEoGAWjYLgDAJOAAwjCGcRPAAAAAElFTkSuQmCC")!
        let clean=R608FramePixelEvidence.inspect(img)
        check(clean["png_ihdr_crc_verified"] as? Bool == true,"IHDR_CRC")
        check(clean["raw_width"] as? Int==48 && clean["raw_height"] as? Int==24,"dimensions")
        check(clean["raw_pixel_aspect"] as? String=="WIDER_THAN_TALL","image_aspect")
        check(clean["display_orientation_verified"] as? Bool == false,"not_screen_orientation")
        check(clean["owner_verified"] as? Bool == false,"not_actor_certified")
        #if canImport(ImageIO) && canImport(CoreGraphics)
        check(clean["decoded_pixels_verified"] as? Bool == true,"macos_real_decode")
        let regions=clean["unverified_region_candidates"] as? [[String:Any]] ?? []
        check(!regions.isEmpty,"color_run_detected_from_pixels")
        #endif
        var broken=[UInt8](img);broken[29] ^= 1
        check(R608FramePixelEvidence.inspect(Data(broken))["status"] as? String ==
            "HOLD_PNG_HEADER_OR_IHDR_INVALID","tampered_crc_rejected")
        check(R608FramePixelEvidence.inspect(img.prefix(15))["status"] as? String ==
            "HOLD_PNG_HEADER_OR_IHDR_INVALID","truncated_rejected")
        let row:[String:Any]=["epoch":Int64(1),"frame_id":Int64(7),
            "source_png_sha256":PNGData.fixtureSHA,"archive_png":"test.png",
            "status":"CONTENT_HASH_MATCH_ONLY_NEEDS_FRAME_AND_OWNER_PROOF"]
        func report(_ bindings:[[String:Any]], png:Data?=img) -> [String:Any] {
            let prev:[String:Any]=["schema":"trueplan.r607.byte_provenance_audit.v1",
                "certified_for_battle":false,"owner_verified":false,"bindings":bindings]
            let evidence=try! JSONSerialization.data(withJSONObject:prev)
            var entries:[R548ResearchArchive.Entry]=[
                .init(name:"r607_frame_provenance_audit.json",bytes:evidence)]
            if let p=png {entries.append(.init(name:"test.png",bytes:p))}
            let out=R608FramePixelEvidence.beforeZip(entries)
            check(out.count==entries.count+1,"receipt_appended")
            return try! JSONSerialization.jsonObject(with:out.last!.bytes) as! [String:Any]
        }
        let a=report([row]); let bindings=a["bindings"] as! [[String:Any]]
        check(bindings.count==1,"one_original_frame")
        check(bindings[0]["raw_width"] as? Int==48,"geometry_from_original_png")
        check(a["owner_verified"] as? Bool==false,"owner_hold")
        check(a["mega_verified"] as? Bool==false,"mega_hold")
        let bad=report([row],png:nil)
        let badRows=bad["bindings"] as! [[String:Any]]
        check(badRows[0]["status"] as? String == "HOLD_ARCHIVE_OR_FRAME_HASH_NOT_VERIFIED","missing_png")
        let duplicate=report([row,row]);check(duplicate["status"] as? String=="HOLD_DUPLICATE_FRAME_BINDING","reused_id")
        let empty=report([]);check((empty["bindings"] as? [[String:Any]])?.isEmpty==true,"empty_safe")
        print("R608_STANDALONE_TESTS_PASS_NOT_FIELD_CERTIFICATION")
    }
}
