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

    // QLPreviewPanel follows the responder chain: this text view declares itself the
    // controller so the panel adopts the coordinator's data source. Direct dataSource
    // assignment is fragile — the panel re-queries the responder chain on key changes.
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        coordinator?.quickLook.url != nil
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = coordinator?.quickLook
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        // Plain, reused data source — nothing to tear down.
    }
}
