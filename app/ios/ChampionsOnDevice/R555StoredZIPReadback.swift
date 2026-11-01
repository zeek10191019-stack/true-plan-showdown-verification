import Foundation
import CryptoKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Strict readback for the app's own STORE-only ZIP format. Generic imported
/// DEFLATE/descriptor archives continue to use R549ZipReadback.
enum R555StoredZIPReadback {
    static let chunkBytes = 64 * 1024
    enum Failure: Error, CustomStringConvertible {
        case invalid(String)
        var description: String { switch self {case .invalid(let code):return "R555_ZIP_READBACK_"+code} }
    }
    struct Receipt {
        let entryCount: Int
        let archiveSHA256: String
        let entrySHA256: [String:String]
        let maximumReadRequestBytes: Int
    }
    private struct Stamp: Equatable {
        let device: Int64, inode: UInt64, size: Int64
        let modifiedSeconds: Int64, modifiedNanoseconds: Int64
        let changedSeconds: Int64, changedNanoseconds: Int64
    }
    private static func stamp(_ value: stat) throws -> Stamp {
        guard value.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {throw Failure.invalid("NOT_REGULAR_FILE")}
        #if canImport(Darwin)
        let modified=value.st_mtimespec,changed=value.st_ctimespec
        #else
        let modified=value.st_mtim,changed=value.st_ctim
        #endif
        return Stamp(device:Int64(value.st_dev),inode:UInt64(value.st_ino),size:Int64(value.st_size),
            modifiedSeconds:Int64(modified.tv_sec),modifiedNanoseconds:Int64(modified.tv_nsec),
            changedSeconds:Int64(changed.tv_sec),changedNanoseconds:Int64(changed.tv_nsec))
    }
    private static func descriptorStamp(_ descriptor: Int32) throws -> Stamp {
        var value=stat()
        guard fstat(descriptor,&value)==0 else {throw Failure.invalid("FSTAT")}
        return try stamp(value)
    }
    private static func pathStamp(_ url: URL) throws -> Stamp {
        var value=stat()
        guard url.path.withCString({lstat($0,&value)})==0 else {throw Failure.invalid("LSTAT")}
        return try stamp(value)
    }
    static func removeIfOwned(_ url: URL,descriptor: Int32) {
        guard let file=try? descriptorStamp(descriptor),let path=try? pathStamp(url),
              file.device==path.device,file.inode==path.inode else {return}
        try? FileManager.default.removeItem(at:url)
    }
    private final class Reader {
        let handle: FileHandle,initial: Stamp,url: URL
        let work: R551EvidenceWork?,onRead: ((Int)->Void)?
        var maximumReadRequestBytes=0
        var count: Int {Int(initial.size)}
        init(url: URL,expectedDescriptor: Int32?,work: R551EvidenceWork?,onRead: ((Int)->Void)?) throws {
            try work?.check()
            let descriptor=url.path.withCString {open($0,O_RDONLY | O_NOFOLLOW | O_NONBLOCK)}
            guard descriptor>=0 else {throw Failure.invalid("OPEN_NOFOLLOW")}
            do {
                let initial=try R555StoredZIPReadback.descriptorStamp(descriptor)
                guard initial.size>=22,initial.size<=128*1024*1024 else {throw Failure.invalid("ARCHIVE_SIZE")}
                guard try R555StoredZIPReadback.pathStamp(url)==initial else {throw Failure.invalid("PATH_CHANGED")}
                if let expectedDescriptor {
                    guard try R555StoredZIPReadback.descriptorStamp(expectedDescriptor)==initial else {throw Failure.invalid("WRITER_FILE_CHANGED")}
                }
                self.initial=initial;self.url=url;self.work=work;self.onRead=onRead
                self.handle=FileHandle(fileDescriptor:descriptor,closeOnDealloc:true)
            } catch {close(descriptor);throw error}
        }
        deinit {try? handle.close()}
        func read(at offset: Int,count requested: Int) throws -> Data {
            try work?.check()
            guard offset>=0,offset<=count,requested>=0,requested<=R555StoredZIPReadback.chunkBytes,
                  requested<=count-offset else {throw Failure.invalid("READ_RANGE")}
            maximumReadRequestBytes=max(maximumReadRequestBytes,requested)
            try handle.seek(toOffset:UInt64(offset))
            var result=Data();result.reserveCapacity(requested)
            while result.count<requested {
                try work?.check()
                let part=try autoreleasepool {try handle.read(upToCount:requested-result.count)}
                guard let part,!part.isEmpty else {throw Failure.invalid("SHORT_READ")}
                result.append(part);onRead?(part.count)
                try work?.check()
            }
            return result
        }
        func verifyUnchanged() throws {
            try work?.check()
            guard try R555StoredZIPReadback.descriptorStamp(handle.fileDescriptor)==initial,
                  try R555StoredZIPReadback.pathStamp(url)==initial else {throw Failure.invalid("FILE_CHANGED_DURING_READBACK")}
        }
    }
    private static let crcTable: [UInt32]=(0..<256).map {index in
        var value=UInt32(index)
        for _ in 0..<8 {value=(value>>1)^((value&1)==1 ? 0xedb88320 : 0)}
        return value
    }
    private static func updateCRC(_ crc: inout UInt32,_ bytes: Data) {
        for byte in bytes {crc=(crc>>8)^crcTable[Int((crc^UInt32(byte))&0xff)]}
    }
    static func checksum(_ data: Data,work: R551EvidenceWork?) throws -> UInt32 {
        var crc:UInt32=0xffffffff,offset=0
        while offset<data.count {
            try work?.check()
            let end=min(data.count,offset+chunkBytes)
            autoreleasepool {updateCRC(&crc,data.subdata(in:(data.startIndex+offset)..<(data.startIndex+end)))}
            offset=end
        }
        try work?.check();return crc^0xffffffff
    }
    private static func u16(_ data: Data,_ offset: Int) -> Int {
        Int(data[offset]) | (Int(data[offset+1])<<8)
    }
    private static func u32(_ data: Data,_ offset: Int) -> Int {
        Int(data[offset]) | (Int(data[offset+1])<<8) | (Int(data[offset+2])<<16) | (Int(data[offset+3])<<24)
    }
    private static func validPath(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count<=120 &&
        name.utf8.allSatisfy {(65...90).contains($0)||(97...122).contains($0)||(48...57).contains($0)||[45,46,47,95].contains($0)} &&
        !name.hasPrefix("/") && !name.contains("..") &&
        !name.split(separator:"/",omittingEmptySubsequences:false).contains {$0.isEmpty || $0=="."}
    }
    private struct Member {
        let name: String,nameBytes: Data
        let size: Int,crc: Int,offset: Int
    }
    static func verify(archiveURL: URL,expectedFiles: [String:Data],expectedDescriptor: Int32?=nil,
                       work: R551EvidenceWork?=nil,onRead: ((Int)->Void)?=nil) throws -> Receipt {
        guard !expectedFiles.isEmpty,expectedFiles.count<=R548ResearchArchive.maximumMembers,expectedFiles.keys.allSatisfy(validPath) else {throw Failure.invalid("EXPECTED_FILES")}
        let reader=try Reader(url:archiveURL,expectedDescriptor:expectedDescriptor,work:work,onRead:onRead)
        let end=try reader.read(at:reader.count-22,count:22)
        guard u32(end,0)==0x06054b50,u16(end,4)==0,u16(end,6)==0,u16(end,20)==0 else {throw Failure.invalid("EOCD")}
        let number=u16(end,10),central=u32(end,16),centralLength=u32(end,12)
        guard number==expectedFiles.count,u16(end,8)==number,central<=reader.count-22,
              centralLength==reader.count-22-central else {throw Failure.invalid("CENTRAL_RANGE_OR_COUNT")}
        var cursor=central,members=[Member](),seen=Set<String>(),total=0
        for _ in 0..<number {
            guard cursor<=reader.count-22-46 else {throw Failure.invalid("CENTRAL_TRUNCATED")}
            let header=try reader.read(at:cursor,count:46)
            guard u32(header,0)==0x02014b50,u16(header,4)==20,u16(header,6)==20,
                  u16(header,8)==0,u16(header,10)==0,u16(header,30)==0,u16(header,32)==0,
                  u16(header,34)==0,u16(header,36)==0,u32(header,38)==0 else {throw Failure.invalid("UNSUPPORTED_CENTRAL_FORMAT")}
            let size=u32(header,24),nameCount=u16(header,28),offset=u32(header,42)
            guard nameCount>0,nameCount<=120,cursor+46+nameCount<=reader.count-22,
                  size==u32(header,20),size<=48*1024*1024,total<=96*1024*1024-size else {throw Failure.invalid("MEMBER_SIZE")}
            let bytes=try reader.read(at:cursor+46,count:nameCount)
            guard let name=String(data:bytes,encoding:.utf8),validPath(name),seen.insert(name.lowercased()).inserted,
                  let expected=expectedFiles[name],expected.count==size else {throw Failure.invalid("UNEXPECTED_DUPLICATE_OR_UNSAFE_NAME")}
            members.append(Member(name:name,nameBytes:bytes,size:size,crc:u32(header,16),offset:offset))
            total+=size;cursor+=46+nameCount
        }
        guard cursor==reader.count-22 else {throw Failure.invalid("CENTRAL_TRAILING")}
        var next=0,verified=[String:String]()
        for member in members {
            guard member.offset==next,next<=central-30 else {throw Failure.invalid("LOCAL_OFFSET_OR_GAP")}
            let header=try reader.read(at:next,count:30)
            guard u32(header,0)==0x04034b50,u16(header,4)==20,u16(header,6)==0,u16(header,8)==0,u16(header,28)==0,
                  u32(header,14)==member.crc,u32(header,18)==member.size,u32(header,22)==member.size,
                  u16(header,26)==member.nameBytes.count else {throw Failure.invalid("LOCAL_CENTRAL_MISMATCH")}
            let body=next+30+member.nameBytes.count
            guard body<=central,member.size<=central-body,
                  try reader.read(at:next+30,count:member.nameBytes.count)==member.nameBytes else {throw Failure.invalid("LOCAL_NAME_OR_RANGE")}
            var offset=0,crc:UInt32=0xffffffff,hash=SHA256()
            while offset<member.size {
                let count=min(chunkBytes,member.size-offset)
                try autoreleasepool {
                    let block=try reader.read(at:body+offset,count:count)
                    updateCRC(&crc,block);hash.update(data:block)
                }
                offset+=count
            }
            guard Int(crc^0xffffffff)==member.crc else {throw Failure.invalid("CRC32_MISMATCH")}
            let actual=hash.finalize().map {String(format:"%02x",$0)}.joined()
            let expected=SHA256.hash(data:expectedFiles[member.name]!).map {String(format:"%02x",$0)}.joined()
            try work?.check()
            guard actual==expected else {throw Failure.invalid("SHA256_MISMATCH")}
            verified[member.name]=actual;next=body+member.size
        }
        guard next==central else {throw Failure.invalid("UNREFERENCED_LOCAL_BYTES")}
        var archiveHash=SHA256(),offset=0
        while offset<reader.count {
            let count=min(chunkBytes,reader.count-offset)
            try autoreleasepool {archiveHash.update(data:try reader.read(at:offset,count:count))}
            offset+=count
        }
        try reader.verifyUnchanged()
        return Receipt(entryCount:number,archiveSHA256:archiveHash.finalize().map {String(format:"%02x",$0)}.joined(),
            entrySHA256:verified,maximumReadRequestBytes:reader.maximumReadRequestBytes)
    }
}
