import XCTest
import SceneKit
import simd
import TubelineCore
@testable import Tubeline

@MainActor
final class PreviewCameraTests: XCTestCase {
    private func preview() -> (PreviewSCNView, SCNNode, SCNNode) {
        let view = PreviewSCNView(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        view.allowsCameraControl = true
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = true
        let scene = SCNScene()
        scene.rootNode.addChildNode(SCNNode(geometry: SCNBox(width: 4, height: 2, length: 0.2, chamferRadius: 0)))
        let owned = SCNNode()
        owned.name = PreviewScene.cameraName
        owned.camera = SCNCamera()
        owned.camera?.fieldOfView = 30
        scene.rootNode.addChildNode(owned)
        view.scene = scene
        // Orbiting can leave a different node driving the viewport.
        let orbitCamera = SCNNode()
        orbitCamera.camera = SCNCamera()
        orbitCamera.position = SCNVector3(20, 10, 30)
        orbitCamera.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(orbitCamera)
        view.pointOfView = orbitCamera
        view.defaultCameraController.pointOfView = orbitCamera
        return (view, owned, orbitCamera)
    }

    func testFrontReplacesTheOrbitCameraAndFacesTheArtwork() {
        let (view, owned, _) = preview()
        view.applyCameraRequest(.front)
        XCTAssertTrue(view.pointOfView === owned)
        XCTAssertTrue(view.defaultCameraController.pointOfView === owned)
        XCTAssertEqual(owned.position.x, 0, accuracy: 0.0001)
        XCTAssertEqual(owned.position.y, 0, accuracy: 0.0001)
        XCTAssertGreaterThan(owned.position.z, 0)
        XCTAssertEqual(owned.simdWorldFront.x, 0, accuracy: 0.0001)
        XCTAssertEqual(owned.simdWorldFront.y, 0, accuracy: 0.0001)
        XCTAssertEqual(owned.simdWorldFront.z, -1, accuracy: 0.0001)
    }

    func testResetRestoresTheDefaultAngleAfterOrbiting() {
        let (view, owned, _) = preview()
        view.applyCameraRequest(.reset)
        XCTAssertTrue(view.pointOfView === owned)
        XCTAssertGreaterThan(owned.position.x, 0)
        XCTAssertGreaterThan(owned.position.y, 0)
        XCTAssertGreaterThan(owned.position.z, 0)
        XCTAssertEqual(owned.position.x / owned.position.z, tan(0.35), accuracy: 0.0001)
    }

    func testFitPreservesTheOrbitAngleAndReframesTheModel() {
        let (view, owned, orbitCamera) = preview()
        let orientation = orbitCamera.simdWorldOrientation
        let oldDistance = simd_length(orbitCamera.simdWorldPosition)
        view.applyCameraRequest(.fit)
        XCTAssertTrue(view.pointOfView === owned)
        XCTAssertTrue(view.defaultCameraController.pointOfView === owned)
        XCTAssertEqual(abs(simd_dot(owned.simdWorldOrientation.vector, orientation.vector)), 1, accuracy: 0.0001)
        XCTAssertLessThan(simd_length(owned.simdWorldPosition), oldDistance)
    }

    func testResizeKeepsTheFrontView() {
        let (view, owned, _) = preview()
        view.applyCameraRequest(.front)
        view.frame.size = CGSize(width: 300, height: 700)
        view.layout()
        XCTAssertTrue(view.pointOfView === owned)
        XCTAssertEqual(owned.position.x, 0, accuracy: 0.0001)
        XCTAssertEqual(owned.position.y, 0, accuracy: 0.0001)
    }

    func testFrontAfterControllerOrbitAndRepeatedCommands() {
        let (view, owned, _) = preview()
        view.applyCameraRequest(.reset)
        view.defaultCameraController.rotateBy(x: 45, y: 20)
        view.applyCameraRequest(.front)
        _ = view.snapshot()
        XCTAssertTrue(view.pointOfView === owned)
        XCTAssertEqual(owned.presentation.simdWorldFront.x, 0, accuracy: 0.0001)
        XCTAssertEqual(owned.presentation.simdWorldFront.y, 0, accuracy: 0.0001)
        XCTAssertEqual(owned.presentation.simdWorldFront.z, -1, accuracy: 0.0001)
    }
}
