import Foundation

/// Strict JSONL framing + command encoding for the `pi --mode rpc` wire protocol.
///
/// Parity anchor: Rust `split_jsonl_records` (src-tauri/src/detdoc/pi_rpc.rs) — split on
/// LF (`0x0A`) only, strip a trailing CR (`0x0D`), drop empty records, and never split on
/// Unicode separators (U+2028/U+2029) that are valid inside JSON strings.
public enum PiRpcCodec {
    /// Split a UTF-8 byte buffer into JSONL records. Operates on bytes so framing matches
    /// the Rust reference exactly. Throws `PI_RPC_UTF8_INVALID` on invalid UTF-8.
    public static func splitRecords(_ data: Data) throws -> [String] {
        var records: [String] = []
        for chunk in data.split(separator: 0x0A, omittingEmptySubsequences: false) {
            var bytes = chunk
            if bytes.last == 0x0D { bytes = bytes.dropLast() }  // strip a trailing CR
            if bytes.isEmpty { continue }
            guard let line = String(bytes: bytes, encoding: .utf8) else {
                throw DetDocError("PI_RPC_UTF8_INVALID", "pi emitted invalid UTF-8 on stdout")
            }
            records.append(line)
        }
        return records
    }

    /// Encode an `Encodable` command as a single-line JSON string (no trailing newline;
    /// the transport appends the LF delimiter). Slashes are not escaped so paths stay readable.
    public static func encode<C: Encodable>(_ command: C) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(command)
        guard let line = String(data: data, encoding: .utf8) else {
            throw DetDocError("PI_RPC_ENCODE_FAILED", "Failed to encode pi RPC command")
        }
        return line
    }

    /// Extract complete LF-terminated records from `buffer`, leaving any trailing partial
    /// record behind. Used by the streaming transport to emit lines as they arrive. LF never
    /// falls inside a multi-byte UTF-8 sequence, so complete portions always decode cleanly.
    public static func drainCompleteRecords(_ buffer: inout Data) -> [String] {
        guard let lastLF = buffer.lastIndex(of: 0x0A) else { return [] }
        let complete = Data(buffer[..<buffer.index(after: lastLF)])
        let remainder = Data(buffer[buffer.index(after: lastLF)...])
        buffer = remainder
        return (try? splitRecords(complete)) ?? []
    }
}
