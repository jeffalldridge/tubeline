import XCTest
import simd
@testable import TubelineCore

final class MeshingTests: XCTestCase {
    private func mesh(_ body: String, options: ConversionOptions = ConversionOptions()) throws -> Mesh {
        let svg = ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="2" stroke-linecap="round">\##(body)</svg>"##
        return try Converter.buildMesh(SVGParser.parse(data: Data(svg.utf8)), options: options)
    }

    /// A closed surface has no boundary: every edge is shared by an even number of triangles
    /// (2, or 4 at the rare pinch where dual contouring joins two sheets at a saddle). Vertices
    /// are welded by position first because crease vertices are duplicated for split normals.
    private func assertWatertight(_ m: Mesh, file: StaticString = #filePath, line: UInt = #line) {
        var ids: [SIMD3<Float>: Int] = [:]
        let weld = m.positions.map { p in ids[p] ?? { ids[p] = ids.count; return ids.count - 1 }() }
        var edges: [SIMD2<Int>: Int] = [:]
        for t in stride(from: 0, to: m.indices.count, by: 3) {
            let v = (0..<3).map { weld[Int(m.indices[t + $0])] }
            for k in 0..<3 {
                let a = v[k], b = v[(k + 1) % 3]
                guard a != b else { continue }
                edges[SIMD2(min(a, b), max(a, b)), default: 0] += 1
            }
        }
        let open = edges.values.filter { $0 % 2 != 0 }.count
        XCTAssertEqual(open, 0, "\(open) of \(edges.count) edges are boundary edges (holes)", file: file, line: line)
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
}
