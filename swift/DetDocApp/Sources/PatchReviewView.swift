import SwiftUI
import DetDocViewModels

struct PatchReviewView: View {
    let patch: PatchReviewViewModel
    let onApply: () -> Void
    let onDiscard: () -> Void
    var body: some View { Text("Patch: \(patch.changedFiles.count) files") }
}
