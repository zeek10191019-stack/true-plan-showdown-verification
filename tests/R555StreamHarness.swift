import Foundation
import CryptoKit

@main struct R555StreamHarness {
    static func main() throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let report=URL(fileURLWithPath:CommandLine.arguments[2])
        var checks=0,negativeCases=[String]()
        func check(_ value: @autoclosure ()->Bool,_ reason: String) {
            guard value() else {fatalError("R555_CHECK_FAILED_"+reason)};checks+=1
        }
        func sha(_ data: Data) -> String {SHA256.hash(data:data).map {String(format:"%02x",$0)}.joined()}
        func u16(_ data: Data,_ offset: Int) -> Int {Int(data[offset]) | (Int(data[offset+1])<<8)}
        func u32(_ data: Data,_ offset: Int) -> Int {
            Int(data[offset]) | (Int(data[offset+1])<<8) | (Int(data[offset+2])<<16) | (Int(data[offset+3])<<24)
        }
        var stress=Data()
        let pattern=Data((0..<256).map {UInt8($0)})
        for _ in 0..<16384 {stress.append(pattern)}
        stress.append(Data(repeating:0x55,count:17))
        var entries=try ["selected_evidence.json","capture_manifest.json","frames/frame_17.png"].map {
            R548ResearchArchive.Entry(name:$0,bytes:try Data(contentsOf:root.appendingPathComponent($0)))
        }
        entries.append(.init(name:"synthetic_streaming_stress.bin",bytes:stress))
        entries=try R551EvidenceIntegrity.appendingIndex(entries,captureSessionID:"capture-test",frame:17,epoch:3,appVersion:"0.5.55",appBuild:"555")
        let files=Dictionary(uniqueKeysWithValues:entries.map {($0.name,$0.bytes)})
        let destination=root.appendingPathComponent("r555_stream.zip")
        var maximumWrite=0
        let bytes=try R548ResearchArchive.write(entries,to:destination,onChunkWritten:{maximumWrite=max(maximumWrite,$0)})
        let streaming=try R555StoredZIPReadback.verify(archiveURL:destination,expectedFiles:files)
        let generic=try R549ZipReadback.verify(archiveURL:destination,expectedFiles:files)
        let original=try Data(contentsOf:destination)
        check(bytes==original.count,"actual archive size")
        check(maximumWrite<=65536 && maximumWrite==65536,"bounded write requests")
        check(streaming.maximumReadRequestBytes==65536,"bounded read requests")
        check(streaming.archiveSHA256==generic.archiveSHA256 && streaming.archiveSHA256==sha(original),"independent generic and streaming archive hash")
        check(streaming.entrySHA256==generic.entrySHA256 && streaming.entryCount==files.count,"every original entry hash")
        let stressCRC=try R555StoredZIPReadback.checksum(stress,work:nil)
        check(stressCRC==R548ResearchArchive.crc32(stress),"incremental checksum agrees")

