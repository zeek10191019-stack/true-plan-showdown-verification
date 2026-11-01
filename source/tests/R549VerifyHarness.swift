import Foundation

// A macOS Swift test harness for the exact iOS validator. Fixtures are created
// by independent Python zipfile, not by R549's writer.
@main
struct R549VerifyHarness {
    static func main() throws {
        let dir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let originals = [
            "manifest.json": try Data(contentsOf: dir.appendingPathComponent("manifest.json")),
            "frame_001.png": try Data(contentsOf: dir.appendingPathComponent("frame_001.png")),
            "ocr.json": try Data(contentsOf: dir.appendingPathComponent("ocr.json"))
        ]
        var passed = 0
        for name in ["valid-stored", "valid-deflated", "valid-descriptor"] {
            let receipt = try R549ZipReadback.verify(
                archiveURL: dir.appendingPathComponent(name + ".zip"), expectedFiles: originals)
            guard receipt.entryCount == originals.count,
                  receipt.entrySHA256.count == originals.count,
                  receipt.archiveSHA256.count == 64 else { fatalError("FAIL_" + name) }
            print("PASS " + name)
            passed += 1
        }
        for name in ["truncated", "corrupted", "missing", "duplicate", "unsafe", "extra", "bad-count", "trailing", "encrypted-flag"] {
            do {
                _ = try R549ZipReadback.verify(
                    archiveURL: dir.appendingPathComponent(name + ".zip"), expectedFiles: originals)
                fatalError("FAIL_ACCEPTED_" + name)
            } catch R549ZipReadback.VerificationError.invalid(let reason) {
                print("PASS_REJECT " + name + " " + reason)
                passed += 1
            } catch {
                // Foundation read errors for truncated/malformed files are also fail closed.
                print("PASS_REJECT " + name + " " + String(describing: error))
                passed += 1
            }
        }
        var changed = originals
        var tamperedExpected = originals["ocr.json"]!
        tamperedExpected[tamperedExpected.startIndex] ^= 1 // Same length, valid ZIP CRC, wrong SHA.
        changed["ocr.json"] = tamperedExpected
        do {
            _ = try R549ZipReadback.verify(archiveURL: dir.appendingPathComponent("valid-stored.zip"), expectedFiles: changed)
            fatalError("FAIL_ACCEPTED_SOURCE_SHA_MISMATCH")
        } catch { passed += 1; print("PASS_REJECT changed-original") }
        print("R549_ZIP_GATE_LOCAL_PASS \(passed)/13")
    }
}
