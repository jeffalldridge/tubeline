import AppKit

/// Remembers sandbox write access to folders the user has granted, as security-scoped
/// bookmarks, so "Save next to original" asks only once per folder.
final class FolderAccess {
    private let defaultsKey = "folderBookmarks"
    private var bookmarks: [String: Data]
    /// Folders currently opened with startAccessingSecurityScopedResource.
    private var active: [String: URL] = [:]

    init() {
        bookmarks = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Data] ?? [:]
    }

    /// True when the app can create files in `folder` right now.
    func canWrite(to folder: URL) -> Bool {
        activate(folder)
        return FileManager.default.isWritableFile(atPath: folder.path)
    }

    /// Makes sure every folder is writable, asking the user for the ones that aren't.
    /// Returns the folders that are still not writable (the user cancelled).
    func ensureWritable(_ folders: [URL]) -> [URL] {
        var denied: [URL] = []
        for folder in Set(folders.map(\.standardizedFileURL)).sorted(by: { $0.path < $1.path }) {
            if canWrite(to: folder) { continue }
            if let granted = ask(for: folder), canWrite(to: granted), granted.standardizedFileURL == folder {
                continue
            }
            denied.append(folder)
        }
        return denied
    }

    /// Records access the user already granted through an open panel.
    func remember(_ folder: URL) {
        guard let data = try? folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil,
                                                  relativeTo: nil) else { return }
        bookmarks[folder.standardizedFileURL.path] = data
        UserDefaults.standard.set(bookmarks, forKey: defaultsKey)
    }

    private func ask(for folder: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.directoryURL = folder
        panel.message = "Tubeline needs permission to save 3D models into “\(folder.lastPathComponent)”."
        panel.prompt = "Allow"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        remember(url)
        return url
    }

    /// Re-opens a remembered bookmark for `folder` or any folder containing it.
    private func activate(_ folder: URL) {
        var path = folder.standardizedFileURL.path
        while true {
            if active[path] == nil, let data = bookmarks[path] {
                var stale = false
                if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                      relativeTo: nil, bookmarkDataIsStale: &stale),
                   url.startAccessingSecurityScopedResource() {
                    active[path] = url
                    if stale { remember(url) }
                }
            }
            if active[path] != nil || path == "/" { return }
            path = (path as NSString).deletingLastPathComponent
        }
    }
}
