import SwiftUI
import AppKit
import Quartz
import DetDocCore

struct LivePreviewTextView: NSViewRepresentable {
    @Bindable var editor: DocEditorViewModel
    var resolver: DocLinkResolver
    var imageImporter: DocImageImporter
    var candidatesProvider: () -> [DocCandidate]
    var onFollowLink: (String) -> Void
    var showCodeLinks: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(editor: editor, resolver: resolver,
                    imageImporter: imageImporter,
                    candidatesProvider: candidatesProvider,
                    onFollowLink: onFollowLink,
                    showCodeLinks: showCodeLinks)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true

        // TextKit 2 stack so the content-storage delegate (live preview) works.
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        let layoutManager = NSTextLayoutManager()
        layoutManager.textContainer = container
        let contentStorage = NSTextContentStorage()
        contentStorage.addTextLayoutManager(layoutManager)

        let tv = ImageDropTextView(frame: .zero, textContainer: container)
        tv.coordinator = context.coordinator
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]

        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.textContainerInset = NSSize(width: 12, height: 12)
        tv.string = editor.source
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        // No automatic link styling: the bubble carries a .link (for cmd-click follow) and the
        // default blue underline/color would peek out from behind the translucent glass chip.
        // Revealed @links keep their own explicit linkColor; cmd-click still works (it's driven
        // by the .link attribute, not this styling).
        tv.linkTextAttributes = [:]
        context.coordinator.textView = tv
        contentStorage.delegate = context.coordinator

        tv.registerForDraggedTypes([.fileURL, .tiff, .png])

        scroll.documentView = tv
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.editor = editor
        context.coordinator.resolver = resolver
        context.coordinator.imageImporter = imageImporter
        context.coordinator.candidatesProvider = candidatesProvider
        context.coordinator.onFollowLink = onFollowLink
        let changed = context.coordinator.showCodeLinks != showCodeLinks
        context.coordinator.showCodeLinks = showCodeLinks
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.string != editor.source {           // external change (open/clear)
            tv.string = editor.source
        }
        if changed { context.coordinator.refreshAllParagraphs() }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, @preconcurrency NSTextContentStorageDelegate {
        var editor: DocEditorViewModel
        var resolver: DocLinkResolver
        var imageImporter: DocImageImporter
        var candidatesProvider: () -> [DocCandidate]
        var onFollowLink: (String) -> Void
        var showCodeLinks = false
        weak var textView: NSTextView?

        let completion = DocLinkCompletionModel()
        private var panel: NSPanel?
        let quickLook = ImageQuickLookSource()
        private var cachedCandidates: [DocCandidate] = []
        private var lastCaret = 0
        // True while the user has stepped INTO a bubble (arrow-left at its trailing edge) to
        // edit the link. It reveals the raw @text while the caret rests at the link's very
        // end (absEnd) — a spot that, when NOT editing, instead reads as "after the collapsed
        // bubble". Cleared by any click and once the caret leaves the token.
        private var editingBubble = false
        private var pendingCanvasInsertIndex = 0
        private var canvasSheet: NSWindow?

        init(editor: DocEditorViewModel, resolver: DocLinkResolver,
             imageImporter: DocImageImporter,
             candidatesProvider: @escaping () -> [DocCandidate],
             onFollowLink: @escaping (String) -> Void,
             showCodeLinks: Bool = false) {
            self.editor = editor
            self.resolver = resolver
            self.imageImporter = imageImporter
            self.candidatesProvider = candidatesProvider
            self.onFollowLink = onFollowLink
            self.showCodeLinks = showCodeLinks
        }

        func refreshAllParagraphs() {
            guard let storage = textView?.textStorage else { return }
            storage.beginEditing()
            storage.edited(.editedAttributes, range: NSRange(location: 0, length: storage.length), changeInLength: 0)
            storage.endEditing()
        }

        // MARK: - NSTextContentStorageDelegate

        func textContentStorage(_ tcs: NSTextContentStorage, textParagraphWith range: NSRange) -> NSTextParagraph? {
            guard let storage = tcs.textStorage, range.location >= 0,
                  range.location + range.length <= storage.length else { return nil }
            let raw = storage.attributedSubstring(from: range)
            let spans = MarkdownStyleScanner.scan(raw.string)
            let refs = DocRefScanner.scan(raw.string)
            let imageRefs = ImageRefScanner.scan(raw.string)
            let codeLinkRanges = CodeLinkScanner.scan(raw.string)
            if spans.isEmpty && refs.isEmpty && imageRefs.isEmpty && codeLinkRanges.isEmpty { return nil }   // plain paragraph -> default rendering

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
                // Collapsed while the caret is away or at the LEADING edge; revealed once it
                // is inside or at the TRAILING edge (see `reveals`).
                let caretInLink = reveals(caret: caret, absStart: absStart, absEnd: absEnd)

                if let res = resolver.resolve(ref.path) {
                    if res.exists {
                        // Always apply link color + .link attribute (so cmd-click works on revealed tokens too).
                        display.addAttribute(.foregroundColor, value: NSColor.linkColor, range: ref.range)
                        display.addAttribute(.link, value: "detdoc://\(res.docPath)", range: ref.range)

                        if !caretInLink {
                            // Collapse to a Liquid Glass bubble. Carry the link on the bubble
                            // glyph itself so a cmd-click follows it (via clickedOnLink), exactly
                            // like a revealed token — a plain click instead lands the caret after it.
                            let docName = String(ref.path.split(separator: "/").last ?? Substring(ref.path))
                            let bubble = DocLinkBubbleAttachment(title: docName)
                            let bubbleStr = NSMutableAttributedString(attachment: bubble)
                            // Pad the display back to the backing token's length with
                            // (near) zero-width chars, so the backing<->display mapping stays
                            // 1:1 and the caret can render at a valid x right AFTER the bubble
                            // (a length-shortening collapse leaves firstRect degenerate at x=0).
                            let padCount = max(0, ref.range.length - 1)
                            if padCount > 0 {
                                let pad = NSMutableAttributedString(string: String(repeating: " ", count: padCount))
                                pad.addAttribute(.font, value: NSFont.systemFont(ofSize: 0.01),
                                                 range: NSRange(location: 0, length: padCount))
                                bubbleStr.append(pad)
                            }
                            bubbleStr.addAttribute(.link, value: "detdoc://\(res.docPath)",
                                                   range: NSRange(location: 0, length: bubbleStr.length))
                            modifications.append((range: ref.range, replacement: bubbleStr))
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

            // --- @-token images ---
            for img in imageRefs {
                let absStart = paraStart + img.range.location
                let absEnd = absStart + img.range.length
                let caretInToken = reveals(caret: caret, absStart: absStart, absEnd: absEnd)   // see caretInLink note

                if let url = imageImporter.resolve(img.path) {
                    display.addAttribute(.foregroundColor, value: NSColor.linkColor, range: img.range)
                    if !caretInToken {
                        let attachment = DocImageAttachment(url: url, editor: editor) { [weak self] in
                            self?.openQuickLook(url)
                        }
                        modifications.append((range: img.range, replacement: NSAttributedString(attachment: attachment)))
                    }
                } else {
                    display.addAttribute(.foregroundColor, value: NSColor.systemRed, range: img.range)
                    display.addAttribute(.underlineStyle, value: NSUnderlineStyle.patternDot.rawValue | NSUnderlineStyle.single.rawValue, range: img.range)
                    display.addAttribute(.toolTip, value: "Missing image: \(img.path)", range: img.range)
                }
            }

            // --- detdoc:link comments ---
            for r in codeLinkRanges {
                if showCodeLinks {
                    display.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: r)
                    display.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), range: r)
                } else {
                    modifications.append((range: r, replacement: nil))   // delete from display
                }
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

        func openQuickLook(_ url: URL) {
            quickLook.url = url
            // QLPreviewPanel follows the responder chain — ensure the text view
            // (which implements QLPreviewPanelController) is first responder so the
            // panel adopts our data source, then present or refresh it.
            if let tv = textView { tv.window?.makeFirstResponder(tv) }
            guard let panel = QLPreviewPanel.shared() else { return }
            if panel.isVisible {
                panel.reloadData()
            } else {
                panel.makeKeyAndOrderFront(nil)
            }
        }

        // MARK: - Image drop / paste

        /// Returns true if the drag carried image file URLs or raster data that we
        /// imported and inserted as @-tokens.
        func handleImageDrop(_ sender: any NSDraggingInfo, into tv: NSTextView) -> Bool {
            guard let docPath = editor.selectedPath else { return false }
            let pb = sender.draggingPasteboard
            let point = tv.convert(sender.draggingLocation, from: nil)
            let charIndex = tv.characterIndexForInsertion(at: point)

            var tokens: [String] = []
            let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
            if let urls = pb.readObjects(forClasses: [NSURL.self], options: opts) as? [URL] {
                for url in urls where ImageRefScanner.isImagePath(url.lastPathComponent) {
                    if let token = try? imageImporter.importFile(at: url, forDoc: docPath) { tokens.append(token) }
                }
            }
            if tokens.isEmpty, let data = imageData(from: pb),
               let token = try? imageImporter.importData(data, basename: Self.generatedBasename(), forDoc: docPath) {
                tokens.append(token)
            }
            // Imported files already live in assets/; if nothing is inserted they are
            // left as harmless orphans (no cleanup — acceptable per the spec edge-cases).
            guard !tokens.isEmpty else { return false }
            insertImageTokens(tokens, at: charIndex, in: tv)
            return true
        }

        /// Returns true if the pasteboard held image data (and no plain text) that we
        /// imported and inserted at the caret.
        func handleImagePaste(into tv: NSTextView) -> Bool {
            guard let docPath = editor.selectedPath else { return false }
            let pb = NSPasteboard.general
            if pb.string(forType: .string) != nil { return false }   // let normal text paste win
            guard let data = imageData(from: pb),
                  let token = try? imageImporter.importData(data, basename: Self.generatedBasename(), forDoc: docPath)
            else { return false }
            insertImageTokens([token], at: tv.selectedRange().location, in: tv)
            return true
        }

        private func imageData(from pb: NSPasteboard) -> Data? {
            if let png = pb.data(forType: .png) { return png }
            if let tiff = pb.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) { return png }
            return nil
        }

        private func insertImageTokens(_ tokens: [String], at index: Int, in tv: NSTextView) {
            let ns = tv.string as NSString
            let loc = max(0, min(index, ns.length))
            let newline = UInt16(UnicodeScalar("\n").value)
            let needsLeading = loc > 0 && ns.character(at: loc - 1) != newline
            let needsTrailing = loc < ns.length && ns.character(at: loc) != newline
            var text = tokens.map { "@\($0)" }.joined(separator: "\n")
            if needsLeading { text = "\n" + text }
            if needsTrailing { text += "\n" }
            let range = NSRange(location: loc, length: 0)
            if tv.shouldChangeText(in: range, replacementString: text) {
                tv.textStorage?.replaceCharacters(in: range, with: text)
                tv.didChangeText()
                tv.setSelectedRange(NSRange(location: loc + (text as NSString).length, length: 0))
            }
            // Routed outside the shouldChangeText guard on purpose — mirrors commitCompletion().
            editor.edit(tv.string)
        }

        private static func generatedBasename() -> String {
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmmss"
            return "image-\(f.string(from: Date()))"
        }

        // MARK: - Canvas sketch

        /// Whether the "Создать канвас" context-menu item should be offered — only
        /// when a document is open (so the sketch has an `assets/` folder to land in).
        var canCreateCanvas: Bool { editor.selectedPath != nil }

        /// Invoked by the context-menu item; `index` is the click's char offset.
        @objc func createCanvasMenuAction(_ sender: NSMenuItem) {
            let index = (sender.representedObject as? Int) ?? (textView?.selectedRange().location ?? 0)
            presentCanvasSheet(insertAt: index)
        }

        private func presentCanvasSheet(insertAt index: Int) {
            guard canvasSheet == nil, let host = textView?.window else { return }
            pendingCanvasInsertIndex = index
            let view = CanvasSketchView(
                onInsert: { [weak self] data in self?.finishCanvas(with: data) },
                onCancel: { [weak self] in self?.dismissCanvasSheet() }
            )
            let sheet = NSWindow(contentViewController: NSHostingController(rootView: view))
            sheet.setContentSize(NSSize(width: 640, height: 520))
            canvasSheet = sheet
            host.beginSheet(sheet) { [weak self] _ in self?.canvasSheet = nil }
        }

        private func dismissCanvasSheet() {
            guard let sheet = canvasSheet else { return }
            (sheet.sheetParent ?? textView?.window)?.endSheet(sheet)
        }

        private func finishCanvas(with data: Data) {
            defer { dismissCanvasSheet() }
            guard let docPath = editor.selectedPath, let tv = textView,
                  let token = try? imageImporter.importData(data, basename: Self.generatedBasename(), forDoc: docPath)
            else { return }
            let idx = max(0, min(pendingCanvasInsertIndex, (tv.string as NSString).length))
            insertImageTokens([token], at: idx, in: tv)
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

        /// Returns the document-absolute NSRange of the @-token span (doc link OR
        /// image) that contains `caret`, or nil if the caret is not inside a token.
        private func tokenRange(atCaret caret: Int) -> NSRange? {
            guard let storage = textView?.textStorage, caret >= 0, caret <= storage.length else { return nil }
            let ns = storage.string as NSString
            let para = ns.paragraphRange(for: NSRange(location: min(caret, max(0, ns.length - 1)), length: 0))
            let paraStr = ns.substring(with: para)
            let ranges = DocRefScanner.scan(paraStr).map(\.range) + ImageRefScanner.scan(paraStr).map(\.range)
            for r in ranges {
                let absStart = para.location + r.location
                let absEnd = absStart + r.length
                // Strict-inside reveal — the editing-at-end case is tracked separately via
                // editingBubble, so this stays the plain strict predicate.
                if caret > absStart && caret < absEnd { return NSRange(location: absStart, length: absEnd - absStart) }
            }
            return nil
        }

        /// A token shows its raw @text (instead of a bubble) when the caret is inside it or
        /// at its trailing edge (absEnd). `textContentStorage(_:textParagraphWith:)` and
        /// `tokenRange(atCaret:)` both gate on this, so the rendered state and the
        /// caret/refresh logic can't drift apart.
        private func reveals(caret: Int, absStart: Int, absEnd: Int) -> Bool {
            // Strictly inside always; the trailing edge (absEnd) only while editing. So a
            // click that lands the caret at absEnd keeps the bubble COLLAPSED (the caret
            // still renders just after it thanks to the zero-width display padding), and
            // arrow-left reveals the raw @text to edit the link from its very end.
            (caret > absStart && caret < absEnd) || (editingBubble && caret == absEnd)
        }

        /// Whether `caret` still sits within a collapsed token's editable span — strictly
        /// inside, or at its trailing edge (absEnd). Link-edit mode stays active while this
        /// holds and is cleared once the caret moves out (to the token's start or past it).
        private func caretEditingEligible(_ caret: Int) -> Bool {
            guard let tok = collapsedTokenRange(containing: caret) else { return false }
            return caret > tok.location
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
            let wasEditing = editingBubble
            // Exit link-edit mode on any click (so a click re-collapses the bubble and never
            // re-opens it), or once the caret leaves the token's editable span.
            if editingBubble, isMouseClick(NSApp.currentEvent) || !caretEditingEligible(new) {
                editingBubble = false
            }
            // Refresh on a strict-inside flip, or when edit mode just ended (so the token
            // revealed at its end re-collapses).
            let oldToken = tokenRange(atCaret: lastCaret)
            let newToken = tokenRange(atCaret: new)
            if oldToken != newToken || (wasEditing && !editingBubble) {
                refreshCaretParagraphs(old: lastCaret, new: new)
            }
            lastCaret = new
            updateCompletion(allowOpen: false)
        }

        // A collapsed token (link bubble or image) is one display glyph standing in for the
        // whole `@token` backing text, so TextKit maps a click in its area to an arbitrary
        // boundary of that range. Snap any click inside a collapsed token to its END: the
        // caret lands at the link's trailing edge, which reveals the raw @text (a caret can't
        // render after a collapsed trailing glyph) so the user can edit/type right there.
        func textView(_ textView: NSTextView,
                      willChangeSelectionFromCharacterRanges oldSelectedCharRanges: [NSValue],
                      toCharacterRanges newSelectedCharRanges: [NSValue]) -> [NSValue] {
            guard isMouseClick(NSApp.currentEvent),
                  newSelectedCharRanges.count == 1,
                  let proposed = newSelectedCharRanges.first?.rangeValue,
                  proposed.length == 0,
                  let target = snapTargetForClick(at: proposed.location)
            else { return newSelectedCharRanges }

            return [NSValue(range: NSRange(location: target, length: 0))]
        }

        /// The caret offset a click should snap to — just AFTER the bubble — when it lands
        /// inside a collapsed token, or nil when it falls outside every collapsed token.
        func snapTargetForClick(at p: Int) -> Int? {
            collapsedTokenRange(containing: p).map { $0.location + $0.length }
        }

        private func isMouseClick(_ e: NSEvent?) -> Bool {
            switch e?.type {
            case .leftMouseDown, .leftMouseUp: return true
            default: return false
            }
        }

        /// The backing range of a resolvable (collapsed) doc-link or image token whose
        /// span contains `p` (inclusive of both ends), or nil. Broken tokens render as
        /// raw text — not collapsed — so they are deliberately excluded.
        private func collapsedTokenRange(containing p: Int) -> NSRange? {
            guard let storage = textView?.textStorage, p >= 0, p <= storage.length else { return nil }
            let ns = storage.string as NSString
            guard ns.length > 0 else { return nil }
            let para = ns.paragraphRange(for: NSRange(location: min(p, ns.length - 1), length: 0))
            let paraStr = ns.substring(with: para)
            for ref in DocRefScanner.scan(paraStr) {
                guard let res = resolver.resolve(ref.path), res.exists else { continue }
                let absStart = para.location + ref.range.location
                let absEnd = absStart + ref.range.length
                if p >= absStart && p <= absEnd { return NSRange(location: absStart, length: ref.range.length) }
            }
            for img in ImageRefScanner.scan(paraStr) {
                guard imageImporter.resolve(img.path) != nil else { continue }
                let absStart = para.location + img.range.location
                let absEnd = absStart + img.range.length
                if p >= absStart && p <= absEnd { return NSRange(location: absStart, length: img.range.length) }
            }
            return nil
        }

        // Dismiss the picker when the text view loses focus.
        func textDidEndEditing(_ notification: Notification) {
            if completion.isActive { completion.cancel(); hidePanel() }
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if !completion.isActive {
                // A collapsed bubble is one atomic glyph, so a plain arrow skips the whole
                // `@token`. Arrow-LEFT from the trailing edge ENTERS the bubble: reveal the
                // raw @path and keep the caret at the link's very end, ready to edit. Arrow-
                // RIGHT from the leading edge steps one char inside to reveal it too.
                let caret = textView.selectedRange().location
                switch selector {
                case #selector(NSResponder.moveLeft(_:)):
                    if !editingBubble, collapsedToken(endingAt: caret) != nil {
                        editingBubble = true
                        refreshCaretParagraphs(old: caret, new: caret)
                        return true
                    }
                case #selector(NSResponder.moveRight(_:)):
                    if let tok = collapsedToken(startingAt: caret) {
                        textView.setSelectedRange(NSRange(location: tok.location + 1, length: 0))
                        return true
                    }
                default:
                    break
                }
                return false
            }
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

        /// Collapsed token whose END coincides with `caret` (caret sits just after the bubble).
        private func collapsedToken(endingAt caret: Int) -> NSRange? {
            guard let tok = collapsedTokenRange(containing: caret),
                  tok.location + tok.length == caret else { return nil }
            return tok
        }

        /// Collapsed token whose START coincides with `caret` (caret sits just before the bubble).
        private func collapsedToken(startingAt caret: Int) -> NSRange? {
            guard let tok = collapsedTokenRange(containing: caret),
                  tok.location == caret else { return nil }
            return tok
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

// QLPreviewPanel's data-source methods are nonisolated in the SDK but the panel only
// drives them on the main thread; @preconcurrency + @MainActor satisfies Swift 6.
@MainActor
final class ImageQuickLookSource: NSObject, @preconcurrency QLPreviewPanelDataSource {
    var url: URL?
    func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int { url == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> any QLPreviewItem {
        (url as NSURL?) ?? NSURL(fileURLWithPath: "/")
    }
}
