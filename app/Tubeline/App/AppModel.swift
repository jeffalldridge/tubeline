import AppKit
import Foundation
import Observation
import TubelineCore

@Observable
final class AppModel {
    var cameraRequest = PreviewCameraRequest()
    static let shared = AppModel()

    enum Destination: String, CaseIterable { case besideOriginal, folder }
    enum EditingScope: String, CaseIterable { case batch, selected }

    var jobs: [Job] = []
    var selection: Job.ID?
    var editingScope = EditingScope.batch
    var options: ConversionOptions {
        didSet {
            guard options != oldValue else { return }
            updateFreshness()
            schedulePreview()
        }
    }
    private var storedStartupOptions: ConversionOptions
    var startupOptionsError: String?
    var startupOptions: ConversionOptions {
        get { storedStartupOptions }
        set {
            if let problem = ConversionOptionValidation.problem(in: newValue) {
                startupOptionsError = problem + " Saved defaults haven’t changed."
                return
            }
            do {
                let data = try JSONEncoder().encode(newValue)
                defaults.set(data, forKey: "defaultOptions")
                storedStartupOptions = newValue
                startupOptionsError = nil
            } catch {
                startupOptionsError = "The conversion defaults couldn’t be saved: \(error.localizedDescription)"
            }
        }
    }
    var destination: Destination { didSet { savePreferences() } }
    var exportFormat: ExportFormat {
        didSet {
            savePreferences()
            updateFreshness()
        }
    }
    var folder: URL? {
        didSet {
            if let folder { folderAccess.remember(folder) }
            savePreferences()
        }
    }
    var exportOnDrop: Bool {
        didSet {
            if !exportOnDrop { automaticExportIDs.removeAll() }
            savePreferences()
        }
    }
    var previewURL: URL?
    var previewStats: ConversionStats?
    var previewError: String?
    var previewBusy = false
    var isExporting = false
    var exportCompleted = 0
    var exportTotal = 0
    var exportError: String?
    var exportSummary: String?

    private let defaults: UserDefaults
    private let worker: ConversionQueue
    private let folderAccess = FolderAccess()
    private let authorizeFolders: (([URL]) -> [URL])?
    private var previewTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    private var exportID: UUID?
    private var exportingIDs: Set<Job.ID> = []
    private var automaticExportIDs: Set<Job.ID> = []
    private var isPreparingExport = false
    private let previewDir: URL

    init(defaults: UserDefaults = .standard, worker: ConversionQueue = ConversionQueue(),
         authorizeFolders: (([URL]) -> [URL])? = nil) {
        self.defaults = defaults
        self.worker = worker
        self.authorizeFolders = authorizeFolders
        let saved = Self.savedOptions(defaults)
        storedStartupOptions = saved.options
        options = saved.options
        startupOptionsError = saved.error
        destination = Destination(rawValue: defaults.string(forKey: "destination") ?? "") ?? .besideOriginal
        exportFormat = ExportFormat(rawValue: defaults.string(forKey: "exportFormat") ?? "") ?? .usdz
        folder = defaults.url(forKey: "folder")
        exportOnDrop = defaults.object(forKey: "exportOnDrop") as? Bool ?? false
        previewDir = FileManager.default.temporaryDirectory.appendingPathComponent("TubelinePreview-\(UUID().uuidString)", isDirectory: true)
        do { try FileManager.default.createDirectory(at: previewDir, withIntermediateDirectories: true) }
        catch { previewError = error.localizedDescription }
    }

    private static func savedOptions(_ defaults: UserDefaults) -> (options: ConversionOptions, error: String?) {
        var rejectedSavedValue = false
        for key in ["defaultOptions", "options"] {
            guard let data = defaults.data(forKey: key) else { continue }
            if let decoded = try? JSONDecoder().decode(ConversionOptions.self, from: data),
               ConversionOptionValidation.problem(in: decoded) == nil {
                return (decoded, rejectedSavedValue ? "Some saved defaults were invalid. Valid settings are active; stored preferences were kept." : nil)
            }
            rejectedSavedValue = true
        }
        return (ConversionOptions(), rejectedSavedValue ? "Saved defaults were invalid. Built-in settings are active; stored preferences were kept." : nil)
    }

