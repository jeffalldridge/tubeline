import SwiftUI

struct MeshControls: View {
    @Binding var detail: Double
    @Binding var optimize: Bool

    var body: some View {
        LabeledSlider(title: "Detail", value: $detail, range: 12...96, step: 2,
                      format: { "\(Int($0))" },
                      help: "Controls mesh density. Lower values produce fewer triangles.")
        HStack(spacing: 8) {
            Button("Low") { detail = 16 }
                .accessibilityLabel("Set Detail to Low")
            Button("Balanced") { detail = 32 }
                .accessibilityLabel("Set Detail to Balanced")
            Button("High") { detail = 64 }
                .accessibilityLabel("Set Detail to High")
        }
        .controlSize(.small)
        Text("Lower detail reduces triangle count. Higher detail smooths curves.")
            .font(.caption).foregroundStyle(.secondary)
        Toggle("Optimize Mesh", isOn: $optimize)
            .help("Reduce triangle count while preserving the surface.")
    }
}
