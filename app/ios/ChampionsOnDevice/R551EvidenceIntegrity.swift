import Foundation
import CryptoKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// An export belongs to one selection. Cancellation never authorizes another export.
final class R551EvidenceWork {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }; return cancelled
    }
    enum Failure: Error { case cancelled }
    func check() throws { if isCancelled { throw Failure.cancelled } }
}

enum R551ExclusiveFile {
    static func create(at url: URL) throws -> FileHandle {
        // createFile/fileExists is a TOCTOU race: another writer could truncate evidence.
        let descriptor = url.path.withCString {
            open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        }
        guard descriptor >= 0 else { throw R548ResearchArchive.Error.invalidArchive }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            #if os(iOS)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: url.path)
            #endif
            return handle
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }
}

/// Portable index of every non-index member. It proves internal consistency,
/// not authenticity; a separately trusted archive SHA is needed for authenticity.
enum R551EvidenceIntegrity {
    static let indexName = "evidence_integrity.json"
    static let schema = "trueplan.screen-read.evidence-integrity.v1"
    static func appendingIndex(_ entries: [R548ResearchArchive.Entry],
                               captureSessionID: String, frame: Int64, epoch: Int64,
                               appVersion: String, appBuild: String) throws -> [R548ResearchArchive.Entry] {
        guard !captureSessionID.isEmpty, captureSessionID.count <= 128,
              frame > 0, epoch > 0, entries.count + 1 <= R548ResearchArchive.maximumMembers,
              !entries.contains(where: { $0.name == indexName }),
              Set(entries.map(\.name)).count == entries.count,
              entries.contains(where: { $0.name == "selected_evidence.json" }),
              entries.contains(where: { $0.name == "capture_manifest.json" }) else {
            throw R548ResearchArchive.Error.invalidEntry
        }
        let rows: [[String: Any]] = entries.sorted { $0.name < $1.name }.map { entry in
            ["path": entry.name, "bytes": entry.bytes.count,
             "sha256": SHA256.hash(data: entry.bytes).map { String(format: "%02x", $0) }.joined(),
             "crc32": UInt64(R548ResearchArchive.crc32(entry.bytes))]
        }
        let object: [String: Any] = [
            "schema": schema, "capture_session_id": captureSessionID,
            "battle_id": NSNull(), "selected_frame_id": frame, "selected_epoch": epoch,
            "entries": rows, "entry_count_excluding_index": rows.count,
            "self_hash_included": false, "integrity_scope": "INTERNAL_BYTE_CONSISTENCY_ONLY",
            "app_version": appVersion, "app_build": appBuild,
            "screen_read_engine_version": "r551.evidence.v1",
            "mechanics_db_version": NSNull(), "battle_advice_authorized": false,
            "device_validation_status": "DEVICE_VALIDATION_PENDING"
        ]
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        return entries + [.init(name: indexName, bytes: bytes)]
    }
}
