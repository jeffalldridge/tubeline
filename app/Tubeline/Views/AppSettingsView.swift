import SwiftUI

struct AppSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var saved = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Startup Defaults") {
                Text("Tubeline starts with your saved conversion settings. Custom settings for individual icons stay with the current batch.")
                    .foregroundStyle(.secondary)
                Button("Use Current Batch Settings as Defaults") {
                    model.saveCurrentAsDefaults()
                    saved = true
                }
                if saved { Label("Defaults Saved", systemImage: "checkmark.circle").foregroundStyle(.secondary) }
                Button("Reset Saved Defaults") { model.resetSavedDefaults(); saved = false }
            }
            Section("Export") {
                Toggle("Export Automatically When Adding SVGs", isOn: $model.exportOnDrop)
                Text("Uses the current batch settings and output destination. Existing files are kept.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).frame(width: 470).padding(.vertical, 8)
    }
}
