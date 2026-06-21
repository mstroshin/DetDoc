import SwiftUI
import DetDocCore

struct DocLinkSuggestionsView: View {
    @Bindable var model: DocLinkCompletionModel
    var onPick: (Int) -> Void

    var body: some View {
        Group {
            if model.items.isEmpty {
                Text("Нет документов").font(.system(size: 13)).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.items.enumerated()), id: \.element.docsRelativePath) { i, c in
                        row(c, selected: i == model.selectedIndex)
                            .contentShape(Rectangle())
                            .onTapGesture { onPick(i) }
                    }
                }
            }
        }
        .padding(6)
        .frame(width: 324, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder private func row(_ c: DocCandidate, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text").font(.system(size: 12)).foregroundStyle(selected ? .white : .secondary)
            highlighted(c.docsRelativePath, query: model.query, selected: selected)
                .font(.system(size: 13, design: .monospaced))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if selected { Capsule().glassEffect(.regular.tint(.accentColor).interactive(), in: Capsule()) }
        }
    }

    private func highlighted(_ path: String, query: String, selected: Bool) -> Text {
        var attr = AttributedString(path)
        attr.foregroundColor = selected ? .white : .primary
        if !query.isEmpty,
           let r = attr.range(of: query, options: .caseInsensitive) {
            attr[r].foregroundColor = selected ? .white : .accentColor
            attr[r].font = .system(size: 13, design: .monospaced).bold()
        }
        return Text(attr)
    }
}
