import XCTest
import simd
@testable import TubelineCore

final class MeshingTests: XCTestCase {
    private func mesh(_ body: String, options: ConversionOptions = ConversionOptions()) throws -> Mesh {
        let svg = ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="2" stroke-linecap="round">\##(body)</svg>"##
        return try Converter.buildMesh(SVGParser.parse(data: Data(svg.utf8)), options: options)
    }

    private func assertWatertight(_ m: Mesh, file: StaticString = #filePath, line: UInt = #line) {
        let validation = m.validation()
        XCTAssertTrue(validation.isValid, validation.summary, file: file, line: line)
    }

    func testCrossingStrokesFuseIntoOneWatertightSolid() throws {
        let m = try mesh(##"<path d="M4 4 20 20"/><path d="M20 4 4 20"/>"##)
        XCTAssertGreaterThan(m.triangleCount, 100)
        assertWatertight(m)
    }

    func testFilletedAndFilledShapesAreWatertight() throws {
        var o = ConversionOptions()
        o.fillet = 0.5
        assertWatertight(try mesh(##"<path d="M4 12h16M12 4v16"/><circle cx="12" cy="12" r="4" fill="#000"/>"##, options: o))
    }

    func testPointSizingUsesPrintPoints() throws {
        // A 20pt line with 2pt round caps spans 22pt = 22/72 in = 0.776 cm.
        let m = try mesh(##"<path d="M2 12h20"/>"##)
        let size = m.bounds.size
        XCTAssertEqual(size.x, 22 * 2.54 / 72, accuracy: 0.01)
        XCTAssertEqual(size.z, 2 * 2.54 / 72, accuracy: 0.01)
    }

    func testFlatCapsEndAtTheEndpoint() throws {
        var o = ConversionOptions()
        o.sizing = .fixed
        o.size = 24
        let round = try mesh(##"<path d="M2 12h20"/>"##, options: o).bounds.size.x
        o.caps = .flat
        let flat = try mesh(##"<path d="M2 12h20"/>"##, options: o).bounds.size.x
        XCTAssertEqual(round, 22, accuracy: 0.1)
        XCTAssertEqual(flat, 20, accuracy: 0.1)
    }

    func testFacetsControlDensity() throws {
        var o = ConversionOptions()
        o.facets = 16
        let coarse = try mesh(##"<circle cx="12" cy="12" r="8"/>"##, options: o).triangleCount
        o.facets = 64
        let fine = try mesh(##"<circle cx="12" cy="12" r="8"/>"##, options: o).triangleCount
        XCTAssertGreaterThan(fine, coarse * 4)
    }

    func testOptimizationIsLighterWatertightAndOnTheSurface() throws {
        let body = ##"<path d="M4 4 20 20"/><path d="M20 4 4 20"/><circle cx="12" cy="12" r="8"/>"##
        var o = ConversionOptions()
        o.optimize = false
        let dense = try mesh(body, options: o)
        o.optimize = true
        let light = try mesh(body, options: o)
        XCTAssertLessThan(light.triangleCount * 3, dense.triangleCount)
        assertWatertight(light)

        // Every vertex stays on the exact tube surface: distance from the nearest centerline must
        // be one tube radius. Simplified vertices are held to one facet's sag; dual contouring's
        // crease vertices (where tubes meet) can sit up to ~2.5% of a radius off at concave seams, so allow 3%.
        let s = 2.54 / 72  // cm per point
        let r = 1 * s, sag = r * (1 - cos(.pi / o.facets))
        for p in light.positions {
            let q = SIMD2<Double>(Double(p.x), Double(p.y)) / s
            func segment(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
                let t = simd_clamp(simd_dot(q - a, b - a) / simd_length_squared(b - a), 0, 1)
                return simd_distance(q, a + (b - a) * t)
            }
            let ring = abs(simd_length(q) - 8)
            let axis = min(ring, segment([-8, -8], [8, 8]), segment([8, -8], [-8, 8])) * s
            let dist = (axis * axis + Double(p.z) * Double(p.z)).squareRoot()
            XCTAssertEqual(dist, r, accuracy: max(sag * 1.5, r * 0.03), "at \(q), z \(Double(p.z) / s) pt")
        }
    }

    func testEmptyDocumentThrows() {
        XCTAssertThrowsError(try mesh(##"<path d="M0 0h24" stroke="none"/>"##))
    }
    func testFlatCapsDoNotChangeWhenStraightSegmentsAreSubdivided() throws {
        var options = ConversionOptions()
        options.caps = .flat
        options.optimize = false
        let plain = try mesh("<path d='M4 12h16'/>", options: options)
        let split = try mesh("<path d='M4 12h0.1h15.9'/>", options: options)
        XCTAssertEqual(plain.bounds.min.x, split.bounds.min.x, accuracy: 0.00001)
        XCTAssertEqual(plain.bounds.max.x, split.bounds.max.x, accuracy: 0.00001)
        assertWatertight(split)
    }

    func testChangingPhysicalScalePreservesTopology() throws {
        let body = "<path d='M4 4 20 20'/><path d='M20 4 4 20'/>"
        var options = ConversionOptions()
        let small = try mesh(body, options: options)
        options.sizing = .fixed
        options.size = 24
        let large = try mesh(body, options: options)
        XCTAssertEqual(small.indices, large.indices)
        assertWatertight(small)
        assertWatertight(large)
    }

    func testMeshValidationRejectsDegeneratesAndDuplicateFaces() {
        let bad = Mesh(positions: [[0,0,0], [1,0,0], [0,1,0]],
                       normals: [[0,0,1], [0,0,1], [0,0,1]],
                       indices: [0,1,2, 0,1,2, 0,0,1])
        let result = bad.validation()
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.degenerateTriangles, 1)
        XCTAssertEqual(result.duplicateTriangles, 1)
        XCTAssertEqual(result.inconsistentEdges, 3)
    }

    func testMeshValidationAcceptsDisconnectedClosedComponents() throws {
        assertWatertight(try mesh("<path d='M2 4h4M18 20h4'/>"))
    }

    func testPhysicalSizingUsesCSSPixels() throws {
        let document = try SVGParser.parse(data: Data("<svg viewBox='0 0 96 96' width='1in' height='1in' stroke='black' stroke-width='2'><path d='M0 48h96'/></svg>".utf8))
        var options = ConversionOptions()
        options.sizing = .physical
        let m = try Converter.buildMesh(document, options: options)
        XCTAssertEqual(m.bounds.size.x, 2.54, accuracy: 0.003)
    }

    func testInvalidDocumentCoordinatesThrowBeforeSampling() throws {
        var document = try SVGParser.parse(data: Data("<svg stroke='black'><path d='M0 0h10'/></svg>".utf8))
        document.canvas = (.zero, [Double.infinity, 24])
        XCTAssertThrowsError(try Converter.buildMesh(document, options: ConversionOptions()))
        var options = ConversionOptions()
        options.thickness = .nan
        XCTAssertThrowsError(try mesh("<path d='M0 0h10'/>", options: options))
    }

    func testIntegerOutputScalePreservesTopology() throws {
        let body = "<path d='M4 4 20 20'/><path d='M20 4 4 20'/>"
        let original = try mesh(body)
        var options = ConversionOptions()
        options.outputScale = 100
        let enlarged = try mesh(body, options: options)
        XCTAssertEqual(original.indices, enlarged.indices)
        XCTAssertEqual(enlarged.bounds.size.x, original.bounds.size.x * 100, accuracy: 0.00001)
        assertWatertight(enlarged)
    }

    func testOlderSavedSettingsKeepDefaultsForNewFields() throws {
        let options = try JSONDecoder().decode(ConversionOptions.self, from: Data("{\"thickness\":2,\"facets\":16}".utf8))
        XCTAssertEqual(options.thickness, 2)
        XCTAssertEqual(options.facets, 16)
        XCTAssertEqual(options.outputScale, 1)
        XCTAssertEqual(options.sizing, .points)
        XCTAssertEqual(try JSONDecoder().decode(ConversionOptions.self, from: JSONEncoder().encode(options)), options)
    }

    func testAmbiguousContourFallbackProducesAClosedManifold() {
        let cm = 2.54 / 72
        let groups = [
            PrimitiveGroup(primitives: [.capsule(Vec3(-8,-8,0) * cm, Vec3(8,8,0) * cm, cm)]),
            PrimitiveGroup(primitives: [.capsule(Vec3(8,-8,0) * cm, Vec3(-8,8,0) * cm, cm)]),
        ]
        let m = FusedMesher(groups: groups, voxel: 2 * .pi * cm / (32 * 1.4), blend: 0).build()
        assertWatertight(m)
        XCTAssertTrue(m.warnings.contains { $0.contains("denser mesh") })
    }

}
