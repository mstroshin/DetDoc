import Foundation

/// Live `pi --mode rpc` subprocess transport: spawns pi via `/usr/bin/env`, writes commands
/// to stdin, and streams LF-delimited JSONL records from stdout. Models the concurrency
/// approach of `ProcessRunner` (NSLock-guarded boxes, @unchecked Sendable).
public final class PiProcessTransport: PiRpcTransport, @unchecked Sendable {
    private let process: Process
    private let stdinHandle: FileHandle
    private let stdoutHandle: FileHandle
    private let stderrHandle: FileHandle
    private let lock = NSLock()
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var didFinish = false

    public init(executable: String, arguments: [String], cwd: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.currentDirectoryURL = cwd
        process.environment = SubprocessEnv.augmenting()  // GUI apps lack /opt/homebrew/bin in PATH
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe
        self.process = process
        self.stdinHandle = inPipe.fileHandleForWriting
        self.stdoutHandle = outPipe.fileHandleForReading
        self.stderrHandle = errPipe.fileHandleForReading

        // Drain stderr continuously so a chatty pi can't deadlock by filling the pipe buffer.
        stderrHandle.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self, !chunk.isEmpty else { return }
            self.lock.lock(); self.stderrBuffer.append(chunk); self.lock.unlock()
        }

        DetDocLog.process.notice("spawn pi: \(executable, privacy: .public) \(arguments.joined(separator: " "), privacy: .public)")
        do {
            try process.run()
        } catch {
            DetDocLog.process.error("pi spawn failed: \(error.localizedDescription, privacy: .public)")
            throw DetDocError("PI_RPC_SPAWN_FAILED", "\(executable): \(error)")
        }
        DetDocLog.process.info("pi running pid=\(process.processIdentifier, privacy: .public)")
    }

    public func send(_ line: String) async throws {
        let data = Data((line + "\n").utf8)
        var shouldWrite = false
        lock.withLock { shouldWrite = !didFinish }
        guard shouldWrite else { return }
        do {
            try stdinHandle.write(contentsOf: data)
        } catch {
            throw DetDocError("PI_RPC_WRITE_FAILED", "Failed to write to pi stdin: \(error)")
        }
    }

    public func events() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            stdoutHandle.readabilityHandler = { [weak self] handle in
                guard let self else { return }
                let chunk = handle.availableData
                if chunk.isEmpty {  // EOF — flush any unterminated trailing record (pi's final
                    handle.readabilityHandler = nil  // agent_end line may arrive without a LF).
                    self.lock.lock()
                    let tail = self.stdoutBuffer
                    self.stdoutBuffer = Data()
                    self.lock.unlock()
                    for record in (try? PiRpcCodec.splitRecords(tail)) ?? [] { continuation.yield(record) }
                    continuation.finish()
                    return
                }
                self.lock.lock()
                self.stdoutBuffer.append(chunk)
                let records = PiRpcCodec.drainCompleteRecords(&self.stdoutBuffer)
                self.lock.unlock()
                for record in records { continuation.yield(record) }
            }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.finish() }
            }
        }
    }

    public func finish() async {
        var already = false
        lock.withLock { already = didFinish; didFinish = true }
        guard !already else { return }
        stdoutHandle.readabilityHandler = nil
        stderrHandle.readabilityHandler = nil
        try? stdinHandle.close()
        if process.isRunning { process.terminate() }
    }

    /// Exit status plus the tail of pi's stderr — surfaced when the stream ends without a
    /// result so transient failures (auth, rate limits, provider errors) aren't a black box.
    /// Call after `finish()`: the stderr handler is already detached, so the final read is safe.
    public func diagnostics() async -> String {
        process.waitUntilExit()
        let captured: Data = lock.withLock {
            if let rest = try? stderrHandle.readToEnd() { stderrBuffer.append(rest) }
            return stderrBuffer
        }
        let signaled = process.terminationReason == .uncaughtSignal
        let status = process.terminationStatus
        DetDocLog.process.notice("pi \(signaled ? "killed by signal" : "exited", privacy: .public) status=\(status, privacy: .public)")
        var lines = ["pi \(signaled ? "killed by signal" : "exited with status") \(status)"]
        if let text = String(data: captured, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { lines.append("pi stderr: \(String(trimmed.suffix(2000)))") }
        }
        return lines.joined(separator: "\n")
    }
}
