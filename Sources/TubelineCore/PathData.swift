import Foundation
import simd

/// A flattened subpath: a polyline that is optionally closed.
/// Closed polylines do not repeat their first point at the end.
public struct Polyline2D: Sendable {
    public var points: [Vec2]
    public var closed: Bool
}

/// Builds flattened polylines from path commands. Curves are subdivided
/// until they deviate from their chords by less than `tolerance`.
final class PathBuilder {
    private(set) var polylines: [Polyline2D] = []
    private var current: [Vec2] = []
    private var cur = Vec2.zero
    private var start = Vec2.zero
    let tolerance: Double

    var currentPoint: Vec2 { cur }

    init(tolerance: Double) {
        self.tolerance = max(tolerance, 1e-6)
    }

    func moveTo(_ p: Vec2) {
        flush(closed: false)
        current = [p]
        cur = p
        start = p
    }

    func lineTo(_ p: Vec2) {
        if current.isEmpty { current = [cur] }
        current.append(p)
        cur = p
    }

    func cubicTo(_ c1: Vec2, _ c2: Vec2, _ p: Vec2) {
        if current.isEmpty { current = [cur] }
        subdivideCubic(cur, c1, c2, p, depth: 0)
        cur = p
    }

    func quadTo(_ c: Vec2, _ p: Vec2) {
        let c1 = cur + (c - cur) * (2.0 / 3.0)
        let c2 = p + (c - p) * (2.0 / 3.0)
        cubicTo(c1, c2, p)
    }

    /// SVG elliptical arc, using the endpoint-to-center conversion from the SVG spec (F.6.5).
    func arcTo(rx rxIn: Double, ry ryIn: Double, rotation: Double, largeArc: Bool, sweep: Bool, _ p: Vec2) {
        let p0 = cur
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx < 1e-12 || ry < 1e-12 || simd_distance(p0, p) < 1e-12 {
            lineTo(p)
            return
        }
        let phi = rotation * .pi / 180
        let cosP = cos(phi), sinP = sin(phi)
        let dx2 = (p0.x - p.x) / 2, dy2 = (p0.y - p.y) / 2
        let x1p = cosP * dx2 + sinP * dy2
        let y1p = -sinP * dx2 + cosP * dy2

        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            rx *= sqrt(lambda); ry *= sqrt(lambda)
        }
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let coef = (largeArc != sweep ? 1.0 : -1.0) * sqrt(max(0, num / den))
        let cxp = coef * rx * y1p / ry
        let cyp = coef * -ry * x1p / rx
        let cx = cosP * cxp - sinP * cyp + (p0.x + p.x) / 2
        let cy = sinP * cxp + cosP * cyp + (p0.y + p.y) / 2

        func angle(_ u: Vec2, _ v: Vec2) -> Double {
            atan2(u.x * v.y - u.y * v.x, simd_dot(u, v))
        }
        let u = Vec2((x1p - cxp) / rx, (y1p - cyp) / ry)
        let v = Vec2((-x1p - cxp) / rx, (-y1p - cyp) / ry)
        let theta1 = angle(Vec2(1, 0), u)
        var dTheta = angle(u, v)
        if !sweep && dTheta > 0 { dTheta -= 2 * .pi }
        if sweep && dTheta < 0 { dTheta += 2 * .pi }

