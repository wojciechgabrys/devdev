import CoreServices
import Foundation

/// A running watch on one folder. It ends on `stop()` or when released.
public protocol FolderWatch: AnyObject, Sendable {
    func stop()
}

/// Starts watching a folder and its subfolders. `onChange` gets absolute paths of changed files.
public typealias FolderWatcherFactory =
    @Sendable (_ folder: String, _ onChange: @escaping @Sendable ([String]) -> Void) -> (any FolderWatch)?

/// Watches a folder tree with FSEvents, file by file. Nothing is ignored.
public final class FSEventsFolderWatcher: FolderWatch, @unchecked Sendable {
    public static let factory: FolderWatcherFactory = { folder, onChange in
        FSEventsFolderWatcher(folder: folder, onChange: onChange)
    }

    private let onChange: @Sendable ([String]) -> Void
    private let queue = DispatchQueue(label: "dev.devdev.folder-watch")
    /// Only touched on `queue`, apart from `init`.
    private var stream: FSEventStreamRef?

    public init?(folder: String, latency: TimeInterval = 0.05, onChange: @escaping @Sendable ([String]) -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil,
            copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FSEventsFolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let changed = (unsafeBitCast(paths, to: NSArray.self) as? [String]) ?? []
            if !changed.isEmpty { watcher.onChange(Array(changed.prefix(count))) }
        }
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard
            let stream = FSEventStreamCreate(
                nil, callback, &context, [folder] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                latency, flags)
        else { return nil }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return nil
        }
        self.stream = stream
    }

    /// Ends the watch. No callback runs after it returns.
    public func stop() {
        queue.sync {
            guard let stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    deinit {
        stop()
    }
}
