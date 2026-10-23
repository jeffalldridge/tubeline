import SwiftUI

struct MeshControls: View {
    @Binding var detail: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Mesh Detail").font(.headline)
                Spacer()
                Text("\(Int(detail))").font(.title2.weight(.semibold).monospacedDigit())
            }
            Slider(value: sliderDetail, in: 6...64, step: 2) { Text("Mesh Detail") }
                .labelsHidden()
                .accessibilityValue("\(Int(detail))")
                .help("Controls surface fidelity and triangle count. Lower values create lighter meshes.")
            HStack(spacing: 8) {
                Button("Draft") { detail = 6 }
                    .accessibilityLabel("Set Mesh Detail to Draft, 6")
                Button("Low") { detail = 16 }
                    .accessibilityLabel("Set Mesh Detail to Low, 16")
                Button("Balanced") { detail = 32 }
                    .accessibilityLabel("Set Mesh Detail to Balanced, 32")
                Button("High") { detail = 64 }
                    .accessibilityLabel("Set Mesh Detail to High, 64")
            }
            .controlSize(.small)
            Text("Lower detail reduces triangles. Higher detail smooths curves.")
                .font(.caption).foregroundStyle(.secondary)
            if detail > 64 {
                Text("Current detail exceeds the slider range. Choose a preset or move the slider to use 6–64.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // Existing saved or CLI values stay intact until the user adjusts this control.
    private var sliderDetail: Binding<Double> {
        Binding(get: { min(max(detail, 6), 64) }, set: { detail = $0 })
    }
}