        let n = arcSegmentCount(radius: max(rx, ry), sweep: abs(dTheta))
        if current.isEmpty { current = [cur] }
        for i in 1...n {
            let t = theta1 + dTheta * Double(i) / Double(n)
            let x = cx + rx * cos(t) * cosP - ry * sin(t) * sinP
            let y = cy + rx * cos(t) * sinP + ry * sin(t) * cosP
            current.append(Vec2(x, y))
        }
        current[current.count - 1] = p
        cur = p
    }

    func close() {
        if current.isEmpty { current = [cur] }
        cur = start
        flush(closed: true)
    }

    func finish() -> [Polyline2D] {
        flush(closed: false)
        return polylines
    }

    func arcSegmentCount(radius: Double, sweep: Double) -> Int {
        guard radius > tolerance else { return max(2, Int(ceil(sweep / (.pi / 4)))) }
        let step = 2 * acos(max(-1, min(1, 1 - tolerance / radius)))
        return max(2, min(1024, Int(ceil(sweep / max(step, 1e-3)))))
    }

    private func subdivideCubic(_ p0: Vec2, _ p1: Vec2, _ p2: Vec2, _ p3: Vec2, depth: Int) {
        if depth >= 16 || isFlat(p0, p1, p2, p3) {
            current.append(p3)
            return
        }
        let p01 = (p0 + p1) * 0.5, p12 = (p1 + p2) * 0.5, p23 = (p2 + p3) * 0.5
        let p012 = (p01 + p12) * 0.5, p123 = (p12 + p23) * 0.5
        let mid = (p012 + p123) * 0.5
        subdivideCubic(p0, p01, p012, mid, depth: depth + 1)
        subdivideCubic(mid, p123, p23, p3, depth: depth + 1)
    }

    private func isFlat(_ p0: Vec2, _ p1: Vec2, _ p2: Vec2, _ p3: Vec2) -> Bool {
        // Max distance of the control points from the chord bounds the curve's deviation.
        let chord = p3 - p0
        let len = simd_length(chord)
        if len < 1e-12 {
            return max(simd_distance(p1, p0), simd_distance(p2, p0)) < tolerance
        }
        let nrm = Vec2(-chord.y, chord.x) / len
        let d1 = abs(simd_dot(p1 - p0, nrm)), d2 = abs(simd_dot(p2 - p0, nrm))
        return max(d1, d2) * 0.75 < tolerance
    }

    private func flush(closed: Bool) {
        defer { current = [] }
        guard !current.isEmpty else { return }
        var pts: [Vec2] = [current[0]]
        for p in current.dropFirst() where simd_distance(p, pts[pts.count - 1]) > 1e-9 {
            pts.append(p)
        }
        if closed, pts.count > 2, simd_distance(pts[0], pts[pts.count - 1]) < 1e-9 {
            pts.removeLast()
        }
        // A single point that came from a zero-length segment ("M5 5 l0 0" or "M5 5 Z") is a dot.
        if pts.count == 1 && current.count < 2 && !closed { return }
        polylines.append(Polyline2D(points: pts, closed: closed && pts.count > 2))
    }
}

