import SwiftUI

/// Scrollable per-file unified-diff renderer shared by the patch-apply gate and the
/// pre-run input review. One source of truth for diff line colors/backgrounds.
struct DiffFilesView: View {
    let files: [DiffFile]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(files, id: \.path) { file in
                    Text(file.path)
                        .font(.system(.caption, design: .monospaced)).bold()
                        .accessibilityIdentifier("diff-file-\(file.path)")
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
        }
        .accessibilityIdentifier("diff-files")
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

#Preview("Two files") {
    DiffFilesView(files: DiffModel.parse("""
    diff --git a/docs/api.md b/docs/api.md
    --- a/docs/api.md
    +++ b/docs/api.md
    @@ -1,2 +1,2 @@
    -old line
    +new line
     context
    diff --git a/docs/guide.md b/docs/guide.md
    --- a/docs/guide.md
    +++ b/docs/guide.md
    @@ -1 +1,2 @@
     intro
    +added paragraph
    """))
    .frame(width: 480, height: 240)
}
