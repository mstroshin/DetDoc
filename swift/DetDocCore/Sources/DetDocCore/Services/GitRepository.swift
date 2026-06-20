import Foundation
import CryptoKit

public struct GitStatusEntry: Sendable, Equatable {
    public let status: String
    public let path: String
    public init(status: String, path: String) {
        self.status = status
        self.path = path
    }
}

public struct GitRepository: Sendable {
    public let cwd: URL
    public init(_ cwd: URL) { self.cwd = cwd }

    @discardableResult
    public func git(_ args: [String], stdin: String? = nil) async throws -> String {
        let result: ProcessResult
        do {
            result = try await ProcessRunner.run("git", ["-c", "core.quotepath=false"] + args, cwd: cwd, stdin: stdin)
        } catch {
            throw DetDocError("GIT_SPAWN_FAILED", "\(error)")
        }
        guard result.status == 0 else {
            throw DetDocError("GIT_COMMAND_FAILED", "git \(args.joined(separator: " ")): \(result.stderrString)")
        }
        return result.stdoutString
    }

    public func headCommit() async throws -> String {
        try await git(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func statusPorcelain() async throws -> [GitStatusEntry] {
        let output = try await git(["status", "--porcelain", "-uall"])
        return output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let text = String(line)
            guard text.count >= 4 else { return nil }
            let status = String(text.prefix(2))
            let path = String(text.dropFirst(3))
            return GitStatusEntry(status: status, path: path)
        }
    }

    public func applyPatch(_ patch: String) async throws {
        let result: ProcessResult
        do {
            result = try await ProcessRunner.run(
                "git", ["-c", "core.quotepath=false", "apply", "--binary", "--whitespace=nowarn", "-"],
                cwd: cwd, stdin: patch
            )
        } catch {
            throw DetDocError("GIT_APPLY_SPAWN_FAILED", "\(error)")
        }
        guard result.status == 0 else {
            throw DetDocError("GIT_APPLY_FAILED", result.stderrString)
        }
    }

    public func diffPaths(_ paths: [String]) async throws -> String {
        guard !paths.isEmpty else { return "" }
        return try await git(["diff", "--no-color", "--no-ext-diff", "--binary", "--"] + paths)
    }

    public func changedFilesFromPatch(_ patch: String) async throws -> [String] {
        let output = try await git(["apply", "--numstat", "-"], stdin: patch)
        return output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            line.split(separator: "\t").last.map(String.init)
        }
    }

    public func fileSha256(_ relativePath: String) -> String? {
        guard let data = try? Data(contentsOf: cwd.appendingPathComponent(relativePath)) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