        let central=u32(original,original.count-6),firstBody=30+u16(original,26)
        func rejects(_ data: Data,_ reason: String,expected: [String:Data]?=nil) throws {
            let url=root.appendingPathComponent("negative_\(negativeCases.count).zip")
            try data.write(to:url)
            do {_=try R555StoredZIPReadback.verify(archiveURL:url,expectedFiles:expected ?? files);fatalError("R555_ACCEPTED_"+reason)}
            catch {negativeCases.append(reason);checks+=1}
            try FileManager.default.removeItem(at:url)
        }
        try rejects(Data(original.dropLast()),"truncated")
        var altered=original;altered.append(0);try rejects(altered,"trailing")
        altered=Data([0]);altered.append(original);try rejects(altered,"prefixed")
        altered=original;altered[firstBody]^=1;try rejects(altered,"persisted CRC corruption")
        altered=original;altered[14]^=1;try rejects(altered,"local CRC mismatch")
        altered=original;altered[central+16]^=1;try rejects(altered,"central CRC mismatch")
        altered=original;altered[central+8]=1;try rejects(altered,"encrypted flag")
        altered=original;altered[central+10]=8;try rejects(altered,"unsupported DEFLATE own-format")
        altered=original;altered[central+41]=0xa0;try rejects(altered,"symlink external attributes")
        altered=original;altered[central+6]=45;try rejects(altered,"unsupported central version")
        altered=original;altered[4]=45;try rejects(altered,"unsupported local version")
        altered=original;altered[central+30]=1;try rejects(altered,"unsupported central extra")
        altered=original;altered[28]=1;try rejects(altered,"unsupported local extra")
        altered=original;altered[central+42]=1;try rejects(altered,"unreferenced local prefix")
        altered=original;altered[30]^=1;try rejects(altered,"local name mismatch")
        altered=original;altered[original.count-12]=0;try rejects(altered,"wrong end entry count")
        var wrong=files;var wrongData=wrong["selected_evidence.json"]!;wrongData[wrongData.startIndex]^=1
        wrong["selected_evidence.json"]=wrongData
        try rejects(original,"original SHA mismatch with valid ZIP CRC",expected:wrong)
        wrong=files;wrong.removeValue(forKey:"selected_evidence.json");try rejects(original,"missing expected member",expected:wrong)
        wrong=files;wrong["extra"]=Data();try rejects(original,"extra expected member",expected:wrong)
        try rejects(original,"empty expectation",expected:[:])
        try rejects(original,"unsafe expectation",expected:["../outside":Data()])
        let symlink=root.appendingPathComponent("readback_symlink.zip")
        try FileManager.default.createSymbolicLink(at:symlink,withDestinationURL:destination)
        do {_=try R555StoredZIPReadback.verify(archiveURL:symlink,expectedFiles:files);fatalError("SYMLINK_ACCEPTED")}
        catch {checks+=1;negativeCases.append("symlink refused")}
        let directory=root.appendingPathComponent("not_regular.zip",isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false)
        do {_=try R555StoredZIPReadback.verify(archiveURL:directory,expectedFiles:files);fatalError("DIRECTORY_ACCEPTED")}
        catch {checks+=1;negativeCases.append("directory refused")}
        let other=root.appendingPathComponent("foreign-file.bin");try original.write(to:other)
        let foreign=try FileHandle(forReadingFrom:other)
        do {_=try R555StoredZIPReadback.verify(archiveURL:destination,expectedFiles:files,expectedDescriptor:foreign.fileDescriptor);fatalError("FOREIGN_DESCRIPTOR_ACCEPTED")}
        catch {checks+=1;negativeCases.append("foreign writer descriptor")}
        try foreign.close()

        let cancelled=R551EvidenceWork();cancelled.cancel()
        let before=root.appendingPathComponent("cancel_before.zip")
        do {_=try R548ResearchArchive.write(entries,to:before,work:cancelled);fatalError("CANCEL_BEFORE_ACCEPTED")}
        catch R551EvidenceWork.Failure.cancelled {checks+=1}
        check(!FileManager.default.fileExists(atPath:before.path),"cancel before creates no file")
        let writing=R551EvidenceWork(),partial=root.appendingPathComponent("cancel_partial.zip")
        do {
            _=try R548ResearchArchive.write(entries,to:partial,work:writing,onChunkWritten:{if $0==65536 {writing.cancel()}})
            fatalError("CANCEL_DURING_ACCEPTED")
        } catch R551EvidenceWork.Failure.cancelled {checks+=1}
        check(!FileManager.default.fileExists(atPath:partial.path),"cancel during removes own partial file")
        let reading=R551EvidenceWork()
        do {_=try R555StoredZIPReadback.verify(archiveURL:destination,expectedFiles:files,work:reading,onRead:{if $0==65536 {reading.cancel()}});fatalError("CANCEL_READ_ACCEPTED")}
        catch R551EvidenceWork.Failure.cancelled {checks+=1}
        let afterReadCancel=try Data(contentsOf:destination)
        check(afterReadCancel==original,"read cancellation preserves completed source")

