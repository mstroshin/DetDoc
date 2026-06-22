import AppKit
import Quartz

/// NSTextView subclass that intercepts image drops and image paste, delegating the
/// import + insertion to the LivePreviewTextView coordinator. Non-image drags/pastes
/// fall through to the default NSTextView behavior.
final class ImageDropTextView: NSTextView {
    weak var coordinator: LivePreviewTextView.Coordinator?

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if coordinator?.handleImageDrop(sender, into: self) == true { return true }
        return super.performDragOperation(sender)
    }

    override func paste(_ sender: Any?) {
        if coordinator?.handleImagePaste(into: self) == true { return }
        super.paste(sender)
    }

    // Prepend "Add drawing…" to the right-click menu. The click's char index is
    // stashed on the item so the resulting sketch inserts where the user clicked.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        guard let coordinator, coordinator.canCreateCanvas else { return menu }
        let point = convert(event.locationInWindow, from: nil)
        let item = NSMenuItem(title: "Add drawing…",
                              action: #selector(LivePreviewTextView.Coordinator.createCanvasMenuAction(_:)),
                              keyEquivalent: "")
        item.target = coordinator
        item.representedObject = characterIndexForInsertion(at: point)
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
        return menu
    }

    // QLPreviewPanel follows the responder chain: this text view declares itself the
    // controller so the panel adopts the coordinator's data source. Direct dataSource
    // assignment is fragile — the panel re-queries the responder chain on key changes.
    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        // The panel only drives these on the main thread; the protocol methods are
        // nonisolated in the SDK, so reach main-actor state via assumeIsolated.
        MainActor.assumeIsolated { coordinator?.quickLook.url != nil }
    }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { panel.dataSource = coordinator?.quickLook }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        // Plain, reused data source — nothing to tear down.
    }
}
