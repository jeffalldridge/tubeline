import SceneKit

final class PreviewCoordinator {
    var loadedKey: String?
    var loadedURL: URL?
    var subject: UUID?
    var cameraRequest: UUID?
    var cameraTransform: SCNMatrix4?
}
