import SwiftUI
import SceneKit
import TubelineCore

/// Orbitable 3D view of a USDZ. Drag to rotate, scroll or pinch to zoom, double-click to reset.
struct ModelPreview: NSViewRepresentable {
    var url: URL?
    /// Identifies which icon is shown; the camera orbit is kept while it stays the same.
    var subject: UUID?
    /// Replace the exported material with a lit one so the tube form is visible.
    var showForm: Bool

    func makeNSView(context: Context) -> SCNView {
        let v = SCNView()
        v.allowsCameraControl = true
        v.autoenablesDefaultLighting = false
        v.antialiasingMode = .multisampling4X
        v.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1)
        v.defaultCameraController.interactionMode = .orbitTurntable
        v.defaultCameraController.inertiaEnabled = true
        return v
    }

    func updateNSView(_ v: SCNView, context: Context) {
        let key = "\(url?.path ?? "")|\(showForm)"
        guard context.coordinator.loadedKey != key else { return }
        let keepCamera = context.coordinator.subject != nil && context.coordinator.subject == subject
        let previousTransform = v.pointOfView?.transform
        context.coordinator.loadedKey = key
        context.coordinator.subject = subject

        guard let url, let scene = try? PreviewScene.make(usdz: url) else {
            v.scene = nil
            return
        }
        if showForm {
            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            m.diffuse.contents = NSColor.white
            m.roughness.contents = 0.45
            scene.rootNode.enumerateHierarchy { node, _ in
                if let g = node.geometry { g.materials = Array(repeating: m, count: max(1, g.materials.count)) }
            }
        }
        v.scene = scene
        let camera = scene.rootNode.childNode(withName: PreviewScene.cameraName, recursively: false)
        // While tweaking settings for the same icon, keep the user's orbit instead of snapping back.
        if keepCamera, let t = previousTransform, let camera { camera.transform = t }
        v.pointOfView = camera
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var loadedKey: String?
        var subject: UUID?
    }
}
