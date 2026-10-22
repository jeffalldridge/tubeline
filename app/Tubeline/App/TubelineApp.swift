import SwiftUI
import AppKit

@main
struct TubelineApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("Tubeline", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 1080, minHeight: 680)
        }
        .defaultSize(width: 1180, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add SVGs…") { model.add(Panels.chooseSVGs()) }
                    .keyboardShortcut("o")
            }
            CommandMenu("Icons") {
                Button("Export All") { model.exportAll() }
                    .disabled(model.jobs.isEmpty || model.isExporting)
                Button("Export Selected") { model.exportSelected() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(model.selectedJob == nil || model.isExporting)
                Button("Refresh Selected SVG") { model.refreshSelected() }
                    .keyboardShortcut("r")
                    .disabled(model.selectedJob == nil)
                Button("Show Export in Finder") { model.revealSelectedExport() }
                    .disabled(model.selectedJob?.exportedURL == nil)
            }
        }
        Settings {
            AppSettingsView().environment(model)
        }
    }
}
