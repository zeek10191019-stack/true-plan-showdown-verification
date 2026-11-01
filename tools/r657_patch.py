from pathlib import Path

base=Path('app/ios/ChampionsOnDevice')
p=base/'R656MegaVisionPair.swift'
s=p.read_text('utf-8')
anchor='''        return image
    }
    private static func printFor'''
assert s.count(anchor)==1,'R657_DECODE_ANCHOR_NOT_UNIQUE'
insert='''        let meta=CGImageSourceCopyPropertiesAtIndex(src,0,nil)
            as? [String:Any]
        let key=kCGImagePropertyOrientation as String
        let orientation: Int?
        if let field=meta?[key] {
            guard let value=field as? NSNumber else {
                throw Failure("HOLD_BAD_EXIF_ORIENTATION")
            }
            orientation=value.intValue
        } else {
            orientation=nil
        }
        guard R657MegaPairMetadataGate.audit(
            orientation:orientation,width:image.width,
            height:image.height,byteCount:data.count) ==
            "PIXEL_GEOMETRY_ONLY_NOT_FORM_CERTIFICATION" else {
            throw Failure("HOLD_UNSUPPORTED_PNG_ORIENTATION")
        }
        return image
    }
    private static func printFor'''
s=s.replace(anchor,insert,1)
anchor='''            "width": beforeImage.width,
            "height": beforeImage.height,'''
assert s.count(anchor)==1,'R657_REPORT_ANCHOR'
s=s.replace(anchor,anchor+'''
            "pixel_orientation": "UP_OR_METADATA_ABSENT",
            "image_crop_scale": "SCALE_FILL_UNCALIBRATED",
            "metadata_gate": R657MegaPairMetadataGate.schema,
            "pair_provenance": "UNVERIFIED_TWO_MANUAL_PNGS",''',1)
p.write_text(s,'utf-8')

p=base/'R656MegaVisionPanel.swift'
s=p.read_text('utf-8')
anchor='''        status = "参照変更。以前の比較結果は無効"
        if before'''
assert s.count(anchor)==1,'R657_LOAD_ANCHOR'
s=s.replace(anchor,'''        status = "参照変更。以前の比較結果は無効"
        busy = false // Invalidate in-flight callback as well as spinner.
        if before''',1)
anchor='''    func clear() {
        precondition(Thread.isMainThread)
        epoch = UUID()
        beforePNG'''
assert s.count(anchor)==1,'R657_CLEAR_ANCHOR'
s=s.replace(anchor,'''    func clear() {
        precondition(Thread.isMainThread)
        epoch = UUID()
        busy = false // A cancelled worker cannot keep the UI locked.
        beforePNG''',1)
anchor='''    func run(formID: String, reviewed: Bool) {
        precondition(Thread.isMainThread)
        guard !busy,'''
assert s.count(anchor)==1,'R657_RUN_ANCHOR'
s=s.replace(anchor,'''    func invalidateControls() {
        precondition(Thread.isMainThread)
        epoch = UUID()
        busy = false
        removeReport()
        status = "形態・目視ラベル変更：旧比較結果を失効"
    }
    func run(formID: String, reviewed: Bool) {
        precondition(Thread.isMainThread)
        guard reviewed else {
            invalidateControls()
            status = "HOLD：2画像のラベル目視確認が未完了"
            return
        }
        guard !busy,''',1)
anchor='''            Toggle("2画像の前後ラベルを自分で確認",isOn:$manualReview)
            Button("③ Vision特徴量を比較してJSONを保存")'''
assert s.count(anchor)==1,'R657_UI_ANCHOR'
s=s.replace(anchor,'''            Toggle("2画像の前後ラベルを自分で確認",isOn:$manualReview)
            .onChange(of:manualReview) { _,_ in
                model.invalidateControls()
            }
            .onChange(of:targetID) { _,_ in
                model.invalidateControls()
            }
            Button("③ Vision特徴量を比較してJSONを保存")''',1)
anchor='''            }.disabled(model.busy)
            if let url = model.reportURL'''
assert s.count(anchor)==1,'R657_BUTTON_DISABLED_ANCHOR'
s=s.replace(anchor,'''            }.disabled(model.busy || !manualReview)
            if let url = model.reportURL''',1)
p.write_text(s,'utf-8')
print('R657_IOS_PATCH_APPLIED')
