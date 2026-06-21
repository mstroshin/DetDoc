import AppKit
import SwiftUI

// MARK: - View

struct DocLinkBubbleView: View {
    let title: String
    let onFollow: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.text").font(.system(size: 10))
            Text(title).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 8).padding(.vertical, 1)
        .glassEffect(.regular.interactive(), in: Capsule())
        .fixedSize()
        .contentShape(Capsule())
        .onTapGesture { onFollow() }
    }
}

// MARK: - Attachment

// DocLinkBubbleAttachment is constructed on the main thread by the @MainActor
// content-storage delegate, and only ever used on the main thread thereafter.
// title is a Sendable String; onFollow is nonisolated(unsafe) because it's a
// non-Sendable closure that is exclusively called on the main thread
// (SwiftUI onTapGesture fires on main). The target docPath is captured inside
// the onFollow closure at the call site — no need to store it separately here.
final class DocLinkBubbleAttachment: NSTextAttachment {
    let title: String
    nonisolated(unsafe) let onFollow: () -> Void

    @MainActor
    init(title: String, onFollow: @escaping @MainActor () -> Void) {
        self.title = title
        self.onFollow = onFollow
        super.init(data: nil, ofType: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    // viewProvider is nonisolated in the superclass; the text system always
    // calls it on the main thread. We satisfy Swift 6 by constructing the
    // provider only with the Sendable title string and the
    // nonisolated(unsafe) closure — no main-actor-isolated types cross here.
    override func viewProvider(
        for parentView: NSView?,
        location: any NSTextLocation,
        textContainer: NSTextContainer?
    ) -> NSTextAttachmentViewProvider? {
        let p = DocLinkBubbleProvider(
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

// NSTextAttachmentViewProvider.loadView() and attachmentBounds(…) are declared
// nonisolated in the SDK, yet the text system always calls them on the main
// thread.  We must touch @MainActor-isolated APIs (view, fittingSize, etc.).
//
// Strategy: store everything we need from the attachment as plain properties
// on DocLinkBubbleProvider (no main-actor isolation), then pass them via an
// @unchecked Sendable wrapper into MainActor.assumeIsolated so the Swift 6
// region-isolation checker is satisfied.  The wrapper is only ever created and
// consumed on the main thread, so the @unchecked annotation is safe.
private struct MainThreadOnly<T>: @unchecked Sendable { let value: T }

final class DocLinkBubbleProvider: NSTextAttachmentViewProvider {
    private let bubbleTitle: String
    // Closure type is not Sendable; MainThreadOnly<@unchecked Sendable> bridges it safely
    // because the closure is always created and invoked on the main thread.
    private let bubbleFollow: MainThreadOnly<() -> Void>

    override init(
        textAttachment: NSTextAttachment,
        parentView: NSView?,
        textLayoutManager: NSTextLayoutManager?,
        location: any NSTextLocation
    ) {
        let a = textAttachment as? DocLinkBubbleAttachment
        self.bubbleTitle = a?.title ?? ""
        self.bubbleFollow = MainThreadOnly(value: a?.onFollow ?? {})
        super.init(textAttachment: textAttachment, parentView: parentView,
                   textLayoutManager: textLayoutManager, location: location)
    }

    override func loadView() {
        // Capture only Sendable / @unchecked Sendable values — not 'self' —
        // so the Swift 6 region checker accepts the assumeIsolated boundary.
        let title = bubbleTitle
        let follow = bubbleFollow
        let providerBox = MainThreadOnly(value: self)   // wrap non-Sendable provider
        MainActor.assumeIsolated {
            providerBox.value.view = NSHostingView(
                rootView: DocLinkBubbleView(title: title, onFollow: follow.value)
            )
        }
    }

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        let providerBox = MainThreadOnly(value: self)
        let size: CGSize = MainActor.assumeIsolated {
            providerBox.value.view?.fittingSize ?? CGSize(width: 60, height: 18)
        }
        return CGRect(x: 0, y: -4, width: size.width, height: size.height) // nudge the capsule down so it sits on the text baseline
    }
}
