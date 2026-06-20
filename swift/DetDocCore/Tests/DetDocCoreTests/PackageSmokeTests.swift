import Testing
@testable import DetDocCore

@Test func packageExposesVersion() {
    #expect(DetDocCore.version == "0.1.0")
}
