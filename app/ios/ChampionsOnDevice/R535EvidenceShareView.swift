import SwiftUI
import UIKit

/// The share sheet is displayed only after a deliberate button press produced
/// a local on-device evidence file. The user chooses the export destination.
@available(iOS 27.0, *)
struct R535EvidenceShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

@available(iOS 27.0, *)
struct R535EvidenceShareView: UIViewControllerRepresentable {
    let url: URL
    let onOutcome: (Bool,Bool) -> Void
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems:[url],applicationActivities:nil)
        controller.completionWithItemsHandler = { _,completed,_,error in
            DispatchQueue.main.async { onOutcome(completed,error != nil) }
        }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController,context:Context) {}
}
