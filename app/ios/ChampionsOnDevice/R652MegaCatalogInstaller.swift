import Foundation

/// User-initiated import of local reference candidates, not Mega proof.
/// A successful import never authorizes battle advice or verifies the label.
enum R652MegaCatalogInstaller {
    static let fileName = "R595FormReferenceCatalog.json"
    static let maximumBytes = 2_097_152
    static let maximumReferences = 512

    enum ImportError: Error {
        case invalid(String)
    }

    private static func reject(_ reason: String) -> ImportError {
        .invalid(reason)
    }

    private static func target() throws -> URL {
        guard let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask).first else {
            throw reject("APPLICATION_SUPPORT_UNAVAILABLE")
        }
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(fileName)
    }

    private static func allowed(
        species: String, form: String, mega: Bool
    ) -> Bool {
        if form == "BASE" && !mega {
            return R649MegaRegistryAudit.entries.contains {
                $0.species.uppercased() == species
            }
        }
        guard mega else { return false }
        return R649MegaRegistryAudit.entries.contains {
            $0.species.uppercased() == species &&
            (form == "MEGA" && $0.variant == "N" ||
             form == "MEGA_" + $0.variant && $0.variant != "N")
        }
    }

    /// Only a reviewed local R595 catalog is accepted. A supplied label is
    /// still a claim, never automatically a verified in-game form.
    static func importLocalFile(_ source: URL) throws -> Int {
        guard source.isFileURL else { throw reject("NOT_LOCAL_FILE") }
        #if os(iOS)
        let granted = source.startAccessingSecurityScopedResource()
        defer { if granted { source.stopAccessingSecurityScopedResource() } }
        #endif
        let meta = try source.resourceValues(
            forKeys: [.isRegularFileKey, .fileSizeKey])
        guard meta.isRegularFile == true,
              let length = meta.fileSize,
              (16...maximumBytes).contains(length) else {
            throw reject("SIZE_OR_FILE_TYPE_INVALID")
        }
        let data = try Data(contentsOf: source)
        guard (16...maximumBytes).contains(data.count),
              let dictionary = try JSONSerialization.jsonObject(
                with: data) as? [String: Any],
              dictionary["schema"] as? String ==
                R595FormReferenceMatcher.catalogSchema,
              let references = dictionary["references"] as? [[String: Any]],
              (1...maximumReferences).contains(references.count) else {
            throw reject("CATALOG_SCHEMA_OR_COUNT_INVALID")
        }
        // Use the real R595 validator, including luminance texture and SHA.
        guard R595FormReferenceMatcher.loadLocalCatalog(
            at: source).count == references.count else {
            throw reject("R595_CATALOG_REJECTED")
        }
        for reference in references {
            guard let species = reference["species_token"] as? String,
                  let form = reference["form_token"] as? String,
                  let mega = reference["mega_label_claim"] as? Bool,
                  allowed(species: species, form: form, mega: mega),
                  reference["certified_as_game_state"] as? Bool == false
            else { throw reject("FORM_NOT_IN_SEASON_REGISTRY") }
        }
        let destination = try target()
        // Data.write(.atomic) preserves the existing file on failure.
        try data.write(to: destination, options: .atomic)
        guard R595FormReferenceMatcher.loadLocalCatalog(
            at: destination).count == references.count else {
            throw reject("DESTINATION_READBACK_REJECTED")
        }
        return references.count
    }

    static func localCount() -> Int {
        guard let url = try? target() else { return 0 }
        return R595FormReferenceMatcher.loadLocalCatalog(
            at: url).count
    }
}
