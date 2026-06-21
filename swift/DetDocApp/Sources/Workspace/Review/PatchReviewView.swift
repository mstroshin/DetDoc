import SwiftUI

struct PatchReviewView: View {
    let patch: PatchReviewViewModel
    let onApply: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Review changes").font(.headline)
            Text("\(patch.changedFiles.count) file(s)").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(patch.diffFiles, id: \.path) { file in
                        Text(file.path).font(.system(.caption, design: .monospaced)).bold()
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(file.lines.enumerated()), id: \.offset) { _, line in
                                Text(line.text)
                                    .font(.system(.caption2, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .foregroundStyle(color(for: line.kind))
                                    .background(background(for: line.kind))
                            }
                        }
                    }
                }
            }.frame(maxHeight: 280)
            if !patch.worktreePath.isEmpty {
                Text("Worktree: \(patch.worktreePath)").font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
            }
            HStack {
                Button("Apply", action: onApply).buttonStyle(.borderedProminent)
                Button("Discard", role: .destructive, action: onDiscard)
            }.padding(.top, 4)
        }
    }

    private func color(for kind: DiffLineKind) -> Color {
        switch kind {
        case .addition: .green
        case .deletion: .red
        case .hunk: .purple
        case .header: .secondary
        case .context: .primary
        }
    }
    private func background(for kind: DiffLineKind) -> Color {
        switch kind {
        case .addition: .green.opacity(0.12)
        case .deletion: .red.opacity(0.12)
        default: .clear
        }
    }
}
