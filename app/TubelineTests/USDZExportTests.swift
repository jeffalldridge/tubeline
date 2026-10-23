import XCTest
import SceneKit
import simd
@testable import TubelineCore

final class USDZExportTests: XCTestCase {
    /// USDZ requires each file's data to start on a 64-byte boundary, uncompressed.
    func testArchiveAlignsFileData() {
        for nameLength in 1...70 {
            let name = String(repeating: "a", count: nameLength) + ".usdc"
            let payload = Data("hello".utf8)
            let zip = USDZArchive.make(entries: [(name, payload)])
            let nameLen = Int(zip[26]) | Int(zip[27]) << 8
            let extraLen = Int(zip[28]) | Int(zip[29]) << 8
            let dataStart = 30 + nameLen + extraLen
            XCTAssertEqual(dataStart % 64, 0, "name length \(nameLength)")
            XCTAssertEqual(zip.subdata(in: dataStart..<dataStart + payload.count), payload)
        }
    }

    func testCRC32MatchesReference() {
        XCTAssertEqual(USDZArchive.crc32(Data("123456789".utf8)), 0xCBF4_3926)
    }

    func testPrimNamesAreValidIdentifiers() {
        XCTAssertEqual(USDZWriter.primName("arrow-left 2"), "arrow_left_2")
        XCTAssertEqual(USDZWriter.primName("3d"), "_3d")
    }

    /// Runs inside the sandboxed app host, so this also proves `usdcat` can be launched there.
    func testExportWritesBinaryUSDInsideThePackage() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let svg = dir.appendingPathComponent("plus.svg")
        try Data(##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" stroke="#000" stroke-width="2"><path d="M12 5v14M5 12h14"/></svg>"##.utf8).write(to: svg)
        let out = dir.appendingPathComponent("plus.usdz")

        let report = try Converter.convert(svg: svg, to: out, options: ConversionOptions())
        XCTAssertGreaterThan(report.triangles, 0)

        let zip = try Data(contentsOf: out)
        let nameLen = Int(zip[26]) | Int(zip[27]) << 8
        let name = String(decoding: zip[30..<30 + nameLen], as: UTF8.self)
        XCTAssertEqual(name, "plus.usdc")
        let extraLen = Int(zip[28]) | Int(zip[29]) << 8
        let start = 30 + nameLen + extraLen
        XCTAssertEqual(String(decoding: zip[start..<start + 8], as: UTF8.self), "PXR-USDC")
    }

    func testSolidSurfaceIsEmissiveOnly() throws {
        let mesh = Mesh(positions: [.zero, [1, 0, 0], [0, 1, 0]], normals: [[0, 0, 1], [0, 0, 1], [0, 0, 1]], indices: [0, 1, 2])
        let solid = try USDZWriter.makeUSDA(mesh: mesh, name: "T", color: SIMD3(1, 0.5, 0), surface: .solid)
        XCTAssertTrue(solid.contains("color3f inputs:emissiveColor = (1.0, \(USDZWriter.linearComponent(0.5)), 0.0)"))
        XCTAssertTrue(solid.contains("color3f inputs:diffuseColor = (0, 0, 0)"))
        let shaded = try USDZWriter.makeUSDA(mesh: mesh, name: "T", color: SIMD3(1, 0.5, 0), surface: .shaded)
        XCTAssertFalse(shaded.contains("emissiveColor"))
        XCTAssertTrue(shaded.contains("metersPerUnit = 0.01"))
    }

    func testHexGrayIsConvertedToLinearShaderColor() throws {
        let mesh = Mesh(positions: [.zero, [1, 0, 0], [0, 1, 0]], normals: [[0, 0, 1], [0, 0, 1], [0, 0, 1]], indices: [0, 1, 2])
        let input = Converter.parseHex("#808080")
        XCTAssertEqual(input.x, 128.0 / 255, accuracy: 1e-12)
        XCTAssertEqual(USDZWriter.linearComponent(input.x), 0.21586050011389926, accuracy: 1e-12)
        XCTAssertEqual(USDZWriter.linearComponent(0.02), 0.0015479876160990713, accuracy: 1e-12)
        let usda = try USDZWriter.makeUSDA(mesh: mesh, name: "gray", color: input, surface: .shaded)
        XCTAssertTrue(usda.contains("inputs:diffuseColor = (0.21586050011389926"))
    }

