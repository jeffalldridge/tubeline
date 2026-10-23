import Foundation

struct PreviewCameraRequest: Equatable {
    enum Mode {
        case fit, front, reset, orbitLeft, orbitRight, orbitUp, orbitDown

        var orbitDelta: (x: Float, y: Float)? {
            switch self {
            case .orbitLeft: (-15, 0)
            case .orbitRight: (15, 0)
            case .orbitUp: (0, -15)
            case .orbitDown: (0, 15)
            default: nil
            }
        }
    }
    let id = UUID()
    var mode = Mode.reset
}
