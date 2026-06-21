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

    final class Coordinator: NSObject, NSTextViewDelegate {
        var editor: DocEditorViewModel
        weak var textView: NSTextView?
        init(editor: DocEditorViewModel) { self.editor = editor }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            editor.edit(tv.string)
            applyStyling()
        }

        func applyStyling() { /* filled in Task 6 */ }
    }
}
