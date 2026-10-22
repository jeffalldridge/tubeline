import AppKit
import UniformTypeIdentifiers

enum Panels {
    @MainActor
    static func chooseSVGs() -> [URL] {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = true
        p.allowedContentTypes = [.svg, .folder]
        p.prompt = "Add"
        return p.runModal() == .OK ? p.urls : []
    }

    @MainActor
    static func chooseFolder() -> URL? {
        let p = NSOpenPanel()
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.canCreateDirectories = true
        p.prompt = "Choose"
        return p.runModal() == .OK ? p.url : nil
    }
}
