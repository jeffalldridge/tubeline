import SwiftUI

struct FileList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: Binding(get: { model.selection }, set: { model.select($0) })) {
            ForEach(model.jobs) { job in
                JobRow(job: job).tag(job.id)
                    .contextMenu {
                        if let url = job.exportedURL {
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        }
                        Button("Export Icon") { model.export([job]) }.disabled(model.isExporting)
                        Button("Refresh SVG") { model.select(job.id); model.refreshSelected() }
                        Divider()
                        Button(job.status == .working ? "Cancel Export and Remove" : "Remove") { model.remove(job) }
                    }
            }
        }
        .overlay {
            if model.jobs.isEmpty { Text("No Icons Yet").foregroundStyle(.tertiary) }
        }
        .safeAreaInset(edge: .bottom) {
            if !model.jobs.isEmpty {
                HStack {
                    Text(model.jobs.count == 1 ? "1 icon" : "\(model.jobs.count) icons")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") { model.clear() }.disabled(model.isExporting)
                }
                .font(.callout).padding(12)
            }
        }
    }
}
