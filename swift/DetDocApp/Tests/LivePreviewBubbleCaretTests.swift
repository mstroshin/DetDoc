import AppKit
import Foundation
import Testing
@testable import DetDoc
@testable import DetDocCore

// Verifies the collapse/reveal contract for link bubbles around the caret:
//  - a bubble stays COLLAPSED while the caret rests on either of its edges
//    (so vertical-nav / click landing on a boundary never pops it open), and
//  - reveals only when the caret is STRICTLY inside the @token.
//  - arrowing toward a bubble from an adjacent edge steps the caret one char
//    inside (the bubble is one atomic glyph, so a plain arrow would skip it).
//
// "foo @guides/setup bar" — the token @guides/setup occupies backing range [4,17):
//   f0 o1 o2 ·3 @4 g5 u6 i7 d8 e9 s10 /11 s12 e13 t14 u15 p16 ·17 b18 …
@MainActor
private struct BubbleStack {
    let coord: LivePreviewTextView.Coordinator
    let tv: NSTextView
    let cs: NSTextContentStorage

    init(text: String, existingDocs: Set<String>) {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let editor = DocEditorViewModel(root: tmp, config: .default)
        coord = LivePreviewTextView.Coordinator(
            editor: editor,
            resolver: DocLinkResolver(candidates: existingDocs),
            imageImporter: DocImageImporter(root: tmp),
            candidatesProvider: { [] },
            onFollowLink: { _ in }
        )
        let container = NSTextContainer(size: CGSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        let layoutManager = NSTextLayoutManager()
        layoutManager.textContainer = container
        cs = NSTextContentStorage()
        cs.addTextLayoutManager(layoutManager)
        tv = NSTextView(frame: .zero, textContainer: container)
        tv.string = text
        coord.textView = tv
        cs.delegate = coord
    }

    /// Renders the paragraph at `caret` through the real content-storage delegate and
    /// reports whether the token collapsed to a bubble (object-replacement glyph present
    /// and the raw @token gone) rather than staying as editable raw text.
    func collapsed(caret: Int, rawToken: String) -> Bool {
        tv.setSelectedRange(NSRange(location: caret, length: 0))
        let ns = tv.string as NSString
        let para = ns.paragraphRange(for: NSRange(location: caret, length: 0))
        guard let p = coord.textContentStorage(cs, textParagraphWith: para) else { return false }
        let str = p.attributedString.string
        return str.contains("\u{FFFC}") && !str.contains(rawToken)
    }
}

@MainActor
@Test func bubbleStaysCollapsedOnEdgesRevealsStrictlyInside() {
    let s = BubbleStack(text: "foo @guides/setup bar", existingDocs: ["guides/setup.md"])
    // Wiring sanity: the content storage holds the same backing as the text view.
    #expect(s.cs.textStorage?.length == ("foo @guides/setup bar" as NSString).length)

    let raw = "@guides/setup"
    #expect(s.collapsed(caret: 0, rawToken: raw) == true)    // far away
    #expect(s.collapsed(caret: 4, rawToken: raw) == true)    // absStart — the reported bug
    #expect(s.collapsed(caret: 10, rawToken: raw) == false)  // strictly inside → revealed
    #expect(s.collapsed(caret: 16, rawToken: raw) == false)  // strictly inside (last char) → revealed
    #expect(s.collapsed(caret: 17, rawToken: raw) == true)   // absEnd → stays collapsed
}

@MainActor
@Test func leftArrowStepsIntoBubbleFromAfter() {
    let s = BubbleStack(text: "foo @guides/setup bar", existingDocs: ["guides/setup.md"])
    s.tv.setSelectedRange(NSRange(location: 17, length: 0))   // just after the bubble
    let handled = s.coord.textView(s.tv, doCommandBy: #selector(NSResponder.moveLeft(_:)))
    #expect(handled == true)
    #expect(s.tv.selectedRange().location == 16)             // stepped one char inside
    #expect(s.collapsed(caret: 16, rawToken: "@guides/setup") == false)  // reveals for editing
}

@MainActor
@Test func rightArrowStepsIntoBubbleFromBefore() {
    let s = BubbleStack(text: "foo @guides/setup bar", existingDocs: ["guides/setup.md"])
    s.tv.setSelectedRange(NSRange(location: 4, length: 0))    // just before the bubble
    let handled = s.coord.textView(s.tv, doCommandBy: #selector(NSResponder.moveRight(_:)))
    #expect(handled == true)
    #expect(s.tv.selectedRange().location == 5)              // stepped one char inside
    #expect(s.collapsed(caret: 5, rawToken: "@guides/setup") == false)
}

@MainActor
@Test func verticalNavLeavesCaretBehindLeadingBubble() {
    // "aa\n@guides/setup\nbb" — the bubble leads its line at backing [3,16).
    let s = BubbleStack(text: "aa\n@guides/setup\nbb", existingDocs: ["guides/setup.md"])
    // Down-arrow drops the caret on the bubble line's leading edge (its start, 3).
    s.tv.setSelectedRange(NSRange(location: 3, length: 0))
    s.coord.relocateCaretBehindLeadingBubble()
    #expect(s.tv.selectedRange().location == 16)                          // moved behind the bubble
    #expect(s.collapsed(caret: 16, rawToken: "@guides/setup") == true)    // preview stays collapsed

    // No-op when the caret isn't at a bubble's start (e.g. plain text line).
    s.tv.setSelectedRange(NSRange(location: 1, length: 0))
    s.coord.relocateCaretBehindLeadingBubble()
    #expect(s.tv.selectedRange().location == 1)
}

@MainActor
@Test func leftArrowAtBubbleStartDoesNotStepIn() {
    // At the bubble's START, moving left must leave (not enter) the bubble.
    let s = BubbleStack(text: "foo @guides/setup bar", existingDocs: ["guides/setup.md"])
    s.tv.setSelectedRange(NSRange(location: 4, length: 0))
    let handled = s.coord.textView(s.tv, doCommandBy: #selector(NSResponder.moveLeft(_:)))
    #expect(handled == false)                                // default move runs
}
