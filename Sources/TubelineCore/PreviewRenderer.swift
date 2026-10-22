import Foundation
import SceneKit
import AppKit

/// Shared SceneKit setup for previewing a converted model, used by the app's 3D view
/// and by the command-line `--png` option.
public enum PreviewScene {
    public static let cameraName = "tubeline.previewCamera"

    /// Loads a USDZ into a scene with a neutral studio light rig and a framed camera.
    /// The lights only exist in the preview; the exported file has none.
    public static func make(usdz: URL, tilt: Double = 0.35) throws -> SCNScene {
        let scene = try SCNScene(url: usdz, options: [.checkConsistency: false])
        let (lo, hi) = scene.rootNode.boundingBox
        let center = SCNVector3((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (lo.z + hi.z) / 2)
        let extent = max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z)

        let camera = SCNCamera()
        camera.fieldOfView = 30
        camera.zNear = Double(extent) * 0.01
        camera.zFar = Double(extent) * 20
        let cameraNode = SCNNode()
        cameraNode.name = PreviewScene.cameraName
        cameraNode.camera = camera
        let distance = Double(extent) * 2.2
        cameraNode.position = SCNVector3(
            center.x + CGFloat(distance * sin(tilt)),
            center.y + CGFloat(distance * sin(tilt * 0.6)),
            center.z + CGFloat(distance * cos(tilt)))
        cameraNode.look(at: center)
        scene.rootNode.addChildNode(cameraNode)

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

    /// Renders a still image of a USDZ, for thumbnails and command-line previews.
    public static func renderPNG(usdz: URL, to output: URL, size: CGSize = CGSize(width: 1024, height: 1024)) throws {
        let scene = try make(usdz: usdz)
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
