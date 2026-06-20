import Foundation
import Testing
@testable import DetDocCore

@Test func splitsOnLineFeedOnlyAndPreservesUnicodeSeparators() throws {
    // Parity with Rust split_jsonl_records: LF-only split, strip trailing CR, keep U+2028 inside JSON.
    // Bytes: {"t":"a<U+2028>b}\n{"ok":true}\r\n
    let input = Data([0x7B,0x22,0x74,0x22,0x3A,0x22,0x61,0xE2,0x80,0xA8,0x62,0x22,0x7D,0x0A,
                      0x7B,0x22,0x6F,0x6B,0x22,0x3A,0x74,0x72,0x75,0x65,0x7D,0x0D,0x0A])
    let records = try PiRpcCodec.splitRecords(input)
    #expect(records == ["{\"t\":\"a\u{2028}b\"}", "{\"ok\":true}"])
}

@Test func splitRecordsThrowsOnInvalidUTF8() {
    let input = Data([0xFF, 0xFE, 0x0A])  // 0xFF/0xFE are not valid UTF-8 lead bytes
    #expect(throws: DetDocError.self) { _ = try PiRpcCodec.splitRecords(input) }
}

@Test func encodesCommandAsSingleLineWithoutEscapingSlashes() throws {
    struct Cmd: Encodable { let type = "prompt"; let message: String }
    let line = try PiRpcCodec.encode(Cmd(message: "docs/a.md"))
    #expect(!line.contains("\n"))
    #expect(line.contains("\"type\":\"prompt\""))
    #expect(line.contains("\"message\":\"docs/a.md\""))  // slash not escaped to \/
}

@Test func drainsOnlyCompleteRecordsAndKeepsRemainder() {
    var buffer = Data("{\"a\":1}\n{\"b\":2}\n{\"partial".utf8)
    let records = PiRpcCodec.drainCompleteRecords(&buffer)
    #expect(records == ["{\"a\":1}", "{\"b\":2}"])
    #expect(String(decoding: buffer, as: UTF8.self) == "{\"partial")
}