    func testInvalidMeshDoesNotReplaceExistingOutput() throws {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("invalid-\(UUID().uuidString).usdz")
        let original = Data("existing model".utf8)
        try original.write(to: out)
        defer { try? FileManager.default.removeItem(at: out) }
        let normals: [SIMD3<Float>] = [[0, 0, 1], [0, 0, 1], [0, 0, 1]]
        let invalid = [
            Mesh(),
            Mesh(positions: [.zero, [1, 0, 0], [0, 1, 0]], normals: normals, indices: [0, 1, 3]),
            Mesh(positions: [.zero, [1, 0, 0], [0, 1, 0]], normals: [], indices: [0, 1, 2]),
            Mesh(positions: [.zero, [.nan, 0, 0], [0, 1, 0]], normals: normals, indices: [0, 1, 2]),
        ]
        for mesh in invalid {
            XCTAssertThrowsError(try USDZWriter.write(mesh: mesh, name: "invalid", color: SIMD3(repeating: 1), surface: .solid, to: out))
            XCTAssertEqual(try Data(contentsOf: out), original)
        }
    }

    func testCameraFitRespectsNarrowViewport() {
        let radius = 2.0
        let square = PreviewScene.fittedCameraDistance(radius: radius, viewportSize: CGSize(width: 500, height: 500), verticalFieldOfView: 30)
        let narrow = PreviewScene.fittedCameraDistance(radius: radius, viewportSize: CGSize(width: 250, height: 1000), verticalFieldOfView: 30)
        let horizontalHalfAngle = atan(tan(Double.pi / 12) * 0.25)
        XCTAssertGreaterThan(narrow, square * 3)
        XCTAssertGreaterThan(narrow * sin(horizontalHalfAngle), radius)
        XCTAssertGreaterThan(square * sin(Double.pi / 12), radius)
    }

    func testFittedCameraLeavesRoomForInteractiveZoom() {
        let scene = SCNScene()
        let geometry = SCNNode(geometry: SCNBox(width: 2, height: 2, length: 2, chamferRadius: 0))
        scene.rootNode.addChildNode(geometry)
        let cameraNode = SCNNode()
        cameraNode.name = PreviewScene.cameraName
        cameraNode.camera = SCNCamera()
        scene.rootNode.addChildNode(cameraNode)
        PreviewScene.fitCamera(in: scene, viewportSize: CGSize(width: 600, height: 600), tilt: 0)
        guard let camera = cameraNode.camera else { return XCTFail("Missing preview camera") }
        let fittedDistance = Double(cameraNode.position.z)
        XCTAssertLessThan(camera.zNear, fittedDistance * 0.01)
        XCTAssertGreaterThan(camera.zFar, fittedDistance * 10)
    }

