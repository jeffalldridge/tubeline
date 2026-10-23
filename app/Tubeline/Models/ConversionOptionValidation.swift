import Foundation
import TubelineCore

enum ConversionOptionValidation {
    static func problem(in options: ConversionOptions) -> String? {
        let positive = [("Thickness", options.thickness), ("Longest Side", options.size),
                        ("Millimeters per Point", options.millimetersPerPoint), ("Extrusion Depth", options.extrudeDepth)]
        for (field, value) in positive where !value.isFinite || value <= 0 {
            return "\(field): Enter a finite number greater than zero."
        }
        guard options.facets.isFinite, (6...256).contains(options.facets) else {
            return "Detail: Enter a value from 6 to 256."
        }
        guard options.fillet.isFinite, (0...1).contains(options.fillet) else {
            return "Intersection Blend: Enter a value from zero to one."
        }
        guard options.extrudeRounding.isFinite, (0...1).contains(options.extrudeRounding) else {
            return "Edge Rounding: Enter a value from zero to one."
        }
        guard (1...10_000).contains(options.outputScale) else { return "Output Scale: Enter a whole number from 1 to 10,000." }
        return nil
    }
}
