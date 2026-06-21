import Testing
@testable import DetDoc

@Test func parseClassifiesLinesPerFile() {
    let patch = """
    diff --git a/src/a.swift b/src/a.swift
    index 111..222 100644
    --- a/src/a.swift
    +++ b/src/a.swift
    @@ -1,2 +1,2 @@
     keep
    -old
    +new
    """
    let files = DiffModel.parse(patch)
    #expect(files.count == 1)
    #expect(files[0].path == "src/a.swift")
    #expect(files[0].lines.contains(DiffLine(kind: .addition, text: "+new")))
    #expect(files[0].lines.contains(DiffLine(kind: .deletion, text: "-old")))
    #expect(files[0].lines.contains(DiffLine(kind: .hunk, text: "@@ -1,2 +1,2 @@")))
    #expect(files[0].lines.contains(DiffLine(kind: .context, text: " keep")))
}

@Test func parseSplitsMultipleFiles() {
    let patch = """
    diff --git a/x b/x
    +++ b/x
    +x
    diff --git a/y b/y
    +++ b/y
    +y
    """
    #expect(DiffModel.parse(patch).map(\.path) == ["x", "y"])
}

@Test func parseMultiSegmentPathWithoutPlusPlusHeader() {
    // Regression: the old replacingOccurrences(of:"b/") would mangle b/lib/sub/x → lisux.
    // Mode-only diffs have no +++ b/ header so the fallback path from diff --git is used.
    let patch = """
    diff --git a/lib/sub/x b/lib/sub/x
    old mode 100644
    new mode 100755
    """
    let files = DiffModel.parse(patch)
    #expect(files.count == 1)
    #expect(files[0].path == "lib/sub/x")
}
