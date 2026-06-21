import Foundation

/// Moves a whole line (paragraph) to another paragraph boundary, preserving the
/// moved line's own-line invariant. Pure string transform — no UI dependencies.
public enum ParagraphMover {
    public struct Move: Equatable, Sendable {
        public let text: String
        public let caret: Int
        public init(text: String, caret: Int) { self.text = text; self.caret = caret }
    }

    /// Moves the line containing `sourceIndex` to `target` (a character index in
    /// `text`, snapped by the caller to a paragraph boundary). Returns nil when the
    /// move changes nothing (target within the source line, or result == input).
    public static func move(in text: String, lineContaining sourceIndex: Int, toBoundary target: Int) -> Move? {
        let ns = text as NSString
        guard ns.length > 0 else { return nil }

        let srcIdx = max(0, min(sourceIndex, ns.length - 1))
        let srcLine = ns.paragraphRange(for: NSRange(location: srcIdx, length: 0))

        // No-op if the target lands inside the source line (or at its own boundaries).
        if target >= srcLine.location && target <= srcLine.location + srcLine.length {
            return nil
        }
        let clampedTarget = max(0, min(target, ns.length))

        // The moved content: one line, no trailing newline.
        var line = ns.substring(with: srcLine)
        while line.hasSuffix("\n") { line.removeLast() }
        guard !line.isEmpty else { return nil }

        // Remove the source line, then translate the target into post-removal coords.
        let remaining = ns.replacingCharacters(in: srcLine, with: "") as NSString
        var insert = clampedTarget
        if clampedTarget > srcLine.location { insert -= srcLine.length }
        insert = max(0, min(insert, remaining.length))

        // Keep the line on its own line at the insertion point.
        let newline: unichar = 10
        let needsLeading = insert > 0 && remaining.character(at: insert - 1) != newline
        let needsTrailing = insert < remaining.length && remaining.character(at: insert) != newline
        var chunk = line
        if needsLeading { chunk = "\n" + chunk }
        if needsTrailing { chunk += "\n" }

        let result = remaining.replacingCharacters(in: NSRange(location: insert, length: 0), with: chunk)
        if result == text { return nil }

        let caret = insert + (needsLeading ? 1 : 0)
        return Move(text: result, caret: caret)
    }
}
