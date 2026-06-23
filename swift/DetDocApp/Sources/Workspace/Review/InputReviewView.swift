import SwiftUI

/// Pre-run modal: shows the documentation diff that will drive the run and gates the start.
struct InputReviewView: View {
    let diff: String
    let onRun: () -> Void
    let onCancel: () -> Void

    private var files: [DiffFile] { DiffModel.parse(diff) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review changes before running").font(.headline)
            Text("\(files.count) documentation file(s) will drive this run.")
                .font(.caption).foregroundStyle(.secondary)
            DiffFilesView(files: files).frame(maxHeight: 320)
            HStack {
                Button("Run", action: onRun)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("input-review-run")
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("input-review-cancel")
            }.padding(.top, 4)
        }
        .padding()
        .frame(minWidth: 480, minHeight: 360)
        .accessibilityIdentifier("input-review-sheet")
    }
}

private let oneFileDiff = """
diff --git a/docs/idea.md b/docs/idea.md
--- a/docs/idea.md
+++ b/docs/idea.md
@@ -1,2 +1,2 @@
-old idea
+new idea
 unchanged
"""

private let manyFilesDiff = oneFileDiff + "\n" + """
diff --git a/docs/api.md b/docs/api.md
--- a/docs/api.md
+++ b/docs/api.md
@@ -1 +1,2 @@
 intro
+added line
"""

private let largeDiff = "diff --git a/docs/big.md b/docs/big.md\n--- a/docs/big.md\n+++ b/docs/big.md\n@@ -1,40 +1,40 @@\n"
    + (1...40).map { "+line \($0)" }.joined(separator: "\n")

#Preview("Single file") {
    InputReviewView(diff: oneFileDiff, onRun: {}, onCancel: {})
}

#Preview("Many files") {
    InputReviewView(diff: manyFilesDiff, onRun: {}, onCancel: {})
}

#Preview("Large diff (scrolls)") {
    InputReviewView(diff: largeDiff, onRun: {}, onCancel: {})
}
