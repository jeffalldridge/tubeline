import Foundation
import simd

/// Splits polylines into dashes following SVG's stroke-dasharray rules.
enum Dasher {
    static func split(_ polys: [Polyline2D], pattern raw: [Double], offset: Double) -> [Polyline2D] {
        // Invalid or all-zero patterns render solid, as in SVG.
        guard !raw.isEmpty, !raw.contains(where: { $0 < 0 }), raw.contains(where: { $0 > 0 }) else { return polys }
        let pattern = raw.count % 2 == 1 ? raw + raw : raw
        let period = pattern.reduce(0, +)
        return polys.flatMap { dash($0, pattern: pattern, period: period, offset: offset) }
    }

    private static func dash(_ poly: Polyline2D, pattern: [Double], period: Double, offset: Double) -> [Polyline2D] {
        var pts = poly.points
        if poly.closed, let first = pts.first { pts.append(first) }
        guard pts.count >= 2 else { return [poly] }

        // Find where in the pattern the path starts.
        var index = 0
        var remaining = pattern[0]
        var skip = offset.truncatingRemainder(dividingBy: period)
        if skip < 0 { skip += period }
        while skip > 0 {
            if skip >= remaining {
                skip -= remaining
                index = (index + 1) % pattern.count
                remaining = pattern[index]
            } else {
                remaining -= skip
                skip = 0
            }
        }

        let startsOn = index % 2 == 0 && remaining > 0
        var out: [Polyline2D] = []
        var current: [Vec2] = index % 2 == 0 ? [pts[0]] : []
        for s in 0..<(pts.count - 1) {
            let a = pts[s], b = pts[s + 1]
            let len = simd_distance(a, b)
            var pos = 0.0
            while len - pos > remaining {
                pos += remaining
                let p = a + (b - a) * (pos / len)
                if index % 2 == 0 {
                    current.append(p)
                    out.append(Polyline2D(points: dedupe(current), closed: false))
                    current = []
                } else {
                    current = [p]
                }
                index = (index + 1) % pattern.count
                remaining = pattern[index]
            }
            remaining -= len - pos
            if index % 2 == 0 { current.append(b) }
        }
        if index % 2 == 0, !current.isEmpty {
            out.append(Polyline2D(points: dedupe(current), closed: false))
        }
        // On a closed path, a dash running through the start point is one dash, not two.
        if poly.closed, out.count >= 2, index % 2 == 0, startsOn,
           let last = out.last, let first = out.first,
           simd_distance(last.points[last.points.count - 1], first.points[0]) < 1e-9 {
            out[0] = Polyline2D(points: dedupe(last.points + first.points.dropFirst()), closed: false)
            out.removeLast()
        }
        return out
    }

    /// Removes repeated points; a zero-length dash stays as a single point (a dot with round caps).
    private static func dedupe(_ pts: [Vec2]) -> [Vec2] {
        var r: [Vec2] = []
        for p in pts where r.last.map({ simd_distance($0, p) > 1e-9 }) ?? true { r.append(p) }
        return r
    }
}
