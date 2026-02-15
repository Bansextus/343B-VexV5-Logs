import SwiftUI

struct VirtualBrainView: View {
    @EnvironmentObject var model: TaheraModel
    @ObservedObject var brain: VirtualBrainCore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PanelTitle(text: "Virtual Brain", icon: "cpu.fill")

                Card {
                    Text("Runtime")
                        .foregroundColor(Theme.text)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))

                    HStack(spacing: 10) {
                        Button(brain.isRunning ? "Running" : "Start") {
                            brain.startSimulation()
                        }
                        .disabled(brain.isRunning)

                        Button("Pause") { brain.pauseSimulation() }
                        Button("Reset") { brain.resetSimulation() }
                        Button("Load Active Slot") { brain.loadActiveSlotFromVirtualSD() }
                        Spacer()
                        Text(brain.isRunning ? "Ticking @ 20ms" : "Paused")
                            .foregroundColor(Theme.subtext)
                            .font(.system(size: 16, weight: .semibold))
                    }

                    Text("Status: \(brain.statusText)")
                        .foregroundColor(Theme.subtext)
                        .font(.system(size: 18, weight: .medium))
                    Text("Ticks: \(brain.tickCount)")
                        .foregroundColor(Theme.subtext)
                        .font(.system(size: 18, weight: .medium))
                    Text(String(format: "Sim Time: %.2fs", brain.simTimeSeconds))
                        .foregroundColor(Theme.subtext)
                        .font(.system(size: 18, weight: .medium))
                }

                Card {
                    Text("Virtual SD")
                        .foregroundColor(Theme.text)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))

                    TextField("Virtual SD path", text: $brain.virtualSDPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 18, weight: .medium, design: .rounded))

                    HStack {
                        Button("Use Repo Default") {
                            brain.setDefaultVirtualSDPath(for: model.repoPath)
                        }
                        Button("Ensure Folder") {
                            brain.ensureVirtualSDReady()
                        }
                    }

                    Text("Active Slot: \(brain.activeSlot)")
                        .foregroundColor(Theme.subtext)
                        .font(.system(size: 18, weight: .medium))
                    Text("Loaded File: \(brain.loadedSlotFile.isEmpty ? "(none)" : brain.loadedSlotFile)")
                        .foregroundColor(Theme.subtext)
                        .font(.system(size: 18, weight: .medium))
                    Text("GPS Steps: \(brain.gpsSteps.count)")
                        .foregroundColor(Theme.subtext)
                        .font(.system(size: 18, weight: .medium))
                    Text("BASIC Steps: \(brain.basicSteps.count)")
                        .foregroundColor(Theme.subtext)
                        .font(.system(size: 18, weight: .medium))
                }

                Card {
                    Text("Auton Runner")
                        .foregroundColor(Theme.text)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))

                    HStack(spacing: 10) {
                        Text("Plan")
                            .foregroundColor(Theme.subtext)
                            .font(.system(size: 18, weight: .semibold))
                        Picker("", selection: $brain.selectedAutonSection) {
                            ForEach(VirtualAutonSection.allCases) { section in
                                Text(section.rawValue).tag(section)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 240)

                        Button("Reload Slot") {
                            brain.loadActiveSlotFromVirtualSD()
                        }
                        Button("Run Plan") {
                            brain.startAutonExecution()
                        }
                        .disabled(brain.isAutonRunning)
                        Button("Stop Plan") {
                            brain.stopAutonExecution(reason: "USER")
                        }
                        .disabled(!brain.isAutonRunning)
                        Spacer()
                    }

                    HStack(spacing: 14) {
                        Text("GPS Parsed: \(brain.parsedGpsAutonSteps.count)")
                        Text("BASIC Parsed: \(brain.parsedBasicAutonSteps.count)")
                        Text(
                            "Progress: \(brain.completedAutonSteps)/\(max(brain.visibleAutonSteps().count, 0))"
                        )
                    }
                    .foregroundColor(Theme.subtext)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))

                    Text("Current Step: \(brain.currentAutonStepText)")
                        .foregroundColor(Theme.subtext)
                        .font(.system(size: 15, weight: .regular, design: .monospaced))

                    ScrollView {
                        let lines = brain.visibleAutonSteps().prefix(24).enumerated().map { idx, step in
                            let marker = idx == brain.currentAutonStepIndex && brain.isAutonRunning ? ">" : " "
                            return "\(marker) \(idx + 1). \(step.shortDescription)"
                        }
                        Text(lines.isEmpty ? "No parsed steps in selected section." : lines.joined(separator: "\n"))
                            .foregroundColor(Theme.subtext)
                            .font(.system(size: 14, weight: .regular, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 130)
                }

                Card {
                    Text("Controller Simulator")
                        .foregroundColor(Theme.text)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))

                    HStack(spacing: 10) {
                        Text("Drive Mode")
                            .foregroundColor(Theme.subtext)
                            .font(.system(size: 18, weight: .semibold))
                        Picker("", selection: $brain.driveMode) {
                            ForEach(DriveControlMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 420)

                        Button("Sync Mapping") {
                            brain.applyControlProfile(
                                driveMode: model.driveControlMode,
                                mapping: model.controllerMapping
                            )
                        }

                        Spacer()

                        Button("Center Sticks") { brain.centerSticks() }
                        Button("Release Buttons") { brain.releaseAllButtons() }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        axisRow(title: "Axis 1 (Right X)", axis: 1)
                        axisRow(title: "Axis 2 (Right Y)", axis: 2)
                        axisRow(title: "Axis 3 (Left Y)", axis: 3)
                        axisRow(title: "Axis 4 (Left X)", axis: 4)
                    }

                    Text("Buttons")
                        .foregroundColor(Theme.text)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(ControllerButton.allCases) { button in
                            Toggle(button.rawValue, isOn: buttonBinding(for: button))
                                .toggleStyle(.button)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                        }
                    }

                    Divider().overlay(Color.white.opacity(0.08))

                    Text("Mapped Actions")
                        .foregroundColor(Theme.text)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))

                    ForEach(ControllerAction.allCases) { action in
                        HStack {
                            Text("\(brain.buttonForAction(action).rawValue) -> \(action.displayName)")
                                .foregroundColor(Theme.subtext)
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                            Spacer()
                            Circle()
                                .fill(brain.isActionHeld(action) ? Theme.accent : Color.white.opacity(0.18))
                                .frame(width: 10, height: 10)
                        }
                    }
                }

                Card {
                    Text("Robot Outputs")
                        .foregroundColor(Theme.text)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))

                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            outputRow("Left Drive", value: "\(brain.leftDriveCommand)")
                            outputRow("Right Drive", value: "\(brain.rightDriveCommand)")
                            outputRow("Left Mid", value: "\(brain.leftMiddleCommand)")
                            outputRow("Right Mid", value: "\(brain.rightMiddleCommand)")
                            outputRow("Intake", value: "\(brain.intakeCommand)")
                            outputRow("Outake", value: "\(brain.outakeCommand)")
                            outputRow("GPS Drive", value: brain.gpsDriveEnabled ? "ON" : "OFF")
                            outputRow("Six Wheel", value: brain.sixWheelDriveEnabled ? "ON" : "OFF")
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            outputRow("X (in)", value: String(format: "%.1f", brain.poseXInches))
                            outputRow("Y (in)", value: String(format: "%.1f", brain.poseYInches))
                            outputRow("Heading", value: String(format: "%.1f deg", brain.headingDegrees))
                            outputRow("IMU", value: String(format: "%.1f deg", brain.imuHeadingDegrees))
                            outputRow("GPS", value: String(format: "%.1f deg", brain.gpsHeadingDegrees))
                            Text(brain.frameSummary)
                                .foregroundColor(Theme.subtext)
                                .font(.system(size: 13, weight: .regular, design: .monospaced))
                                .padding(.top, 6)
                        }

                        Spacer()
                    }

                    VirtualFieldPreview(pathSamples: brain.pathSamples)
                        .frame(height: 280)
                }

                Card {
                    Text("Virtual Recording")
                        .foregroundColor(Theme.text)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))

                    HStack(spacing: 10) {
                        Button(brain.isRecording ? "Recording..." : "Start Recording") {
                            brain.startRecording()
                        }
                        .disabled(brain.isRecording)

                        Button("Stop + Save") {
                            brain.stopRecording(reason: "USER")
                        }
                        .disabled(!brain.isRecording)

                        Spacer()

                        Text("Lines: \(brain.recordingLineCount)")
                            .foregroundColor(Theme.subtext)
                            .font(.system(size: 16, weight: .semibold))
                    }

                    HStack(spacing: 10) {
                        Button("Export Field Replay CSV") {
                            brain.exportTelemetryToFieldReplayCSV()
                        }
                        .disabled(brain.telemetryFrameCount == 0)
                        Button("Clear Telemetry") {
                            brain.clearTelemetry()
                        }
                        .disabled(brain.telemetryFrameCount == 0)

                        Spacer()

                        Text("Frames: \(brain.telemetryFrameCount)")
                            .foregroundColor(Theme.subtext)
                            .font(.system(size: 16, weight: .semibold))
                    }

                    Text("Last Saved: \(brain.lastRecordingFileName.isEmpty ? "(none)" : brain.lastRecordingFileName)")
                        .foregroundColor(Theme.subtext)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                    Text("Last CSV: \(brain.lastTelemetryExportFileName.isEmpty ? "(none)" : brain.lastTelemetryExportFileName)")
                        .foregroundColor(Theme.subtext)
                        .font(.system(size: 16, weight: .medium, design: .rounded))

                    ScrollView {
                        Text(brain.recordingPreview.isEmpty ? "No recording data yet." : brain.recordingPreview.joined(separator: "\n"))
                            .foregroundColor(Theme.subtext)
                            .font(.system(size: 14, weight: .regular, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 130)
                }

                Card {
                    Text("Input -> Action")
                        .foregroundColor(Theme.text)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                    ScrollView {
                        Text(brain.inputActionLog.isEmpty ? "No controller button events yet." : brain.inputActionLog.joined(separator: "\n"))
                            .foregroundColor(Theme.subtext)
                            .font(.system(size: 15, weight: .regular, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 160)
                }

                Card {
                    Text("Auton Log")
                        .foregroundColor(Theme.text)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                    ScrollView {
                        Text(brain.autonRunLog.isEmpty ? "No auton events yet." : brain.autonRunLog.joined(separator: "\n"))
                            .foregroundColor(Theme.subtext)
                            .font(.system(size: 15, weight: .regular, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 120)
                }

                Card {
                    Text("Runtime Log")
                        .foregroundColor(Theme.text)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                    ScrollView {
                        Text(brain.runtimeLog.isEmpty ? "No virtual brain activity yet." : brain.runtimeLog.joined(separator: "\n"))
                            .foregroundColor(Theme.subtext)
                            .font(.system(size: 15, weight: .regular, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 180)
                }
            }
            .buttonStyle(TaheraActionButtonStyle())
            .onAppear {
                if brain.virtualSDPath.isEmpty {
                    brain.setDefaultVirtualSDPath(for: model.repoPath)
                }
                brain.applyControlProfile(
                    driveMode: model.driveControlMode,
                    mapping: model.controllerMapping
                )
            }
        }
    }

    private func axisRow(title: String, axis: Int) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .foregroundColor(Theme.subtext)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .frame(width: 170, alignment: .leading)
            Slider(
                value: Binding(
                    get: { Double(brain.axisValue(axis)) },
                    set: { brain.setAxis(axis, value: Int($0.rounded())) }
                ),
                in: -127...127,
                step: 1
            )
            .tint(Theme.accent)
            Text("\(brain.axisValue(axis))")
                .foregroundColor(Theme.text)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .frame(width: 48, alignment: .trailing)
        }
    }

    private func buttonBinding(for button: ControllerButton) -> Binding<Bool> {
        Binding(
            get: { brain.buttonIsPressed(button) },
            set: { brain.setButton(button, pressed: $0) }
        )
    }

    private func outputRow(_ label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .foregroundColor(Theme.subtext)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .frame(width: 105, alignment: .leading)
            Text(value)
                .foregroundColor(Theme.text)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
        }
    }
}

