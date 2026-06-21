import Foundation
import DetDocCore

enum MarkdownStyleApplier {
    static func styledLinkRanges(spans: [MarkdownSpan], caret: NSRange) -> [MarkdownSpan] {
        spans.filter { span in
            guard case .link = span.kind else { return false }
            return !NSLocationInRange(caret.location, NSRange(location: span.range.location, length: span.range.length + 1))
        }
    }
}