        let replaced=root.appendingPathComponent("replaced_during_write.zip")
        let replacement=Data("replacement belongs to another operation".utf8)
        var didReplace=false
        do {
            _=try R548ResearchArchive.write(entries,to:replaced,onChunkWritten:{count in
                if count==65536 && !didReplace {
                    do {try FileManager.default.removeItem(at:replaced);try replacement.write(to:replaced);didReplace=true}
                    catch {fatalError("REPLACEMENT_FIXTURE_FAILED")}
                }
            })
            fatalError("REPLACED_OUTPUT_ACCEPTED")
        } catch {checks+=1}
        check(didReplace,"replacement interleaving exercised")
        let retainedReplacement=try Data(contentsOf:replaced)
        check(retainedReplacement==replacement,"failure cleanup cannot delete replacement")

        let mutated=root.appendingPathComponent("mutated_during_read.zip");try original.write(to:mutated)
        var local=0,stressBody=0
        for _ in entries {
            let n=u16(original,local+26),size=u32(original,local+18)
            let name=String(data:original.subdata(in:local+30..<local+30+n),encoding:.utf8)!
            if name=="synthetic_streaming_stress.bin" {stressBody=local+30+n}
            local+=30+n+size
        }
        var didMutate=false,mutationRejected=false
        do {
            _=try R555StoredZIPReadback.verify(archiveURL:mutated,expectedFiles:files,onRead:{count in
                if count==65536 && !didMutate {
                    do {
                        let writer=try FileHandle(forWritingTo:mutated)
                        try writer.seek(toOffset:UInt64(stressBody));try writer.write(contentsOf:Data([0xff]));try writer.synchronize();try writer.close()
                        didMutate=true
                    } catch {fatalError("MUTATION_FIXTURE_FAILED")}
                }
            })
            fatalError("MUTATING_SOURCE_ACCEPTED")
        } catch R555StoredZIPReadback.Failure.invalid(let reason) {mutationRejected=reason=="FILE_CHANGED_DURING_READBACK";checks+=1}
        check(didMutate && mutationRejected,"in-place mutation rejected even after block was read")

        let sliced=stress[11..<1000]
        let slicedURL=root.appendingPathComponent("sliced_data.zip")
        _=try R548ResearchArchive.write([.init(name:"slice.bin",bytes:sliced),.init(name:"empty.bin",bytes:Data())],to:slicedURL)
        let sliceReceipt=try R555StoredZIPReadback.verify(archiveURL:slicedURL,expectedFiles:["slice.bin":sliced,"empty.bin":Data()])
        check(sliceReceipt.entrySHA256["slice.bin"]==sha(Data(sliced)),"nonzero Data slice indices")
        check(sliceReceipt.entrySHA256["empty.bin"]==sha(Data()),"zero-byte STORE member")
        let caseURL=root.appendingPathComponent("case_collision.zip")
        do {_=try R548ResearchArchive.write([.init(name:"a.txt",bytes:Data()),.init(name:"A.txt",bytes:Data())],to:caseURL);fatalError("CASE_COLLISION_ACCEPTED")}
        catch {checks+=1}
        check(!FileManager.default.fileExists(atPath:caseURL.path),"case collision rejected before creation")
        for path in ["dir//file","dir/./file","/absolute","../escape"] {
            do {_=try R548ResearchArchive.write([.init(name:path,bytes:Data())],to:caseURL);fatalError("UNSAFE_NAME_ACCEPTED")}
            catch {checks+=1}
        }
        let object:[String:Any]=["schema":"trueplan.r555.native-stream-audit.v1","archive_sha256":streaming.archiveSHA256,
            "entry_sha256":streaming.entrySHA256,"entry_count":streaming.entryCount,"archive_bytes":bytes,
            "stress_payload_bytes":stress.count,"maximum_read_request_bytes":streaming.maximumReadRequestBytes,
            "maximum_write_request_bytes":maximumWrite,"checks":checks,"negative_cases":negativeCases,
            "read_cancel_preserves_source":true,"write_cancel_removes_partial":true,
            "replacement_cleanup_preserves_foreign_file":true,"mutation_rejected":true,
            "game_accuracy_certified":false,"device_certified":false]
        try JSONSerialization.data(withJSONObject:object,options:[.sortedKeys]).write(to:report)
        print("R555_NATIVE_STREAM_CHECKS_PASS=\(checks)")
    }
}
