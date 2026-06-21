import Foundation

/// Polls `predicate` until true or the timeout elapses; fatalErrors on timeout so a hang fails fast.
func poll(timeout: Double = 5.0, _ predicate: @Sendable () async -> Bool) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await predicate() { return }
        try? await Task.sleep(nanoseconds: 5_000_000)  // 5ms
    }
    fatalError("poll timed out")
}
