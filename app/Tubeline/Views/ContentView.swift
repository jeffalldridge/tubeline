import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                FileList()
                    .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 340)
            } detail: {
                HStack(spacing: 0) {
                    PreviewPane()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    SettingsPanel().frame(width: 310)
                }
            }
            .frame(minHeight: 0, maxHeight: .infinity)
            ExportBar()
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            loadURLs(providers)
            return true
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .padding(6).allowsHitTesting(false)
            }
        }
        .toolbar {
            ToolbarItem {
                Button { model.add(Panels.chooseSVGs()) } label: {
                    Label("Add SVGs…", systemImage: "plus").labelStyle(.titleAndIcon)
                }
                .help("Add SVG files or folders. Preview them before exporting.")
            }
        }
    }

    private func loadURLs(_ providers: [NSItemProvider]) {
        // Gather a drop before adding it so overlapping files and folders are deduplicated together.
        let group = DispatchGroup()
        let collector = DroppedURLs()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { collector.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) { model.add(collector.values) }
    }
}
