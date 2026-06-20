import SwiftUI
import DetDocViewModels

struct DocEditorScreen: View {
    @Bindable var editor: DocEditorViewModel

    private var sourceBinding: Binding<String> {
        Binding(get: { editor.source }, set: { editor.edit($0) })
    }

    var body: some View {
        Group {
            if editor.selectedPath == nil {
                ContentUnavailableView("Select a document", systemImage: "doc.text", description: Text("Pick a Markdown file from the sidebar."))
            } else {
                // Plain HStack (not HSplitView): HSplitView sizes to the sum of its
                // children's ideal widths and overflows the NavigationSplitView detail.
                HStack(spacing: 0) {
                    TextEditor(text: sourceBinding)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    ScrollView {
                        MarkdownPreview(source: editor.source)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text(editor.selectedPath ?? "").font(.headline)
                    }
                    ToolbarItem {
                        Button("Save") { editor.save() }
                            .disabled(!editor.isDirty)
                    }
                }
            }
        }
    }
}

/// Lightweight block renderer for the preview: headings, bullets, and
/// inline-styled paragraphs (bold/italic/links via AttributedString).
private struct MarkdownPreview: View {
    let source: String

    private var lines: [(Int, String)] {
        Array(source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).enumerated())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(lines, id: \.0) { _, raw in
                line(raw)
            }
        }
    }

    @ViewBuilder private func line(_ text: String) -> some View {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            Color.clear.frame(height: 4)
        } else if let level = headingLevel(trimmed) {
            Text(inline(headingText(trimmed, level: level)))
                .font(headingFont(level))
                .bold()
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•")
                Text(inline(String(trimmed.dropFirst(2))))
            }
        } else {
            Text(inline(text))
        }
    }

    private func headingLevel(_ s: String) -> Int? {
        let hashes = s.prefix(while: { $0 == "#" }).count
        guard hashes >= 1, hashes <= 6, s.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }
    private func headingText(_ s: String, level: Int) -> String {
        String(s.dropFirst(level)).trimmingCharacters(in: .whitespaces)
    }
    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .largeTitle
        case 2: .title
        case 3: .title2
        default: .headline
        }
    }
    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}
