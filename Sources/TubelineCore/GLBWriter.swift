import Foundation
import simd

/// Writes a mesh as binary glTF 2.0 (GLB) for apps such as After Effects, Cinema 4D, and
/// Blender: one mesh, one material, smooth normals, Y up, in meters. The model faces +Z,
/// like the USDZ output.
///
/// Solid Color uses `KHR_materials_unlit` so it renders as flat color; viewers without that
/// extension fall back to a rough, non-metallic base color. Shaded is a plain matte
/// `pbrMetallicRoughness` material.
public enum GLBWriter {
    public static func write(mesh: Mesh, name: String, color: SIMD3<Double>,
                             surface: ConversionOptions.Surface, to url: URL) throws {
        try make(mesh: mesh, name: name, color: color, surface: surface).write(to: url, options: .atomic)
    }

    static func make(mesh: Mesh, name: String, color: SIMD3<Double>, surface: ConversionOptions.Surface) -> Data {
        // Our meshes are in centimeters; glTF is always meters.
        let positions = mesh.positions.map { $0 / 100 }
        let normals = mesh.normals.map { n -> SIMD3<Float> in
            let length = simd_length(n)
            return length > 0 ? n / length : SIMD3(0, 0, 1)
        }
        var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
        for p in positions { lo = simd_min(lo, p); hi = simd_max(hi, p) }

        // Binary chunk: positions, normals, then indices, each 4-byte aligned.
        var bin = Data()
        func append3(_ values: [SIMD3<Float>]) {
            for v in values { for c in [v.x, v.y, v.z] { withUnsafeBytes(of: c.bitPattern.littleEndian) { bin.append(contentsOf: $0) } } }
        }
        append3(positions)
        let positionsLength = bin.count
        append3(normals)
        let normalsLength = bin.count - positionsLength
        for i in mesh.indices { withUnsafeBytes(of: i.littleEndian) { bin.append(contentsOf: $0) } }
        let indicesLength = bin.count - positionsLength - normalsLength
        while bin.count % 4 != 0 { bin.append(0) }

        // glTF colors are linear; our color is sRGB.
        func toLinear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let linear = SIMD3(toLinear(color.x), toLinear(color.y), toLinear(color.z))
        var material: [String: Any] = [
            "name": "Surface",
            "pbrMetallicRoughness": [
                "baseColorFactor": [linear.x, linear.y, linear.z, 1.0],
                "metallicFactor": 0.0,
                "roughnessFactor": surface == .solid ? 1.0 : 0.5,
            ],
        ]
        if surface == .solid { material["extensions"] = ["KHR_materials_unlit": [String: Any]()] }

        var json: [String: Any] = [
            "asset": ["version": "2.0", "generator": "Tubeline"],
            "scene": 0,
            "scenes": [["nodes": [0]]],
            "nodes": [["name": name, "mesh": 0]],
            "meshes": [[
                "name": name,
                "primitives": [[
                    "attributes": ["POSITION": 0, "NORMAL": 1],
                    "indices": 2,
                    "material": 0,
                    "mode": 4,
                ]],
            ]],
            "materials": [material],
            "buffers": [["byteLength": bin.count]],
            "bufferViews": [
                ["buffer": 0, "byteOffset": 0, "byteLength": positionsLength, "target": 34962],
                ["buffer": 0, "byteOffset": positionsLength, "byteLength": normalsLength, "target": 34962],
                ["buffer": 0, "byteOffset": positionsLength + normalsLength, "byteLength": indicesLength, "target": 34963],
            ],
            "accessors": [
                ["bufferView": 0, "componentType": 5126, "count": positions.count, "type": "VEC3",
                 "min": [lo.x, lo.y, lo.z].map(Double.init), "max": [hi.x, hi.y, hi.z].map(Double.init)],
                ["bufferView": 1, "componentType": 5126, "count": normals.count, "type": "VEC3"],
                ["bufferView": 2, "componentType": 5125, "count": mesh.indices.count, "type": "SCALAR"],
            ],
        ]
        if surface == .solid {
            json["extensionsUsed"] = ["KHR_materials_unlit"]
        }

        // JSONSerialization can't fail for these plain values; keys are sorted for stable output.
        var jsonData = (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])) ?? Data("{}".utf8)
        while jsonData.count % 4 != 0 { jsonData.append(0x20) }  // Pad JSON with spaces.

        var glb = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { glb.append(contentsOf: $0) } }
        u32(0x4654_6C67)                                      // "glTF"
        u32(2)                                                // Version
        u32(UInt32(12 + 8 + jsonData.count + 8 + bin.count))  // Total length
        u32(UInt32(jsonData.count)); u32(0x4E4F_534A)          // "JSON" chunk
        glb.append(jsonData)
        u32(UInt32(bin.count)); u32(0x004E_4942)               // "BIN" chunk
        glb.append(bin)
        return glb
    }
}
