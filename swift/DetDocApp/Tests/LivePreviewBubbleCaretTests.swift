import AppKit
import Foundation
import Testing
@testable import DetDoc
@testable import DetDocCore

// Verifies the collapse/reveal contract for link bubbles around the caret:
//  - a bubble stays COLLAPSED while the caret rests on either of its edges (so a click that
//    snaps the caret to the trailing edge keeps the chip collapsed), and reveals only when
//    the caret is STRICTLY inside the @token OR has stepped into it for editing (arrow-left).
//  - the collapsed display is PADDED back to the backing token's length, so the caret has a
//    real position to render at just after the chip (a length-shortening collapse leaves
//    firstRect degenerate and the caret jumps to the line start).
//  - arrow-left from the trailing edge enters the bubble with the caret at the link's very
//    end; arrow-right from the leading edge steps one char inside.
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

    private func paragraph(at caret: Int) -> NSTextParagraph? {
        tv.setSelectedRange(NSRange(location: caret, length: 0))
        let ns = tv.string as NSString
        let para = ns.paragraphRange(for: NSRange(location: caret, length: 0))
        return coord.textContentStorage(cs, textParagraphWith: para)
    }

    /// Whether the token collapsed to a bubble (object-replacement glyph present and the raw
    /// @token gone) rather than staying as editable raw text.
    func collapsed(caret: Int, rawToken: String) -> Bool {
        guard let p = paragraph(at: caret) else { return false }
        let str = p.attributedString.string
        return str.contains("\u{FFFC}") && !str.contains(rawToken)
    }

    /// The rendered display length of the paragraph at `caret` (for the padding invariant).
    func displayLength(caret: Int) -> Int { paragraph(at: caret)?.attributedString.length ?? -1 }
}

@MainActor
@Test func bubbleStaysCollapsedOnEdgesRevealsStrictlyInside() {
    let s = BubbleStack(text: "foo @guides/setup bar", existingDocs: ["guides/setup.md"])
    #expect(s.cs.textStorage?.length == ("foo @guides/setup bar" as NSString).length)

    let raw = "@guides/setup"
    #expect(s.collapsed(caret: 0, rawToken: raw) == true)    // far away
    #expect(s.collapsed(caret: 4, rawToken: raw) == true)    // absStart (leading edge)
    #expect(s.collapsed(caret: 10, rawToken: raw) == false)  // strictly inside → revealed
    #expect(s.collapsed(caret: 16, rawToken: raw) == false)  // strictly inside (last char) → revealed
    #expect(s.collapsed(caret: 17, rawToken: raw) == true)   // absEnd (trailing edge) → stays collapsed
}

@MainActor
@Test func collapsedBubblePadsToBackingLength() {
    // The collapsed paragraph keeps the SAME length as the backing text — the token is
    // replaced by [attachment + zero-width padding], not a single glyph — so the caret has a
    // valid position to render at right after the chip.
    let s = BubbleStack(text: "foo @guides/setup bar", existingDocs: ["guides/setup.md"])
    let backingLen = ("foo @guides/setup bar" as NSString).length
    #expect(s.collapsed(caret: 0, rawToken: "@guides/setup") == true)  // collapsed
    #expect(s.displayLength(caret: 0) == backingLen)                   // …but display length preserved
}

@MainActor
@Test func leftArrowEntersBubbleAtLinkEnd() {
    // Arrow-left from just after the bubble ENTERS it: the chip reveals and the caret stays
    // at the link's very end (absEnd), ready to edit — it does not jump one char inside.
    let s = BubbleStack(text: "foo @guides/setup bar", existingDocs: ["guides/setup.md"])
    s.tv.setSelectedRange(NSRange(location: 17, length: 0))   // just after the bubble (absEnd)
    let handled = s.coord.textView(s.tv, doCommandBy: #selector(NSResponder.moveLeft(_:)))
    #expect(handled == true)
    #expect(s.tv.selectedRange().location == 17)             // caret rests at the link's very end
    #expect(s.collapsed(caret: 17, rawToken: "@guides/setup") == false)  // revealed for editing at the end

    // A second left press is a normal move — the handler defers to the default mover.
    let again = s.coord.textView(s.tv, doCommandBy: #selector(NSResponder.moveLeft(_:)))
    #expect(again == false)
}

@MainActor
@Test func clickInsideBubbleSnapsCaretToTrailingEdge() {
    // A click landing anywhere inside the collapsed token snaps the caret to the trailing
    // edge (absEnd) — the chip stays collapsed and the caret sits just after it.
    let s = BubbleStack(text: "foo @guides/setup bar", existingDocs: ["guides/setup.md"])
    #expect(s.coord.snapTargetForClick(at: 4) == 17)    // at the bubble's start → after it
    #expect(s.coord.snapTargetForClick(at: 10) == 17)   // mid-bubble → after it
    #expect(s.coord.snapTargetForClick(at: 17) == 17)   // at the trailing edge → stays
    #expect(s.coord.snapTargetForClick(at: 18) == nil)  // past the bubble → no snap
    #expect(s.coord.snapTargetForClick(at: 0) == nil)   // far away → no snap
}

@MainActor
@Test func leavingBubbleAfterEditingRecollapses() {
    // After entering a bubble to edit, moving the caret out clears edit mode and the token
    // collapses back to a chip.
    let s = BubbleStack(text: "foo @guides/setup bar", existingDocs: ["guides/setup.md"])
    s.tv.setSelectedRange(NSRange(location: 17, length: 0))
    _ = s.coord.textView(s.tv, doCommandBy: #selector(NSResponder.moveLeft(_:)))   // enter edit mode
    #expect(s.collapsed(caret: 17, rawToken: "@guides/setup") == false)            // revealed at the end

    s.tv.setSelectedRange(NSRange(location: 19, length: 0))                         // caret out into "bar"
    s.coord.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: s.tv))
    #expect(s.collapsed(caret: 17, rawToken: "@guides/setup") == true)             // collapsed again
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
