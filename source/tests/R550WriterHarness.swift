import Foundation

@main
struct R550WriterHarness {
  static func main() throws {
    let dir=URL(fileURLWithPath:NSTemporaryDirectory(),isDirectory:true)
    let destination=dir.appendingPathComponent("R550Test-\(UUID().uuidString).zip")
    defer { try? FileManager.default.removeItem(at:destination) }
    let files=[
      R548ResearchArchive.Entry(name:"manifest.json",bytes:Data("{\"gate\":\"HOLD\"}".utf8)),
      R548ResearchArchive.Entry(name:"frame_001.png",bytes:Data((0..<2000).map { UInt8($0 % 251) })),
      R548ResearchArchive.Entry(name:"ocr.json",bytes:Data("[]".utf8))
    ]
    let written=try R548ResearchArchive.write(files,to:destination)
    let actual=try Data(contentsOf:destination)
    guard written==actual.count, written>0 else {fatalError("R550_WRITER_SIZE_INCONSISTENT")}
    let receipt=try R549ZipReadback.verify(
      archiveURL:destination,
      expectedFiles:Dictionary(uniqueKeysWithValues:files.map { ($0.name,$0.bytes) }))
    guard receipt.entryCount==3 && receipt.entrySHA256.count==3 else {fatalError("R550_WRITER_READBACK_FAILURE")}
    // Reject destinations already containing an archive; do not overwrite evidence.
    do { _=try R548ResearchArchive.write(files,to:destination)
      fatalError("R550_WRITER_OVERWROTE_EXISTING")
    } catch R548ResearchArchive.Error.invalidArchive { }
    // A non-printable or traversal name must never enter the evidence archive.
    let invalid=dir.appendingPathComponent("R550Invalid-\(UUID().uuidString).zip")
    do { _=try R548ResearchArchive.write([.init(name:"../escape",bytes:Data())],to:invalid)
      fatalError("R550_WRITER_ACCEPTED_TRAVERSAL")
    } catch R548ResearchArchive.Error.duplicate { }
    guard !FileManager.default.fileExists(atPath:invalid.path) else {fatalError("R550_INVALID_ARCHIVE_CREATED")}
    print("PASS_R550_REAL_WRITER_READBACK_EXISTING_AND_UNSAFE_PATH")
  }
}
