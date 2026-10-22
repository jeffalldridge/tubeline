import SwiftUI

struct DropPrompt: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 48, weight: .light)).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Give Your Icons Dimension")
                .font(.title2.weight(.medium))
            Text("Drop SVG files or folders here.\nAdjust the shape, preview it, and export to USDZ.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Add SVGs…") { model.add(Panels.chooseSVGs()) }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Text("For Apple Motion and other apps that import USDZ.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
