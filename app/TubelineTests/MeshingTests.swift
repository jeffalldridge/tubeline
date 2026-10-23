import XCTest
import simd
@testable import TubelineCore

final class MeshingTests: XCTestCase {
    private func mesh(_ body: String, options: ConversionOptions = ConversionOptions.trueSize) throws -> Mesh {
        let svg = ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="2" stroke-linecap="round">\##(body)</svg>"##
        return try Converter.buildMesh(SVGParser.parse(data: Data(svg.utf8)), options: options)
    }

    private func assertWatertight(_ m: Mesh, file: StaticString = #filePath, line: UInt = #line) {
        let validation = m.validation()
        XCTAssertTrue(validation.isValid, validation.summary, file: file, line: line)
    }

    func testDefaultFillExtrudesLikeExplicitFillWithoutAnOutline() throws {
        var options = ConversionOptions.trueSize
        options.extrudeDepth = 2
        options.extrudeRounding = 0
        options.thickness = 3
        func convert(_ paint: String) throws -> Mesh {
            let svg = "<svg viewBox='0 0 12 12'><rect x='2' y='3' width='8' height='6' \(paint)/></svg>"
            return try Converter.buildMesh(SVGParser.parse(data: Data(svg.utf8)), options: options)
        }
        let expected = try convert("fill='black' stroke='none'")
        for paint in ["", "fill='black' stroke='red' stroke-width='0'"] {
            let actual = try convert(paint)
            assertWatertight(actual)
            XCTAssertEqual(actual.positions, expected.positions)
            XCTAssertEqual(actual.indices, expected.indices)
            XCTAssertEqual(actual.bounds.size.x, 8 * 2.54 / 72, accuracy: 0.003)
            XCTAssertEqual(actual.bounds.size.y, 6 * 2.54 / 72, accuracy: 0.003)
            XCTAssertEqual(actual.bounds.size.z, 2 * 2.54 / 72, accuracy: 0.003)
        }
    }

