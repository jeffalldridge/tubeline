import Foundation

/// Item-provider callbacks may arrive on different queues.
final class DroppedURLs: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        urls.append(url)
    }

    var values: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls.sorted { $0.path < $1.path }
    }
}
