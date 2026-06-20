import Foundation
import Testing
@testable import DetDocCore

@Test func runIdHasTimestampModeAndHexSuffix() {
    let date = Date(timeIntervalSince1970: 1_750_000_000)  // fixed instant
    let uuid = UUID(uuidString: "1A2B3C4D-0000-0000-0000-000000000000")!
    let id = RunID.create(mode: .run, now: date, uuid: uuid)
    #expect(id.hasSuffix("-run-1a2b3c4d"))
    #expect(id.range(of: #"^\d{8}T\d{6}Z-run-[0-9a-f]{8}$"#, options: .regularExpression) != nil)
}

@Test func runIdUsesFixPrefixForFixMode() {
    let id = RunID.create(mode: .fix)
    #expect(id.range(of: #"^\d{8}T\d{6}Z-fix-[0-9a-f]{8}$"#, options: .regularExpression) != nil)
}
