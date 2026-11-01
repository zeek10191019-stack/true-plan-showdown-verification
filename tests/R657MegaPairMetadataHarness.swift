import Foundation
@main struct R657MegaPairMetadataHarness {
    static func main() {
        var n = 0
        func check(_ ok: Bool, _ name: String) {
            guard ok else { fatalError("R657_" + name) }
            n += 1
        }
        let good = "PIXEL_GEOMETRY_ONLY_NOT_FORM_CERTIFICATION"
        func result(_ ori: Int?,_ w: Int = 512,_ h: Int = 256,
                    _ bytes: Int = 12345) -> String {
            R657MegaPairMetadataGate.audit(orientation: ori,
                width: w,height: h,byteCount: bytes)
        }
        check(result(nil) == good,"nil_exif_default_up")
        check(result(1) == good,"exif_up")
        for i in 2...8 {
            check(result(i) == "HOLD_EXIF_ORIENTATION_NOT_UP",
                  "reject_non_up_\(i)")
        }
        check(result(0) == "HOLD_EXIF_ORIENTATION_NOT_UP",
              "invalid_orientation_zero")
        check(result(9) == "HOLD_EXIF_ORIENTATION_NOT_UP",
              "invalid_orientation_nine")
        check(result(1,255) == "HOLD_IMAGE_GEOMETRY","width_low")
        check(result(1,4097) == "HOLD_IMAGE_GEOMETRY","width_high")
        check(result(1,512,191) == "HOLD_IMAGE_GEOMETRY","height_low")
        check(result(1,512,4097) == "HOLD_IMAGE_GEOMETRY","height_high")
        check(result(1,512,256,44) == "HOLD_IMAGE_BYTES","bytes_low")
        check(result(1,512,256,12*1024*1024+1) == "HOLD_IMAGE_BYTES","bytes_high")
        check(result(1,256,192,45) == good,"lower_boundary")
        check(result(1,4096,4096,12*1024*1024) == good,"upper_boundary")
        print("R657_METADATA_GATE_PASS",n)
    }
}
