import AppKit
import DetDocCore

/// Drives drag-to-reorder for one inline image preview. A click opens Quick Look; a
/// pan moves the image's token line to another paragraph boundary, with a live
/// insertion indicator. Created per preview by DocImageProvider and retained by it.
@MainActor
final class DocImageDragController: NSObject {
    private let onOpen: () -> Void
    private let sourceIndex: Int            // backing char index inside the token's line
    private weak var editor: DocEditorViewModel?
    private weak var hostingView: NSView?
    private var indicator: NSView?
    private var liveSourceIndex: Int?
    private var clickRecognizer: NSClickGestureRecognizer?
    private var panRecognizer: NSPanGestureRecognizer?

    init(hostingView: NSView, onOpen: @escaping () -> Void, sourceIndex: Int, editor: DocEditorViewModel) {
        self.hostingView = hostingView
        self.onOpen = onOpen
        self.sourceIndex = sourceIndex
        self.editor = editor
        super.init()
        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        self.clickRecognizer = click
        self.panRecognizer = pan
        click.delegate = self
        hostingView.addGestureRecognizer(click)
        hostingView.addGestureRecognizer(pan)
    }

    @objc private func handleClick() { onOpen() }

    private func enclosingTextView() -> NSTextView? {
        var v: NSView? = hostingView?.superview
        while let cur = v {
            if let tv = cur as? NSTextView { return tv }
            v = cur.superview
        }
        return nil
    }

    @objc private func handlePan(_ g: NSPanGestureRecognizer) {
        guard let tv = enclosingTextView() else { return }
        switch g.state {
        case .began:
            hostingView?.alphaValue = 0.4
            liveSourceIndex = currentSourceIndex(in: tv)
            if let target = targetBoundary(in: tv, at: g.location(in: tv)) {
                positionIndicator(in: tv, atBoundary: target)
            }
        case .changed:
            if let target = targetBoundary(in: tv, at: g.location(in: tv)) {
                positionIndicator(in: tv, atBoundary: target)
            }
        case .ended:
            defer { endDrag() }
            if let target = targetBoundary(in: tv, at: g.location(in: tv)) {
                commitMove(in: tv, toBoundary: target)
            }
        default:
            endDrag()
        }
    }

    private func targetBoundary(in tv: NSTextView, at point: NSPoint) -> Int? {
        let ns = tv.string as NSString
        guard ns.length > 0 else { return nil }
        let idx = max(0, min(tv.characterIndexForInsertion(at: point), ns.length))
        let para = ns.paragraphRange(for: NSRange(location: min(idx, ns.length - 1), length: 0))
        return para.location
    }

    private func positionIndicator(in tv: NSTextView, atBoundary boundary: Int) {
        var rect = tv.firstRect(forCharacterRange: NSRange(location: boundary, length: 0), actualRange: nil)
        if rect == .zero { return }   // no glyph rect (e.g. document end) — skip
        if let win = tv.window {
            rect = win.convertFromScreen(rect)
            rect = tv.convert(rect, from: nil)
        }
        let inset = tv.textContainerInset.width
        let bar = indicator ?? makeIndicator(in: tv)
        bar.frame = NSRect(x: inset, y: rect.minY - 1, width: max(0, tv.bounds.width - inset * 2), height: 2)
    }

    private func makeIndicator(in tv: NSTextView) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        tv.addSubview(v)
        indicator = v
        return v
    }

    private func commitMove(in tv: NSTextView, toBoundary target: Int) {
        let srcIndex = liveSourceIndex ?? sourceIndex
        guard let editor,
              let move = ParagraphMover.move(in: tv.string, lineContaining: srcIndex, toBoundary: target)
        else { return }
        let full = NSRange(location: 0, length: (tv.string as NSString).length)
        guard tv.shouldChangeText(in: full, replacementString: move.text) else { return }
        tv.textStorage?.replaceCharacters(in: full, with: move.text)
        tv.didChangeText()
        let caret = max(0, min(move.caret, (move.text as NSString).length))
        tv.setSelectedRange(NSRange(location: caret, length: 0))
        editor.edit(tv.string)
    }

    private func endDrag() {
        indicator?.removeFromSuperview()
        indicator = nil
        hostingView?.alphaValue = 1.0
        liveSourceIndex = nil
    }

    /// The preview stays in place during a drag, so its current frame maps to the
    /// token's LIVE backing index — robust against edits made above it since the
    /// provider was built (the cached sourceIndex can go stale).
    private func currentSourceIndex(in tv: NSTextView) -> Int {
        guard let host = hostingView else { return sourceIndex }
        let ns = tv.string as NSString
        guard ns.length > 0 else { return sourceIndex }
        let frame = host.convert(host.bounds, to: tv)
        let point = NSPoint(x: frame.midX, y: frame.midY)
        return max(0, min(tv.characterIndexForInsertion(at: point), ns.length - 1))
    }
}

extension DocImageDragController: NSGestureRecognizerDelegate {
    // The click should only fire when the pan does NOT begin, so a real drag never
    // also triggers Quick Look.
    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer,
                           shouldRequireFailureOf other: NSGestureRecognizer) -> Bool {
        gestureRecognizer === clickRecognizer && other === panRecognizer
    }
}
