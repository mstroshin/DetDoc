import SwiftUI
import DetDocCore

struct DocsExplorerView: View {
    let tree: DocsTreeViewModel
    @Binding var selection: String?
    var dirtyPath: String?
    /// Double click on a file row — open its text (the caller leaves the canvas if shown).
    var onActivate: (String) -> Void = { _ in }

    @State private var showNewFile = false
    @State private var showNewFolder = false
    @State private var nameInput = ""
    @State private var renameTarget: String?
    @State private var deleteTarget: String?

    var body: some View {
        List(tree.nodes, children: \.children, selection: $selection) { node in
            let row = HStack(spacing: 6) {
                Label(node.name, systemImage: node.isDirectory ? "folder" : "doc.text")
                if !node.isDirectory, node.id == dirtyPath {
                    Spacer()
                    Circle().fill(.secondary).frame(width: 6, height: 6)
                        .help("Unsaved changes")
                }
            }
            .contextMenu {
                Button("Rename…") { nameInput = node.name; renameTarget = node.id }
                Button("Delete…", role: .destructive) { deleteTarget = node.id }
            }

            if node.isDirectory {
                row   // folders keep the List's native selection + disclosure behaviour
            } else {
                // Make the whole row (the label included) the hit area: single click
                // selects, double click opens the text. A gesture on the label alone
                // would steal clicks on the text from the List's own selection — which is
                // why clicking the file name used to do nothing.
                row.contentShape(Rectangle())
                    .onTapGesture(count: 2) { selection = node.id; onActivate(node.id) }
                    .onTapGesture(count: 1) { selection = node.id }
            }
        }
        .overlay {
            if tree.nodes.isEmpty {
                ContentUnavailableView("No documents", systemImage: "doc",
                    description: Text("Markdown files under docs/ appear here."))
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Button { nameInput = ""; showNewFile = true } label: { Image(systemName: "doc.badge.plus") }
                    .help("New File")
                Button { nameInput = ""; showNewFolder = true } label: { Image(systemName: "folder.badge.plus") }
                    .help("New Folder")
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .alert("New File", isPresented: $showNewFile) {
            TextField("Name", text: $nameInput)
            Button("Create") {
                let dir = tree.directoryForNewEntry(selection: selection)
                if let path = tree.newFile(name: nameInput, in: dir) { selection = path }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Name", text: $nameInput)
            Button("Create") {
                let dir = tree.directoryForNewEntry(selection: selection)
                if let path = tree.newFolder(name: nameInput, in: dir) { selection = path }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField("Name", text: $nameInput)
            Button("Rename") {
                if let target = renameTarget, let newPath = tree.rename(target, to: nameInput) {
                    selection = DocsTreeViewModel.remapAfterRename(selection: selection, from: target, to: newPath)
                }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
        .alert("Delete", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
            Button("Delete", role: .destructive) {
                if let target = deleteTarget {
                    tree.delete(target)
                    selection = DocsTreeViewModel.remapAfterDelete(selection: selection, deleted: target)
                }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("Delete \"\(deleteTarget ?? "")\"? This cannot be undone.")
        }
        .alert("Operation failed",
               isPresented: Binding(get: { tree.error != nil }, set: { if !$0 { tree.dismissError() } }),
               presenting: tree.error) { _ in
            Button("OK") {}
        } message: { err in
            Text(err.message)
        }
    }
}