    private func savePreferences() {
        defaults.set(destination.rawValue, forKey: "destination")
        defaults.set(exportFormat.rawValue, forKey: "exportFormat")
        defaults.set(folder, forKey: "folder")
        defaults.set(exportOnDrop, forKey: "exportOnDrop")
    }

    func saveCurrentAsDefaults() {
        startupOptions = options
    }

    func resetSavedDefaults() {
        startupOptions = ConversionOptions()
    }

    func restoreDefaults() { options = startupOptions }
    func resetEditingOptions() {
        if editingScope == .selected { resetSelectedOverrides() } else { restoreDefaults() }
    }

    var selectedJob: Job? { jobs.first { $0.id == selection } }
    var selectedHasOverrides: Bool { selectedJob?.hasOverrides ?? false }
    var exportProgress: Double { exportTotal == 0 ? 0 : Double(exportCompleted) / Double(exportTotal) }
    var destinationSummary: String {
        destination == .besideOriginal ? "Next to Each Original" : (folder?.path ?? "Choose an Output Folder")
    }
    var editingOptions: ConversionOptions {
        get { editingScope == .selected ? selectedJob.map { effectiveOptions(for: $0) } ?? options : options }
        set {
            guard editingScope == .selected else { options = newValue; return }
            guard let job = selectedJob else { return }
            let previous = effectiveOptions(for: job)
            job.overrides.update(from: previous, to: newValue, base: options)
            updateFreshness()
            schedulePreview()
        }
    }

    func effectiveOptions(for job: Job) -> ConversionOptions { job.overrides.applying(to: options) }
    func resetSelectedOverrides() {
        guard let job = selectedJob else { return }
        job.overrides = ConversionOverrides()
        updateFreshness()
        schedulePreview()
    }

    private func updateFreshness() {
        for job in jobs {
            guard let url = job.lastExportURL else { continue }
            switch job.status {
            case .exported, .outdated: break
            default: continue
            }
            let current = job.lastExportOptions == effectiveOptions(for: job) && job.lastExportRevision == job.revision
                && job.lastExportURLs.map { $0.pathExtension.lowercased() } == exportFormat.formats.map(\.rawValue)
            job.status = current ? .exported(url) : .outdated(url)
        }
    }

    // MARK: Input

    func add(_ urls: [URL]) {
        var seen: Set<URL> = []
        let sources = SVGFinder.collect(urls).map(\.standardizedFileURL).filter { seen.insert($0).inserted }
        guard !sources.isEmpty else {
            exportError = "No SVG files were found. Choose SVG files or a folder containing them."
            return
        }
        exportError = nil
        var added: [Job] = []
        var affected: [Job] = []
        for source in sources {
            if let existing = jobs.first(where: { $0.source == source }) {
                refresh(existing, automaticallyExport: false)
                affected.append(existing)
            } else {
                let job = Job(source: source)
                jobs.append(job)
                added.append(job)
                affected.append(job)
            }
        }
        if selectedJob == nil { select(added.first?.id ?? jobs.first?.id) }
        if exportOnDrop { enqueueAutomaticExport(affected) }
    }

    func refresh(_ job: Job, automaticallyExport: Bool = true) {
        job.revision += 1
        if job.status != .working { job.status = job.lastExportURL.map(Job.Status.outdated) ?? .pending }
        if selection == job.id { schedulePreview(immediately: true) }
        if automaticallyExport && exportOnDrop { enqueueAutomaticExport([job]) }
    }
    func refreshSelected() { if let job = selectedJob { refresh(job) } }
    func remove(_ job: Job) {
        automaticExportIDs.remove(job.id)
        if job.status == .working && exportingIDs.contains(job.id) { cancelExports() }
        jobs.removeAll { $0.id == job.id }
        if selection == job.id { select(jobs.first?.id) }
    }
    func clear() {
        cancelExports()
        jobs.removeAll()
        select(nil)
    }
    func select(_ id: Job.ID?) {
        selection = id
        schedulePreview(immediately: true)
    }

