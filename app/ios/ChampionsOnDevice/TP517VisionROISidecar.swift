import Foundation
import CoreFoundation
#if canImport(Vision) && canImport(UIKit)
import Vision
import UIKit
#endif

/// R517: experimental *observation source* for capture-pixel OCR rectangles.
/// Uses a second Vision text pass ONLY for research geometry; text must match
/// uniquely between the existing OCR Wire and Vision before adding a candidate.
/// No text classification, OWN/OPP assignment, HP/PP validation or battle action.
enum TP517VisionROISidecar {
    struct Candidate {
        let text: String
        let x: Int
        let y: Int
        let width: Int
        let height: Int
    }
    struct Result {
        let wire: String
        let added: Int
        let reason: String
        var ownerCertified: Bool { false }
        var decisionEligible: Bool { false }
    }
    private static func positiveInt(_ any: Any?) -> Int? {
        guard let n=any as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              let i=Int(n.stringValue),i>=0 else { return nil }
        return i
    }
    private static func validHash(_ value: Any?) -> String? {
        guard let s=value as? String,s.utf8.count==64,
              s.utf8.allSatisfy({($0>=48 && $0<=57)||($0>=97 && $0<=102)})
        else {return nil}
        return s
    }
    static func attach(wire: String, verifiedPNGHash: String?,
                       battleID: String, epoch: Int, frameID: Int64,
                       imageWidth: Int,imageHeight: Int,
                       candidates: [Candidate]) -> Result {
        func fail(_ reason:String)->Result {Result(wire:wire,added:0,reason:reason)}
        guard epoch>=0,frameID>0,(1...16384).contains(imageWidth),
              (1...16384).contains(imageHeight),candidates.count<=256,
              wire.utf8.count<=1_000_000,
              let verified=validHash(verifiedPNGHash),
              let b=wire.data(using:.utf8),
              var outer=(try? JSONSerialization.jsonObject(with:b)) as? [String:Any]
        else {return fail("NO_INDEPENDENT_PNG_PROOF_OR_INVALID_WIRE")}
        let wrapped=outer.keys.contains("payload_json")
        var body=outer
        if wrapped {
            guard let s=outer["payload_json"] as? String,s.utf8.count<=1_000_000,
                  let raw=s.data(using:.utf8),
                  let inner=(try? JSONSerialization.jsonObject(with:raw)) as? [String:Any]
            else {return fail("INVALID_WRAPPED_WIRE")}
            body=inner
        }
        guard let id=body["battle_id"] as? String,id==battleID,
              positiveInt(body["epoch"])==epoch,
              positiveInt(body["frame_id"]).map(Int64.init)==frameID,
              validHash(body["image_sha256"])==verified,
              let rawRows=body["readings"] as? [[String:Any]],rawRows.count<=256
        else {return fail("FRAME_OR_IMAGE_HASH_MISMATCH")}
        // Uniqueness is required in *both* passes; duplicated values are ambiguous.
        var ocounts=[String:Int](),rcounts=[String:Int]()
        for c in candidates where !c.text.isEmpty && c.text.utf8.count<=96 {
            ocounts[c.text,default:0]+=1
        }
        for r in rawRows {
            if let t=r["raw_text"] as? String,!t.isEmpty,t.utf8.count<=96 {
                rcounts[t,default:0]+=1
            }
        }
        var byText=[String:Candidate]()
        for c in candidates {
            guard ocounts[c.text]==1,rcounts[c.text]==1,
                  c.width>0,c.height>0,c.x>=0,c.y>=0,
                  c.x<imageWidth,c.y<imageHeight,
                  c.width<=imageWidth-c.x,c.height<=imageHeight-c.y else {continue}
            byText[c.text]=c
        }
        var rows=rawRows,added=0
        for i in rows.indices {
            guard rows[i]["roi_rect"]==nil || rows[i]["roi_rect"] is NSNull,
                  let text=rows[i]["raw_text"] as? String,
                  let c=byText[text],
                  (rows[i]["source_epoch"]==nil || positiveInt(rows[i]["source_epoch"])==epoch),
                  (rows[i]["source_frame_id"]==nil || positiveInt(rows[i]["source_frame_id"]).map(Int64.init)==frameID),
                  (rows[i]["source_image_sha256"]==nil || validHash(rows[i]["source_image_sha256"])==verified)
            else {continue}
            rows[i]["roi_rect"]=["x":c.x,"y":c.y,"width":c.width,"height":c.height]
            rows[i]["source_epoch"]=epoch
            rows[i]["source_frame_id"]=frameID
            rows[i]["source_image_sha256"]=verified
            rows[i]["roi_source"]="VISION_SECOND_PASS_EXACT_TEXT_UNCERTIFIED"
            rows[i]["roi_owner_certified"]=false
            added+=1
        }
        guard added>0 else{return fail("NO_UNIQUE_MATCHED_CAPTURE_ROI")}
        body["readings"]=rows
        if wrapped {
            guard JSONSerialization.isValidJSONObject(body),
                  let inner=try? JSONSerialization.data(withJSONObject:body,options:[.sortedKeys]),
                  let value=String(data:inner,encoding:.utf8) else{return fail("ENCODING_FAILED")}
            outer["payload_json"]=value
        } else { outer=body }
        guard JSONSerialization.isValidJSONObject(outer),
              let data=try? JSONSerialization.data(withJSONObject:outer,options:[.sortedKeys]),
              data.count<=1_000_000,let output=String(data:data,encoding:.utf8)
        else{return fail("ENCODING_FAILED")}
        return Result(wire:output,added:added,reason:"RESEARCH_ROI_CANDIDATES_ONLY")
    }
}

