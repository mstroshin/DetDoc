import SwiftUI

/// Scrollable per-file unified-diff renderer shared by the patch-apply gate and the
/// pre-run input review. One source of truth for diff line colors/backgrounds.
struct DiffFilesView: View {
    let files: [DiffFile]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(files, id: \.path) { file in
                    fileCard(file)
                }
            }
            .padding(1)   // keep the 1pt card borders from clipping at the scroll edges
        }
        .accessibilityIdentifier("diff-files")
    }

    /// One file as a bordered card — a path header bar above its diff lines — so adjacent files
    /// in a multi-file diff read as distinct blocks rather than one run-on list.
    private func fileCard(_ file: DiffFile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(displayPath(file.path))
                .font(.system(.caption, design: .monospaced)).bold()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(.quaternary)
                .accessibilityIdentifier("diff-file-\(file.path)")
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(file.lines.enumerated()), id: \.offset) { _, line in
                    Text(line.text)
                        .font(.system(.caption2, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(color(for: line.kind))
                        .background(background(for: line.kind))
                }
            }
            .padding(.vertical, 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary, lineWidth: 1))
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

    /// Drop the redundant leading `docs/` from the displayed path; paths without it (code files in
    /// the patch review, or markdown outside docs/) are shown unchanged. The accessibility id keeps
    /// the full path for debugging.
    private func displayPath(_ path: String) -> String {
        path.hasPrefix("docs/") ? String(path.dropFirst("docs/".count)) : path
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
