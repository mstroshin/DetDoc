# Canvas Sketch — Design

Date: 2026-06-22

## Goal

Let the user open a drawing canvas from a right-click context menu in the doc
editor, sketch a quick freehand drawing, and insert the result into the document
exactly like an imported image (`@…png` token). The purpose is to let the user
explain visual UI details to the agent with hand-drawn sketches.

## User decisions

- Right-click in the editor shows a **"Создать канвас…"** context-menu item.
- Background is **always black** (not theme-dependent).
- Default pen color is **white**, plus **5 additional colors** offered as
  selectable swatches (circles).
- The saved sketch is inserted into the doc like an image.

## Approach

Reuse the existing image pipeline end-to-end. A sketch is just another PNG
written into the document's `assets/` folder and referenced by an `@…png` token,
so rendering, drag-reorder, and Quick Look all work for free.

### Presentation

A modal **sheet** on the main window (consistent with `RunsSheet` /
`SettingsSheet`), ~640×520, hosting a SwiftUI canvas. It is opened from the
AppKit coordinator (`LivePreviewTextView.Coordinator`) via
`window.beginSheet(_:)`, so all wiring stays in the editor layer and reuses the
existing insertion code. No changes to `DocEditorScreen` / SwiftUI plumbing are
needed.

### Drawing engine

A custom SwiftUI `Canvas` + drag gesture (not PencilKit) — full control over
color, predictable export, and unit-testable rasterization. Tools:

- Freehand pen.
- Color palette: white (default) + 5 colors as circular swatches.
- Pen width: 3 sizes.
- Undo (remove last stroke), Clear (remove all).
- Cancel / Insert.

Each stroke records its own color and width (the user can switch mid-drawing).

### Theme / export

Background is always solid black. Strokes render in their chosen colors. The PNG
is exported with the black background baked in (so the sketch reads identically
regardless of the app's later light/dark state), at 2× scale for crispness.

### Insertion position

The char index under the right-click point is captured when the menu is built
(`characterIndexForInsertion(at:)`, same as image drop) and used as the
insertion location, so the sketch lands where the user clicked.

## Components / files

1. `CanvasSketchView.swift` (new, App/Sources/Workspace/Docs) — SwiftUI sheet:
   `CanvasStroke` model, live `Canvas` rendering, color/width/undo/clear toolbar,
   `onInsert(Data)` / `onCancel` callbacks. Builds PNG via the renderer.
2. `CanvasImageRenderer.swift` (new, App) — pure function
   `strokes + size + scale + background → PNG Data` using `NSBitmapImageRep`.
   Unit-testable.
3. `ImageDropTextView.swift` (edit) — override `menu(for:)` to prepend
   "Создать канвас…" (only when a doc is open) and store the click char index.
4. `LivePreviewTextView.swift` (edit, Coordinator) — hold the pending insert
   index; `presentCanvasSheet()` (NSHostingController + `beginSheet`); on insert
   call `imageImporter.importData(...)` + existing `insertImageTokens(...)`.

## Tests

- `CanvasImageRendererTests` (DetDocAppTests):
  - Render a known horizontal stroke → decode PNG → assert an ink-colored pixel
    on the stroke and a black pixel in a corner.
  - Empty strokes → still a valid all-black PNG of the expected pixel size.
  - A colored stroke → assert the stroke pixel matches the chosen color.
- Import pipeline already covered by `DocImageImporterTests`.

## Edge cases

- No open document → context-menu item is hidden.
- Empty drawing → Insert is disabled.
- Cancel → no file written, sheet closes, document untouched.
