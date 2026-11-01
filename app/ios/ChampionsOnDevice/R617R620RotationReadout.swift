import Foundation
#if canImport(Vision) && canImport(ImageIO) && canImport(CoreGraphics)
import Vision
import ImageIO
import CoreGraphics
#endif

// R617: four-way original-PNG OCR, R618: orientation-specific text geometry,
// R619: repeat-location hypotheses, R620: bounded one-tap evidence receipt.
// The orientation and the own/opponent actor are NEVER certified here.
enum R617R620RotationReadout {
    static let memberName = "r617_r620_rotation_readout.json"
    static let maxFrames = 2
    static let maxTokensPerRotation = 12
    static let maxInputBytes = 8_000_000
    private static let maxJSONBytes = 96_000
    private static let shaChars = Set("0123456789abcdef")
    private static let orientationNames = ["UP", "RIGHT", "DOWN", "LEFT"]

    static func parseVisualToken(_ raw: String) -> [String:Any]? {
        var text = raw.trimmingCharacters(in:.whitespacesAndNewlines)
            .replacingOccurrences(of:" ",with:"")
            .replacingOccurrences(of:"\u{3000}",with:"")
            .replacingOccurrences(of:"／",with:"/")
            .replacingOccurrences(of:"％",with:"%")
        for (full,ascii) in zip("０１２３４５６７８９", "0123456789") {
            text=text.replacingOccurrences(of:String(full),with:String(ascii))
        }
        guard !text.isEmpty && text.utf8.count <= 96 else { return nil }
        func number(_ s:Substring, maxDigits:Int)->Int? {
            guard !s.isEmpty && s.count<=maxDigits,
                  s.utf8.allSatisfy({(48...57).contains($0)}) else {return nil}
            return Int(s)
        }
        let halves=text.split(separator:"/",omittingEmptySubsequences:false)
        if halves.count==2, let current=number(halves[0],maxDigits:4),
           let total=number(halves[1],maxDigits:4),total>0,current<=total {
            // Fraction is compatible with HP and PP. No role or field assignment.
            return ["kind":"FRACTION_HP_OR_PP_UNASSIGNED", "numerator":current,
                    "denominator":total,"source":"OCR_VISUAL_TOKEN_NOT_BATTLE_STATE"]
        }
        if text.hasSuffix("%"),let percent=number(text.dropLast(),maxDigits:3),percent<=100 {
            return ["kind":"PERCENT_HP_OR_OTHER_UNASSIGNED","percent":percent,
                    "source":"OCR_VISUAL_TOKEN_NOT_BATTLE_STATE"]
        }
        // Mega evolution dialogue is a scene cue, never actor/form proof.
        let megaText = text.uppercased().replacingOccurrences(of:" ",with:"")
        if text.contains("メガシンカ") || text.contains("メガ進化") ||
           megaText.contains("MEGAEVOLUTION") {
            return ["kind":"MEGA_SCENE_TEXT_CUE_UNASSIGNED",
                    "source":"OCR_SCENE_WORD_NOT_ACTOR_OR_FORM"]
        }
        let statusMap:[String:String] = [
            "まひ":"PAR","やけど":"BRN","どく":"PSN", "もうどく":"TOX",
            "ねむり":"SLP","こおり":"FRZ","ひんし":"FNT",
            "PAR":"PAR","BRN":"BRN","PSN":"PSN","TOX":"TOX",
            "SLP":"SLP","FRZ":"FRZ","FNT":"FNT"]
        if let state=statusMap[text.uppercased()] ?? statusMap[text] {
            return ["kind":"STATUS_WORD_UNASSIGNED","status_code":state,
                    "source":"OCR_VISUAL_TOKEN_NOT_BATTLE_STATE"]
        }
        return nil
    }

