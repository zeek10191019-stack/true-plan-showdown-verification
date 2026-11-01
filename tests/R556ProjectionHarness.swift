import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

@main struct R556ProjectionHarness {
    static func main() throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let reportURL=URL(fileURLWithPath:CommandLine.arguments[2])
        var checks=0
        func check(_ value:@autoclosure ()->Bool,_ reason:String) {
            guard value() else {fatalError("R556_CHECK_FAILED_"+reason)};checks+=1
        }
        func sha(_ data:Data)->String {SHA256.hash(data:data).map {String(format:"%02x",$0)}.joined()}
        func json(_ value:Any)throws->Data {try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys,.withoutEscapingSlashes])}
        let rawURL=root.appendingPathComponent("frames/frame_17.png")
        let rawPNG=try Data(contentsOf:rawURL)
        guard let decoder=CGImageSourceCreateWithData(rawPNG as CFData,nil),let raw=CGImageSourceCreateImageAtIndex(decoder,0,nil) else {fatalError("FIXTURE_IMAGE")}
        let crop=R556AnalysisProjection.Rect(x:2,y:1,width:3,height:2)
        // Literal expected pixel matrices, independent of the transform algorithm.
        let expected:[[UInt8]]=[[12,13,14,22,23,24],[14,24,13,23,12,22],[24,23,22,14,13,12],[22,12,23,13,24,14]]
        var primary:CGImage?
        for turn in 0..<4 {
            let plan=R556AnalysisProjection.Plan(rawWidth:7,rawHeight:5,crop:crop,quarterTurnsCCW:turn)
            let output=try R556PixelTransform.apply(raw,plan:plan)
            check(output.width==plan.analysisWidth && output.height==plan.analysisHeight,"actual pixel dimensions")
            let data=output.dataProvider!.data! as Data
            let reds=stride(from:0,to:data.count,by:4).map {data[$0]}
            check(reds==expected[turn],"literal non-square cropped pixel matrix for turn \(turn)")
            check(stride(from:0,to:data.count,by:4).allSatisfy {data[$0+1]==100 && data[$0+2]==200 && data[$0+3]==255},"all RGBA channels preserved")
            check(plan.sourceRect(.init(x:0,y:0,width:output.width,height:output.height))==crop,"full image inverse covers actual crop")
            for y in 0..<output.height {
                for x in 0..<output.width {
                    let marker=Int(expected[turn][y*output.width+x])
                    let inverse=plan.sourceRect(.init(x:x,y:y,width:1,height:1))
                    check(inverse == R556AnalysisProjection.Rect(x:marker%10,y:marker/10,width:1,height:1),"every pixel maps to its source")
                }
            }
            check(plan.sourceRect(.init(x:output.width,y:0,width:1,height:1))==nil,"outside ROI withheld")
            if turn==1 {primary=output}
        }
        for plan in [R556AnalysisProjection.Plan(rawWidth:7,rawHeight:5,crop:.init(x:-1,y:0,width:2,height:2),quarterTurnsCCW:0),
                     .init(rawWidth:7,rawHeight:5,crop:crop,quarterTurnsCCW:4),
                     .init(rawWidth:7,rawHeight:5,crop:.init(x:6,y:4,width:3,height:2),quarterTurnsCCW:0),
                     .init(rawWidth:8,rawHeight:5,crop:crop,quarterTurnsCCW:0)] {
            do {_=try R556PixelTransform.apply(raw,plan:plan);fatalError("INVALID_TRANSFORM_ACCEPTED")}catch {checks+=1}
        }
        let cancelled=R551EvidenceWork();cancelled.cancel()
        let plan=R556AnalysisProjection.Plan(rawWidth:7,rawHeight:5,crop:crop,quarterTurnsCCW:1)
        do {_=try R556PixelTransform.apply(raw,plan:plan,work:cancelled);fatalError("CANCELLED_TRANSFORM_ACCEPTED")}
        catch R551EvidenceWork.Failure.cancelled {checks+=1}
        let analysisURL=root.appendingPathComponent("analysis_native.png")
        guard let encoder=CGImageDestinationCreateWithURL(analysisURL as CFURL,UTType.png.identifier as CFString,1,nil),let image=primary else {fatalError("PNG_DESTINATION")}
        CGImageDestinationAddImage(encoder,image,nil);check(CGImageDestinationFinalize(encoder),"actual transformed PNG encoded")
        let analysis=try Data(contentsOf:analysisURL),analysisSHA=sha(analysis)
        var selected=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("selected_evidence.json"))) as! [String:Any]
        let wrapper=try JSONSerialization.jsonObject(with:Data((selected["research_candidate_envelope"] as! String).utf8)) as! [String:Any]
        var packet=try JSONSerialization.jsonObject(with:Data((wrapper["payload_json"] as! String).utf8)) as! [String:Any]
        var rows=packet["readings"] as! [[String:Any]]
        packet["image_sha256"]=analysisSHA;rows[0]["source_image_sha256"]=analysisSHA;packet["readings"]=rows
        func envelope(_ object:[String:Any])throws->String {
            let payload=try json(object)
            return String(data:try json(["schema":"trueplan.mobile-envelope.v1","payload_json":String(data:payload,encoding:.utf8)!,"payload_sha256":sha(payload)]),encoding:.utf8)!
        }
        let wire=try envelope(packet)
        selected["analysis_image"]=["width":2,"height":3,"png_bytes":analysis.count,"png_sha256":analysisSHA,"image_png_base64":analysis.base64EncodedString()]
        selected["research_candidate_envelope"]=wire
        let projection=R556AnalysisProjection.report(plan:plan,envelope:wire,session:"capture-test",frame:17,epoch:3,observedMs:1200,rawSHA:sha(rawPNG),analysisSHA:analysisSHA)
        check(projection["status"] as? String=="DECLARED_GEOMETRY_ONLY","same-source transform report")
        let mapped=projection["mapped_rois"] as! [[String:Any]],omitted=projection["omitted_rois"] as! [[String:Any]]
        check(mapped.count==1 && omitted.count==1,"all bound and missing ROIs accounted")
        check(mapped[0]["raw_rect"] as? [String:Int]==["x":3,"y":1,"width":2,"height":1],"literal inverse ROI")
        check(projection["pixel_equality_verified"] as? Bool==false && projection["owner_certified"] as? Bool==false,"synthetic tests never certify game pixels or owner")
        var bad=packet;bad["frame_id"]=true
        let boolWire=try envelope(bad)
        check(R556AnalysisProjection.report(plan:plan,envelope:boolWire,session:"capture-test",frame:1,epoch:3,observedMs:1200,rawSHA:sha(rawPNG),analysisSHA:analysisSHA)["status"] as? String=="HOLD","boolean identity withheld")
        check(R556AnalysisProjection.report(plan:plan,envelope:wire,session:"foreign",frame:17,epoch:3,observedMs:1200,rawSHA:sha(rawPNG),analysisSHA:analysisSHA)["status"] as? String=="HOLD","foreign source withheld")
        selected["analysis_projection"]=projection
        selected["screen_read_state"]=R551ScreenReadState.make(envelope:wire,captureSessionID:"capture-test",frame:17,epoch:3,observedMs:1200,imageSHA:analysisSHA,width:2,height:3)
        var entries=[R548ResearchArchive.Entry(name:"selected_evidence.json",bytes:try json(selected))]
        for name in ["capture_manifest.json","frames/frame_17.png"] {entries.append(.init(name:name,bytes:try Data(contentsOf:root.appendingPathComponent(name))))}
        entries=try R551EvidenceIntegrity.appendingIndex(entries,captureSessionID:"capture-test",frame:17,epoch:3,appVersion:"0.5.56",appBuild:"556")
        _=try R548ResearchArchive.write(entries,to:root.appendingPathComponent("r556_projection.zip"))
        try json(["checks":checks,"image_transform_vectors":4,"input":"HAND_AUTHORED_OPAQUE_RGB_GRID","projection":projection,"game_accuracy_certified":false,"device_certified":false]).write(to:reportURL)
        print("R556_NATIVE_PROJECTION_CHECKS_PASS=\(checks); SYNTHETIC_PIXELS_ONLY")
    }
}
