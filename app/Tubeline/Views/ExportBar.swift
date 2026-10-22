import SwiftUI

struct ExportBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = model.exportError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red).font(.callout).textSelection(.enabled)
            }
            if model.isExporting {
                HStack(spacing: 12) {
                    ProgressView(value: model.exportProgress).frame(maxWidth: 220)
                    Text("Exporting \(model.exportCompleted) of \(model.exportTotal)…")
                        .font(.callout.monospacedDigit())
                    Spacer()
                    Button("Cancel Export") { model.cancelExports() }
                        .keyboardShortcut(.cancelAction)
                        .help("Stop unfinished exports (Escape or Command-period). Completed files are kept.")
                }
            } else if let summary = model.exportSummary {
                HStack {
                    Text(summary).font(.callout).foregroundStyle(.secondary)
                    if !failedJobs.isEmpty {
                        Button("Retry Failed") { model.export(failedJobs) }.controlSize(.small)
                    }
                }
            }
            HStack(spacing: 12) {
                Text("USDZ").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                Divider().frame(height: 22)
                Picker("Save To", selection: destinationBinding) {
                    Text("Next to Original").tag(AppModel.Destination.besideOriginal)
                    Text("Folder…").tag(AppModel.Destination.folder)
                }
                .fixedSize()
                .disabled(model.isExporting)
                if model.destination == .folder {
                    Button {
                        if let folder = Panels.chooseFolder() { model.folder = folder }
                    } label: {
                        Text(model.folder?.lastPathComponent ?? "Choose Folder…")
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .help(model.folder?.path ?? "Choose an output folder.")
                    .frame(maxWidth: 180)
                    .disabled(model.isExporting)
                }
                Spacer(minLength: 8)
                if model.selectedJob?.exportedURL != nil {
                    Button("Show in Finder") { model.revealSelectedExport() }
                }
                if model.jobs.count > 1 {
                    Button("Export Selected") { model.exportSelected() }
                        .disabled(model.selectedJob == nil || model.isExporting || (model.destination == .folder && model.folder == nil))
                }
                Button(exportTitle) { model.exportAll() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.jobs.isEmpty || model.isExporting || (model.destination == .folder && model.folder == nil))
            }
            Text("Existing files are kept. New exports receive a unique name when needed.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var exportTitle: String {
        model.jobs.count == 1 ? "Export Icon" : "Export \(model.jobs.count) Icons"
    }

    private var failedJobs: [Job] {
        model.jobs.filter { if case .failed = $0.status { return true }; return false }
    }

    private var destinationBinding: Binding<AppModel.Destination> {
        Binding(get: { model.destination }, set: { destination in
            if destination == .folder {
                if let folder = Panels.chooseFolder() {
                    model.folder = folder
                    model.destination = .folder
                }
            } else {
                model.destination = destination
            }
        })
    }
}
