import SwiftUI
import AppKit
import DetDocCore

struct LivePreviewTextView: NSViewRepresentable {
    @Bindable var editor: DocEditorViewModel
    var resolver: DocLinkResolver
    var candidatesProvider: () -> [DocCandidate]
    var onFollowLink: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(editor: editor, resolver: resolver,
                    candidatesProvider: candidatesProvider,
                    onFollowLink: onFollowLink)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        let tv = scroll.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.textContainerInset = NSSize(width: 12, height: 12)
        tv.string = editor.source
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        context.coordinator.textView = tv
        if let tcs = tv.textLayoutManager?.textContentManager as? NSTextContentStorage {
            tcs.delegate = context.coordinator
        }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.editor = editor
        context.coordinator.resolver = resolver
        context.coordinator.candidatesProvider = candidatesProvider
        context.coordinator.onFollowLink = onFollowLink
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.string != editor.source {           // external change (open/clear)
            tv.string = editor.source
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, @preconcurrency NSTextContentStorageDelegate {
        var editor: DocEditorViewModel
        var resolver: DocLinkResolver
        var candidatesProvider: () -> [DocCandidate]
        var onFollowLink: (String) -> Void
        weak var textView: NSTextView?

        let completion = DocLinkCompletionModel()
        private var panel: NSPanel?
        private var cachedCandidates: [DocCandidate] = []
        private var lastCaret = 0

        init(editor: DocEditorViewModel, resolver: DocLinkResolver,
             candidatesProvider: @escaping () -> [DocCandidate],
             onFollowLink: @escaping (String) -> Void) {
            self.editor = editor
            self.resolver = resolver
            self.candidatesProvider = candidatesProvider
            self.onFollowLink = onFollowLink
        }

        // MARK: - NSTextContentStorageDelegate

        func textContentStorage(_ tcs: NSTextContentStorage, textParagraphWith range: NSRange) -> NSTextParagraph? {
            guard let storage = tcs.textStorage, range.location >= 0,
                  range.location + range.length <= storage.length else { return nil }
            let raw = storage.attributedSubstring(from: range)
            let spans = MarkdownStyleScanner.scan(raw.string)
            let refs = DocRefScanner.scan(raw.string)
            if spans.isEmpty && refs.isEmpty { return nil }   // plain paragraph -> default rendering

            let display = NSMutableAttributedString(attributedString: raw)
            let full = NSRange(location: 0, length: (raw.string as NSString).length)
            display.setAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.textColor,
            ], range: full)

            let caret = textView?.selectedRange().location ?? -1
            let paraStart = range.location

            // Pending modifications to apply highest-offset-first after styling.
            // nil replacement = delete; non-nil = replace with attachment.
            var modifications: [(range: NSRange, replacement: NSAttributedString?)] = []

            // --- Heading / bold / italic ---
            for span in spans {
                switch span.kind {
                case let .heading(level):
                    let size: CGFloat = [1: 22, 2: 19, 3: 16].first { $0.key == level }?.value ?? 14
                    display.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: size, weight: .bold), range: span.range)
                case .bold:
                    display.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold), range: span.range)
                case .italic:
                    if let it = NSFontManager.shared.convert(.monospacedSystemFont(ofSize: 13, weight: .regular), toHaveTrait: .italicFontMask) as NSFont? {
                        display.addAttribute(.font, value: it, range: span.range)
                    }
                }
            }

            // --- @-token links ---
            for ref in refs {
                let absStart = paraStart + ref.range.location
                let absEnd = absStart + ref.range.length
                let caretInLink = caret >= absStart && caret < absEnd

                if let res = resolver.resolve(ref.path) {
                    if res.exists {
                        // Always apply link color + .link attribute (so cmd-click works on revealed tokens too).
                        display.addAttribute(.foregroundColor, value: NSColor.linkColor, range: ref.range)
                        display.addAttribute(.link, value: "detdoc://\(res.docPath)", range: ref.range)

                        if !caretInLink {
                            // Collapse to a Liquid Glass bubble.
                            let docName = String(ref.path.split(separator: "/").last ?? Substring(ref.path))
                            let docPath = res.docPath
                            let bubble = DocLinkBubbleAttachment(title: docName) { [weak self] in
                                self?.onFollowLink(docPath)
                            }
                            modifications.append((range: ref.range, replacement: NSAttributedString(attachment: bubble)))
                        }
                    } else {
                        // Broken token: red dotted — no bubble, regardless of caret.
                        display.addAttribute(.foregroundColor, value: NSColor.systemRed, range: ref.range)
                        display.addAttribute(.underlineStyle, value: NSUnderlineStyle.patternDot.rawValue | NSUnderlineStyle.single.rawValue, range: ref.range)
                        display.addAttribute(.toolTip, value: "Missing: \(res.docsRelativePath)", range: ref.range)
                    }
                }
                // If resolver returns nil (empty path), nothing is styled — token stays as-is.
            }

            // Apply highest-offset-first so earlier paragraph-local offsets stay valid.
            for mod in modifications.sorted(by: { $0.range.location > $1.range.location }) {
                if let replacement = mod.replacement {
                    display.replaceCharacters(in: mod.range, with: replacement)
                } else {
                    display.deleteCharacters(in: mod.range)
                }
            }
            return NSTextParagraph(attributedString: display)
        }

        // MARK: - Panel management

        private func showPanel() {
            let host = NSHostingController(rootView: DocLinkSuggestionsView(model: completion) { [weak self] i in
                self?.completion.selectByTap(i)
                self?.commitCompletion()
            })
            let p = NSPanel(contentViewController: host)
            p.styleMask = [.nonactivatingPanel, .borderless]
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.level = .popUpMenu
            panel = p
        }

        private func positionPanel() {
            guard let tv = textView, let win = tv.window, let panel else { return }
            let caret = tv.selectedRange()
            var rect = tv.firstRect(forCharacterRange: NSRange(location: caret.location, length: 0), actualRange: nil)
            if rect == .zero {
                let fallbackLoc = max(0, caret.location - 1)
                rect = tv.firstRect(forCharacterRange: NSRange(location: fallbackLoc, length: 1), actualRange: nil)
            }
            panel.setFrameTopLeftPoint(NSPoint(x: rect.minX, y: rect.minY - 6))
            if panel.parent == nil { win.addChildWindow(panel, ordered: .above) }
        }

        private func hidePanel() {
            if let p = panel { p.parent?.removeChildWindow(p); p.orderOut(nil) }
            panel = nil
        }

        // MARK: - Completion logic

        private func updateCompletion(allowOpen: Bool) {
            guard let tv = textView else { return }
            let cursor = tv.selectedRange().location
            guard let q = DocLinkCompletion.activeQuery(in: tv.string, cursorUTF16Offset: cursor) else {
                if completion.isActive { completion.cancel(); hidePanel() }
                return
            }
            if !completion.isActive { cachedCandidates = candidatesProvider() }
            if completion.isActive {
                completion.update(query: q, caretRect: .zero, candidates: cachedCandidates)
                positionPanel()
            } else {
                guard allowOpen else { return }
                completion.begin(query: q, caretRect: .zero, candidates: cachedCandidates)
                if panel == nil { showPanel() }
                positionPanel()
            }
        }

        private func commitCompletion() {
            guard let tv = textView, let ins = completion.commit() else { return }
            if tv.shouldChangeText(in: ins.range, replacementString: ins.text) {
                tv.textStorage?.replaceCharacters(in: ins.range, with: ins.text)
                tv.didChangeText()
                tv.setSelectedRange(NSRange(location: ins.range.location + (ins.text as NSString).length, length: 0))
            }
            editor.edit(tv.string)
            hidePanel()
            // Force refresh of the paragraph containing the inserted token so it collapses immediately.
            let insertEnd = ins.range.location + (ins.text as NSString).length
            refreshCaretParagraphs(old: insertEnd, new: insertEnd)
        }

        // MARK: - Refresh helper

        /// Returns the document-absolute NSRange of the @-token span (if any) that
        /// contains `caret`, or nil if the caret is not inside a token.
        private func linkRange(atCaret caret: Int) -> NSRange? {
            guard let storage = textView?.textStorage, caret >= 0, caret <= storage.length else { return nil }
            let ns = storage.string as NSString
            let para = ns.paragraphRange(for: NSRange(location: min(caret, max(0, ns.length - 1)), length: 0))
            let paraStr = ns.substring(with: para)
            for ref in DocRefScanner.scan(paraStr) {
                let absStart = para.location + ref.range.location
                let absEnd = absStart + ref.range.length
                if caret >= absStart && caret < absEnd { return NSRange(location: absStart, length: absEnd - absStart) }
            }
            return nil
        }

        func refreshCaretParagraphs(old: Int, new: Int) {
            guard let storage = textView?.textStorage else { return }
            let ns = storage.string as NSString
            func paraRange(_ loc: Int) -> NSRange {
                let l = max(0, min(loc, ns.length))
                return ns.paragraphRange(for: NSRange(location: l, length: 0))
            }
            let union = NSUnionRange(paraRange(old), paraRange(new))
            storage.beginEditing()
            storage.edited(.editedAttributes, range: union, changeInLength: 0)
            storage.endEditing()
        }

        // MARK: - NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            editor.edit(tv.string)
            // Editing already makes the content storage re-run the delegate for changed
            // paragraphs, so no manual refresh needed here.
            updateCompletion(allowOpen: true)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            let new = textView?.selectedRange().location ?? 0
            let oldLink = linkRange(atCaret: lastCaret)
            let newLink = linkRange(atCaret: new)
            if oldLink != newLink {
                refreshCaretParagraphs(old: lastCaret, new: new)
            }
            lastCaret = new
            updateCompletion(allowOpen: false)
        }

        // Dismiss the picker when the text view loses focus.
        func textDidEndEditing(_ notification: Notification) {
            if completion.isActive { completion.cancel(); hidePanel() }
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard completion.isActive else { return false }
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                completion.moveUp(); return true
            case #selector(NSResponder.moveDown(_:)):
                completion.moveDown(); return true
            case #selector(NSResponder.insertNewline(_:)):
                commitCompletion(); return true
            case #selector(NSResponder.cancelOperation(_:)):
                completion.cancel(); hidePanel(); return true
            default:
                return false
            }
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard NSApp.currentEvent?.modifierFlags.contains(.command) == true else { return false }
            let raw: String?
            if let s = link as? String { raw = s }
            else if let url = link as? URL { raw = url.absoluteString.removingPercentEncoding ?? url.absoluteString }
            else { raw = nil }
            guard let s = raw, s.hasPrefix("detdoc://") else { return false }
            onFollowLink(String(s.dropFirst("detdoc://".count)))
            return true
        }
    }
}