    // MARK: Export

    /// Where an export would go, without an extension (each format adds its own).
    func outputStem(for job: Job) -> URL? {
        let dir: URL
        if destination == .folder {
            guard let folder else { return nil }
            dir = folder
        } else { dir = job.source.deletingLastPathComponent() }
        return dir.appendingPathComponent(job.name)
    }
    func exportAll() { export(jobs) }
    func exportSelected() { if let job = selectedJob { export([job]) } }
    func revealSelectedExport() {
        if let urls = selectedJob?.lastExportURLs, !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }

    func cancelExports() {
        automaticExportIDs.removeAll()
        exportTask?.cancel()
        exportTask = nil
        exportID = nil
        for job in jobs where exportingIDs.contains(job.id) && job.status == .working { job.status = .cancelled }
        exportingIDs.removeAll()
        if isExporting { exportSummary = "Export canceled. Completed files were kept." }
        isExporting = false
    }

    private func enqueueAutomaticExport(_ list: [Job]) {
        automaticExportIDs.formUnion(list.map(\.id))
        drainAutomaticExports()
    }

    private func drainAutomaticExports() {
        guard exportOnDrop, !isExporting, !isPreparingExport, !automaticExportIDs.isEmpty else { return }
        let pending = jobs.filter { automaticExportIDs.contains($0.id) }
        automaticExportIDs.removeAll()
        // Capture current settings and source revisions when the request reaches the worker.
        // Consuming the request first prevents failures from becoming automatic retries.
        export(pending)
    }

