import SwiftUI

struct ControllerMappingView: View {
    @EnvironmentObject var model: TaheraModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PanelTitle(text: "Controller Mapping", icon: "gamecontroller.fill")

                Card {
                    Text("Map each action to any controller button.")
                        .foregroundColor(Theme.subtext)
                        .font(.system(size: 19, weight: .medium))

                    HStack(spacing: 14) {
                        Text("Drive Mode")
                            .foregroundColor(Theme.text)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .frame(width: 240, alignment: .leading)

                        Picker("", selection: $model.driveControlMode) {
                            ForEach(DriveControlMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 220, alignment: .leading)
                    }

                    ForEach(ControllerAction.allCases) { action in
                        HStack(spacing: 14) {
                            Text(action.displayName)
                                .foregroundColor(Theme.text)
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .frame(width: 240, alignment: .leading)

                            Picker("", selection: binding(for: action)) {
                                ForEach(ControllerButton.allCases) { button in
                                    Text(button.rawValue).tag(button)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 220, alignment: .leading)
                        }
                    }
                }

                if !model.controllerMappingConflicts().isEmpty {
                    Card {
                        Text("Conflicts")
                            .foregroundColor(Theme.text)
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                        ForEach(model.controllerMappingConflicts(), id: \.0) { button, actions in
                            Text("\(button.rawValue): \(actions.map { $0.displayName }.joined(separator: ", "))")
                                .foregroundColor(Color(hex: 0xFFB3A4))
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                        }
                    }
                }

                Card {
                    Text("Save / Load")
                        .foregroundColor(Theme.text)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))

                    HStack {
                        Button("Load Repo") { model.loadControllerMappingFromRepo() }
                        Button("Save Repo") { model.saveControllerMappingToRepo() }
                        Button("Load SD") { model.loadControllerMappingFromSD() }
                        Button("Save SD") { model.saveControllerMappingToSD() }
                        Button("Reset Defaults") { model.resetControllerMappingDefaults() }
                    }

                    Text(model.controllerMappingStatus.isEmpty ? "No recent mapping action." : model.controllerMappingStatus)
                        .foregroundColor(Theme.subtext)
                        .font(.system(size: 17, weight: .medium))
                }
            }
            .buttonStyle(TaheraActionButtonStyle())
        }
    }

    private func binding(for action: ControllerAction) -> Binding<ControllerButton> {
        Binding(
            get: { model.controllerMapping[action] ?? action.defaultButton },
            set: { model.setControllerButton($0, for: action) }
        )
    }
}
