import Foundation
import Testing
@testable import DetDocCore

@Test func imageScanFindsPngToken() {
    let refs = ImageRefScanner.scan("see @guides/assets/window.png here")
    #expect(refs.count == 1)
    #expect(refs[0].path == "guides/assets/window.png")
    // range covers "@guides/assets/window.png" = 25 chars at offset 4
    #expect(refs[0].range == NSRange(location: 4, length: 25))
}

@Test func imageScanRecognizesAllExtensions() {
    for ext in ["png", "jpg", "jpeg", "gif", "heic", "webp"] {
        let refs = ImageRefScanner.scan("@a/b.\(ext)")
        #expect(refs.count == 1, "expected \(ext) to be an image")
    }
}

@Test func imageScanIsCaseInsensitiveOnExtension() {
    let refs = ImageRefScanner.scan("@a/B.PNG")
    #expect(refs.count == 1)
    #expect(refs[0].path == "a/B.PNG")
}

@Test func imageScanIgnoresNonImageTokens() {
    #expect(ImageRefScanner.scan("@guides/setup").isEmpty)
    #expect(ImageRefScanner.scan("@a/b.txt").isEmpty)
}

@Test func imageScanTrimsTrailingPunctuation() {
    // trailing sentence dot is not part of the path; ".png" stays
    let refs = ImageRefScanner.scan("img @a/b.png.")
    #expect(refs.count == 1)
    #expect(refs[0].path == "a/b.png")
    #expect(refs[0].range == NSRange(location: 4, length: 8)) // "@a/b.png"
}

@Test func isImagePathClassifies() {
    #expect(ImageRefScanner.isImagePath("x/y.png"))
    #expect(ImageRefScanner.isImagePath("x/y.JPEG"))
    #expect(!ImageRefScanner.isImagePath("x/y"))
    #expect(!ImageRefScanner.isImagePath("x/y.md"))
}
