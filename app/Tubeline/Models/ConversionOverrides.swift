import Foundation
import TubelineCore

/// Only customized fields stop inheriting the batch setting.
struct ConversionOverrides: Equatable {
    var thickness: Double?
    var facets: Double?
    var fillet: Double?
    var caps: ConversionOptions.Caps?
    var includeFills: Bool?
    var fillStyle: ConversionOptions.FillStyle?
    var extrudeDepth: Double?
    var extrudeRounding: Double?
    var framing: ConversionOptions.Framing?
    var sizing: ConversionOptions.Sizing?
    var millimetersPerPoint: Double?
    var size: Double?
    var outputScale: Int?
    var optimize: Bool?
    var color: String?
    var surface: ConversionOptions.Surface?

    var isEmpty: Bool { self == ConversionOverrides() }

    func applying(to base: ConversionOptions) -> ConversionOptions {
        var value = base
        if let thickness { value.thickness = thickness }
        if let facets { value.facets = facets }
        if let fillet { value.fillet = fillet }
        if let caps { value.caps = caps }
        if let includeFills { value.includeFills = includeFills }
        if let fillStyle { value.fillStyle = fillStyle }
        if let extrudeDepth { value.extrudeDepth = extrudeDepth }
        if let extrudeRounding { value.extrudeRounding = extrudeRounding }
        if let framing { value.framing = framing }
        if let sizing { value.sizing = sizing }
        if let millimetersPerPoint { value.millimetersPerPoint = millimetersPerPoint }
        if let size { value.size = size }
        if let outputScale { value.outputScale = outputScale }
        if let optimize { value.optimize = optimize }
        if let color { value.color = color }
        if let surface { value.surface = surface }
        return value
    }

    /// Editing one field preserves inheritance for every untouched field.
    mutating func update(from old: ConversionOptions, to new: ConversionOptions, base: ConversionOptions) {
        if old.thickness != new.thickness { thickness = new.thickness == base.thickness ? nil : new.thickness }
        if old.facets != new.facets { facets = new.facets == base.facets ? nil : new.facets }
        if old.fillet != new.fillet { fillet = new.fillet == base.fillet ? nil : new.fillet }
        if old.caps != new.caps { caps = new.caps == base.caps ? nil : new.caps }
        if old.includeFills != new.includeFills { includeFills = new.includeFills == base.includeFills ? nil : new.includeFills }
        if old.fillStyle != new.fillStyle { fillStyle = new.fillStyle == base.fillStyle ? nil : new.fillStyle }
        if old.extrudeDepth != new.extrudeDepth { extrudeDepth = new.extrudeDepth == base.extrudeDepth ? nil : new.extrudeDepth }
        if old.extrudeRounding != new.extrudeRounding { extrudeRounding = new.extrudeRounding == base.extrudeRounding ? nil : new.extrudeRounding }
        if old.framing != new.framing { framing = new.framing == base.framing ? nil : new.framing }
        if old.sizing != new.sizing { sizing = new.sizing == base.sizing ? nil : new.sizing }
        if old.millimetersPerPoint != new.millimetersPerPoint { millimetersPerPoint = new.millimetersPerPoint == base.millimetersPerPoint ? nil : new.millimetersPerPoint }
        if old.size != new.size { size = new.size == base.size ? nil : new.size }
        if old.outputScale != new.outputScale { outputScale = new.outputScale == base.outputScale ? nil : new.outputScale }
        if old.optimize != new.optimize { optimize = new.optimize == base.optimize ? nil : new.optimize }
        if old.color != new.color { color = new.color == base.color ? nil : new.color }
        if old.surface != new.surface { surface = new.surface == base.surface ? nil : new.surface }
    }
}
