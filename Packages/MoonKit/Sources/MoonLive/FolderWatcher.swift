#if os(macOS)
import CoreServices
import Foundation

/// Yields each time anything under `folders` changes, recursively, however
/// the file got saved. Bursts arrive merged by FSEvents' latency.
public func folderChanges(_ folders: [URL], latency: TimeInterval = 0.05) -> AsyncStream<Void> {
    AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
        let box = Unmanaged.passRetained(ContinuationBox(continuation))
        var context = FSEventStreamContext(
            version: 0, info: box.toOpaque(), retain: nil, release: nil, copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        let created = FSEventStreamCreate(
            nil,
            { _, info, _, _, _, _ in
                guard let info else { return }
                Unmanaged<ContinuationBox>.fromOpaque(info).takeUnretainedValue().continuation.yield()
            },
            &context, folders.map(\.path) as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags
        )
        guard let created else {
            box.release()
            continuation.finish()
            return
        }
        nonisolated(unsafe) let stream = created
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        continuation.onTermination = { _ in
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            box.release()
        }
    }
}

private final class ContinuationBox: Sendable {
    let continuation: AsyncStream<Void>.Continuation

    nonisolated init(_ continuation: AsyncStream<Void>.Continuation) {
        self.continuation = continuation
    }
}
#endif
