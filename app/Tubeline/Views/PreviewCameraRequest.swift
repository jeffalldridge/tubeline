import Foundation

struct PreviewCameraRequest: Equatable {
    enum Mode { case fit, front, reset }
    let id = UUID()
    var mode = Mode.reset
}
