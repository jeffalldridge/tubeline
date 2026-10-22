import SwiftUI
import UniformTypeIdentifiers
import TubelineCore

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var dropTargeted = false
    @AppStorage("showForm") private var showForm = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            FileList()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            HStack(spacing: 0) {
                previewPane
                Divider()
                SettingsPanel()
                    .frame(width: 290)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            loadURLs(providers)
            return true
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { model.add(Panels.chooseSVGs()) } label: { Label("Add SVGs", systemImage: "plus") }
                Button { model.exportAll() } label: { Label("Export All", systemImage: "square.and.arrow.up.on.square") }
                    .disabled(model.jobs.isEmpty)
                    .help("Export every icon in the list with the current settings")
            }
        }
    }

    @ViewBuilder private var previewPane: some View {
        ZStack {
            if model.jobs.isEmpty {
                DropPrompt()
            } else {
                ModelPreview(url: model.previewURL, subject: model.selection, showForm: showForm)
                    .overlay(alignment: .bottom) { previewFooter }
                    .overlay(alignment: .topTrailing) {
                        Picker("", selection: $showForm) {
                            Text("As Exported").tag(false)
                            Text("Show Form").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        .padding(12)
                        .help("Show Form lights the model so you can judge its shape. It does not change the exported file.")
                    }
                if model.previewBusy && model.previewURL == nil { ProgressView() }
                if let err = model.previewError {
                    Text(err).foregroundStyle(.secondary).padding().background(.regularMaterial, in: .rect(cornerRadius: 8))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var previewFooter: some View {
        HStack(spacing: 14) {
            if let s = model.previewStats {
                Label("\(s.triangles.formatted()) triangles", systemImage: "triangle")
                Label("\(s.vertices.formatted()) vertices", systemImage: "circle.grid.3x3")
                Label(String(format: "%.2f × %.2f × %.2f cm", s.dimensions.x, s.dimensions.y, s.dimensions.z),
                      systemImage: "ruler")
                Label(String(format: "%.2fs", s.seconds), systemImage: "timer")
                if !s.skipped.isEmpty {
                    Label("Skipped \(s.skipped.joined(separator: ", "))", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            if model.previewBusy { ProgressView().controlSize(.small) }
        }
        .font(.callout.monospacedDigit())
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.regularMaterial, in: .capsule)
        .padding(12)
    }

    private func loadURLs(_ providers: [NSItemProvider]) {
        for p in providers {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in model.add([url]) }
            }
        }
    }
}

struct DropPrompt: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "scribble.variable")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text("Drop SVG icons or folders here")
                .font(.title2.weight(.medium))
            Text("Stroked paths become 3D tubes, saved as USDZ for Apple Motion.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FileList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: Binding(get: { model.selection }, set: { model.select($0) })) {
            ForEach(model.jobs) { job in
                JobRow(job: job)
                    .tag(job.id)
                    .contextMenu {
                        if let url = job.exportedURL {
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        }
                        Button("Export") { model.export([job]) }
                        Divider()
                        Button("Remove") { model.remove(job) }
                    }
            }
        }
        .overlay {
            if model.jobs.isEmpty {
                Text("No icons yet").foregroundStyle(.tertiary)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !model.jobs.isEmpty {
                HStack {
                    Text("\(model.jobs.count) icons").foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") { model.clear() }.buttonStyle(.link)
                }
                .font(.callout)
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
        }
    }
}

struct JobRow: View {
    let job: Job

    var body: some View {
        HStack(spacing: 8) {
            statusIcon.frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.name).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .help(helpText)
    }

    @ViewBuilder private var statusIcon: some View {
        switch job.status {
        case .pending: Image(systemName: "circle").foregroundStyle(.tertiary)
        case .working: ProgressView().controlSize(.small)
        case .exported: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .outdated: Image(systemName: "arrow.triangle.2.circlepath.circle").foregroundStyle(.orange)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }

    private var detail: String {
        switch job.status {
        case .pending: return "Not exported"
        case .working: return "Converting…"
        case .exported: return job.stats.map { "\($0.triangles.formatted()) tris" } ?? "Exported"
        case .outdated: return "Settings changed — export again"
        case .failed(let msg): return msg
        }
    }

    private var helpText: String {
        if let url = job.exportedURL { return url.path }
        return job.source.path
    }
}

extension Job {
    var exportedURL: URL? {
        switch status {
        case .exported(let u), .outdated(let u): return u
        default: return nil
        }
    }
}
