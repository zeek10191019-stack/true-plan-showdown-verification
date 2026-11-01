from pathlib import Path
path=Path('app/ios/ChampionsOnDevice/R652MegaCatalogInstaller.swift')
text=path.read_text(encoding='utf-8')
old='''        let destination = try target()
        // Data.write(.atomic) preserves the existing file on failure.
        try data.write(to: destination, options: .atomic)
        guard R595FormReferenceMatcher.loadLocalCatalog(
            at: destination).count == references.count else {
            throw reject("DESTINATION_READBACK_REJECTED")
        }
        return references.count
'''
new='''        return try transactionalStore(data, to: target(),
                                     count: references.count)
'''
assert text.count(old)==1,'R653_INSTALLER_ANCHOR_DRIFT'
text=text.replace(old,new)
needle='''    static func localCount() -> Int {
'''
transaction='''    // Pre-write validation is performed by importLocalFile.
    // Readback detects a damaged replacement and restores the old file.
    // The injected writer is for deterministic failure tests only.
    static func transactionalStore(
        _ data: Data, to destination: URL, count: Int,
        writer: (Data, URL) throws -> Void = {
            try $0.write(to: $1, options: .atomic)
        }
    ) throws -> Int {
        let fm = FileManager.default
        let existed = fm.fileExists(atPath: destination.path)
        let original = existed ? try Data(contentsOf: destination) : nil
        do {
            try writer(data, destination)
            let readback = try Data(contentsOf: destination)
            guard readback == data,
                  R595FormReferenceMatcher.loadLocalCatalog(
                    at: destination).count == count else {
                throw reject("DESTINATION_READBACK_REJECTED")
            }
            return count
        } catch {
            do {
                if let original {
                    try original.write(to: destination,
                                       options: .atomic)
                } else if fm.fileExists(atPath: destination.path) {
                    try fm.removeItem(at: destination)
                }
            } catch {
                throw reject("ROLLBACK_FAILED_CHECK_CATALOG")
            }
            throw error
        }
    }

'''
assert text.count(needle)==1,'R653_FUNCTION_ANCHOR_DRIFT'
text=text.replace(needle,transaction+needle)
path.write_text(text,encoding='utf-8')
ui=Path('app/ios/ChampionsOnDevice/ChampionsOnDeviceApp.swift')
s=ui.read_text(encoding='utf-8')
a='''                        megaCatalogStatus = "取込拒否。以前の台帳を保持"'''
b='''                        megaCatalogStatus = "取込拒否。現在の有効参照は\\(R652MegaCatalogInstaller.localCount())件。異常時は再確認"'''
assert s.count(a)==1,'R653_UI_ANCHOR_DRIFT'
s=s.replace(a,b)
ui.write_text(s,encoding='utf-8')
print('R653_TRANSACTION_PATCH_APPLIED')
