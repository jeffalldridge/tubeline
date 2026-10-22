import SwiftUI
import SceneKit
import TubelineCore

struct ModelPreview: NSViewRepresentable {
    var url: URL?
    var subject: UUID?
    var showForm: Bool
    var cameraRequest: PreviewCameraRequest
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var renderingError: String?

    func makeNSView(context: Context) -> PreviewSCNView {
        let view = PreviewSCNView()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1)
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = !reduceMotion
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.image)
        view.setAccessibilityLabel("3D Model Preview")
        view.setAccessibilityHelp("Drag to orbit or use Fit, Front, and Reset View below the preview.")
        return view
    }

    func updateNSView(_ view: PreviewSCNView, context: Context) {
        let coordinator = context.coordinator
        view.defaultCameraController.inertiaEnabled = !reduceMotion
        if reduceMotion { view.defaultCameraController.stopInertia() }
        view.setAccessibilityValue(url == nil ? "No model displayed" : (showForm ? "Shaded inspection preview" : "Export material preview"))
        let sameSubject = coordinator.subject == subject
        if !sameSubject { coordinator.cameraTransform = nil }
        let sameGeometry = sameSubject && coordinator.loadedURL == url
        if sameGeometry, let camera = view.pointOfView { coordinator.cameraTransform = camera.transform }
        if !sameGeometry { coordinator.cameraTransform = nil }
        coordinator.subject = subject
        let key = "\(url?.path ?? "")|\(showForm)"
        if coordinator.loadedKey != key {
            coordinator.loadedKey = key
            coordinator.loadedURL = url
            do {
                if let url {
                    let scene = try PreviewScene.make(usdz: url, tilt: view.cameraTilt, viewportSize: view.bounds.size)
                    if showForm {
                        let material = SCNMaterial()
                        material.lightingModel = .physicallyBased
                        material.diffuse.contents = NSColor.white
                        material.roughness.contents = 0.45
                        scene.rootNode.enumerateHierarchy { node, _ in
                            if let geometry = node.geometry {
                                geometry.materials = Array(repeating: material, count: max(1, geometry.materials.count))
                            }
                        }
                    }
                    view.scene = scene
                    let camera = scene.rootNode.childNode(withName: PreviewScene.cameraName, recursively: false)
                    if let transform = coordinator.cameraTransform { camera?.transform = transform }
                    view.pointOfView = camera
                    view.defaultCameraController.pointOfView = camera
                    let (lo, hi) = scene.rootNode.boundingBox
                    view.defaultCameraController.target = SCNVector3((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (lo.z + hi.z) / 2)
                    view.needsLayout = true
                    view.setAccessibilityHelp("Use the View menu or Fit, Front, and Reset View buttons. Drag to orbit the model.")
                    Task { @MainActor in
                        guard coordinator.loadedKey == key else { return }
                        renderingError = nil
                    }
                } else {
                    view.scene = nil
                }
            } catch {
                view.scene = nil
                view.setAccessibilityHelp(error.localizedDescription)
                Task { @MainActor in
                    guard coordinator.loadedKey == key else { return }
                    renderingError = error.localizedDescription
                }
            }
        }
        if coordinator.cameraRequest != cameraRequest.id, view.scene != nil {
            coordinator.cameraRequest = cameraRequest.id
            view.applyCameraRequest(cameraRequest.mode)
            coordinator.cameraTransform = view.pointOfView?.transform
        }
    }

    func makeCoordinator() -> PreviewCoordinator { PreviewCoordinator() }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PreviewSCNView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 320, height: proposal.height ?? 240)
    }
}
