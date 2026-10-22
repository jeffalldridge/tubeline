import Foundation
import Observation
import TubelineCore

@Observable
final class AppModel {
    static let shared = AppModel()

    enum Destination: String, CaseIterable {
        case besideOriginal, folder
    }

    var jobs: [Job] = []
    var selection: Job.ID?

    var options: ConversionOptions {
        didSet {
            guard options != oldValue else { return }
            save()
            for job in jobs { if case .exported(let url) = job.status { job.status = .outdated(url) } }
            schedulePreview()
        }
    }
    var destination: Destination { didSet { save() } }
    var folder: URL? {
        didSet {
            if let folder { folderAccess.remember(folder) }
            save()
        }
    }
    var exportOnDrop: Bool { didSet { save() } }

    /// Live preview of the selected icon, rendered to a temporary file with the current settings.
    var previewURL: URL?
    var previewStats: ConversionStats?
    var previewError: String?
    var previewBusy = false

    private let folderAccess = FolderAccess()
    private var previewTask: Task<Void, Never>?
    private let previewDir = FileManager.default.temporaryDirectory.appendingPathComponent("TubelinePreview", isDirectory: true)

    init() {
        let d = UserDefaults.standard
        options = d.data(forKey: "options").flatMap { try? JSONDecoder().decode(ConversionOptions.self, from: $0) }
            ?? ConversionOptions()
        destination = Destination(rawValue: d.string(forKey: "destination") ?? "") ?? .besideOriginal
        folder = d.url(forKey: "folder")
        exportOnDrop = d.object(forKey: "exportOnDrop") as? Bool ?? true
        try? FileManager.default.createDirectory(at: previewDir, withIntermediateDirectories: true)
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(try? JSONEncoder().encode(options), forKey: "options")
        d.set(destination.rawValue, forKey: "destination")
        d.set(folder, forKey: "folder")
        d.set(exportOnDrop, forKey: "exportOnDrop")
    }

    var selectedJob: Job? { jobs.first { $0.id == selection } }

    // MARK: Adding files

    func add(_ urls: [URL]) {
        let known = Set(jobs.map(\.source))
        let new = SVGFinder.collect(urls).filter { !known.contains($0) }.map { Job(source: $0) }
        guard !new.isEmpty else { return }
        jobs += new
        if selection == nil || selectedJob == nil { select(new[0].id) }
        if exportOnDrop { export(new) }
    }

    func remove(_ job: Job) {
        jobs.removeAll { $0.id == job.id }
        if selection == job.id { select(jobs.first?.id) }
    }

    func clear() {
        jobs.removeAll()
        select(nil)
    }

    func select(_ id: Job.ID?) {
        selection = id
        schedulePreview(immediately: true)
    }

    // MARK: Export

    func outputURL(for job: Job) -> URL {
        let dir = destination == .folder ? (folder ?? job.source.deletingLastPathComponent()) : job.source.deletingLastPathComponent()
        return dir.appendingPathComponent(job.name + ".usdz")
    }

    func exportAll() { export(jobs) }

    func export(_ list: [Job]) {
        let options = self.options
        var pairs = list.map { ($0, outputURL(for: $0)) }
        // The sandbox only lets us write where the user has granted access; ask once per folder.
        let denied = Set(folderAccess.ensureWritable(pairs.map { $0.1.deletingLastPathComponent() }))
        for (job, out) in pairs where denied.contains(out.deletingLastPathComponent().standardizedFileURL) {
            job.status = .failed("Tubeline doesn’t have permission to save in “\(out.deletingLastPathComponent().lastPathComponent)”.")
        }
        pairs.removeAll { denied.contains($0.1.deletingLastPathComponent().standardizedFileURL) }
        for (job, _) in pairs { job.status = .working }
        Task.detached(priority: .userInitiated) {
            await withTaskGroup(of: Void.self) { group in
                for (job, out) in pairs {
                    let src = job.source
                    group.addTask {
                        let result: Result<ConversionReport, Error> = Result {
                            try Converter.convert(svg: src, to: out, options: options)
                        }
                        await MainActor.run {
                            switch result {
                            case .success(let r):
                                job.status = .exported(out)
                                job.stats = ConversionStats(triangles: r.triangles, vertices: r.vertices,
                                                            seconds: r.seconds, skipped: r.skipped, dimensions: r.dimensions)
                            case .failure(let e):
                                job.status = .failed(e.localizedDescription)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Preview

    func schedulePreview(immediately: Bool = false) {
        previewTask?.cancel()
        guard let job = selectedJob else {
            previewURL = nil; previewStats = nil; previewError = nil; previewBusy = false
            return
        }
        let src = job.source
        let options = self.options
        let out = previewDir.appendingPathComponent("\(job.name)-\(UUID().uuidString.prefix(8)).usdz")
        previewBusy = true
        previewTask = Task { [weak self] in
            if !immediately { try? await Task.sleep(for: .milliseconds(200)) }
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .userInitiated) {
                Result { try Converter.convert(svg: src, to: out, options: options) }
            }.value
            guard !Task.isCancelled, let self else { return }
            self.previewBusy = false
            switch result {
            case .success(let r):
                if let old = self.previewURL { try? FileManager.default.removeItem(at: old) }
                self.previewURL = out
                self.previewStats = ConversionStats(triangles: r.triangles, vertices: r.vertices,
                                                    seconds: r.seconds, skipped: r.skipped, dimensions: r.dimensions)
                self.previewError = nil
            case .failure(let e):
                self.previewError = e.localizedDescription
                self.previewStats = nil
            }
        }
    }
}
