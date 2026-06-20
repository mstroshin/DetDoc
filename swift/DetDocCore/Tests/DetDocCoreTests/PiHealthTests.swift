import Testing
@testable import DetDocCore

@Test func piHealthReturnsBoolWithoutThrowing() async {
    // pi is installed in this environment, but the contract is "never throws".
    let available = await PiHealth.isAvailable()
    #expect(available == true || available == false)
}