#if canImport(Vision) && canImport(UIKit)
extension TP517VisionROISidecar {
    /// Optional research sidecar on the *same physically oriented PNG* sent to OCR.
    /// A second Vision pass has real latency; no battle action may wait on it.
    static func enrich(wire: String, png: Data,battleID: String,
                       epoch: Int,frameID: Int64) -> Result {
        guard png.count>0,png.count<=32_000_000,
              let image=UIImage(data:png)?.cgImage,
              let hash=TP509CaptureAttestation.sha256Hex(png),
              TP509CaptureAttestation.verify(wire,actualPNGHash:hash,
                  battleID:battleID,epoch:epoch,frameID:frameID) == .verified
        else {return Result(wire:wire,added:0,reason:"IMAGE_BYTES_NOT_VERIFIED")}
        let width=image.width,height=image.height
        let request=VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        do {
            try VNImageRequestHandler(cgImage:image,options:[:]).perform([request])
        } catch {return Result(wire:wire,added:0,reason:"VISION_OCR_UNAVAILABLE")}
        var candidates=[Candidate]()
        for observation in request.results ?? [] {
            guard let text=observation.topCandidates(1).first?.string,
                  !text.isEmpty,text.utf8.count<=96 else {continue}
            let b=observation.boundingBox
            guard b.minX>=0,b.minY>=0,b.maxX<=1,b.maxY<=1,
                  b.width>0,b.height>0 else {continue}
            let x=Int(floor(Double(b.minX)*Double(width)))
            let y=Int(floor((1-Double(b.maxY))*Double(height)))
            let x2=Int(ceil(Double(b.maxX)*Double(width)))
            let y2=Int(ceil((1-Double(b.minY))*Double(height)))
            guard x>=0,y>=0,x2<=width,y2<=height,x2>x,y2>y else {continue}
            candidates.append(Candidate(text:text,x:x,y:y,width:x2-x,height:y2-y))
        }
        return attach(wire:wire,verifiedPNGHash:hash,battleID:battleID,
                      epoch:epoch,frameID:frameID,imageWidth:width,
                      imageHeight:height,candidates:candidates)
    }
}
#endif
