import SceneKit
import TubelineCore
import simd

final class PreviewSCNView: SCNView {
    private var fittedSize = CGSize.zero
    var cameraTilt = 0.35

    /// SceneKit can replace the displayed camera during orbiting. Always reconnect both
    /// the renderer and its controller after moving our scene camera.
    func applyCameraRequest(_ mode: PreviewCameraRequest.Mode) {
        guard let scene,
              let camera = scene.rootNode.childNode(withName: PreviewScene.cameraName, recursively: false) else { return }
        let orientation = (pointOfView ?? camera).simdWorldOrientation
        defaultCameraController.stopInertia()
        let cameraControlEnabled = allowsCameraControl
        allowsCameraControl = false
        defaultCameraController.pointOfView = nil
        pointOfView = nil
        if mode == .front { cameraTilt = 0 }
        if mode == .reset { cameraTilt = 0.35 }

        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        PreviewScene.fitCamera(in: scene, viewportSize: bounds.size, tilt: cameraTilt)
        let (lo, hi) = scene.rootNode.boundingBox
        let center = SIMD3<Float>(Float((lo.x + hi.x) / 2), Float((lo.y + hi.y) / 2), Float((lo.z + hi.z) / 2))
        if mode == .fit {
            let distance = simd_distance(camera.simdWorldPosition, center)
            camera.simdWorldPosition = center + orientation.act(SIMD3<Float>(0, 0, 1)) * distance
            camera.simdWorldOrientation = orientation
        }
        pointOfView = camera
        allowsCameraControl = cameraControlEnabled
        defaultCameraController.pointOfView = camera
        defaultCameraController.target = SCNVector3(center)
        SCNTransaction.commit()
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0, fittedSize != bounds.size, scene != nil else { return }
        fittedSize = bounds.size
        applyCameraRequest(.fit)
    }
}
