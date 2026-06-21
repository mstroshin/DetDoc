# Design: Docs file tree in the left panel

## Goal

Replace the flat list of full document paths in the workspace left panel with a
hierarchical **file tree** of the `docs/` directory, and add basic file
operations (new file, new folder, rename, delete). Scope is limited to `docs/`
Markdown files (respecting the config `docs` include/exclude policy) — the tree
is not a whole-repository browser. This matches DetDoc's documentation-as-source-of-truth
model: only docs are editable.

## Current state

`DocsExplorerView` renders `List(selection:)` over `workspace.docs`
(`[DocFile]`), one row per file showing the full relative path
(`docs/guide/intro.md`) via `Label(doc.path, …)`. `DocFile` is `{ path, title }`.
`WorkspaceViewModel.refresh()` populates `docs` from `DocsService(root:config:).list()`,
which enumerates `docs/` recursively for policy-allowed `.md` files. Selecting a
row drives `DocEditorViewModel.open(path)` through the `selectedDoc` binding in
`WorkspaceView`. `DocsService` already exposes `read`, `write`, `create`,
`rename`, and `delete`, but the mutation methods are not wired to any UI.

## Architecture

Follow the app convention (thin views; logic in `@MainActor @Observable` view
models; headless tests via `DetDocAppTests`). Approach: a dedicated
`DocsTreeViewModel` plus a pure tree builder, both in the `DetDocApp` target.

### Data model (App target)

```swift
struct DocTreeNode: Identifiable, Hashable {
    let id: String          // relative path: "docs/guide/intro.md" or "docs/guide"
    let name: String        // last path component: "intro.md" / "guide"
    let isDirectory: Bool
    var children: [DocTreeNode]?   // nil for files; [] for an empty directory
}
```

`id` is the relative path — stable, and exactly what `DocEditorViewModel.open`
and `DocsService` expect. `children == nil` marks a leaf (file) so
`OutlineGroup` / `List(children:)` shows no disclosure triangle on files.

### Tree builder (App target, pure)

```swift
enum DocTreeBuilder {
    static func build(files: [String], directories: [String]) -> [DocTreeNode]
}
```

- `files` — relative paths from `DocsService.list()`.
- `directories` — relative paths of all subdirectories under `docs/`. Supplying
  these explicitly lets the tree show **empty** directories (including
  freshly created ones), which never appear in the files list.
- Folds paths on `/` into a hierarchy; intermediate directories are derived from
  file paths and merged with the explicit `directories`. Sort order: directories
  before files, then alphabetical by name (case-insensitive).
- Pure and filesystem-free, so it is trivially unit-testable.

### Directory source (Core)

```swift
// DocsService
public func listDirectories() -> [String]   // relative paths of subdirectories under docs/
```

Enumerates subdirectories under `docs/`. Lives in Core next to the existing file
enumeration. `New Folder` creates a real directory on disk
(`FileManager.createDirectory`); after refresh `listDirectories()` returns it, so
empty folders are persistent and do not disappear.

### View model (App target)

`@MainActor @Observable DocsTreeViewModel`, constructed with `root` + `config`
(wrapping a `DocsService`), owns:

- `nodes: [DocTreeNode]` — the current tree.
- `error: DetDocError?` — last operation error, surfaced as an alert.
- `refresh()` — calls `DocsService.list()` + `listDirectories()`, feeds
  `DocTreeBuilder.build`, and assigns `nodes`. It unwraps the single `docs`
  root node so the top level shows the contents of `docs/` directly (ids remain
  full relative paths).
- `newFile(name:in:)`, `newFolder(name:in:)`, `rename(_:to:)`, `delete(_:)` —
  wrap the matching `DocsService` methods, map thrown `DetDocError` into `error`,
  and `refresh()` on success. New/rename/delete return the affected new path so
  the workspace can sync editor selection.

The destination directory for new file/folder: the selected node's directory if
a directory is selected; the selected file's parent if a file is selected;
otherwise the `docs/` root.

## User interface

`DocsExplorerView` is rewritten to a hierarchy:

```swift
List(tree.nodes, children: \.children, selection: $selection) { node in
    Label(node.name, systemImage: node.isDirectory ? "folder" : "doc.text")
}
```

- **New File** / **New Folder** — buttons in the panel's bottom bar. Name is
  requested via an `.alert` with a `TextField` (the pattern already used for the
  "Fix intent" prompt). New File appends `.md` if the typed name lacks it, creates
  the file, and immediately selects/opens it.
- **Rename** / **Delete** — node context menu (right-click). Delete shows a
  confirmation. Directories rename/delete recursively (`DocsService.rename`/`delete`
  already use `moveItem`/`removeItem`).
- Operation errors (`DetDocError`) are shown via an alert.
- A small "unsaved changes" dot is shown on the file currently being edited
  (`editor.isDirty` for the selected path). Git modified/dirty badges are out of
  scope (possible future enhancement).
- Folders use the native `List(_:children:selection:)` disclosure and start
  collapsed (standard for file trees); expansion state is not persisted. The
  single `docs` root is unwrapped so docs/ contents appear at the top level.
- The empty-state `ContentUnavailableView` ("No documents") is preserved when the
  tree is empty.

## Data flow / selection behavior

1. `WorkspaceView` owns a `DocsTreeViewModel` and a `selectedDoc: String?` binding
   (as today), shared with the tree and the editor.
2. Selecting a **file** node → `onChange(of: selectedDoc)` calls `editor.open(path)`
   (unchanged). Selecting a **directory** node does not open the editor (guard:
   the path is in the files set / not a known directory).
3. **Rename** of the open file → `selectedDoc` updates to the new path and the
   editor reopens it. Renaming a directory containing the open file → the open
   file's new path is recomputed and reselected.
4. **Delete** of the open file (or a directory containing it) → `selectedDoc = nil`
   and the editor clears.
5. After any operation, `DocsTreeViewModel.refresh()` rebuilds `nodes`; the
   workspace also refreshes as needed.

## Error handling

All filesystem failures originate from `DocsService` as `DetDocError`
(`DOC_ALREADY_EXISTS`, `DOC_RENAME_FAILED`, `DOC_DELETE_FAILED`,
`DOC_WRITE_FAILED`). `DocsTreeViewModel` captures them into `error` and the view
presents an alert. Operations never crash on a missing/renamed selection — the
selection sync handles stale paths by clearing or remapping.

## Testing

- `DocTreeBuilder` (DetDocAppTests, pure): nesting, empty directories, sort order
  (directories before files), single-segment and deep paths, files at `docs/` root.
- `DocsService.listDirectories()` (fast DetDocCore suite): subdirectories under
  `docs/`, empty result when none.
- `DocsTreeViewModel` (DetDocAppTests, temp directory): new file/folder creates the
  expected path and updates `nodes`; new file in selected subfolder lands in that
  folder; rename moves the entry and reports the new path; delete removes the node;
  duplicate create / bad rename map to `DetDocError` in `error`.
- Selection sync (DetDocAppTests): renaming the open doc updates selection;
  deleting the open doc clears it.

## Out of scope (YAGNI)

- Whole-repository file browser (docs-only by decision).
- Git dirty/modified badges in the tree.
- Persisted folder expansion state, and default-expanded / expand-all folders
  (native collapsed disclosure is used).
- Drag-and-drop move/reordering.
