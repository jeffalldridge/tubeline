import TubelineCore

/// Which files an export writes. USDZ is the default; GLB suits After Effects, Cinema 4D,
/// and Blender.
enum ExportFormat: String, CaseIterable {
    case usdz, glb, both

    var formats: [Converter.Format] {
        switch self {
        case .usdz: [.usdz]
        case .glb: [.glb]
        case .both: [.usdz, .glb]
        }
    }

    var title: String {
        switch self {
        case .usdz: "USDZ"
        case .glb: "GLB"
        case .both: "USDZ and GLB"
        }
    }

    var help: String {
        switch self {
        case .usdz: "USDZ works in Apple Motion and other Apple apps."
        case .glb: "GLB works in After Effects, Cinema 4D, Blender, and web tools."
        case .both: "Saves a USDZ file and a GLB file for each icon."
        }
    }
}