    func testExportKeepsSVGArtworkFrontOnWithoutBakedTransforms() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("asymmetric.svg")
        let output = directory.appendingPathComponent("asymmetric.usdz")
        // An asymmetric L catches rotations, mirroring, and an unflipped SVG Y axis.
        try Data("<svg viewBox='0 0 24 24' fill='none' stroke='black' stroke-width='2' stroke-linecap='round'><path d='M4 4v16h10'/></svg>".utf8).write(to: source)
        let document = try SVGParser.parse(url: source, tolerance: 0.005)
        let mesh = try Converter.buildMesh(document, options: ConversionOptions())
        let pointsToCentimeters = 2.54 / 72
        XCTAssertEqual(mesh.bounds.min.x, -9 * pointsToCentimeters, accuracy: 0.002)
        XCTAssertEqual(mesh.bounds.max.x, 3 * pointsToCentimeters, accuracy: 0.002)
        XCTAssertEqual(mesh.bounds.min.y, -9 * pointsToCentimeters, accuracy: 0.002)
        XCTAssertEqual(mesh.bounds.max.y, 9 * pointsToCentimeters, accuracy: 0.002)
        XCTAssertEqual(mesh.bounds.min.z, -pointsToCentimeters, accuracy: 0.002)
        XCTAssertEqual(mesh.bounds.max.z, pointsToCentimeters, accuracy: 0.002)
        assertLowerRightArm(mesh.positions)
        let usd = try USDZWriter.makeUSDA(mesh: mesh, name: "asymmetric", color: SIMD3(repeating: 1), surface: .solid)
        XCTAssertTrue(usd.contains("upAxis = \"Y\""))
        XCTAssertFalse(usd.contains("xformOp"))
        XCTAssertFalse(usd.contains("def Camera"))
        try USDZWriter.write(mesh: mesh, name: "asymmetric", color: SIMD3(repeating: 1), surface: .solid, to: output)
        let scene = try SCNScene(url: output)
        var geometryCount = 0
        scene.rootNode.enumerateHierarchy { node, _ in
            guard node.geometry != nil else { return }
            geometryCount += 1
            let transform = node.simdWorldTransform
            let x = simd_normalize(SIMD3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z))
            let y = simd_normalize(SIMD3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z))
            let z = simd_normalize(SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z))
            XCTAssertLessThan(simd_distance(x, SIMD3<Float>(1, 0, 0)), 0.0001)
            XCTAssertLessThan(simd_distance(y, SIMD3<Float>(0, 1, 0)), 0.0001)
            XCTAssertLessThan(simd_distance(z, SIMD3<Float>(0, 0, 1)), 0.0001)
            guard let source = node.geometry?.sources(for: .vertex).first,
                  source.usesFloatComponents,
                  source.bytesPerComponent == MemoryLayout<Float>.size,
                  source.componentsPerVector >= 3 else {
                return XCTFail("Expected float3 vertex positions in the exported mesh")
            }
            let loadedPositions: [SIMD3<Float>] = source.data.withUnsafeBytes { bytes in
                (0..<source.vectorCount).map { index in
                    let offset = source.dataOffset + index * source.dataStride
                    let position = SIMD3<Float>(
                        bytes.loadUnaligned(fromByteOffset: offset, as: Float.self),
                        bytes.loadUnaligned(fromByteOffset: offset + 4, as: Float.self),
                        bytes.loadUnaligned(fromByteOffset: offset + 8, as: Float.self))
                    return node.simdConvertPosition(position, to: nil)
                }
            }
            self.assertLowerRightArm(loadedPositions)
        }
        XCTAssertEqual(geometryCount, 1)
    }

    private func assertLowerRightArm(_ positions: [SIMD3<Float>],
                                    file: StaticString = #filePath, line: UInt = #line) {
        guard let minX = positions.map(\.x).min(), let maxX = positions.map(\.x).max(),
              let minY = positions.map(\.y).min(), let maxY = positions.map(\.y).max() else {
            return XCTFail("The L has no vertices", file: file, line: line)
        }
        // Symmetric Y bounds cannot distinguish this L from its vertical reflection.
        let rightSide = minX + (maxX - minX) * 0.6
        let centerY = (minY + maxY) / 2
        let quarterHeight = (maxY - minY) / 4
        XCTAssertTrue(positions.contains { $0.x > rightSide && $0.y < centerY - quarterHeight },
                      "The L must have a lower-right arm", file: file, line: line)
        XCTAssertFalse(positions.contains { $0.x > rightSide && $0.y > centerY + quarterHeight },
                       "The L must not have an upper-right arm", file: file, line: line)
    }

    func testFrontPreviewUsesOrthographicProjectionAndNoRotation() {
        let scene = SCNScene()
        scene.rootNode.addChildNode(SCNNode(geometry: SCNBox(width: 4, height: 2, length: 0.2, chamferRadius: 0)))
        let camera = SCNNode()
        camera.name = PreviewScene.cameraName
        camera.camera = SCNCamera()
        camera.eulerAngles = SCNVector3(0.2, 0.5, 0.4)
        scene.rootNode.addChildNode(camera)
        PreviewScene.fitCamera(in: scene, viewportSize: CGSize(width: 400, height: 600), tilt: 0)
        XCTAssertTrue(camera.camera?.usesOrthographicProjection == true)
        XCTAssertEqual(camera.eulerAngles.x, 0, accuracy: 0.0001)
        XCTAssertEqual(camera.eulerAngles.y, 0, accuracy: 0.0001)
        XCTAssertEqual(camera.eulerAngles.z, 0, accuracy: 0.0001)
        PreviewScene.fitCamera(in: scene, viewportSize: CGSize(width: 400, height: 600), tilt: 0.35)
        XCTAssertFalse(camera.camera?.usesOrthographicProjection == true)
    }
}

