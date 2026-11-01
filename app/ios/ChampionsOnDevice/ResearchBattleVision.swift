import Foundation
import UIKit
import Vision
import CryptoKit

// Local-only manual diagnostic on the exact displayed selected frame.
// The single-frame ROI profile is unvalidated on other layouts/resolutions.
enum ResearchBattleVision {
    static let productionEnabled = false
    // The background stream must not repeat CPU-expensive HP/gender crop OCR.
    // Manual research on a selected past frame retains the detailed checks.
    enum InspectionMode { case automaticFirstPass, manualDetailed }
    static func inspect(png: Data, battleID: String, epoch: Int, frame: Int,
                        turn: Int?, observedMs: Int64,
                        mode: InspectionMode = .manualDetailed,work: R551EvidenceWork?=nil) throws -> (String,[String]) {
        // Decode the exact hashed/exported bytes. A UIImage metadata rotation
        // must never silently differ from the physical CGImage submitted to Vision.
        guard frame>0,epoch>0,observedMs>0,!battleID.isEmpty else {throw Failure.invalidImage}
        let decoded=try R558FullFrameOCR.decodePNG(png,work:work)
        let cg=decoded.image,hash=decoded.sha256
        var readings = [ResearchReading]()
        var lines = [String]()
        let aspect = Double(cg.width)/Double(cg.height)
        if mode == .manualDetailed && abs(aspect - 578.0/267.0) < 0.025 {
            // Geometry is calibrated to ONE diagnostic 578x267 display sample,
            // not certified for different content, scaling or battle UI layouts.
            let hpROIs:[(String,CGRect)] = [
                ("own",CGRect(x:92.0/578.0,y:240.0/267.0,width:47.0/578.0,height:18.0/267.0)),
                ("opp",CGRect(x:481.0/578.0,y:25.0/267.0,width:46.0/578.0,height:18.0/267.0))
            ]
            for (side,roi) in hpROIs {
                guard let crop=cropImage(cg,relative:roi) else { continue }
                let primary=(try recognize(crop,work:work)).map(\.0).joined()
                // Bilinear magnification is an OCR aid only; unlike inferred
                // 110/185 from 170/185, it never fabricates a numeric value.
                let enlargedCG=enlarge(crop,scale:3)
                let enlarged=try enlargedCG.map { try recognize($0,work:work).map(\.0).joined() }
                // R27.470: owner ROI, clock provenance and epoch cannot yet be
                // independently attested. Do not turn visual diagnostics into
                // own/opp state. Preserve raw OCR via inspectStrict readings.
                let hpContext = ResearchHPContext(owner: side,
                    ownerROIAttested: false, frameAgeMs: nil,
                    epochConsistent: false, liveTurnKnown: turn != nil)
                let audit=ResearchHPCandidateConsensus.inspectStrict(
                    [primary,enlarged ?? ""],side:side,context:hpContext)
                readings += audit.readings
                lines.append("\(side) HP独立候補：標準=\(primary.isEmpty ? "未検出" : primary)／拡大=\(enlarged ?? "変換失敗")／\(audit.status)／帰属未認証")
                // R27.472 extra diagnostic: only when the original two OCR passes
                // failed to read a valid full HP token, and ONLY in own-side
                // manual research mode. This never changes inspectStrict or its
                // safety HOLD, never changes owner or numeric Battle State.
                if side == "own" && !ResearchHPSplitDiagnostic.hasLiteralSlashHP(primary)
                    && !ResearchHPSplitDiagnostic.hasLiteralSlashHP(enlarged ?? ""),
                   let splitPlan=ResearchHPSplitPlan.own(
                       calibratedLandscapeAspect:abs(aspect - 578.0/267.0)<0.025,
                       roiWidth:crop.width,roiHeight:crop.height) {
                    func rectangle(_ r:ResearchHPSplitRect) -> CGRect {
                        CGRect(x:CGFloat(r.x),y:CGFloat(r.y),
                               width:CGFloat(r.width),height:CGFloat(r.height))
                    }
                    if let left=cropImage(crop,relative:rectangle(splitPlan.numerator)),
                       let right=cropImage(crop,relative:rectangle(splitPlan.denominator)) {
                        // Exactly two additional bounded OCR requests, only in
                        // manual diagnostics after conventional HP OCR has failed.
                        let leftOCR=try recognize(enlarge(left,scale:3) ?? left,work:work).map(\.0).joined()
                        let rightOCR=try recognize(enlarge(right,scale:3) ?? right,work:work).map(\.0).joined()
                        let result=ResearchHPSplitDiagnostic.inspectOwn(
                            leftRaw:leftOCR,rightRaw:rightOCR,roiProfileAvailable:true)
                        if let candidate=ResearchHPSplitDiagnostic.diagnosticReading(result) {
                            readings.append(candidate)
                            lines.append("own HP分割研究候補：\(candidate.value)／未認証・Battle State未使用")
                        } else {
                            lines.append("own HP分割研究候補：不成立・HOLD")
                        }
                    }
                }
            }
            // Symbol-specific ROIs do NOT infer gender from the Pokemon name,
            // colour of the HP gauge, nor the opponent's gender.
            let sexROIs:[(String,CGRect)] = [
                ("own",CGRect(x:130.0/578.0,y:215.0/267.0,width:25.0/578.0,height:27.0/267.0)),
                ("opp",CGRect(x:515.0/578.0,y:4.0/267.0,width:26.0/578.0,height:28.0/267.0))
            ]
            for (side,roi) in sexROIs {
                guard let crop=cropImage(cg,relative:roi) else { continue }
                let symbolImage=enlarge(crop,scale:3) ?? crop
                let all=try recognize(symbolImage,work:work)
                let textSymbol=all.compactMap { ResearchGenderCandidates.observed($0.0,side:side) }.first
                let pixelSymbol=rgbaBytes(crop).flatMap { ResearchGenderGlyphProbe.inspect(
                    rgba:$0,width:crop.width,height:crop.height,side:side) }
                if let textSymbol { readings.append(textSymbol) }
                if let pixelSymbol {
                    // Diagnostic only: key=nil; never assign a certified party gender.
                    readings.append(ResearchReading(key:nil,value:.string(pixelSymbol.literal),
                        raw_text:"white-glyph-shape:\(pixelSymbol.literal)",confidence:nil,
                        reason:"UNVERIFIED_GENDER_SHAPE_CANDIDATE_"+side.uppercased()))
                }
                let conflicting=(textSymbol != nil && pixelSymbol != nil &&
                    textSymbol?.raw_text != pixelSymbol?.literal)
                let label=conflicting ? "OCRと画像形状不一致・HOLD" :
                    "文字=\(textSymbol?.raw_text ?? "未検出")／形状=\(pixelSymbol?.literal ?? "未検出")"
                lines.append("\(side) 性別アイコン候補：\(label)／未認証")
            }
        } else if mode == .manualDetailed {
            lines.append("HP・性別ROI：画面比率不一致・HOLD")
        } else {
            lines.append("自動フレーム：HP・性別の追加OCRを省略／全画面一次OCRのみ／所有者未認証")
        }
        // R530: reuse bounding boxes from the SAME full-frame Vision request.
        // No second full-frame OCR, no 85ms blocking Vision sidecar.
        let fullFrame=try R558FullFrameOCR.inspect(decoded:decoded,session:battleID,frame:Int64(frame),epoch:Int64(epoch),
            observedMs:observedMs,speedPriority:mode == .automaticFirstPass,work:work)
        if fullFrame.audit.execution_audit?.attempt_count==2 {lines.append("文字認識を1回再試行しました")}
        let located=fullFrame.tokens.map {($0.text,$0.confidence,$0.rect,$0.alternatives)}
        // A subtype is only a provisional UI observation, not a legal-action authorization.
        // Classify only OCR rows that will be preserved, with source-bound ROIs.
        let bound=located.filter {$0.2 != nil}
        let screenKind=R557ScreenEvidence.decide(primary:bound.map {$0.0},
            allVariants:bound.flatMap {$0.3.map(\.raw_text)}).kind
        lines.append("画面分類候補：\(screenKind)／未認証")
        for row in fullFrame.readings {
            readings.append(row)
            if let alias=ResearchNameCandidates.diagnostic(row.raw_text) {readings.append(alias)}
        }
        if fullFrame.audit.truncated_region_count>0 || !fullFrame.audit.omitted_observations.isEmpty || fullFrame.audit.unbound_roi_count>0 {
            lines.append("文字または位置情報の一部を取得できませんでした。未確認の項目は確定しません")
        }
        lines.append("状態異常・能力ランク・ログ：帰属とターンの確認待ち")
        let now=Int64(ProcessInfo.processInfo.systemUptime*1000)
        // R27.473: publication-time provenance fence. These timestamps are
        // locally recorded, but their common clock domain has not been
        // independently attested. Never authorize a turn or inferred owner.
        let receipt=ResearchFrameStamp(battleID:battleID,epoch:epoch,frameID:frame,
            observedMs:observedMs,receivedMs:now)
        let receiptResult=ResearchFrameHistoryRegistry.selected.inspectSelectedFrame(receipt)
        readings.append(ResearchObservationFence.diagnostic(receiptResult,
            rawObservedMs:observedMs,rawReceivedMs:now))
        lines.append("フレーム鮮度・時計領域：\(receiptResult.verdict.rawValue)／未認証")
        // Reject ANY future bug that emits a certified-looking key from this
        // research-only pathway, regardless of apparent OCR confidence.
        guard ResearchObservationFence.allReadingsProvisional(readings) else {
            throw Failure.invalidJSON
        }
        var packet=ResearchBattlePacket(battle_id:battleID,epoch:epoch,frame_id:frame,turn:turn,
            observed_at_ms:observedMs,received_at_ms:now,image_sha256:hash,
            source_ref:"device-local:selected-frame:\(frame)",screen_kind:screenKind,readings:readings)
        packet.ocr_engine_version=R558FullFrameOCR.engineVersion
        packet.ocr_request_audit=fullFrame.audit
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys,.withoutEscapingSlashes]
        let data=try encoder.encode(packet)
        guard let raw=String(data:data,encoding:.utf8) else { throw Failure.invalidJSON }
        let envelope:[String:String]=["schema":"trueplan.mobile-envelope.v1","payload_json":raw,
             "payload_sha256":SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()]
        let result=try JSONSerialization.data(withJSONObject:envelope,options:[.sortedKeys,.withoutEscapingSlashes])
        guard let json=String(data:result,encoding:.utf8) else { throw Failure.invalidJSON }
        return (json,lines)
    }
    private static func rgbaBytes(_ source:CGImage) -> [UInt8]? {
        let w=source.width,h=source.height
        guard w >= 90,h >= 90,w <= 400,h <= 400 else { return nil }
        var pixels=[UInt8](repeating:0,count:w*h*4)
        let success=pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let base=buffer.baseAddress,let context=CGContext(data:base,
                width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,
                space:CGColorSpaceCreateDeviceRGB(),
                bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue |
                    CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(source,in:CGRect(x:0,y:0,width:CGFloat(w),height:CGFloat(h)))
            return true
        }
        return success ? pixels : nil
    }
    private static func cropImage(_ source:CGImage,relative: CGRect) -> CGImage? {
        let rect=CGRect(x:relative.minX*CGFloat(source.width),
            y:relative.minY*CGFloat(source.height),
            width:relative.width*CGFloat(source.width),
            height:relative.height*CGFloat(source.height)).integral
        guard rect.minX >= 0, rect.minY >= 0,
              rect.maxX <= CGFloat(source.width),rect.maxY <= CGFloat(source.height),
              rect.width > 0,rect.height > 0 else { return nil }
        return source.cropping(to:rect)
    }
    private static func enlarge(_ source:CGImage,scale:Int) -> CGImage? {
        guard scale > 1,scale <= 4,
              source.width <= 1024,source.height <= 1024 else { return nil }
        let format=UIGraphicsImageRendererFormat()
        format.scale=1;format.opaque=true
        let size=CGSize(width:CGFloat(source.width*scale),height:CGFloat(source.height*scale))
        let scaled=UIGraphicsImageRenderer(size:size,format:format).image { context in
            context.cgContext.interpolationQuality = .high
            UIImage(cgImage:source).draw(in:CGRect(origin:.zero,size:size))
        }
        return scaled.cgImage
    }
    private static func recognizeLocated(_ image:CGImage,speedPriority:Bool=false,
                                         work:R551EvidenceWork?=nil) throws -> [(String,Float,TP530VisionRect.Rect?,[ResearchTextAlternative])] {
        try R558FullFrameOCR.recognizeImage(image,speedPriority:speedPriority,work:work).tokens.map {
            ($0.text,$0.confidence,$0.rect,$0.alternatives)
        }
    }
    private static func recognize(_ image:CGImage,work:R551EvidenceWork?=nil) throws -> [(String,Float)] {
        try recognizeLocated(image,work:work).map {($0.0,$0.1)}
    }
    enum Failure:Error { case invalidImage, invalidJSON }
}

