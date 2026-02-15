import Foundation
import SwiftUI

struct BuildUploadView: View {
    @EnvironmentObject var model: TaheraModel
    private static let statusTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PanelTitle(text: "Build & Upload", icon: "gearshape.2.fill")

                ForEach(model.projects.indices, id: \.self) { idx in
                    let project = model.projects[idx]
                    let status = model.buildUploadStatus(for: project)
                    Card {
                        HStack {
                            Text(project.name)
                                .foregroundColor(Theme.text)
                                .font(.system(size: 25, weight: .semibold, design: .rounded))
                            Spacer()
                            Stepper("Slot \(project.slot)", value: $model.projects[idx].slot, in: 1...8)
                                .foregroundColor(Theme.subtext)
                                .font(.system(size: 18, weight: .semibold))
                        }

                        HStack {
                            Button("Build") { model.build(project: project) }
                                .disabled(model.isBusy)
                            Button("Upload") { model.upload(project: project) }
                                .disabled(model.isBusy)
                            Button("Build + Upload") { model.buildAndUpload(project: project) }
                                .disabled(model.isBusy)
                        }

                        Divider()
                            .overlay(Color.white.opacity(0.1))

                        HStack(spacing: 10) {
                            Circle()
                                .fill(color(for: status.phase))
                                .frame(width: 10, height: 10)
                            Text(title(for: status.phase))
                                .foregroundColor(Theme.text)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                            if status.phase.isRunning {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Spacer()
                            if let port = status.port, !port.isEmpty {
                                Text(port)
                                    .foregroundColor(Theme.subtext)
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                            }
                        }

                        Text(status.message)
                            .foregroundColor(Theme.subtext)
                            .font(.system(size: 14, weight: .medium, design: .rounded))

                        Text("Updated \(Self.statusTimeFormatter.string(from: status.updatedAt))")
                            .foregroundColor(Theme.subtext.opacity(0.85))
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                    }
                }
            }
            .buttonStyle(TaheraActionButtonStyle())
        }
    }

    private func title(for phase: BuildUploadPhase) -> String {
        switch phase {
        case .idle:
            return "Ready"
        case .building:
            return "Building"
        case .buildSucceeded:
            return "Build Succeeded"
        case .buildFailed:
            return "Build Failed"
        case .uploading:
            return "Uploading"
        case .uploadSucceeded:
            return "Upload Succeeded"
        case .uploadFailed:
            return "Upload Failed"
        }
    }

    private func color(for phase: BuildUploadPhase) -> Color {
        switch phase {
        case .idle:
            return Theme.subtext
        case .building, .uploading:
            return Color(hex: 0xFFD166)
        case .buildSucceeded, .uploadSucceeded:
            return Theme.accent
        case .buildFailed, .uploadFailed:
            return Color(hex: 0xFF6B6B)
        }
    }
}
