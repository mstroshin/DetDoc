import AppKit

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
}