    func testCrossingStrokesFuseIntoOneWatertightSolid() throws {
        let m = try mesh(##"<path d="M4 4 20 20"/><path d="M20 4 4 20"/>"##)
        XCTAssertGreaterThan(m.triangleCount, 100)
        assertWatertight(m)
    }

    func testFilletedAndFilledShapesAreWatertight() throws {
        var o = ConversionOptions.trueSize
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
        var o = ConversionOptions.trueSize
        o.sizing = .fixed
        o.size = 24
        let round = try mesh(##"<path d="M2 12h20"/>"##, options: o).bounds.size.x
        o.caps = .flat
        let flat = try mesh(##"<path d="M2 12h20"/>"##, options: o).bounds.size.x
        XCTAssertEqual(round, 22, accuracy: 0.1)
        XCTAssertEqual(flat, 20, accuracy: 0.1)
    }

    func testFacetsControlDensity() throws {
        var o = ConversionOptions.trueSize
        o.facets = 16
        let coarse = try mesh(##"<circle cx="12" cy="12" r="8"/>"##, options: o).triangleCount
        o.facets = 64
        let fine = try mesh(##"<circle cx="12" cy="12" r="8"/>"##, options: o).triangleCount
        XCTAssertGreaterThan(fine, coarse * 4)
    }

    func testOptimizationIsLighterWatertightAndOnTheSurface() throws {
        let body = ##"<path d="M4 4 20 20"/><path d="M20 4 4 20"/><circle cx="12" cy="12" r="8"/>"##
        var o = ConversionOptions.trueSize
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

    private let tee = "<path d='M4 8h16'/><path d='M12 8v12'/>"

    func testBlendedTeeStaysFlatOnTopAndFilletsUnderneath() throws {
        let pt = 2.54 / 72
        var options = ConversionOptions.trueSize
        options.fillet = 1
        let blended = try mesh(tee, options: options)
        assertWatertight(blended)
        // The bar's centerline is 4 pt above the canvas center and its tube radius is 1 pt, so its
        // top is at 5 pt. The upright's rounded end inside the bar must not raise a bump there.
        XCTAssertEqual(blended.bounds.max.y, 5 * pt, accuracy: 0.02 * pt)
        // Its depth stays one stroke width: no bulge toward the viewer at the joint.
        XCTAssertEqual(blended.bounds.size.z, 2 * pt, accuracy: 0.02 * pt)
        // Underneath, the inside corners get material that a crisp union leaves empty.
        func cornerVertices(_ m: Mesh) -> Int {
            m.positions.filter { p in
                let x = abs(Double(p.x)) / pt, y = Double(p.y) / pt
                return x > 1.1 && x < 1.5 && y > 2.5 && y < 2.9 && abs(Double(p.z)) / pt < 0.5
            }.count
        }
        options.fillet = 0
        XCTAssertEqual(cornerVertices(try mesh(tee, options: options)), 0)
        XCTAssertGreaterThan(cornerVertices(blended), 0)
    }

    func testFullBlendAtABusyCrossingIsValidWithoutFallback() throws {
        var options = ConversionOptions.trueSize
        options.fillet = 1
        let m = try mesh("<path d='M5 5 19 19M19 5 5 19'/><path d='M4 12h16'/><circle cx='12' cy='12' r='7'/>", options: options)
        assertWatertight(m)
        XCTAssertFalse(m.warnings.contains { $0.contains("denser mesh") })
    }

    func testEmptyDocumentThrows() {
        XCTAssertThrowsError(try mesh(##"<path d="M0 0h24" stroke="none"/>"##))
    }
    func testFlatCapsDoNotChangeWhenStraightSegmentsAreSubdivided() throws {
        var options = ConversionOptions.trueSize
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
        var options = ConversionOptions.trueSize
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
        var options = ConversionOptions.trueSize
        options.sizing = .physical
        let m = try Converter.buildMesh(document, options: options)
        XCTAssertEqual(m.bounds.size.x, 2.54, accuracy: 0.003)
    }

    func testInvalidDocumentCoordinatesThrowBeforeSampling() throws {
        var document = try SVGParser.parse(data: Data("<svg stroke='black'><path d='M0 0h10'/></svg>".utf8))
        document.canvas = (.zero, [Double.infinity, 24])
        XCTAssertThrowsError(try Converter.buildMesh(document, options: ConversionOptions.trueSize))
        var options = ConversionOptions.trueSize
        options.thickness = .nan
        XCTAssertThrowsError(try mesh("<path d='M0 0h10'/>", options: options))
    }

    func testIntegerOutputScalePreservesTopology() throws {
        let body = "<path d='M4 4 20 20'/><path d='M20 4 4 20'/>"
        let original = try mesh(body)
        var options = ConversionOptions.trueSize
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
        XCTAssertEqual(options.outputScale, 10, "A missing Output Scale takes the current default")
        XCTAssertEqual(options.sizing, .points)
        XCTAssertEqual(try JSONDecoder().decode(ConversionOptions.self, from: JSONEncoder().encode(options)), options)
        XCTAssertEqual(ConversionOptions().outputScale, 10, "USDZ and GLB default to 10× so icons import at a workable size")
    }

    private func crossingX(cm: Double) -> [PrimitiveGroup] {
        [PrimitiveGroup(primitives: [.capsule(Vec3(-8,-8,0) * cm, Vec3(8,8,0) * cm, cm)]),
         PrimitiveGroup(primitives: [.capsule(Vec3(8,-8,0) * cm, Vec3(-8,8,0) * cm, cm)])]
    }

    func testCrossingSheetsContourToAManifoldWithoutFallback() {
        // Before per-sheet contouring, this X pinched at its crease and needed the dense fallback.
        let cm = 2.54 / 72
        let m = FusedMesher(groups: crossingX(cm: cm), voxel: 2 * .pi * cm / (32 * 1.4), blend: 0,
                            tolerance: cm * (1 - cos(.pi / 32))).build()
        assertWatertight(m)
        XCTAssertFalse(m.warnings.contains { $0.contains("denser mesh") })
    }

    func testTetrahedralFallbackProducesAClosedManifold() {
        let cm = 2.54 / 72
        var mesher = FusedMesher(groups: crossingX(cm: cm), voxel: 2 * .pi * cm / (32 * 1.4), blend: 0)
        mesher.forceTetrahedralFallback = true
        let m = mesher.build()
        assertWatertight(m)
        XCTAssertTrue(m.warnings.contains { $0.contains("denser mesh") })
    }

    func testCellWithOneCornerInsideHasOneSheet() {
        var v = [Float](repeating: 1, count: 8)
        v[0] = -1
        let (packed, count) = FusedMesher.sheets(values: v)
        XCTAssertEqual(count, 1)
        // Edges 0, 4, and 8 touch corner 0; all belong to sheet 0.
        for e in [0, 4, 8] { XCTAssertEqual((packed >> (4 * UInt64(e))) & 0xF, 0) }
    }

    func testOppositeCubeCornersFormTwoSheets() {
        var v = [Float](repeating: 1, count: 8)
        v[0] = -1
        v[7] = -1
        XCTAssertEqual(FusedMesher.sheets(values: v).count, 2)
    }

    func testAmbiguousFaceFollowsItsSaddle() {
        // Corners 0 and 3 are inside, diagonally across the z = 0 face.
        var weak = [Float](repeating: 1, count: 8)
        weak[0] = -0.2; weak[3] = -0.2
        weak[1] = 1; weak[2] = 1
        // The saddle is outside, so each inside corner is cut off: two sheets.
        XCTAssertEqual(FusedMesher.sheets(values: weak).count, 2)

        var strong = [Float](repeating: 1, count: 8)
        strong[0] = -1; strong[3] = -1
        strong[1] = 0.1; strong[2] = 0.1
        // The saddle is inside, so the inside corners connect across the face: one sheet.
        XCTAssertEqual(FusedMesher.sheets(values: strong).count, 1)
    }

    func testFastValidationStillRejectsPinchedVerticesWithClosedEdges() {
        // Two tetrahedra touch only at the origin. Every edge has two incident faces,
        // but the shared vertex has two separate surface neighborhoods.
        let pinched = Mesh(positions: [[0,0,0], [1,0,0], [0,1,0], [0,0,1], [-1,0,0], [0,-1,0], [0,0,-1]],
                           normals: Array(repeating: [0,0,1], count: 7),
                           indices: [0,2,1, 0,1,3, 0,3,2, 1,2,3, 0,4,5, 0,6,4, 0,5,6, 4,6,5])
        let full = pinched.validation()
        XCTAssertEqual(full.boundaryEdges, 0)
        XCTAssertEqual(full.nonManifoldEdges, 0)
        XCTAssertEqual(full.inconsistentEdges, 0)
        XCTAssertEqual(full.invalidVertexLinks, 1)
        XCTAssertFalse(pinched.validation(checkAllFailures: false).isValid)

        let tetrahedron = Mesh(positions: Array(pinched.positions.prefix(4)),
                               normals: Array(pinched.normals.prefix(4)),
                               indices: Array(pinched.indices.prefix(12)))
        XCTAssertTrue(tetrahedron.validation().isValid)
        XCTAssertTrue(tetrahedron.validation(checkAllFailures: false).isValid)
    }

}
