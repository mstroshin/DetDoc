import Foundation
@testable import DetDocCore

/// An in-memory `PiRpcTransport` for tests: records sent command lines and replays a fixed
/// script of stdout JSONL records.
final class FakePiTransport: PiRpcTransport, @unchecked Sendable {
    private let scriptLines: [String]
    private let diagnosticsText: String
    private let lock = NSLock()
    private var sent: [String] = []

    init(scriptLines: [String], diagnostics: String = "") {
        self.scriptLines = scriptLines
        self.diagnosticsText = diagnostics
    }

    var sentLines: [String] { lock.lock(); defer { lock.unlock() }; return sent }

    func diagnostics() async -> String { diagnosticsText }

    func send(_ line: String) async throws {
        lock.withLock { sent.append(line) }
    }

    func events() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            for line in scriptLines { continuation.yield(line) }
            continuation.finish()
        }
    }

    func finish() async {}
}