/// Parses SVG path data (the `d` attribute) into flattened polylines.
enum PathDataParser {
    static func parse(_ d: String, tolerance: Double) -> [Polyline2D] {
        var s = Scanner(Array(d.utf8))
        let b = PathBuilder(tolerance: tolerance)
        var cmd: UInt8 = 0
        var lastCubicCtrl: Vec2? = nil
        var lastQuadCtrl: Vec2? = nil

        while true {
            if let c = s.command() {
                cmd = c
            } else if s.atEnd || cmd == 0 || cmd == UInt8(ascii: "Z") || cmd == UInt8(ascii: "z") {
                break
            }
            // An implicit repeat must start with a number; otherwise the data is malformed.
            let rel = cmd >= UInt8(ascii: "a")
            let o = rel ? b.currentPoint : .zero
            var cubicCtrl: Vec2? = nil
            var quadCtrl: Vec2? = nil

            switch cmd | 0x20 {  // lowercase
            case UInt8(ascii: "m"):
                guard let x = s.number(), let y = s.number() else { return b.finish() }
                b.moveTo(o + Vec2(x, y))
                cmd = rel ? UInt8(ascii: "l") : UInt8(ascii: "L")
            case UInt8(ascii: "l"):
                guard let x = s.number(), let y = s.number() else { return b.finish() }
                b.lineTo(o + Vec2(x, y))
            case UInt8(ascii: "h"):
                guard let x = s.number() else { return b.finish() }
                b.lineTo(Vec2(rel ? b.currentPoint.x + x : x, b.currentPoint.y))
            case UInt8(ascii: "v"):
                guard let y = s.number() else { return b.finish() }
                b.lineTo(Vec2(b.currentPoint.x, rel ? b.currentPoint.y + y : y))
            case UInt8(ascii: "c"):
                guard let x1 = s.number(), let y1 = s.number(),
                      let x2 = s.number(), let y2 = s.number(),
                      let x = s.number(), let y = s.number() else { return b.finish() }
                let c2 = o + Vec2(x2, y2)
                b.cubicTo(o + Vec2(x1, y1), c2, o + Vec2(x, y))
                cubicCtrl = c2
            case UInt8(ascii: "s"):
                guard let x2 = s.number(), let y2 = s.number(),
                      let x = s.number(), let y = s.number() else { return b.finish() }
                let p0 = b.currentPoint
                let c1 = lastCubicCtrl.map { p0 * 2 - $0 } ?? p0
                let c2 = o + Vec2(x2, y2)
                b.cubicTo(c1, c2, o + Vec2(x, y))
                cubicCtrl = c2
            case UInt8(ascii: "q"):
                guard let x1 = s.number(), let y1 = s.number(),
                      let x = s.number(), let y = s.number() else { return b.finish() }
                let c = o + Vec2(x1, y1)
                b.quadTo(c, o + Vec2(x, y))
                quadCtrl = c
            case UInt8(ascii: "t"):
                guard let x = s.number(), let y = s.number() else { return b.finish() }
                let p0 = b.currentPoint
                let c = lastQuadCtrl.map { p0 * 2 - $0 } ?? p0
                b.quadTo(c, o + Vec2(x, y))
                quadCtrl = c
            case UInt8(ascii: "a"):
                guard let rx = s.number(), let ry = s.number(), let rot = s.number(),
                      let large = s.flag(), let sweep = s.flag(),
                      let x = s.number(), let y = s.number() else { return b.finish() }
                b.arcTo(rx: rx, ry: ry, rotation: rot, largeArc: large, sweep: sweep, o + Vec2(x, y))
            case UInt8(ascii: "z"):
                b.close()
            default:
                return b.finish()
            }
            lastCubicCtrl = cubicCtrl
            lastQuadCtrl = quadCtrl
        }
        return b.finish()
    }

    struct Scanner {
        let c: [UInt8]
        var i = 0
        init(_ c: [UInt8]) { self.c = c }

        var atEnd: Bool {
            mutating get { skipSeparators(); return i >= c.count }
        }

        mutating func skipSeparators() {
            while i < c.count, c[i] == 0x20 || c[i] == 0x2C || c[i] == 0x09 || c[i] == 0x0A || c[i] == 0x0D || c[i] == 0x0C {
                i += 1
            }
        }

        mutating func command() -> UInt8? {
            skipSeparators()
            guard i < c.count else { return nil }
            let ch = c[i]
            if "MmLlHhVvCcSsQqTtAaZz".utf8.contains(ch) {
                i += 1
                return ch
            }
            return nil
        }

        mutating func flag() -> Bool? {
            skipSeparators()
            guard i < c.count else { return nil }
            if c[i] == UInt8(ascii: "0") { i += 1; return false }
            if c[i] == UInt8(ascii: "1") { i += 1; return true }
            return nil
        }

        mutating func number() -> Double? {
            skipSeparators()
            let start = i
            func isDigit(_ j: Int) -> Bool { j < c.count && c[j] >= 0x30 && c[j] <= 0x39 }
            if i < c.count, c[i] == UInt8(ascii: "+") || c[i] == UInt8(ascii: "-") { i += 1 }
            var digits = 0
            while isDigit(i) { i += 1; digits += 1 }
            if i < c.count, c[i] == UInt8(ascii: ".") {
                i += 1
                while isDigit(i) { i += 1; digits += 1 }
            }
            guard digits > 0 else { i = start; return nil }
            if i < c.count, c[i] == UInt8(ascii: "e") || c[i] == UInt8(ascii: "E") {
                var j = i + 1
                if j < c.count, c[j] == UInt8(ascii: "+") || c[j] == UInt8(ascii: "-") { j += 1 }
                if isDigit(j) {
                    while isDigit(j) { j += 1 }
                    i = j
                }
            }
            return Double(String(decoding: c[start..<i], as: UTF8.self))
        }
    }
}
