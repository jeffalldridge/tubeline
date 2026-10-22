import SwiftUI

struct PreviewPane: View {
    @Environment(AppModel.self) private var model
    @AppStorage("showForm") private var showForm = false
    @State private var cameraRequest = PreviewCameraRequest()
    @State private var renderingError: String?

    var body: some View {
        if let job = model.selectedJob {
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(job.name).font(.title3.weight(.semibold)).lineLimit(1)
                        Text(job.source.path).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle).help(job.source.path)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Triangles").font(.caption).foregroundStyle(.secondary)
                        Text(model.previewStats?.triangles.formatted() ?? "—")
                            .font(.title2.weight(.semibold).monospacedDigit())
                        if model.previewBusy { Text("Updating…").font(.caption2).foregroundStyle(.secondary) }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Triangle Count")
                    .accessibilityValue(model.previewStats.map { $0.triangles.formatted() } ?? "Updating")
                    Button("Refresh SVG", systemImage: "arrow.clockwise") { model.refreshSelected() }
                        .labelStyle(.iconOnly).help("Reload changes saved in your SVG editor.")
                }
                .padding(16)
                Divider()
                ZStack {
                    ModelPreview(url: model.previewURL, subject: model.selection, showForm: showForm, cameraRequest: cameraRequest, renderingError: $renderingError)
                        .accessibilityLabel("3D Preview of \(job.name)")
                        .accessibilityValue(previewDescription)
                    if model.previewBusy && model.previewURL == nil {
                        VStack(spacing: 10) {
                            ProgressView()
                            Text("Building Preview…").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    if let error = model.previewError ?? renderingError {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle").font(.title)
                            Text(error).multilineTextAlignment(.center).textSelection(.enabled)
                            Button("Try Again") { model.refreshSelected() }
                        }
                        .padding(24).frame(maxWidth: 360)
                        .background(.regularMaterial, in: .rect(cornerRadius: 12)).padding()
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .contentShape(Rectangle())
                .clipped()
                .overlay(alignment: .top) {
                    HStack(spacing: 8) {
                        Picker("Preview Material", selection: $showForm) {
                            Text("Export Material").tag(false)
                            Text("Show Form").tag(true)
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                        .help("Show Form uses studio lighting to inspect geometry. It does not change the export.")
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                }
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 12) {
                        Button("Fit") { cameraRequest = PreviewCameraRequest(mode: .fit) }
                            .keyboardShortcut("0", modifiers: .command)
                            .help("Frame the model without changing the viewing angle (Command-0).")
                        Button("Front") { cameraRequest = PreviewCameraRequest(mode: .front) }
                            .keyboardShortcut("1", modifiers: .command)
                            .help("View the SVG head-on without perspective (Command-1).")
                        Button("Reset View") { cameraRequest = PreviewCameraRequest(mode: .reset) }
                            .keyboardShortcut("2", modifiers: .command)
                            .help("Restore the default viewing angle and framing (Command-2).")
                        if model.previewBusy { ProgressView().controlSize(.small) }
                    }
                    .controlSize(.small).padding(10)
                    .background(.regularMaterial, in: .rect(cornerRadius: 8))
                    .padding(12)
                }
                if let stats = model.previewStats {
                    VStack(alignment: .leading, spacing: 7) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 14) {
                                Text(dimensions(stats.dimensions))
                                Text("\(stats.vertices.formatted()) vertices")
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(dimensions(stats.dimensions))
                                Text("\(stats.vertices.formatted()) vertices")
                            }
                        }
                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        if !stats.skipped.isEmpty {
                            DisclosureGroup("Conversion Warnings (\(stats.skipped.count))") {
                                VStack(alignment: .leading, spacing: 5) {
                                    ForEach(stats.skipped, id: \.self) { Text($0).textSelection(.enabled) }
                                }
                                .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.bottom, 14)
                }
                if case .failed(let error) = job.status {
                    Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                        .padding(.horizontal, 16).padding(.bottom, 14)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .onChange(of: model.previewURL) { renderingError = nil }
        } else {
            DropPrompt()
        }
    }

    private var previewDescription: String {
        guard let stats = model.previewStats else { return model.previewBusy ? "Building preview" : "No model available" }
        return "\(stats.triangles) triangles, \(dimensions(stats.dimensions)), \(cameraRequest.mode == .front ? "Front view" : "3D view")"
    }

    private func dimensions(_ size: SIMD3<Double>) -> String {
        String(format: "%.2f × %.2f × %.2f cm", size.x, size.y, size.z)
    }
}
