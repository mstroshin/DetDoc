import SwiftUI
import AppKit
import DetDocCore

struct LivePreviewTextView: NSViewRepresentable {
    @Bindable var editor: DocEditorViewModel
    var resolver: DocLinkResolver
    var onFollowLink: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(editor: editor, resolver: resolver, onFollowLink: onFollowLink) }

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
        context.coordinator.applyStyling()
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.editor = editor
        context.coordinator.resolver = resolver
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.string != editor.source {           // external change (open/clear)
            tv.string = editor.source
            context.coordinator.applyStyling()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var editor: DocEditorViewModel
        var resolver: DocLinkResolver
        let onFollowLink: (String) -> Void
        weak var textView: NSTextView?
        init(editor: DocEditorViewModel, resolver: DocLinkResolver, onFollowLink: @escaping (String) -> Void) {
            self.editor = editor
            self.resolver = resolver
            self.onFollowLink = onFollowLink
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            editor.edit(tv.string)
            applyStyling()
        }

        func applyStyling() {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let full = NSRange(location: 0, length: (tv.string as NSString).length)
            let caret = tv.selectedRange()
            let spans = MarkdownStyleScanner.scan(tv.string)

            storage.beginEditing()
            storage.setAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.textColor,
            ], range: full)

            for span in spans {
                switch span.kind {
                case let .heading(level):
                    let size: CGFloat = [1: 22, 2: 19, 3: 16].first { $0.key == level }?.value ?? 14
                    storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: size, weight: .bold), range: span.range)
                case .bold:
                    storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold), range: span.range)
                case .italic:
                    if let italic = NSFontManager.shared.convert(.monospacedSystemFont(ofSize: 13, weight: .regular), toHaveTrait: .italicFontMask) as NSFont? {
                        storage.addAttribute(.font, value: italic, range: span.range)
                    }
                case let .link(destination, _):
                    let styledLinks = MarkdownStyleApplier.styledLinkRanges(spans: spans, caret: caret)
                    let isStyled = styledLinks.contains(span)
                    if let res = resolver.resolve(destination) {
                        let color: NSColor = res.exists ? .linkColor : .systemRed
                        storage.addAttribute(.foregroundColor, value: color, range: span.range)
                        if !res.exists {
                            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.patternDot.rawValue | NSUnderlineStyle.single.rawValue, range: span.range)
                            storage.addAttribute(.toolTip, value: "Missing: \(res.docsRelativePath)", range: span.range)
                        }
                        if isStyled, res.exists {
                            storage.addAttribute(.link, value: "detdoc://\(res.docPath)", range: span.range)
                        }
                    }
                }
            }
            storage.endEditing()
        }

        func textViewDidChangeSelection(_ notification: Notification) { applyStyling() }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:)),
                  url.scheme == "detdoc" else { return false }
            let docPath = String(url.absoluteString.dropFirst("detdoc://".count))
            onFollowLink(docPath)
            return true
        }
    }
}
