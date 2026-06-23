import AppKit
import SwiftUI

// MARK: - View

struct DocLinkBubbleView: View {
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.text").font(.system(size: 10))
            Text(title).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 8).padding(.vertical, 1)
        .glassEffect(.regular, in: Capsule())   // Liquid Glass; not .interactive() — the bubble handles no taps
        .fixedSize()
        .accessibilityIdentifier("doc-link-bubble-\(title)")
    }
}

// A hosting view that is transparent to mouse events so the enclosing NSTextView owns
// every click on the bubble: a plain click lands the caret beside the bubble (the text
// view snaps it to the trailing edge) and a cmd-click hits the bubble's .link attribute
// to follow. The bubble is a pure visual — no taps of its own.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - Attachment

// Built on the main thread by the @MainActor content-storage delegate and only used on the
// main thread thereafter. `title` is a Sendable String, so nothing non-Sendable crosses an
// actor boundary: the link target rides on the attachment string's .link attribute (set by
// the delegate) and is followed by the text view's cmd-click handler, not by the bubble.
nonisolated final class DocLinkBubbleAttachment: NSTextAttachment {
    let title: String

    @MainActor
    init(title: String) {
        self.title = title
        super.init(data: nil, ofType: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    // viewProvider is nonisolated in the superclass; the text system always calls it on the
    // main thread. We satisfy Swift 6 by constructing the provider only with the Sendable
    // title string — no main-actor-isolated type crosses here.
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

// loadView()/attachmentBounds(…) are declared nonisolated in the SDK, yet the text system
// always calls them on the main thread, where we touch @MainActor-isolated APIs (view,
// fittingSize, …). We reach main-actor state via MainActor.assumeIsolated, passing the
// non-Sendable provider through a main-thread-only box so the Swift 6 region checker is happy.
nonisolated private struct MainThreadOnly<T>: @unchecked Sendable { let value: T }

nonisolated final class DocLinkBubbleProvider: NSTextAttachmentViewProvider {
    private let bubbleTitle: String

    override init(
        textAttachment: NSTextAttachment,
        parentView: NSView?,
        textLayoutManager: NSTextLayoutManager?,
        location: any NSTextLocation
    ) {
        self.bubbleTitle = (textAttachment as? DocLinkBubbleAttachment)?.title ?? ""
        super.init(textAttachment: textAttachment, parentView: parentView,
                   textLayoutManager: textLayoutManager, location: location)
    }

    override func loadView() {
        // Capture only the Sendable title — not 'self' — so the Swift 6 region checker
        // accepts the assumeIsolated boundary.
        let title = bubbleTitle
        let providerBox = MainThreadOnly(value: self)   // wrap non-Sendable provider
        MainActor.assumeIsolated {
            providerBox.value.view = PassthroughHostingView(
                rootView: DocLinkBubbleView(title: title)
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
        return CGRect(x: 0, y: -4, width: size.width, height: size.height) // nudge the capsule onto the text baseline
    }
}

#Preview("Doc link bubbles") {
    VStack(alignment: .leading, spacing: 12) {
        DocLinkBubbleView(title: "setup")                    // short
        DocLinkBubbleView(title: "architecture-overview")    // long
        DocLinkBubbleView(title: "a")                        // single char
    }
    .padding()
}
