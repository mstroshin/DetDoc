import SwiftUI
import DetDocCore

/// Scrim + floating command-palette card, à la Spotlight. Tap-outside or Esc to close.
struct DocSearchOverlay: View {
    @Bindable var model: DocSearchViewModel
    var onOpen: (String) -> Void
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.15)
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
            DocSearchView(model: model, onOpen: onOpen, onClose: onClose)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 12)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
        .ignoresSafeArea()
        .accessibilityIdentifier("docSearch.overlay")
    }
}

struct DocSearchView: View {
    @Bindable var model: DocSearchViewModel
    var onOpen: (String) -> Void
    var onClose: () -> Void
    @FocusState private var queryFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            results
            Divider()
            hintBar
        }
        .frame(width: 620, height: 480)
        .background(.ultraThinMaterial)
        .accessibilityIdentifier("docSearch.panel")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search docs", text: Binding(
                get: { model.query },
                set: { model.query = $0; model.reload() }
            ))
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($queryFocused)
                .onAppear { queryFocused = true }
                .onKeyPress(.upArrow) { model.move(-1); return .handled }
                .onKeyPress(.downArrow) { model.move(1); return .handled }
                .onKeyPress(.return) { open(); return .handled }
                .onKeyPress(.escape) { onClose(); return .handled }
                .accessibilityIdentifier("docSearch.field")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder private var results: some View {
        if model.resultCount == 0 {
            placeholder(model.query.isEmpty ? "No documents." : "No results.")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        let fileCount = model.fileResults.count
                        let bothGroups = fileCount > 0 && !model.contentResults.isEmpty

                        if bothGroups { sectionLabel("Files") }
                        ForEach(Array(model.fileResults.enumerated()), id: \.element.docsRelativePath) { index, c in
                            row(FileResultRow(candidate: c), index: index).id(c.docsRelativePath)
                        }
                        if bothGroups { sectionLabel("In documents").padding(.top, 6) }
                        ForEach(Array(model.contentResults.enumerated()), id: \.element.id) { i, hit in
                            row(ContentResultRow(hit: hit), index: fileCount + i).id(hit.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .onChange(of: model.selectedIndex) { _, _ in
                    if let id = selectedScrollID {
                        withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
            .accessibilityIdentifier("docSearch.results")
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ content: some View, index: Int) -> some View {
        content
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(index == model.selectedIndex ? Color.accentColor.opacity(0.18) : .clear)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                model.selectedIndex = index
                open()
            }
    }

    /// Scroll identity of the highlighted row, matching each ForEach's element id.
    private var selectedScrollID: String? {
        let i = model.selectedIndex
        let fileCount = model.fileResults.count
        if i < fileCount {
            return model.fileResults.indices.contains(i) ? model.fileResults[i].docsRelativePath : nil
        }
        let ci = i - fileCount
        return model.contentResults.indices.contains(ci) ? model.contentResults[ci].id : nil
    }

    private func placeholder(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("docSearch.placeholder")
    }

    private var hintBar: some View {
        HStack(spacing: 14) {
            HintChip(keys: "↑↓", label: "navigate")
            HintChip(keys: "⏎", label: "open")
            HintChip(keys: "Esc", label: "close")
            Spacer()
            Text("\(model.resultCount) results")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func open() {
        if let path = model.selectedPath() { onOpen(path) }
    }
}

private struct FileResultRow: View {
    let candidate: DocCandidate
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.title ?? candidate.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                let dir = (candidate.docsRelativePath as NSString).deletingLastPathComponent
                if !dir.isEmpty {
                    Text(dir)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}

private struct ContentResultRow: View {
    let hit: DocContentHit
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text((hit.path as NSString).lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.head)
                Text(":\(hit.line)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            Text(highlighted)
                .font(.system(size: 11.5, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private var highlighted: AttributedString {
        var s = AttributedString(hit.lineText)
        if let r = s.range(of: hit.match, options: .caseInsensitive) {
            s[r].foregroundColor = .accentColor
            s[r].inlinePresentationIntent = .stronglyEmphasized
        }
        return s
    }
}

private struct HintChip: View {
    let keys: String
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.caption.monospaced())
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.secondary.opacity(0.15)))
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(Color.secondary.opacity(0.25), lineWidth: 0.5))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Previews

// Previews run the real search path: the custom text binding calls reload(), which
// recomputes from DocSearch. So seed a temp docs/ tree on disk rather than injecting
// result arrays (those get overwritten by reload against the real, empty root).
private func previewModel(query: String) -> DocSearchViewModel {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("DocSearchPreview", isDirectory: true)
    let docs = root.appendingPathComponent("docs")
    try? FileManager.default.createDirectory(at: docs.appendingPathComponent("guides"), withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: docs.appendingPathComponent("ci"), withIntermediateDirectories: true)
    try? "# Setup Guide\nrun the setup script before anything else\n".write(to: docs.appendingPathComponent("guides/setup.md"), atomically: true, encoding: .utf8)
    try? "# Release pipeline\nthe setup step caches dependencies\n".write(to: docs.appendingPathComponent("ci/release.md"), atomically: true, encoding: .utf8)
    try? "# Readme\nwelcome to the project\n".write(to: docs.appendingPathComponent("readme.md"), atomically: true, encoding: .utf8)
    let model = DocSearchViewModel(root: root, config: .default)
    model.present()
    model.query = query
    model.reload()
    return model
}

#Preview("Combined") {        // file match (setup.md) on top, in-document matches below
    @Previewable @State var model = previewModel(query: "setup")
    DocSearchView(model: model, onOpen: { _ in }, onClose: {})
        .padding(40)
        .frame(width: 720, height: 600)
        .background(Color.gray.opacity(0.3))
}

#Preview("Browse (empty)") { // empty query lists all files, no content section
    @Previewable @State var model = previewModel(query: "")
    DocSearchView(model: model, onOpen: { _ in }, onClose: {})
        .padding(40)
        .frame(width: 720, height: 600)
        .background(Color.gray.opacity(0.3))
}

#Preview("Empty") {          // no matches
    @Previewable @State var model = previewModel(query: "zzzz")
    DocSearchView(model: model, onOpen: { _ in }, onClose: {})
        .padding(40)
        .frame(width: 720, height: 600)
        .background(Color.gray.opacity(0.3))
}
