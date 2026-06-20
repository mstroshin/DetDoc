import Foundation

public struct ProcessResult: Sendable {
    public let status: Int32
    public let stdout: Data
    public let stderr: Data
    public var stdoutString: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrString: String { String(decoding: stderr, as: UTF8.self) }
}

/// Mutable box used to collect pipe data off concurrent reader queues.
private final class DataBox: @unchecked Sendable {
    var value = Data()
}

public enum ProcessRunner {
    public static func run(
        _ executable: String,
        _ arguments: [String],
        cwd: URL,
        stdin: String? = nil
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.currentDirectoryURL = cwd

        let outPipe = Pipe()
        let errPipe = Pipe()
        let inPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        if stdin != nil { process.standardInput = inPipe }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProcessResult, Error>) in
            let outBox = DataBox()
            let errBox = DataBox()
            let group = DispatchGroup()
            let queue = DispatchQueue(label: "DetDocCore.ProcessRunner", attributes: .concurrent)
            queue.async(group: group) { outBox.value = outPipe.fileHandleForReading.readDataToEndOfFile() }
            queue.async(group: group) { errBox.value = errPipe.fileHandleForReading.readDataToEndOfFile() }

            process.terminationHandler = { proc in
                group.wait()
                continuation.resume(returning: ProcessResult(status: proc.terminationStatus, stdout: outBox.value, stderr: errBox.value))
            }

            do {
                try process.run()
                if let stdin {
                    let handle = inPipe.fileHandleForWriting
                    handle.write(Data(stdin.utf8))
                    try? handle.close()
                }
            } catch {
                continuation.resume(throwing: DetDocError("PROCESS_SPAWN_FAILED", "\(executable): \(error)"))
            }
        }
    }
}
