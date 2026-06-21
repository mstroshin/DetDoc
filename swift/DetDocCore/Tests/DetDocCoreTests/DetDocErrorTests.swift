import Testing
@testable import DetDocCore

@Test func errorDescriptionIsCodeColonMessage() {
    let error = DetDocError("CONFIG_MISSING", "DetDoc config is missing")
    #expect(error.code == "CONFIG_MISSING")
    #expect(error.message == "DetDoc config is missing")
    #expect(String(describing: error) == "CONFIG_MISSING: DetDoc config is missing")
}
