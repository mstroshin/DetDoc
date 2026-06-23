import SwiftUI

struct PatchReviewView: View {
    let patch: PatchReviewViewModel
    let onApply: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Review changes").font(.headline)
            Text("\(patch.changedFiles.count) file(s)").font(.caption).foregroundStyle(.secondary)
            DiffFilesView(files: patch.diffFiles).frame(maxHeight: 280)
            if !patch.worktreePath.isEmpty {
                Text("Worktree: \(patch.worktreePath)").font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
            }
            HStack {
                Button("Apply", action: onApply).buttonStyle(.borderedProminent)
                Button("Discard", role: .destructive, action: onDiscard)
            }.padding(.top, 4)
        }
    }
}
