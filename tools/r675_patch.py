from pathlib import Path
p=Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
s=p.read_text()
anchor='''                        let glyphArchive:[String:Any]=['''
insert='''                        // R675: selected OCR vs historical raw-pixel HP.
                        // Cross-modal agreement is NOT a live HP or owner proof.
                        let hpCrossmodal=R675PixelOCRHPAgreement.audit(
                            ocr:bundle["r668_plain_hud_ocr"] as? [String:Any] ?? [:],
                            pixelFrames:hpFillSamples,
                            rawSHA:bundle["png_sha256"] as? String ?? "",
                            frame:frame,epoch:epoch,
                            projection:bundle["analysis_projection"] as? [String:Any])
'''
assert s.count(anchor)==1
assert 'let hpCrossmodal=R675PixelOCRHPAgreement.audit(' not in s
s=s.replace(anchor,insert+anchor)
anchor2='''                            "r672_pixel_hp_fill_tracks":hpFillSamples,'''
replacement=anchor2+'''
                            "r675_ocr_pixel_hp_agreement":hpCrossmodal,'''
assert s.count(anchor2)==1
assert '"r675_ocr_pixel_hp_agreement"' not in s
s=s.replace(anchor2,replacement)
p.write_text(s)
print('R675_CROSSMODAL_READER_ONE_TAP_INTEGRATED')
