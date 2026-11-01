import Foundation

/// Validates that a Vision evidence reference matches its observation index and
/// candidate rank exactly, before the provisional layout is allowed to use it.
/// These checks establish traceability only, never the Pokémon's owner.
enum R568ObservationReferenceFence {
    static func canonical(_ site:R553LayoutReading.Site)->Bool {
        guard site.reading>=0 && site.reading<512,
              site.rank>=0 && site.rank<32 else {return false}
        let root="payload_json.readings[\(site.reading)]"
        return site.reference == (site.rank == 0 ? root : root+".ocr_alternatives[\(site.rank)]")
    }
    static func reading(_ site:R553LayoutReading.Site)->Int? {
        canonical(site) ? site.reading : nil
    }
}