    func export(_ list: [Job]) {
        guard !isExporting, !isPreparingExport, !list.isEmpty else { return }
        isPreparingExport = true
        defer {
            isPreparingExport = false
            drainAutomaticExports()
        }
        guard destination != .folder || folder != nil else {
            exportError = "Choose an output folder before exporting."
            return
        }
        exportError = nil
        exportSummary = nil
        var reserved: Set<String> = []
        let formats = exportFormat.formats
        let plans = list.compactMap { job -> ExportSnapshot? in
            guard jobs.contains(where: { $0.id == job.id }), let proposed = outputStem(for: job) else { return nil }
            let stem = ExportPlanner.uniqueStem(for: proposed, extensions: formats.map(\.rawValue), reserved: &reserved)
            return ExportSnapshot(job: job, stem: stem, formats: formats,
                                  options: effectiveOptions(for: job), revision: job.revision,
                                  sourceStamp: SourceStamp(url: job.source))
        }
        guard !plans.isEmpty else { return }
        let folders = plans.map(\.folder)
        let denied = Set((authorizeFolders?(folders) ?? folderAccess.ensureWritable(folders)).map(\.standardizedFileURL))
        for plan in plans where denied.contains(plan.folder.standardizedFileURL) {
            plan.job.status = .failed("Tubeline doesn’t have permission to save in “\(plan.folder.lastPathComponent)”. Choose another folder or allow access, then retry.")
        }
        let allowed = plans.filter { !denied.contains($0.folder.standardizedFileURL) }
        guard !allowed.isEmpty else {
            exportError = "No files were exported. Allow access to the output folder or choose another folder."
            return
        }
        exportTotal = allowed.count
        exportCompleted = 0
        isExporting = true
        let id = UUID()
        exportID = id
        exportingIDs = Set(allowed.map { $0.job.id })
        for plan in allowed { plan.job.status = .working }
        exportTask = Task { [weak self] in
            guard let self else { return }
            var failures = plans.count - allowed.count
            var warnings = 0
            for plan in allowed {
                guard !Task.isCancelled, self.exportID == id else { return }
                // Conversion never touches the final URL until this snapshot is accepted.
                let stagingDirectory = plan.folder.appendingPathComponent(".Tubeline-\(UUID().uuidString)", isDirectory: true)
                let staged = plan.extensions.map {
                    stagingDirectory.appendingPathComponent(plan.stem.lastPathComponent).appendingPathExtension($0)
                }
                defer { try? FileManager.default.removeItem(at: stagingDirectory) }
                do {
                    try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: false)
                    let report = try await self.worker.run(source: plan.job.source, outputs: staged, options: plan.options)
                    try Task.checkCancellation()
                    guard self.exportID == id else { return }
                    guard SourceStamp(url: plan.job.source) == plan.sourceStamp else {
                        throw AppConversionError.sourceChanged
                    }
                    // Another app may have taken the name while converting; recheck every format.
                    var publicationReservations: Set<String> = []
                    let finalStem = ExportPlanner.uniqueStem(for: plan.stem, extensions: plan.extensions,
                                                             reserved: &publicationReservations)
                    var published: [URL] = []
                    do {
                        for (file, ext) in zip(staged, plan.extensions) {
                            let destination = finalStem.appendingPathExtension(ext)
                            try FileManager.default.moveItem(at: file, to: destination)
                            published.append(destination)
                        }
                    } catch {
                        // Keep an icon's formats together: don't leave half an export behind.
                        for file in published { try? FileManager.default.removeItem(at: file) }
                        throw error
                    }
                    let final = published[0]
                    plan.job.lastExportURLs = published
                    plan.job.lastExportOptions = plan.options
                    plan.job.lastExportRevision = plan.revision
                    plan.job.stats = ConversionStats(report)
                    let current = self.effectiveOptions(for: plan.job) == plan.options && plan.job.revision == plan.revision
                    plan.job.status = current ? .exported(final) : .outdated(final)
                    if !report.skipped.isEmpty { warnings += 1 }
                } catch is CancellationError {
                    return
                } catch {
                    guard self.exportID == id else { return }
                    plan.job.status = .failed(error.localizedDescription)
                    failures += 1
                }
                self.exportCompleted += 1
            }
            guard self.exportID == id else { return }
            self.isExporting = false
            self.exportingIDs.removeAll()
            self.exportTask = nil
            self.exportID = nil
            self.exportSummary = "\(plans.count - failures) exported, \(warnings) with warnings, \(failures) failed."
            self.drainAutomaticExports()
        }
    }

    // MARK: Preview

    func schedulePreview(immediately: Bool = false) {
        previewTask?.cancel()
        if let old = previewURL { try? FileManager.default.removeItem(at: old) }
        previewURL = nil
        previewStats = nil
        previewError = nil
        guard let job = selectedJob else { previewBusy = false; return }
        let source = job.source
        let snapshot = effectiveOptions(for: job)
        let revision = job.revision
        let stamp = SourceStamp(url: source)
        let out = previewDir.appendingPathComponent("\(UUID().uuidString).usdz")
        previewBusy = true
        previewTask = Task { [weak self] in
            guard let self else { return }
            do {
                if !immediately { try await Task.sleep(for: .milliseconds(200)) }
                let report = try await self.worker.run(source: source, outputs: [out], options: snapshot)
                try Task.checkCancellation()
                guard self.selection == job.id, self.effectiveOptions(for: job) == snapshot, job.revision == revision else {
                    try? FileManager.default.removeItem(at: out)
                    return
                }
                guard SourceStamp(url: source) == stamp else { throw AppConversionError.sourceChanged }
                self.previewURL = out
                self.previewStats = ConversionStats(report)
                self.previewBusy = false
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: out)
            } catch {
                try? FileManager.default.removeItem(at: out)
                guard !Task.isCancelled else { return }
                self.previewError = error.localizedDescription
                self.previewBusy = false
            }
        }
    }
}