private struct VirtualFieldPreview: View {
    let pathSamples: [VirtualPoseSample]

    private let fieldSizeInches: Double = 144

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.black.opacity(0.34), Color.black.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)

                if pathSamples.count > 1 {
                    Path { path in
                        let first = point(for: pathSamples[0], in: size)
                        path.move(to: first)
                        for sample in pathSamples.dropFirst() {
                            path.addLine(to: point(for: sample, in: size))
                        }
                    }
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .shadow(color: Theme.accent.opacity(0.42), radius: 4)
                }

                if let last = pathSamples.last {
                    let center = point(for: last, in: size)
                    let headingLen = max(14, size.width * 0.03)
                    let headingRadians = last.headingDeg * .pi / 180.0
                    let headingPoint = CGPoint(
                        x: center.x + CGFloat(cos(headingRadians)) * headingLen,
                        y: center.y - CGFloat(sin(headingRadians)) * headingLen
                    )

                    Circle()
                        .fill(Color(hex: 0xF4E1C2))
                        .frame(width: 11, height: 11)
                        .position(center)

                    Path { p in
                        p.move(to: center)
                        p.addLine(to: headingPoint)
                    }
                    .stroke(Color(hex: 0x3EA9F5), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                }
            }
        }
    }

    private func point(for sample: VirtualPoseSample, in size: CGSize) -> CGPoint {
        let x = CGFloat(sample.x / fieldSizeInches) * size.width
        let y = CGFloat((fieldSizeInches - sample.y) / fieldSizeInches) * size.height
        return CGPoint(x: x, y: y)
    }
}
