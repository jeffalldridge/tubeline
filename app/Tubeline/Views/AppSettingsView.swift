import SwiftUI

struct AppSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Default Mesh") {
                MeshControls(detail: $model.startupOptions.facets, optimize: $model.startupOptions.optimize)
                Text("Saved automatically for new sessions. Choose Restore Saved Defaults to apply them to the current batch.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Default Shape and Size") {
                LabeledSlider(title: "Thickness", value: $model.startupOptions.thickness, range: 0.25...3, step: 0.05,
                              format: { String(format: "%.2f×", $0) })
                HStack {
                    Text("Output Scale")
                    Spacer()
                    TextField("Default Output Scale", value: $model.startupOptions.outputScale, format: .number)
                        .labelsHidden().multilineTextAlignment(.trailing).frame(width: 55)
                    Text("×").foregroundStyle(.secondary)
                    Stepper("Default Output Scale", value: $model.startupOptions.outputScale, in: 1...10_000)
                        .labelsHidden().fixedSize()
                }
            }
            Section("All Conversion Defaults") {
                Button("Use Current Batch Settings as Defaults") { model.saveCurrentAsDefaults() }
                Button("Reset Saved Defaults") { model.resetSavedDefaults() }
            }
            Section("Export") {
                Toggle("Export Automatically When Adding SVGs", isOn: $model.exportOnDrop)
                Text("Uses the current batch settings and output destination. Existing files are kept.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).frame(width: 470, height: 620).padding(.vertical, 8)
    }
}
