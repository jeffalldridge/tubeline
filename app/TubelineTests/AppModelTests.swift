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

    func testStartupPreferencesPersistWithoutChangingCurrentBatch() {
        let defaults = makeDefaults()
        let model = AppModel(defaults: defaults, authorizeFolders: { _ in [] })
        let current = model.options
        model.startupOptions.facets = 16
        model.startupOptions.optimize = false
        model.startupOptions.outputScale = 10
        XCTAssertEqual(model.options, current)
        let reopened = AppModel(defaults: defaults, authorizeFolders: { _ in [] })
        XCTAssertEqual(reopened.options.facets, 16)
        XCTAssertFalse(reopened.options.optimize)
        XCTAssertEqual(reopened.options.outputScale, 10)
        model.restoreDefaults()
        XCTAssertEqual(model.options, reopened.options)
        model.resetSavedDefaults()
        XCTAssertEqual(model.startupOptions, ConversionOptions())
        XCTAssertEqual(model.options.facets, 16)
        model.clear()
        reopened.clear()
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

    func testRemovingSettledRowDoesNotCancelRemainingExports() async throws {
        for firstFails in [false, true] {
            let dir = try makeDirectory()
            defer { try? FileManager.default.removeItem(at: dir) }
            let secondStarted = expectation(description: "Second conversion started")
            let gate = DispatchSemaphore(value: 0)
            let result = report()
            let worker = ConversionQueue { source, output, _ in
                if source.lastPathComponent == "second.svg" {
                    secondStarted.fulfill()
                    guard gate.wait(timeout: .now() + 3) == .success else { throw CocoaError(.userCancelled) }
                } else if firstFails { throw CocoaError(.fileReadCorruptFile) }
                try Data("export".utf8).write(to: output)
                return result
            }
            let model = AppModel(defaults: makeDefaults(), worker: worker, authorizeFolders: { _ in [] })
            let first = Job(source: dir.appendingPathComponent("first.svg"))
            let second = Job(source: dir.appendingPathComponent("second.svg"))
            model.jobs = [first, second]
            model.exportAll()
            await fulfillment(of: [secondStarted], timeout: 2)
            if firstFails {
                guard case .failed = first.status else { return XCTFail("First job should have failed") }
            } else {
                guard case .exported = first.status else { return XCTFail("First job should have completed") }
            }
            model.remove(first)
            XCTAssertTrue(model.isExporting)
            XCTAssertEqual(second.status, .working)
            gate.signal()
            try await waitForExport(model)
            guard case .exported = second.status else { return XCTFail("Removing a settled row must preserve the remaining export") }
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("second.usdz").path))
        }
    }

    func testAutomaticExportQueuesNewAndReaddedInputsWithLatestSettings() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let firstSource = dir.appendingPathComponent("first.svg")
        let secondSource = dir.appendingPathComponent("second.svg")
        try Data("first".utf8).write(to: firstSource)
        try Data("second".utf8).write(to: secondSource)
        let started = expectation(description: "Initial export started")
        let gate = DispatchSemaphore(value: 0)
        let result = report()
        let worker = ConversionQueue { source, output, options in
            if output.deletingLastPathComponent().lastPathComponent.hasPrefix(".Tubeline-"),
               output.lastPathComponent == "first.usdz" {
                started.fulfill()
                guard gate.wait(timeout: .now() + 3) == .success else { throw CocoaError(.userCancelled) }
            }
            try Data("\(source.lastPathComponent):\(options.thickness)".utf8).write(to: output)
            return result
        }
        let model = AppModel(defaults: makeDefaults(), worker: worker, authorizeFolders: { _ in [] })
        let first = Job(source: firstSource)
        model.jobs = [first]
        model.exportOnDrop = true
        model.exportAll()
        await fulfillment(of: [started], timeout: 2)
        model.add([firstSource, secondSource])
        model.add([firstSource])
        model.select(nil)
        model.options.thickness = 2
        gate.signal()
        try await waitForExport(model)
        XCTAssertEqual(model.jobs.count, 2)
        XCTAssertEqual(first.revision, 2)
        XCTAssertEqual(first.lastExportRevision, 2)
        XCTAssertTrue(model.jobs.allSatisfy { if case .exported = $0.status { return true }; return false })
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("first.usdz"), encoding: .utf8), "first.svg:1.0")
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("first 2.usdz"), encoding: .utf8), "first.svg:2.0")
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("second.usdz"), encoding: .utf8), "second.svg:2.0")
        let outputs = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "usdz" }
        XCTAssertEqual(outputs.count, 3, "Repeated adds during work should coalesce into one follow-up export per job")
        model.clear()
    }

    func testCancelAndWorkingRemovalDiscardQueuedAutomaticExports() async throws {
        for removeWorkingRow in [false, true] {
            let dir = try makeDirectory()
            defer { try? FileManager.default.removeItem(at: dir) }
            let started = expectation(description: "Conversion started")
            let finished = expectation(description: "Canceled worker finished")
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
            let active = Job(source: dir.appendingPathComponent("active.svg"))
            model.jobs = [active]
            model.exportOnDrop = true
            model.exportAll()
            await fulfillment(of: [started], timeout: 2)
            let queuedSource = dir.appendingPathComponent("queued.svg")
            try Data("queued".utf8).write(to: queuedSource)
            model.add([queuedSource])
            model.select(nil)
            if removeWorkingRow { model.remove(active) } else { model.cancelExports() }
            XCTAssertFalse(model.isExporting)
            XCTAssertEqual(model.jobs.count, removeWorkingRow ? 1 : 2)
            XCTAssertEqual(model.jobs.last?.status, .pending)
            if !removeWorkingRow { XCTAssertEqual(active.status, .cancelled) }
            gate.signal()
            await fulfillment(of: [finished], timeout: 2)
            try await Task.sleep(for: .milliseconds(50))
            XCTAssertFalse(model.isExporting)
            let remaining = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            XCTAssertEqual(remaining, ["queued.svg"], "Cancellation must not restart queued automatic exports")
            model.clear()
        }
    }

    func testFailedAutomaticExportIsNotRetriedWithoutANewRequest() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("broken.svg")
        try Data("broken".utf8).write(to: source)
        let attempted = expectation(description: "Automatic export attempted once")
        attempted.assertForOverFulfill = true
        let worker = ConversionQueue { _, output, _ in
            if output.deletingLastPathComponent().lastPathComponent.hasPrefix(".Tubeline-") { attempted.fulfill() }
            throw CocoaError(.fileReadCorruptFile)
        }
        let model = AppModel(defaults: makeDefaults(), worker: worker, authorizeFolders: { _ in [] })
        model.exportOnDrop = true
        model.add([source])
        model.select(nil)
        await fulfillment(of: [attempted], timeout: 2)
        try await waitForExport(model)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(model.isExporting)
        guard case .failed = model.jobs.first?.status else { return XCTFail("Failure should remain available for an explicit retry") }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["broken.svg"])
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
