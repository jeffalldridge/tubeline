import XCTest
@testable import Tubeline
@testable import TubelineCore

@MainActor
final class AppModelTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "TubelineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TubelineStateTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func report() -> ConversionReport {
        ConversionReport(strokes: 1, fills: 0, vertices: 3, triangles: 1,
                         dimensions: SIMD3(1, 1, 1), skipped: [], seconds: 0)
    }

    func testSelectedOverridesKeepUntouchedFieldsInherited() {
        let model = AppModel(defaults: makeDefaults(), authorizeFolders: { _ in [] })
        let job = Job(source: URL(fileURLWithPath: "/tmp/example.svg"))
        model.jobs = [job]
        model.selection = job.id
        model.editingScope = .selected
        model.editingOptions.thickness = 2
        model.editingOptions.outputScale = 10
        model.options.outputScale = 100
        model.options.facets = 48
        XCTAssertEqual(model.effectiveOptions(for: job).thickness, 2)
        XCTAssertEqual(model.effectiveOptions(for: job).outputScale, 10)
        XCTAssertEqual(model.effectiveOptions(for: job).facets, 48)
        XCTAssertNil(job.overrides.facets)
        model.editingOptions.thickness = model.options.thickness
        model.editingOptions.outputScale = model.options.outputScale
        XCTAssertFalse(job.hasOverrides)
        XCTAssertEqual(model.effectiveOptions(for: job).outputScale, 100)
        model.options.outputScale = 1
        XCTAssertEqual(model.effectiveOptions(for: job).outputScale, 1)
        model.clear()
    }

    func testExportPlannerKeepsExistingAndDuplicateNames() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let original = dir.appendingPathComponent("icon.usdz")
        try Data("existing".utf8).write(to: original)
        var reserved: Set<String> = []
        let first = ExportPlanner.uniqueURL(for: original, reserved: &reserved)
        let second = ExportPlanner.uniqueURL(for: original, reserved: &reserved)
        let third = ExportPlanner.uniqueURL(for: dir.appendingPathComponent("ICON.usdz"), reserved: &reserved)
        XCTAssertEqual(first.lastPathComponent, "icon 2.usdz")
        XCTAssertEqual(second.lastPathComponent, "icon 3.usdz")
        XCTAssertEqual(third.lastPathComponent, "ICON 4.usdz")
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "existing")
    }

    func testUnresolvedFolderBlocksExport() {
        let model = AppModel(defaults: makeDefaults(), authorizeFolders: { _ in [] })
        let job = Job(source: URL(fileURLWithPath: "/tmp/example.svg"))
        model.jobs = [job]
        model.destination = .folder
        XCTAssertNil(model.outputURL(for: job))
        model.exportAll()
        XCTAssertFalse(model.isExporting)
        XCTAssertNotNil(model.exportError)
        XCTAssertEqual(job.status, .pending)
    }

    func testSettingsChangedDuringExportRemainOutdated() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let started = expectation(description: "Conversion started")
        let gate = DispatchSemaphore(value: 0)
        let result = report()
        let worker = ConversionQueue { _, output, options in
            started.fulfill()
            guard gate.wait(timeout: .now() + 3) == .success else { throw CocoaError(.userCancelled) }
            try Data(String(options.thickness).utf8).write(to: output)
            return result
        }
        let model = AppModel(defaults: makeDefaults(), worker: worker, authorizeFolders: { _ in [] })
        let source = dir.appendingPathComponent("example.svg")
        try Data("original".utf8).write(to: source)
        let job = Job(source: source)
        model.jobs = [job]
        model.exportAll()
        await fulfillment(of: [started], timeout: 2)
        model.options.thickness = 2
        gate.signal()
        try await waitForExport(model)
        guard case .outdated(let output) = job.status else { return XCTFail("Old snapshot must be outdated") }
        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "1.0")
        model.options.thickness = 1
        guard case .exported = job.status else { return XCTFail("Returning to the exported settings should restore freshness") }
    }

    func testCancelDoesNotPublishRunningConversionOrStartQueuedJobs() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let started = expectation(description: "Conversion started")
        let finished = expectation(description: "Worker finished")
        let gate = DispatchSemaphore(value: 0)
        let result = report()
        let worker = ConversionQueue { _, output, _ in
            started.fulfill()
            guard gate.wait(timeout: .now() + 3) == .success else { throw CocoaError(.userCancelled) }
            try Data("temporary".utf8).write(to: output)
            finished.fulfill()
            return result
        }
        let model = AppModel(defaults: makeDefaults(), worker: worker, authorizeFolders: { _ in [] })
        model.jobs = [Job(source: dir.appendingPathComponent("first.svg")), Job(source: dir.appendingPathComponent("second.svg"))]
        model.exportAll()
        await fulfillment(of: [started], timeout: 2)
        model.cancelExports()
        gate.signal()
        await fulfillment(of: [finished], timeout: 2)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(model.isExporting)
        XCTAssertTrue(model.jobs.allSatisfy { $0.status == .cancelled })
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }

    func testReaddingSourceRefreshesWithoutDuplicateJobs() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("example.svg")
        try Data("svg".utf8).write(to: source)
        let model = AppModel(defaults: makeDefaults(), authorizeFolders: { _ in [] })
        model.add([dir, source])
        XCTAssertEqual(model.jobs.count, 1)
        let id = try XCTUnwrap(model.jobs.first?.id)
        model.add([source])
        XCTAssertEqual(model.jobs.count, 1)
        XCTAssertEqual(model.jobs.first?.id, id)
        XCTAssertEqual(model.jobs.first?.revision, 1)
        XCTAssertFalse(model.exportOnDrop)
        model.clear()
    }

    func testBatchEditsDoNotSilentlyReplaceSavedDefaults() {
        let defaults = makeDefaults()
        let model = AppModel(defaults: defaults, authorizeFolders: { _ in [] })
        model.options.thickness = 2
        XCTAssertEqual(AppModel(defaults: defaults).options.thickness, 1)
        let job = Job(source: URL(fileURLWithPath: "/tmp/example.svg"))
        model.jobs = [job]
        model.selection = job.id
        model.editingScope = .selected
        model.editingOptions.thickness = 3
        model.saveCurrentAsDefaults()
        XCTAssertEqual(AppModel(defaults: defaults).options.thickness, 2)
        model.clear()
        model.resetSavedDefaults()
        XCTAssertEqual(AppModel(defaults: defaults).options.thickness, 1)
    }

    func testFailedNewPreviewCannotDisplayPreviousIcon() async throws {
        let result = report()
        let worker = ConversionQueue { source, output, _ in
            if source.lastPathComponent == "broken.svg" { throw CocoaError(.fileReadCorruptFile) }
            try Data("preview".utf8).write(to: output)
            return result
        }
        let model = AppModel(defaults: makeDefaults(), worker: worker, authorizeFolders: { _ in [] })
        let first = Job(source: URL(fileURLWithPath: "/tmp/valid.svg"))
        let second = Job(source: URL(fileURLWithPath: "/tmp/broken.svg"))
        model.jobs = [first, second]
        model.select(first.id)
        try await waitForPreview(model)
        XCTAssertNotNil(model.previewURL)
        model.select(second.id)
        XCTAssertNil(model.previewURL)
        XCTAssertNil(model.previewStats)
        try await waitForPreview(model)
        XCTAssertNil(model.previewURL)
        XCTAssertNotNil(model.previewError)
        model.clear()
    }

    private func waitForPreview(_ model: AppModel) async throws {
        let deadline = Date().addingTimeInterval(3)
        while model.previewBusy && Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(model.previewBusy)
    }

    private func waitForExport(_ model: AppModel) async throws {
        let deadline = Date().addingTimeInterval(3)
        while model.isExporting && Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(model.isExporting)
    }
}
