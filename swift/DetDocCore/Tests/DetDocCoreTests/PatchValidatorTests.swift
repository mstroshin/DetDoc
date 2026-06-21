import Testing
@testable import DetDocCore

@Test func patchTouchingOnlyApprovedTargetsPasses() throws {
    let patch = """
    diff --git a/src/app.ts b/src/app.ts
    --- a/src/app.ts
    +++ b/src/app.ts
    @@ -1 +1 @@
    -old
    +new
    """
    try PatchValidator.validatePaths(patch, approvedTargets: ["src/app.ts"], config: .default)
}

@Test func newFileAgainstDevNullIsAllowedWhenApproved() throws {
    let patch = """
    diff --git a/src/new.ts b/src/new.ts
    --- /dev/null
    +++ b/src/new.ts
    @@ -0,0 +1 @@
    +created
    """
    try PatchValidator.validatePaths(patch, approvedTargets: ["src/new.ts"], config: .default)
}

@Test func unapprovedPathIsRejected() {
    let patch = """
    --- a/src/other.ts
    +++ b/src/other.ts
    """
    #expect { try PatchValidator.validatePaths(patch, approvedTargets: ["src/app.ts"], config: .default) }
        throws: { ($0 as? DetDocError)?.code == "PATCH_UNAPPROVED_PATH" }
}

@Test func deniedPathIsRejected() {
    let patch = """
    --- a/.env
    +++ b/.env
    """
    #expect { try PatchValidator.validatePaths(patch, approvedTargets: [".env"], config: .default) }
        throws: { ($0 as? DetDocError)?.code == "PATCH_DENIED_PATH" }
}

@Test func docPathIsRejected() {
    let patch = """
    --- a/docs/idea.md
    +++ b/docs/idea.md
    """
    #expect { try PatchValidator.validatePaths(patch, approvedTargets: ["docs/idea.md"], config: .default) }
        throws: { ($0 as? DetDocError)?.code == "PATCH_DOC_PATH" }
}

/// G3: even an *approved* patch path must be rejected when it touches run artifacts under
/// `.detdoc/runs/` (parity with the TS PATCH_ARTIFACT_CHANGE guard). Such a path is neither
/// denied, doc, nor unapproved here, so without the artifact guard it would slip through.
@Test func runArtifactPathIsRejected() {
    let patch = """
    --- a/.detdoc/runs/run-1/changes.patch
    +++ b/.detdoc/runs/run-1/changes.patch
    """
    #expect { try PatchValidator.validatePaths(patch, approvedTargets: [".detdoc/runs/run-1/changes.patch"], config: .default) }
        throws: { ($0 as? DetDocError)?.code == "PATCH_ARTIFACT_CHANGE" }
}
