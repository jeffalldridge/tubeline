import Foundation
import SceneKit
import AppKit

/// Shared SceneKit setup for previewing a converted model, used by the app's 3D view
/// and by the command-line `--png` option.
public enum PreviewScene {
    public static let cameraName = "tubeline.previewCamera"

    /// Loads a USDZ into a scene with a neutral studio light rig and a framed camera.
    /// The lights only exist in the preview; the exported file has none.
    public static func make(usdz: URL, tilt: Double = 0.35,
                            viewportSize: CGSize = CGSize(width: 1, height: 1)) throws -> SCNScene {
        let scene = try SCNScene(url: usdz, options: [.checkConsistency: false])
        let camera = SCNCamera()
        camera.fieldOfView = 30
        camera.projectionDirection = .vertical
        camera.automaticallyAdjustsZRange = true
        let cameraNode = SCNNode()
        cameraNode.name = PreviewScene.cameraName
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        fitCamera(in: scene, viewportSize: viewportSize, tilt: tilt)

        func light(_ type: SCNLight.LightType, _ intensity: CGFloat, _ euler: SCNVector3 = SCNVector3Zero) {
            let l = SCNLight()
            l.type = type
            l.intensity = intensity
            let n = SCNNode()
            n.light = l
            n.eulerAngles = euler
            scene.rootNode.addChildNode(n)
        }
        light(.ambient, 250)
        light(.directional, 900, SCNVector3(-0.7, 0.5, 0))
        light(.directional, 350, SCNVector3(0.3, -2.4, 0))
        scene.background.contents = NSColor(calibratedWhite: 0.16, alpha: 1)
        return scene
    }

    /// Fits the complete bounding sphere, including in a narrow preview pane.
    /// Call when resetting the view or when its viewport changes, rather than during an orbit.
    public static func fitCamera(in scene: SCNScene, viewportSize: CGSize, tilt: Double = 0.35) {
        guard let node = scene.rootNode.childNode(withName: cameraName, recursively: false),
              let camera = node.camera else { return }
        let (lo, hi) = scene.rootNode.boundingBox
        let center = SCNVector3((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (lo.z + hi.z) / 2)
        let dx = Double(hi.x - lo.x), dy = Double(hi.y - lo.y), dz = Double(hi.z - lo.z)
        let radius = max(sqrt(dx * dx + dy * dy + dz * dz) / 2, 1e-6)
        let distance = fittedCameraDistance(radius: radius, viewportSize: viewportSize,
                                            verticalFieldOfView: camera.fieldOfView)
        camera.usesOrthographicProjection = tilt == 0
        if camera.usesOrthographicProjection {
            let aspect = viewportSize.width > 0 && viewportSize.height > 0 ? Double(viewportSize.width / viewportSize.height) : 1
            camera.orthographicScale = radius * 1.08 * max(1, 1 / aspect)
        }
        // Camera control can move well beyond the fitted view. Keep a broad fallback range
        // while SceneKit adjusts the planes to the model during interaction.
        camera.zNear = radius * 0.001
        camera.zFar = max(distance * 20, radius * 100)
        let yaw = tilt, pitch = tilt * 0.6
        node.position = SCNVector3(
            center.x + CGFloat(distance * sin(yaw) * cos(pitch)),
            center.y + CGFloat(distance * sin(pitch)),
            center.z + CGFloat(distance * cos(yaw) * cos(pitch)))
        if tilt == 0 {
            node.eulerAngles = SCNVector3Zero
        } else {
            node.look(at: center, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        }
    }

    static func fittedCameraDistance(radius: Double, viewportSize: CGSize,
                                     verticalFieldOfView: Double) -> Double {
        let aspect: Double
        if viewportSize.width.isFinite, viewportSize.height.isFinite,
           viewportSize.width > 0, viewportSize.height > 0 {
            aspect = Double(viewportSize.width / viewportSize.height)
        } else {
            aspect = 1
        }
        let verticalHalfAngle = verticalFieldOfView * .pi / 360
        let horizontalHalfAngle = atan(tan(verticalHalfAngle) * aspect)
        return radius / sin(min(verticalHalfAngle, horizontalHalfAngle)) * 1.08
    }

    /// Renders a still image of a USDZ, for thumbnails and command-line previews.
    public static func renderPNG(usdz: URL, to output: URL, size: CGSize = CGSize(width: 1024, height: 1024),
                                 transparent: Bool = false, tilt: Double = 0.35) throws {
        let scene = try make(usdz: usdz, tilt: tilt, viewportSize: size)
        if transparent { scene.background.contents = NSColor.clear }
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.pointOfView = scene.rootNode.childNode(withName: cameraName, recursively: false)
        let image = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: output)
    }
}
