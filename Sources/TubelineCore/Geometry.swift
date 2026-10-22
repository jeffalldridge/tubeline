import Foundation
import simd

public typealias Vec2 = SIMD2<Double>
public typealias Vec3 = SIMD3<Double>

/// 2D affine transform using SVG's matrix(a b c d e f) convention:
/// x' = a·x + c·y + e,  y' = b·x + d·y + f
public struct Affine: Equatable, Sendable {
    public var a = 1.0, b = 0.0, c = 0.0, d = 1.0, e = 0.0, f = 0.0

    public static let identity = Affine()

    public init() {}
    public init(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ e: Double, _ f: Double) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.e = e; self.f = f
    }

    public static func translate(_ x: Double, _ y: Double) -> Affine { Affine(1, 0, 0, 1, x, y) }
    public static func scale(_ x: Double, _ y: Double) -> Affine { Affine(x, 0, 0, y, 0, 0) }
    public static func rotate(degrees: Double) -> Affine {
        let r = degrees * .pi / 180
        return Affine(cos(r), sin(r), -sin(r), cos(r), 0, 0)
    }

    public func apply(_ p: Vec2) -> Vec2 {
        Vec2(a * p.x + c * p.y + e, b * p.x + d * p.y + f)
    }

    /// Returns self × o, i.e. `o` is applied first, then `self`.
    public func concatenating(_ o: Affine) -> Affine {
        Affine(a * o.a + c * o.b,
               b * o.a + d * o.b,
               a * o.c + c * o.d,
               b * o.c + d * o.d,
               a * o.e + c * o.f + e,
               b * o.e + d * o.f + f)
    }

    /// Uniform scale estimate, used to scale stroke widths.
    public var scaleFactor: Double { sqrt(abs(a * d - b * c)) }
}

/// Axis-aligned bounding box in 3D.
public struct Box3: Sendable {
    public var min = Vec3(repeating: .infinity)
    public var max = Vec3(repeating: -.infinity)

    public init() {}
    public init(min: Vec3, max: Vec3) { self.min = min; self.max = max }

    public var isEmpty: Bool { min.x > max.x }
    public var size: Vec3 { max - min }
    public var center: Vec3 { (min + max) * 0.5 }

    public mutating func include(_ p: Vec3) {
        min = simd_min(min, p); max = simd_max(max, p)
    }
    public mutating func include(_ b: Box3) {
        guard !b.isEmpty else { return }
        min = simd_min(min, b.min); max = simd_max(max, b.max)
    }
    public func expanded(by r: Double) -> Box3 {
        Box3(min: min - Vec3(repeating: r), max: max + Vec3(repeating: r))
    }
}