    private static func safeName(_ s:String)->Bool {
        !s.isEmpty && s.utf8.count<=160 && !s.hasPrefix("/") &&
        !s.contains("..") && !s.contains("\\") && !s.contains("//") &&
        s.hasSuffix(".png") && s.utf8.allSatisfy({$0>=32 && $0 != 127})
    }
    private static func validSHA(_ s:String)->Bool {
        s.utf8.count==64 && s.allSatisfy({shaChars.contains($0)})
    }
    private static func bound(_ r:[String:Any])->Bool {
        guard let x=r["x"] as? Double,let y=r["y"] as? Double,
              let w=r["width"] as? Double,let h=r["height"] as? Double,
              [x,y,w,h].allSatisfy({$0.isFinite}),x>=0,y>=0,w>0,h>0,
              x+w<=1.000001,y+h<=1.000001 else {return false}
        return true
    }
    private static func key(_ x:[String:Any])->String? {
        guard let e=x["epoch"] as? Int64,e>0,
              let id=x["frame_id"] as? Int64,id>0 else {return nil}
        return "\(e):\(id)"
    }
    private static func verifiedHoldFlags(_ obj:[String:Any])->Bool {
        ["certified_for_battle","owner_verified","roi_verified","mega_verified",
         "display_orientation_verified"].allSatisfy { obj[$0] as? Bool == false }
    }
    private static func rotationOCR(_ png:Data)->([[String:Any]],String) {
        #if canImport(Vision) && canImport(ImageIO) && canImport(CoreGraphics)
        let rotations:[(String,CGImagePropertyOrientation)] = [
            ("UP",.up),("RIGHT",.right),("DOWN",.down),("LEFT",.left)]
        var rows=[[String:Any]]()
        var failed=false
        for (label,orientation) in rotations {
            let request=VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["ja-JP","en-US"]
            do {
                let handler=VNImageRequestHandler(data:png,orientation:orientation,options:[:])
                try handler.perform([request])
                var candidates=[[String:Any]]()
                for o in (request.results ?? []).prefix(maxTokensPerRotation) {
                    guard let text=o.topCandidates(1).first,
                          text.confidence.isFinite,
                          text.confidence>=0 && text.confidence<=1,
                          let kind=parseVisualToken(text.string) else {continue}
                    let rect=o.boundingBox
                    let box:[String:Any]=["x":Double(rect.minX),"y":Double(rect.minY),
                                          "width":Double(rect.width),"height":Double(rect.height)]
                    guard bound(box) else {continue}
                    candidates.append(["token":String(text.string.prefix(96)),
                        "visual_semantics":kind,"confidence":Double(text.confidence),
                        "rect_norm_bottom_left_in_orientation_hypothesis":box,
                        "identity":"UNKNOWN","battle_field_certified":false])
                }
                rows.append(["hypothesis":label,"status":"OCR_OBSERVED_NOT_ORIENTATION_CALIBRATED",
                             "visual_tokens":candidates,
                             "raw_observations_truncated":(request.results?.count ?? 0)>maxTokensPerRotation])
            } catch {
                failed=true
                rows.append(["hypothesis":label,"status":"HOLD_VISION_REQUEST_FAILED",
                             "visual_tokens":[[String:Any]]()])
            }
        }
        return (rows,failed ? "HOLD_PARTIAL_VISION_ORIENTATION_FAILURE" : "HOLD_FOUR_ORIENTATION_HYPOTHESES")
        #else
        return (orientationNames.map {["hypothesis":$0,"status":"HOLD_VISION_UNAVAILABLE",
                                      "visual_tokens":[[String:Any]]()]},"HOLD_VISION_UNAVAILABLE")
        #endif
    }
    // A repeated location is NOT proof of the same Pokemon or a fixed UI role.
    static func continuity(_ frames:[[String:Any]])->[[String:Any]] {
        guard frames.count==2,
              let a=frames[0]["orientation_probes"] as? [[String:Any]],
              let b=frames[1]["orientation_probes"] as? [[String:Any]],
              a.count==4,b.count==4 else {return []}
        var matches=[[String:Any]]()
        for name in orientationNames {
            guard let old=a.first(where:{$0["hypothesis"] as? String==name}),
                  let new=b.first(where:{$0["hypothesis"] as? String==name}),
                  let left=old["visual_tokens"] as? [[String:Any]],
                  let right=new["visual_tokens"] as? [[String:Any]] else {continue}
            var used=Set<Int>()
            for (i,x) in left.enumerated() {
                guard let kind=x["visual_semantics"] as? [String:Any],
                      let t=kind["kind"] as? String,
                      let r=x["rect_norm_bottom_left_in_orientation_hypothesis"] as? [String:Any],
                      bound(r),let cx=r["x"] as? Double,let cy=r["y"] as? Double else {continue}
                let found=right.enumerated().filter { j,y in
                    guard !used.contains(j),
                          let kind2=y["visual_semantics"] as? [String:Any],
                          kind2["kind"] as? String==t,
                          let s=y["rect_norm_bottom_left_in_orientation_hypothesis"] as? [String:Any],
                          bound(s),let dx=s["x"] as? Double,let dy=s["y"] as? Double else{return false}
                    return abs(cx-dx)<=0.035 && abs(cy-dy)<=0.035
                }
                if found.count==1 {
                    used.insert(found[0].offset)
                    matches.append(["hypothesis":name,"first_token_index":i,
                                    "next_token_index":found[0].offset,
                                    "status":"HOLD_LOCATION_ONLY_NOT_ACTOR_CONTINUITY"])
                }
            }
        }
        return Array(matches.prefix(24))
    }
    static func beforeZip(_ entries:[R548ResearchArchive.Entry])->[R548ResearchArchive.Entry] {
        let names=entries.map(\.name)
        guard entries.count<R548ResearchArchive.maximumMembers,
              names.count==Set(names).count,!names.contains(memberName) else{return entries}
        var status="HOLD_SOURCE_MISSING_OR_CONTRADICTORY"
        var frames=[[String:Any]]()
        if let original=entries.first(where:{$0.name=="r608_original_pixel_evidence.json"}),
           let ocr=entries.first(where:{$0.name=="r609_vision_text_spatial_evidence.json"}),
           let readiness=entries.first(where:{$0.name=="r613_r616_integrated_readiness.json"}),
           [original,ocr,readiness].allSatisfy({$0.bytes.count<=160_000}),
           let r8=(try? JSONSerialization.jsonObject(with:original.bytes)) as? [String:Any],
           let r9=(try? JSONSerialization.jsonObject(with:ocr.bytes)) as? [String:Any],
           let r16=(try? JSONSerialization.jsonObject(with:readiness.bytes)) as? [String:Any],
           verifiedHoldFlags(r8),verifiedHoldFlags(r9),verifiedHoldFlags(r16),
           r8["schema"] as? String=="trueplan.r608.raw_png_visual_evidence.v1",
           r9["schema"] as? String=="trueplan.r609.vision_text_spatial_evidence.v1",
           r16["schema"] as? String=="trueplan.r613-r616.integrated_readiness.v1",
           let rows8=r8["bindings"] as? [[String:Any]],rows8.count<=8,
           let rows9=r9["bindings"] as? [[String:Any]],rows9.count<=3,
           !rows9.isEmpty {
            var map8=[String:[String:Any]]()
            for row in rows8 {
                guard let id=key(row),map8[id]==nil else {status="HOLD_DUPLICATE_FRAME";break}
                map8[id]=row
            }
            if status=="HOLD_SOURCE_MISSING_OR_CONTRADICTORY" {
                status="HOLD_ROTATION_SWEEP_RESEARCH_NOT_ACTOR_CERTIFICATION"
                var seen=Set<String>(),images=Set<String>(),digests=Set<String>()
                for row in rows9.prefix(maxFrames) {
                    guard let id=key(row),seen.insert(id).inserted,
                          let other=map8[id],
                          let filename=row["archive_png"] as? String,safeName(filename),
                          other["archive_png"] as? String==filename,
                          images.insert(filename).inserted,
                          let sha=row["original_png_sha256"] as? String,validSHA(sha),
                          other["original_png_sha256"] as? String==sha,
                          digests.insert(sha).inserted,
                          other["png_ihdr_crc_verified"] as? Bool==true,
                          other["decoded_pixels_verified"] as? Bool==true,
                          let png=entries.first(where:{$0.name==filename}),
                          png.bytes.count<=maxInputBytes,
                          R598OneButtonFormAttachment.testDigest(png.bytes)==sha else {
                        frames=[];status="HOLD_FRAME_IMAGE_OR_HASH_CONTRADICTION";break
                    }
                    let (probes,scanStatus)=rotationOCR(png.bytes)
                    frames.append(["epoch":row["epoch"]!,"frame_id":row["frame_id"]!,
                         "archive_png":filename,"original_png_sha256":sha,
                         "orientation_probes":probes,"scan_status":scanStatus])
                }
            }
        }
        let pairs=continuity(frames)
        let report:[String:Any]=[
            "schema":"trueplan.r617-r620.rotation_readout.v1",
            "status":status,"frames":frames,"r617_frame_count":frames.count,
            "r618_coordinate_system":"BOTTOM_LEFT_NORMALIZED_PER_ORIENTATION_HYPOTHESIS",
            "r619_location_only_links":pairs,
            "r620_evidence_scope":["target_fields":79,"certified_fields":0,
                 "owner_assignment":"UNKNOWN","display_orientation":"UNKNOWN",
                 "megas":"UNKNOWN","sample_frame_cap":maxFrames,
                 "scanner_does_not_make_battle_recommendations":true],
            "certified_for_battle":false,"owner_verified":false,"roi_verified":false,
            "mega_verified":false,"display_orientation_verified":false,
            "limitations":"Vision OCR orientation hypotheses only; strings and proximity are not actors, HP, PP, turn, Mega or battle truth."]
        guard let data=try? JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),
              data.count<=maxJSONBytes else{return entries}
        return entries+[.init(name:memberName,bytes:data)]
    }
}
