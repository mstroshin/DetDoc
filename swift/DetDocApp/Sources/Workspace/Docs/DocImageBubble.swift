import AppKit
import SwiftUI

// MARK: - View

struct DocImageView: View {
    let image: NSImage
    let size: CGSize

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
            .help("Drag to move • click to open full size")
    }
}

// MARK: - Attachment

// Same isolation strategy as DocLinkBubbleAttachment: the attachment is built on the
// main thread by the @MainActor content-storage delegate and only used on main.
// `url` and `editor` (a @MainActor-isolated, hence Sendable, type) cross freely;
// `onOpen` is a non-Sendable closure marked nonisolated(unsafe) because it is
// exclusively invoked on the main thread.
nonisolated final class DocImageAttachment: NSTextAttachment {
    let url: URL
    nonisolated(unsafe) let onOpen: () -> Void
    let editor: DocEditorViewModel

    @MainActor
    init(url: URL, editor: DocEditorViewModel, onOpen: @escaping @MainActor () -> Void) {
        self.url = url
        self.editor = editor
        self.onOpen = onOpen
        super.init(data: nil, ofType: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func viewProvider(
        for parentView: NSView?,
        location: any NSTextLocation,
        textContainer: NSTextContainer?
    ) -> NSTextAttachmentViewProvider? {
        let p = DocImageProvider(
            textAttachment: self,
            parentView: parentView,
            textLayoutManager: textContainer?.textLayoutManager,
            location: location
        )
        p.tracksTextAttachmentViewBounds = true
        return p
    }
}

// MARK: - Attachment view provider

// loadView()/attachmentBounds(…) are nonisolated in the SDK but always called on the
// main thread; we bridge non-Sendable values through MainThreadOnly + assumeIsolated,
// exactly like DocLinkBubble.
nonisolated private struct MainThreadOnly<T>: @unchecked Sendable { let value: T }

nonisolated final class DocImageProvider: NSTextAttachmentViewProvider {
    private let image: NSImage?
    private let onOpen: MainThreadOnly<() -> Void>
    private let editor: MainThreadOnly<DocEditorViewModel?>
    private let sourceIndex: Int
    private let containerWidth: CGFloat
    private var dragController: DocImageDragController?

    override init(
        textAttachment: NSTextAttachment,
        parentView: NSView?,
        textLayoutManager: NSTextLayoutManager?,
        location: any NSTextLocation
    ) {
        let a = textAttachment as? DocImageAttachment
        self.image = a.flatMap { NSImage(contentsOf: $0.url) }
        self.onOpen = MainThreadOnly(value: a?.onOpen ?? {})
        self.editor = MainThreadOnly(value: a?.editor)
        if let cm = textLayoutManager?.textContentManager {
            self.sourceIndex = cm.offset(from: cm.documentRange.location, to: location)
        } else {
            self.sourceIndex = 0
        }
        let cw = textLayoutManager?.textContainer?.size.width ?? 480
        self.containerWidth = (cw.isFinite && cw > 0) ? cw : 480
        super.init(textAttachment: textAttachment, parentView: parentView,
                   textLayoutManager: textLayoutManager, location: location)
    }

    /// Compact preview: <=120 pt tall, width by aspect, capped to the container width.
    private func displaySize() -> CGSize {
        guard let image, image.size.width > 0, image.size.height > 0 else {
            return CGSize(width: 120, height: 90)
        }
        let aspect = image.size.width / image.size.height
        var h = min(image.size.height, 120)
        var w = h * aspect
        let cap = max(80, containerWidth - 24)
        if w > cap { w = cap; h = w / aspect }
        return CGSize(width: w.rounded(), height: h.rounded())
    }

    override func loadView() {
        let size = displaySize()
        let providerBox = MainThreadOnly(value: self)
        if let image {
            let imageBox = MainThreadOnly(value: image)
            let follow = onOpen
            let ed = editor
            let idx = sourceIndex
            MainActor.assumeIsolated {
                let host = NSHostingView(rootView: DocImageView(image: imageBox.value, size: size))
                providerBox.value.view = host
                if let editor = ed.value {
                    providerBox.value.dragController = DocImageDragController(
                        hostingView: host, onOpen: follow.value, sourceIndex: idx, editor: editor
                    )
                }
            }
        } else {
            MainActor.assumeIsolated { providerBox.value.view = NSView() }
        }
    }

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        let size = displaySize()
        return CGRect(x: 0, y: -4, width: size.width, height: size.height)
    }
}
