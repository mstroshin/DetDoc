import Foundation
import CoreServices

/// Watches a directory subtree via FSEvents and calls `onChange` (on the main
/// actor) whenever anything under it is created, deleted, or renamed — even
/// while DetDoc is in the foreground. Stops automatically on deinit.
///
/// ponytail: changes are coalesced with a 0.3s latency — fine for a docs tree,
/// not a high-frequency change feed.
nonisolated final class DirectoryWatcher {
    private let stream: FSEventStreamRef?

    init(_ url: URL, onChange: @escaping @MainActor () -> Void) {
        let box = Box(onChange)
        var ctx = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(box).toOpaque(),
            retain: nil,
            release: { ptr in if let ptr { Unmanaged<Box>.fromOpaque(ptr).release() } },
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<Box>.fromOpaque(info).takeUnretainedValue().fire()
        }
        let stream = FSEventStreamCreate(
            nil, callback, &ctx,
            [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        )
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            FSEventStreamStart(stream)
        }
        self.stream = stream
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    /// Bridges the @MainActor callback across the C function-pointer boundary.
    /// `fire()` runs on the main queue (we set the stream's dispatch queue to it).
    nonisolated private final class Box {
        let onChange: @MainActor () -> Void
        init(_ onChange: @escaping @MainActor () -> Void) { self.onChange = onChange }
        func fire() {
            let onChange = self.onChange
            MainActor.assumeIsolated { onChange() }
        }
    }
}
