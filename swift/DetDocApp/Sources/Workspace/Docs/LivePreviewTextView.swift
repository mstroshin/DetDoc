import SwiftUI
import AppKit
import DetDocCore

struct LivePreviewTextView: NSViewRepresentable {
    @Bindable var editor: DocEditorViewModel

    func makeCoordinator() -> Coordinator { Coordinator(editor: editor) }

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
        context.coordinator.textView = tv
        context.coordinator.applyStyling()
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.editor = editor
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.string != editor.source {           // external change (open/clear)
            tv.string = editor.source
            context.coordinator.applyStyling()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var editor: DocEditorViewModel
        weak var textView: NSTextView?
        init(editor: DocEditorViewModel) { self.editor = editor }

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
                case .link:
                    break   // links styled in Task 7 (needs the resolver)
                }
            }
            _ = MarkdownStyleApplier.styledLinkRanges(spans: spans, caret: caret)  // wired in Task 7
            storage.endEditing()
        }

        func textViewDidChangeSelection(_ notification: Notification) { applyStyling() }
    }
}
