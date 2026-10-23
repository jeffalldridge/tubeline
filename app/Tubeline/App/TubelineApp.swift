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
                .frame(minWidth: 940, minHeight: 560)
        }
        .defaultSize(width: 1180, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add SVGs…") { model.add(Panels.chooseSVGs()) }
                    .keyboardShortcut("o")
            }
            CommandMenu("Icons") {
                Button("Export All") { model.exportAll() }
                    .keyboardShortcut("e")
                    .disabled(model.jobs.isEmpty || model.isExporting)
                Button("Export Selected") { model.exportSelected() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(model.selectedJob == nil || model.isExporting)
                Button("Refresh Selected SVG") { model.refreshSelected() }
                    .keyboardShortcut("r")
                    .disabled(model.selectedJob == nil)
                Button("Show Export in Finder") { model.revealSelectedExport() }
                    .disabled(model.selectedJob?.exportedURL == nil)
                Divider()
                Button(model.selectedJob?.status == .working ? "Cancel Export and Remove Icon" : "Remove Selected Icon") {
                    if let job = model.selectedJob { model.remove(job) }
                }
                .disabled(model.selectedJob == nil)
                Button("Cancel Export") { model.cancelExports() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!model.isExporting)
            }
            CommandGroup(after: .sidebar) {
                Divider()
                Button("Fit Model") { model.cameraRequest = PreviewCameraRequest(mode: .fit) }
                    .keyboardShortcut("0")
                    .disabled(model.previewURL == nil)
                Button("Front View") { model.cameraRequest = PreviewCameraRequest(mode: .front) }
                    .keyboardShortcut("1")
                    .disabled(model.previewURL == nil)
                Button("Reset View") { model.cameraRequest = PreviewCameraRequest(mode: .reset) }
                    .keyboardShortcut("2")
                    .disabled(model.previewURL == nil)
                Menu("Orbit Model") {
                    Button("Left") { model.cameraRequest = PreviewCameraRequest(mode: .orbitLeft) }
                    Button("Right") { model.cameraRequest = PreviewCameraRequest(mode: .orbitRight) }
                    Button("Up") { model.cameraRequest = PreviewCameraRequest(mode: .orbitUp) }
                    Button("Down") { model.cameraRequest = PreviewCameraRequest(mode: .orbitDown) }
                }
                .disabled(model.previewURL == nil)
            }
        }
        Settings {
            AppSettingsView().environment(model)
        }
    }
}
