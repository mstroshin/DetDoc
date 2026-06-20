import Foundation

/// A bidirectional JSONL channel to a `pi --mode rpc` process. Abstracted so `PiAgentRunner`
/// is testable with an in-memory fake and runs live via `PiProcessTransport`.
public protocol PiRpcTransport: Sendable {
    /// Write one command as a single JSONL record (the transport appends the LF delimiter).
    func send(_ line: String) async throws
    /// Decoded JSONL records streamed from pi stdout, in order, until the process ends.
    func events() -> AsyncThrowingStream<String, Error>
    /// Close stdin and let pi exit; idempotent.
    func finish() async
}
