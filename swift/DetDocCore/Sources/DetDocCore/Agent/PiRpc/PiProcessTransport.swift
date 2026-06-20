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

        do {
            try process.run()
        } catch {
            throw DetDocError("PI_RPC_SPAWN_FAILED", "\(executable): \(error)")
        }
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
                if chunk.isEmpty {  // EOF
                    handle.readabilityHandler = nil
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
}
