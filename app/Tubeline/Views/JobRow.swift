import SwiftUI

struct JobRow: View {
    let job: Job

    var body: some View {
        HStack(spacing: 9) {
            statusIcon.frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(job.name).lineLimit(1)
                    if job.hasOverrides {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(.secondary).help("Custom Icon Settings")
                    }
                }
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text(job.source.deletingLastPathComponent().lastPathComponent)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 3)
        .help("Source: \(job.source.path)" + (job.exportedURL.map { "\nExport: \($0.path)" } ?? ""))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(job.name), source folder \(job.source.deletingLastPathComponent().lastPathComponent), \(accessibilityStatus)\(job.hasOverrides ? ", custom settings" : "")")
        .accessibilityValue("Source: \(job.source.path)")
    }

    @ViewBuilder private var statusIcon: some View {
        switch job.status {
        case .pending: Image(systemName: "circle").foregroundStyle(.tertiary)
        case .working: ProgressView().controlSize(.small)
        case .exported:
            if job.stats?.skipped.isEmpty == false {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        case .outdated: Image(systemName: "arrow.triangle.2.circlepath.circle").foregroundStyle(.orange)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .cancelled: Image(systemName: "stop.circle").foregroundStyle(.secondary)
        }
    }

    private var detail: String {
        switch job.status {
        case .pending: "Ready to Export"
        case .working: "Converting…"
        case .exported:
            if let stats = job.stats {
                "\(stats.triangles.formatted()) triangles\(stats.skipped.isEmpty ? "" : " · Warnings")"
            } else { "Exported" }
        case .outdated: "Changed—Export Again"
        case .failed(let message): message
        case .cancelled: "Canceled"
        }
    }

    private var accessibilityStatus: String {
        switch job.status {
        case .exported: job.stats == nil ? "Exported" : "Exported, \(detail)"
        case .failed: "Export Failed, \(detail)"
        default: detail
        }
    }
}
