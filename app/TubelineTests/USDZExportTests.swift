import XCTest
@testable import TubelineCore

final class USDZExportTests: XCTestCase {
    /// USDZ requires each file's data to start on a 64-byte boundary, uncompressed.
    func testArchiveAlignsFileData() {
        for nameLength in 1...70 {
            let name = String(repeating: "a", count: nameLength) + ".usdc"
            let payload = Data("hello".utf8)
            let zip = USDZArchive.make(entries: [(name, payload)])
            let nameLen = Int(zip[26]) | Int(zip[27]) << 8
            let extraLen = Int(zip[28]) | Int(zip[29]) << 8
            let dataStart = 30 + nameLen + extraLen
            XCTAssertEqual(dataStart % 64, 0, "name length \(nameLength)")
            XCTAssertEqual(zip.subdata(in: dataStart..<dataStart + payload.count), payload)
        }
    }

    func testCRC32MatchesReference() {
        XCTAssertEqual(USDZArchive.crc32(Data("123456789".utf8)), 0xCBF4_3926)
    }

    func testPrimNamesAreValidIdentifiers() {
        XCTAssertEqual(USDZWriter.primName("arrow-left 2"), "arrow_left_2")
        XCTAssertEqual(USDZWriter.primName("3d"), "_3d")
    }

    /// Runs inside the sandboxed app host, so this also proves `usdcat` can be launched there.
    func testExportWritesBinaryUSDInsideThePackage() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let svg = dir.appendingPathComponent("plus.svg")
        try Data(##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" stroke="#000" stroke-width="2"><path d="M12 5v14M5 12h14"/></svg>"##.utf8).write(to: svg)
        let out = dir.appendingPathComponent("plus.usdz")

        let report = try Converter.convert(svg: svg, to: out, options: ConversionOptions())
        XCTAssertGreaterThan(report.triangles, 0)

        let zip = try Data(contentsOf: out)
        let nameLen = Int(zip[26]) | Int(zip[27]) << 8
        let name = String(decoding: zip[30..<30 + nameLen], as: UTF8.self)
        XCTAssertEqual(name, "plus.usdc")
        let extraLen = Int(zip[28]) | Int(zip[29]) << 8
        let start = 30 + nameLen + extraLen
        XCTAssertEqual(String(decoding: zip[start..<start + 8], as: UTF8.self), "PXR-USDC")
    }

    func testSolidSurfaceIsEmissiveOnly() {
        let mesh = Mesh(positions: [.zero, [1, 0, 0], [0, 1, 0]], normals: [[0, 0, 1], [0, 0, 1], [0, 0, 1]], indices: [0, 1, 2])
        let solid = USDZWriter.makeUSDA(mesh: mesh, name: "T", color: SIMD3(1, 0.5, 0), surface: .solid)
        XCTAssertTrue(solid.contains("color3f inputs:emissiveColor = (1.0, 0.5, 0.0)"))
        XCTAssertTrue(solid.contains("color3f inputs:diffuseColor = (0, 0, 0)"))
        let shaded = USDZWriter.makeUSDA(mesh: mesh, name: "T", color: SIMD3(1, 0.5, 0), surface: .shaded)
        XCTAssertFalse(shaded.contains("emissiveColor"))
        XCTAssertTrue(shaded.contains("metersPerUnit = 0.01"))
    }
}
