import XCTest
import simd
@testable import TubelineCore

final class SVGParsingTests: XCTestCase {
    private func doc(_ body: String, root: String = ##"viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="2""##) throws -> SVGDocument {
        try SVGParser.parse(data: Data(##"<svg xmlns="http://www.w3.org/2000/svg" \##(root)>\##(body)</svg>"##.utf8))
    }

    func testPathCommandsAbsoluteRelativeAndImplicitLineTo() {
        let polys = PathDataParser.parse("M2 2 4 2 l0 3 h2 V9 H2 z", tolerance: 0.01)
        XCTAssertEqual(polys.count, 1)
        XCTAssertTrue(polys[0].closed)
        XCTAssertEqual(polys[0].points, [Vec2(2, 2), Vec2(4, 2), Vec2(4, 5), Vec2(6, 5), Vec2(6, 9), Vec2(2, 9)])
    }

    func testCompactNumbersAndArcFlags() {
        // "1.5.5" is 1.5 then .5; arc flags may be written without separators.
        let polys = PathDataParser.parse("M1.5.5-1-2a5 5 0 01 10 0", tolerance: 0.01)
        XCTAssertEqual(polys.count, 1)
        XCTAssertEqual(polys[0].points.first, Vec2(1.5, 0.5))
        XCTAssertEqual(polys[0].points[1], Vec2(-1, -2))
        let end = polys[0].points.last!
        XCTAssertEqual(end.x, 9, accuracy: 1e-9)
        XCTAssertEqual(end.y, -2, accuracy: 1e-9)
        // A half circle of radius 5 should bulge 5 units off its chord.
        let minY = polys[0].points.map(\.y).min()!
        XCTAssertEqual(abs(minY - -2), 5, accuracy: 0.02)
    }

    func testCurveFlatteningStaysWithinTolerance() {
        let polys = PathDataParser.parse("M0 0 C0 10 10 10 10 0", tolerance: 0.01)
        // Cubic midpoint at t=0.5 is (5, 7.5); the polyline must pass close to it.
        let near = polys[0].points.map { simd_distance($0, Vec2(5, 7.5)) }.min()!
        XCTAssertLessThan(near, 0.2)
        XCTAssertGreaterThan(polys[0].points.count, 8)
    }

    func testStrokeInheritanceTransformsAndSkips() throws {
        let d = try doc("""
            <g transform="translate(10 0) scale(2)" stroke-linecap="round">
              <line x1="0" y1="0" x2="1" y2="0"/>
            </g>
            <path d="M0 0h24v24H0z" stroke="none"/>
            <defs><path d="M0 0h5"/></defs>
            <circle cx="5" cy="5" r="2" display="none"/>
            <text>Hi</text>
            """)
        XCTAssertEqual(d.strokes.count, 1)
        XCTAssertEqual(d.strokes[0].points, [Vec2(10, 0), Vec2(12, 0)])
        XCTAssertEqual(d.strokes[0].width, 4, accuracy: 1e-9, "stroke width scales with the transform")
        XCTAssertEqual(d.strokes[0].cap, .round)
        XCTAssertEqual(d.skipped, ["<text>"])
    }

    func testOnlyExplicitFillsCount() throws {
        let d = try doc(##"<circle cx="12" cy="12" r="5" fill="#000"/><circle cx="4" cy="4" r="2"/>"##,
                        root: ##"viewBox="0 0 24 24" stroke="#000""##)
        XCTAssertEqual(d.fills.count, 1, "the default black fill must not turn line art into solids")
        XCTAssertEqual(d.fills[0].strokeWidth, 1)
        XCTAssertEqual(d.strokes.count, 2)
    }

    func testFillOnlyShapeHasNoOutlineWidth() throws {
        let d = try doc(##"<rect x="2" y="2" width="4" height="4" fill="red" stroke="none"/>"##)
        XCTAssertEqual(d.fills.count, 1)
        XCTAssertNil(d.fills[0].strokeWidth)
        XCTAssertTrue(d.strokes.isEmpty)
    }

    func testIllustratorStyleClasses() throws {
        let d = try doc("""
            <defs><style>.cls-1{fill:none;stroke:#231f20;stroke-linecap:square;stroke-width:3px;}</style></defs>
            <polyline class="cls-1" points="1 1 5 5 9 1"/>
            """, root: ##"viewBox="0 0 10 10""##)
        XCTAssertEqual(d.strokes.count, 1)
        XCTAssertEqual(d.strokes[0].width, 3)
        XCTAssertEqual(d.strokes[0].cap, .square)
        XCTAssertTrue(d.fills.isEmpty)
    }

    func testPointsPerUnitFromWidthAndViewBox() throws {
        XCTAssertEqual(try doc("<path d='M0 0h1'/>", root: ##"width="48" height="48" viewBox="0 0 24 24" stroke="#000""##).pointsPerUnit, 2)
        XCTAssertEqual(try doc("<path d='M0 0h1'/>", root: ##"width="1in" viewBox="0 0 72 72" stroke="#000""##).pointsPerUnit, 1)
        XCTAssertEqual(try doc("<path d='M0 0h1'/>", root: ##"viewBox="0 0 24 24" stroke="#000""##).pointsPerUnit, 1)
    }

    func testDashesSplitAndDots() {
        let line = [Polyline2D(points: [Vec2(0, 0), Vec2(10, 0)], closed: false)]
        let dashes = Dasher.split(line, pattern: [4, 2], offset: 0)
        XCTAssertEqual(dashes.map(\.points), [[Vec2(0, 0), Vec2(4, 0)], [Vec2(6, 0), Vec2(10, 0)]])

        let dots = Dasher.split(line, pattern: [0, 5], offset: 0)
        XCTAssertEqual(dots.map(\.points.count), [1, 1, 1], "zero-length dashes become single points")

        let shifted = Dasher.split(line, pattern: [4, 2], offset: 3)
        XCTAssertEqual(shifted.first?.points, [Vec2(0, 0), Vec2(1, 0)])
    }

    func testDashThroughClosedPathStartIsOneDash() {
        let square = [Polyline2D(points: [Vec2(0, 0), Vec2(4, 0), Vec2(4, 4), Vec2(0, 4)], closed: true)]
        // Perimeter 16, pattern period 8: the last dash runs into the first through the start point.
        let dashes = Dasher.split(square, pattern: [6, 2], offset: 3)
        XCTAssertEqual(dashes.count, 2)
    }
}
