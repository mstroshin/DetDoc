# Doc Graph (Canvas) — Design

A new whole-corpus view that renders the project's documentation as an Obsidian-style
network: each document is a node, each doc-to-doc link is a line between nodes. Images
embedded in a document show as thumbnails on its node. Clicking a node opens that document
in the editor.

## Goals

- Show every doc as a node and every doc→doc link as a connecting line.
- Show embedded images as thumbnails on the owning node; click a thumbnail for a full-size view.
- Auto-lay-out the network on first show; let the user drag nodes, and remember those positions.
- Open a document from the canvas.

## Non-goals (YAGNI)

- No doc→code links on the graph (doc↔doc only, per request).
- No live/animated physics simulation — layout is computed once, then the user drags.
- No shared-via-git layout, no minimap, no graph search/filtering.

## Naming

The name `Canvas` is already taken in code by the in-document sketch feature
(`CanvasSketchView`, `CanvasImageRenderer`). To avoid collision, code uses the `DocGraph*`
prefix; the user-facing toolbar button is still labelled "Canvas".

## Architecture

Data flow:

```
DocsService → DocGraphBuilder → DocGraph → (ForceLayout + CanvasLayoutStore) → DocGraphViewModel → DocGraphView
```

Each unit has one job; the Core units are pure and tested headless (no Xcode).

### 1. Core — `DocGraphBuilder` (`DetDocCore/Services/DocGraph.swift`)

Builds the graph from docs. Pure, `Sendable`.

- Input: a `DocsService` (root + config).
- For each doc: read text → `DocRefScanner.scan` (doc links) + `ImageRefScanner.scan` (images).
  Resolve link tokens with `DocLinkResolver`; keep only edges to **existing** docs.
- Output `DocGraph`:
  - `nodes: [DocGraphNode]` — `path` (docs-relative, e.g. `guides/setup.md`),
    `title` (first heading or filename), `imagePaths: [String]` (docs-relative image paths).
  - `edges: [DocGraphEdge]` — `{from, to}`, undirected, de-duplicated (A↔B counts once;
    a self-link is dropped).
- No coordinates, no UI. `Equatable` for testability.

Self-check (headless test): a fixture docs tree with known links/images produces the
expected node set, de-duplicated undirected edges, dangling links excluded, and the right
image paths per node.

### 2. Core — `ForceLayout` (`DetDocCore/Services/ForceLayout.swift`)

Pure deterministic auto-layout.

- `compute(nodes:edges:) -> [String: Point]` where `Point { x, y }` is a plain struct
  (no CoreGraphics, keeps Core portable/pure).
- Fruchterman–Reingold style: deterministic seed (node index → angle on a circle, **no RNG**),
  fixed iteration count (~300), repulsion between all nodes + attraction along edges.
- Deterministic: same input → same output.

Self-check (headless test): for a small graph, connected nodes end up closer than
unconnected ones, and two runs produce identical coordinates.

### 3. Core — `CanvasLayoutStore` (`DetDocCore/Services/CanvasLayoutStore.swift`)

Persists user-dragged positions locally (outside git).

- `load(root) -> [String: Point]` / `save(_:root:)` → `.detdoc/canvas-layout.json`,
  shape `{ "guides/setup.md": { "x": …, "y": … }, … }`, `Codable`.
- Add `.detdoc/canvas-layout.json` to `GitignoreManager.managedEntries` so it stays local.
- Missing/corrupt file → empty map (never throws into the UI).

### 4. App — `DocGraphViewModel` (`@MainActor @Observable`, tested headless)

- On present: build graph → load saved positions → for nodes without a saved position,
  use the auto-layout position → merge. Deleted docs drop out; new docs get an auto position.
- State: `nodes` (path, title, imagePaths, position), `edges`, `scale`, `offset`, `zoomedImage`.
- Actions:
  - `moveNode(path, to:)` — update a node's position; persist on drag-end.
  - `select(path)` — invokes an "open doc" callback supplied by the view.
  - `showImage(path)` / `closeImage()` — drive the full-size overlay.
  - `resetView()` — reset pan/zoom.
- Refresh when the docs tree changes (same change signal the docs tree already uses), so
  added/removed docs and edited links re-flow.

Self-check (headless test): merging keeps saved positions, assigns auto positions to new
nodes, drops removed nodes; `moveNode` updates state and triggers a save.

### 5. App — `DocGraphView` (`DetDocApp/Workspace/Docs/DocGraphView.swift`)

- One `Canvas` layer draws all edges (lines) in a single pass.
- Overlaid `DocGraphNodeView` per node: title + thumbnail of the first image (a `+N` badge
  if there are more). Tap node → open doc; tap thumbnail → full-size overlay; drag → `moveNode`.
- Shared `scaleEffect` + `offset`; `MagnifyGesture` (zoom) and background `DragGesture` (pan),
  plus a "reset view" button.
- Image thumbnails load via `NSImage(contentsOf: root/docs/<imagePath>)` (same convention as
  `DocImageBubble`).
- Accessibility IDs (per CLAUDE.md): `docGraph.canvas`, `docGraph.node.<path>`,
  `docGraph.image.<path>`, `docGraph.resetView`.
- Previews with states: empty graph, a few connected nodes, a node with an image.

### 6. App — Workspace integration (`WorkspaceView`)

- Add `@State showCanvas`. A toolbar "Canvas" toggle button.
- When on, the detail (center) area shows `DocGraphView` instead of `DocEditorScreen`; the
  sidebar docs tree stays.
- Node tap: `selectedDoc = path; showCanvas = false` → returns to the editor with that doc open.

## Error handling

- Unreadable doc → skipped from the graph (logged), not fatal.
- Missing image file → node renders without that thumbnail.
- Corrupt/absent layout file → treated as empty; everything auto-lays-out.

## Testing

- Core (headless, `swift test`): `DocGraphBuilder`, `ForceLayout`, `CanvasLayoutStore`.
- App (`DetDocAppTests`): `DocGraphViewModel` merge/move/refresh behavior.
- SwiftUI Previews cover the visual states listed above.