final class GLBExportTests: XCTestCase {
    private func glb(surface: ConversionOptions.Surface) throws -> (json: [String: Any], bin: Data, mesh: Mesh) {
        let svg = ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="2" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>"##
        let mesh = try Converter.buildMesh(SVGParser.parse(data: Data(svg.utf8)), options: ConversionOptions())
        let data = GLBWriter.make(mesh: mesh, name: "plus", color: SIMD3(1, 0.5, 0), surface: surface)
        func u32(_ at: Int) -> UInt32 { data.subdata(in: at..<at + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } }
        XCTAssertEqual(u32(0), 0x4654_6C67, "glTF magic")
        XCTAssertEqual(u32(4), 2, "glTF version")
        XCTAssertEqual(Int(u32(8)), data.count, "header length")
        let jsonLength = Int(u32(12))
        XCTAssertEqual(u32(16), 0x4E4F_534A, "JSON chunk")
        XCTAssertEqual(jsonLength % 4, 0)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data.subdata(in: 20..<20 + jsonLength)) as? [String: Any])
        let binStart = 20 + jsonLength
        XCTAssertEqual(u32(binStart + 4), 0x004E_4942, "BIN chunk")
        let bin = data.subdata(in: binStart + 8..<binStart + 8 + Int(u32(binStart)))
        return (json, bin, mesh)
    }

    func testGLBLayoutUsesMetersAndMatchesTheMesh() throws {
        let (json, bin, mesh) = try glb(surface: .solid)
        let accessors = try XCTUnwrap(json["accessors"] as? [[String: Any]])
        XCTAssertEqual(accessors[0]["count"] as? Int, mesh.positions.count)
        XCTAssertEqual(accessors[2]["count"] as? Int, mesh.indices.count)
        let max = try XCTUnwrap(accessors[0]["max"] as? [Double])
        // Centimeters in the mesh become meters in glTF.
        XCTAssertEqual(max[0], Double(mesh.bounds.max.x) / 100, accuracy: 1e-6)
        let first = bin.subdata(in: 0..<12).withUnsafeBytes { SIMD3<Float>($0.loadUnaligned(as: Float.self),
            $0.loadUnaligned(fromByteOffset: 4, as: Float.self), $0.loadUnaligned(fromByteOffset: 8, as: Float.self)) }
        XCTAssertEqual(first, mesh.positions[0] / 100)
    }

    func testSolidColorIsUnlitAndShadedIsMatte() throws {
        let solid = try glb(surface: .solid).json
        XCTAssertEqual(solid["extensionsUsed"] as? [String], ["KHR_materials_unlit"])
        let solidMaterial = try XCTUnwrap((solid["materials"] as? [[String: Any]])?.first)
        XCTAssertNotNil((solidMaterial["extensions"] as? [String: Any])?["KHR_materials_unlit"])
        let factor = try XCTUnwrap((solidMaterial["pbrMetallicRoughness"] as? [String: Any])?["baseColorFactor"] as? [Double])
        // sRGB 0.5 is about 0.214 in linear light, which glTF expects.
        XCTAssertEqual(factor[1], 0.214, accuracy: 0.001)

        let shaded = try glb(surface: .shaded).json
        XCTAssertNil(shaded["extensionsUsed"])
        let pbr = try XCTUnwrap(((shaded["materials"] as? [[String: Any]])?.first?["pbrMetallicRoughness"]) as? [String: Any])
        XCTAssertEqual(pbr["roughnessFactor"] as? Double, 0.5)
        XCTAssertEqual(pbr["metallicFactor"] as? Double, 0)
    }

    func testConvertWritesEveryRequestedFormatFromOneMesh() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let svg = dir.appendingPathComponent("icon.svg")
        try Data(##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" stroke="#000" stroke-width="2" fill="none"><path d="M4 12h16"/></svg>"##.utf8).write(to: svg)
        let outputs = [dir.appendingPathComponent("icon.usdz"), dir.appendingPathComponent("icon.glb")]
        try Converter.convert(svg: svg, to: outputs, options: ConversionOptions())
        let usdz = try Data(contentsOf: outputs[0]), glb = try Data(contentsOf: outputs[1])
        XCTAssertEqual(usdz.prefix(4), Data([0x50, 0x4B, 0x03, 0x04]), "USDZ is a zip package")
        XCTAssertEqual(glb.prefix(4), Data("glTF".utf8))
    }
}
