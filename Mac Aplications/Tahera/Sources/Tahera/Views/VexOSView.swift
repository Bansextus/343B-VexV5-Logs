import SwiftUI
import AppKit
import GameController

private enum EmulatedProgram: String, CaseIterable, Identifiable {
    case tahera = "The Tahera Sequence"
    case autonPlanner = "Auton Planner"
    case imageSelector = "Image Selector"
    case basicBonkers = "Basic Bonkers"

    var id: String { rawValue }
}

private enum VexColor {
    static let white = Color(hex: 0xFFFFFF)
    static let green = Color(hex: 0x00FF00)
    static let red = Color(hex: 0xFF0000)
    static let cyan = Color(hex: 0x00FFFF)
    static let yellow = Color(hex: 0xFFFF00)
}

struct VexOSView: View {
    @EnvironmentObject var model: TaheraModel
    @ObservedObject var brain: VirtualBrainCore

    @State private var emulatedProgram: EmulatedProgram = .tahera
    @State private var plannerStepIndex: Int = 0
    @State private var selectorIndex: Int = 0
    @State private var selectorFiles: [String] = []
    @State private var splashFile: String = ""
    @State private var autonFile: String = ""
    @State private var driverFile: String = ""
    @State private var selectorStatus: String = ""
    @State private var displayPoseX: Double = 24
    @State private var displayPoseY: Double = 24
    @State private var displayHeadingDegrees: Double = 0
    @AppStorage("Tahera.ExactBrainMode") private var exactBrainMode: Bool = false
    @StateObject private var gamepad = GamepadBridge()

    private let vexScreenWidth: CGFloat = 480
    private let vexScreenHeight: CGFloat = 240
    private let renderTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PanelTitle(text: "Digital Twin", icon: "display.2")

                Card {
                    HStack {
                        Text("V5 Screen Emulation")
                            .foregroundColor(Theme.text)
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                        Spacer()
                        Toggle("Exact Brain Mode", isOn: $exactBrainMode)
                            .toggleStyle(.switch)
                            .foregroundColor(Theme.subtext)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Picker("Program", selection: $emulatedProgram) {
                            ForEach(EmulatedProgram.allCases) { program in
                                Text(program.rawValue).tag(program)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 560)
                    }

                    HStack(spacing: 16) {
                        Button("Load Slot") {
                            brain.loadActiveSlotFromVirtualSD()
                        }
                        .buttonStyle(TaheraActionButtonStyle())

                        Button("Sync Mapping") {
                            brain.applyControlProfile(
                                driveMode: model.driveControlMode,
                                mapping: model.controllerMapping
                            )
                        }
                        .buttonStyle(TaheraActionButtonStyle())

                        Spacer()

                        Text(brain.statusText)
                            .foregroundColor(Theme.subtext)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }

                    vexBrainFrame
                }

                Card {
                    Text("Field Movement Controls")
                        .foregroundColor(Theme.text)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))

                    HStack(spacing: 16) {
                        Text("Controller: \(gamepad.statusText)")
                        Text("PS5: \(gamepad.isPS5Connected ? "PAIRED" : "NOT PAIRED")")
                        Text("Mode: \(brain.driveMode.displayName)")
                        Text(String(format: "X %.1f  Y %.1f  H %.1f", brain.poseXInches, brain.poseYInches, brain.headingDegrees))
                        Spacer()
                    }
                    .foregroundColor(Theme.subtext)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))

                    Picker("Drive Mode", selection: driveModeBinding) {
                        ForEach(DriveControlMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 10) {
                        Button(brain.isRunning ? "Simulation Running" : "Start Simulation") {
                            brain.startSimulation()
                        }
                        .buttonStyle(TaheraActionButtonStyle())

                        Button("Pause") {
                            brain.pauseSimulation()
                        }
                        .buttonStyle(TaheraActionButtonStyle())

                        Button("Reset") {
                            brain.resetSimulation()
                        }
                        .buttonStyle(TaheraActionButtonStyle())

                        Button(brain.isRecording ? "Stop Recording" : "Start Recording") {
                            brain.toggleRecordingFromVex()
                        }
                        .buttonStyle(TaheraActionButtonStyle())

                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Digital Bot Settings")
                            .foregroundColor(Theme.text)
                            .font(.system(size: 18, weight: .bold, design: .rounded))

                        HStack(spacing: 10) {
                            Text("Speed")
                                .foregroundColor(Theme.subtext)
                                .frame(width: 56, alignment: .leading)
                            Slider(value: $brain.botSpeedScale, in: 0.35...2.4)
                                .tint(Theme.accent)
                            Text(String(format: "%.2fx", brain.botSpeedScale))
                                .foregroundColor(Theme.subtext)
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .frame(width: 56, alignment: .trailing)
                        }

                        HStack(spacing: 10) {
                            Text("Size")
                                .foregroundColor(Theme.subtext)
                                .frame(width: 56, alignment: .leading)
                            Slider(value: $brain.botSizeScale, in: 0.5...2.2)
                                .tint(Theme.accent)
                            Text(String(format: "%.2fx", brain.botSizeScale))
                                .foregroundColor(Theme.subtext)
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .frame(width: 56, alignment: .trailing)
                        }
                    }

                    if let fieldImage = loadFieldImage() {
                        fieldCanvas(image: fieldImage)
                    } else {
                        Text("Field image missing from resources.")
                            .foregroundColor(Theme.subtext)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Click Drive Controls")
                                .foregroundColor(Theme.text)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                            Spacer()
                            Text("Click to hold, click again to release")
                                .foregroundColor(Theme.subtext)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }

                        HStack(alignment: .top, spacing: 12) {
                            controlCluster(title: "D-Pad") {
                                VStack(spacing: 8) {
                                    HStack {
                                        Spacer()
                                        ClickToggleButton(
                                            label: "UP",
                                            isOn: brain.touchButtonIsPressed(.up),
                                            tint: Theme.accent
                                        ) {
                                            toggleClickHold(.up)
                                        }
                                        .frame(width: 104)
                                        Spacer()
                                    }

                                    HStack(spacing: 8) {
                                        ClickToggleButton(
                                            label: "LEFT",
                                            isOn: brain.touchButtonIsPressed(.left),
                                            tint: Theme.accent
                                        ) {
                                            toggleClickHold(.left)
                                        }
                                        .frame(width: 104)

                                        ControlStatePill(
                                            label: "DRIVE",
                                            active: brain.touchButtonIsPressed(.up)
                                                || brain.touchButtonIsPressed(.down)
                                                || brain.touchButtonIsPressed(.left)
                                                || brain.touchButtonIsPressed(.right),
                                            tint: Theme.accent
                                        )
                                        .frame(width: 94, height: 42)

                                        ClickToggleButton(
                                            label: "RIGHT",
                                            isOn: brain.touchButtonIsPressed(.right),
                                            tint: Theme.accent
                                        ) {
                                            toggleClickHold(.right)
                                        }
                                        .frame(width: 104)
                                    }

                                    HStack {
                                        Spacer()
                                        ClickToggleButton(
                                            label: "DOWN",
                                            isOn: brain.touchButtonIsPressed(.down),
                                            tint: Theme.accent
                                        ) {
                                            toggleClickHold(.down)
                                        }
                                        .frame(width: 104)
                                        Spacer()
                                    }
                                }
                            }

                            controlCluster(title: "Mechanisms") {
                                VStack(spacing: 8) {
                                    HStack(spacing: 8) {
                                        ClickToggleButton(
                                            label: "L1 Intake In",
                                            isOn: brain.touchButtonIsPressed(.l1),
                                            tint: Color(hex: 0x4CD7A8)
                                        ) {
                                            toggleClickHold(.l1)
                                        }
                                        ClickToggleButton(
                                            label: "L2 Intake Out",
                                            isOn: brain.touchButtonIsPressed(.l2),
                                            tint: Color(hex: 0x4CD7A8)
                                        ) {
                                            toggleClickHold(.l2)
                                        }
                                    }

                                    HStack(spacing: 8) {
                                        ClickToggleButton(
                                            label: "R1 Outake Out",
                                            isOn: brain.touchButtonIsPressed(.r1),
                                            tint: Color(hex: 0x49B5E8)
                                        ) {
                                            toggleClickHold(.r1)
                                        }
                                        ClickToggleButton(
                                            label: "R2 Outake In",
                                            isOn: brain.touchButtonIsPressed(.r2),
                                            tint: Color(hex: 0x49B5E8)
                                        ) {
                                            toggleClickHold(.r2)
                                        }
                                    }

                                    HStack(spacing: 8) {
                                        ControlStatePill(
                                            label: "INTAKE",
                                            active: brain.touchButtonIsPressed(.l1)
                                                || brain.touchButtonIsPressed(.l2),
                                            tint: Color(hex: 0x4CD7A8)
                                        )
                                        ControlStatePill(
                                            label: "OUTAKE",
                                            active: brain.touchButtonIsPressed(.r1)
                                                || brain.touchButtonIsPressed(.r2),
                                            tint: Color(hex: 0x49B5E8)
                                        )
                                        ControlStatePill(
                                            label: "HELD \(heldClickCount)",
                                            active: heldClickCount > 0,
                                            tint: Color(hex: 0xE2C45A)
                                        )
                                    }
                                }
                            }
                        }

                        HStack(spacing: 8) {
                            PulsePadButton(label: "A GPS ON", tint: Color(hex: 0x2CBF6B)) {
                                pulseTouchButton(.a)
                            }
                            PulsePadButton(label: "B GPS OFF", tint: Color(hex: 0xBF4B4B)) {
                                pulseTouchButton(.b)
                            }
                            PulsePadButton(label: "Y 6WD ON", tint: Color(hex: 0x2CBF6B)) {
                                pulseTouchButton(.y)
                            }
                            PulsePadButton(label: "X 6WD OFF", tint: Color(hex: 0xBF4B4B)) {
                                pulseTouchButton(.x)
                            }
                            Spacer()
                            Button("Release Click Holds") {
                                brain.clearTouchInputs()
                            }
                            .buttonStyle(TaheraActionButtonStyle())
                        }
                    }

                    Divider().overlay(Color.white.opacity(0.12))

                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("PS5 Pairing")
                                .foregroundColor(Theme.text)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                            Text(gamepad.pairingStatusText)
                                .foregroundColor(gamepad.isPS5Connected ? Theme.accent : Color(hex: 0xF39A84))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                            Text(gamepad.pairingDetailText)
                                .foregroundColor(Theme.subtext)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }

                        Spacer()

                        Button("Refresh PS5 Scan") {
                            gamepad.refreshControllerScan()
                        }
                        .buttonStyle(TaheraActionButtonStyle())
                    }
                }
            }
            .background(
                KeyboardCaptureView(
                    onKeyDown: { token in
                        brain.handleKeyboardTokenDown(token)
                    },
                    onKeyUp: { token in
                        brain.handleKeyboardTokenUp(token)
                    }
                )
                .frame(width: 0, height: 0)
            )
            .onAppear {
                if brain.virtualSDPath.isEmpty {
                    brain.setDefaultVirtualSDPath(for: model.repoPath)
                }
                if brain.loadedSlotFile.isEmpty {
                    brain.loadActiveSlotFromVirtualSD()
                }
                if selectorFiles.isEmpty {
                    refreshSelectorFiles()
                }
                brain.applyControlProfile(
                    driveMode: model.driveControlMode,
                    mapping: model.controllerMapping
                )
                displayPoseX = brain.poseXInches
                displayPoseY = brain.poseYInches
                displayHeadingDegrees = brain.headingDegrees
                gamepad.connect(brain: brain)
            }
            .onDisappear {
                brain.clearTouchInputs()
                gamepad.disconnect()
            }
            .onReceive(renderTimer) { _ in
                smoothFieldPose()
            }
        }
    }

    private var driveModeBinding: Binding<DriveControlMode> {
        Binding(
            get: { brain.driveMode },
            set: { mode in
                model.driveControlMode = mode
                brain.applyControlProfile(driveMode: mode, mapping: model.controllerMapping)
            }
        )
    }

    private var heldClickCount: Int {
        ControllerButton.allCases.filter { brain.touchButtonIsPressed($0) }.count
    }

    private func controlCluster<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .foregroundColor(Theme.text)
                .font(.system(size: 15, weight: .bold, design: .rounded))
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var vexBrainFrame: some View {
        let baseWidth: CGFloat = 960
        let baseHeight: CGFloat = 510

        return ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    exactBrainMode
                        ? Color(hex: 0x343A44)
                        : Color.clear
                )
                .overlay {
                    if !exactBrainMode {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: 0x3B434F), Color(hex: 0x262E38)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1.2)
                )

            VStack(spacing: 10) {
                portRow(top: true)

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(exactBrainMode ? Color(hex: 0x2A2E35) : Color(hex: 0x262B31))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .overlay(vexScreen)
                    .padding(.horizontal, 16)

                HStack(spacing: 10) {
                    portRow(top: false)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("VEX")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundColor(Color(hex: 0xF65B4D))
                        Circle()
                            .fill(Color(hex: 0x13171E))
                            .frame(width: 26, height: 26)
                            .overlay(
                                Circle()
                                    .stroke(Color(hex: 0xF65B4D), lineWidth: 2)
                            )
                    }
                    .padding(.trailing, 16)
                }
                .padding(.bottom, 8)
            }
        }
        .frame(width: baseWidth, height: baseHeight)
        .aspectRatio(baseWidth / baseHeight, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    private var vexScreen: some View {
        GeometryReader { proxy in
            let fitScale = min(proxy.size.width / vexScreenWidth, proxy.size.height / vexScreenHeight)
            let renderScale = exactBrainMode ? min(1.0, fitScale) : fitScale
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.black)

                programScreen
                    .frame(width: vexScreenWidth, height: vexScreenHeight, alignment: .topLeading)
                    .scaleEffect(renderScale, anchor: .center)
                    .position(
                        x: proxy.size.width / 2.0,
                        y: proxy.size.height / 2.0
                    )
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: exactBrainMode ? 2 : 8,
                    style: .continuous
                )
            )
        }
    }

    @ViewBuilder
    private var programScreen: some View {
        switch emulatedProgram {
        case .tahera:
            taheraScreen
        case .autonPlanner:
            autonPlannerScreen
        case .imageSelector:
            imageSelectorScreen
        case .basicBonkers:
            basicBonkersScreen
        }
    }

    private var taheraScreen: some View {
        ZStack(alignment: .topLeading) {
            VexScreenButton(label: "GPS", x: 10, y: 10, w: 140, h: 30,
                            color: brain.selectedAutonSection == .gps ? VexColor.green : VexColor.white) {
                brain.setAutonSectionFromVex(.gps)
            }
            VexScreenButton(label: "BASIC", x: 170, y: 10, w: 140, h: 30,
                            color: brain.selectedAutonSection == .basic ? VexColor.green : VexColor.white) {
                brain.setAutonSectionFromVex(.basic)
            }
            VexScreenButton(label: brain.isAutonRunning ? "RUNNING" : "RUN", x: 330, y: 10, w: 140, h: 30,
                            color: VexColor.red) {
                if brain.isAutonRunning {
                    brain.stopAutonExecution(reason: "USER")
                } else {
                    brain.startAutonExecution()
                }
            }
            VexScreenButton(label: brain.isRecording ? "STOP REC" : "REC", x: 330, y: 50, w: 140, h: 30,
                            color: brain.isRecording ? VexColor.red : VexColor.green) {
                brain.toggleRecordingFromVex()
            }

            screenText("AUTON: \(brain.selectedAutonSection.rawValue)", x: 10, y: 70)
            screenText("SOURCE: \(brain.vexSourceText)", x: 10, y: 95)
            screenText("SD: \(brain.vexSDStatusText)", x: 10, y: 120)
            screenText("SLOT: \(brain.activeSlot)", x: 10, y: 145)
            screenText("DRIVE: \(brain.vexDriveModeText)", x: 10, y: 170)
            screenText("REC: \(brain.isRecording ? "ON" : "OFF")", x: 10, y: 195)
            screenText("FILE: \(shortFileName(brain.vexRecordFileText))", x: 170, y: 195)
            screenText("Tap RUN for auton / REC for driving log", x: 10, y: 220)
        }
    }

    private var autonPlannerScreen: some View {
        let steps = brain.visibleAutonSteps()
        let maxIndex = max(steps.count - 1, 0)
        let safeIndex = min(max(plannerStepIndex, 0), maxIndex)
        let step = steps.isEmpty ? nil : steps[safeIndex]

        return ZStack(alignment: .topLeading) {
            VexScreenButton(label: "GPS", x: 10, y: 10, w: 90, h: 30,
                            color: brain.selectedAutonSection == .gps ? VexColor.green : VexColor.white) {
                brain.setAutonSectionFromVex(.gps)
            }
            VexScreenButton(label: "BASIC", x: 110, y: 10, w: 90, h: 30,
                            color: brain.selectedAutonSection == .basic ? VexColor.green : VexColor.white) {
                brain.setAutonSectionFromVex(.basic)
            }
            VexScreenButton(label: "SAVE", x: 210, y: 10, w: 90, h: 30, color: VexColor.yellow) {
                selectorStatus = "Saved plan (emulated)"
            }
            VexScreenButton(label: "S1", x: 310, y: 10, w: 50, h: 30,
                            color: brain.activeSlot == 1 ? VexColor.green : VexColor.white) {
                brain.setSlotFromVex(1)
            }
            VexScreenButton(label: "S2", x: 365, y: 10, w: 50, h: 30,
                            color: brain.activeSlot == 2 ? VexColor.green : VexColor.white) {
                brain.setSlotFromVex(2)
            }
            VexScreenButton(label: "S3", x: 420, y: 10, w: 50, h: 30,
                            color: brain.activeSlot == 3 ? VexColor.green : VexColor.white) {
                brain.setSlotFromVex(3)
            }

            VexScreenButton(label: "PREV", x: 10, y: 60, w: 70, h: 30, color: VexColor.white) {
                plannerStepIndex = max(0, plannerStepIndex - 1)
            }
            VexScreenButton(label: "NEXT", x: 90, y: 60, w: 70, h: 30, color: VexColor.white) {
                plannerStepIndex = min(maxIndex, plannerStepIndex + 1)
            }
            VexScreenButton(label: "TYPE", x: 170, y: 60, w: 140, h: 30, color: VexColor.white) {}
            VexScreenButton(label: "V1-", x: 320, y: 60, w: 50, h: 30, color: VexColor.white) {}
            VexScreenButton(label: "V1+", x: 380, y: 60, w: 50, h: 30, color: VexColor.white) {}
            VexScreenButton(label: "V2-", x: 320, y: 100, w: 50, h: 30, color: VexColor.white) {}
            VexScreenButton(label: "V2+", x: 380, y: 100, w: 50, h: 30, color: VexColor.white) {}
            VexScreenButton(label: "V3-", x: 320, y: 140, w: 50, h: 30, color: VexColor.white) {}
            VexScreenButton(label: "V3+", x: 380, y: 140, w: 50, h: 30, color: VexColor.white) {}
            VexScreenButton(label: brain.isRecording ? "STOP" : "REC", x: 10, y: 180, w: 140, h: 30,
                            color: brain.isRecording ? VexColor.red : VexColor.green) {
                brain.toggleRecordingFromVex()
            }
            VexScreenButton(label: "CLEAR", x: 170, y: 180, w: 140, h: 30, color: VexColor.white) {
                plannerStepIndex = 0
            }

            screenText("SLOT: \(brain.activeSlot)", x: 10, y: 95)
            screenText("STEP: \(safeIndex + 1) / \(max(steps.count, 1))", x: 10, y: 120)
            screenText("TYPE: \(step?.type.rawValue ?? "EMPTY")", x: 10, y: 140)
            screenText("V1:\(step?.value1 ?? 0)  V2:\(step?.value2 ?? 0)  V3:\(step?.value3 ?? 0)", x: 10, y: 160)
        }
    }

    private var imageSelectorScreen: some View {
        let file = currentSelectorFile()

        return ZStack(alignment: .topLeading) {
            VexScreenButton(label: "PREV", x: 10, y: 10, w: 70, h: 30, color: VexColor.white) {
                guard !selectorFiles.isEmpty else { return }
                selectorIndex = (selectorIndex - 1 + selectorFiles.count) % selectorFiles.count
            }
            VexScreenButton(label: "NEXT", x: 90, y: 10, w: 70, h: 30, color: VexColor.white) {
                guard !selectorFiles.isEmpty else { return }
                selectorIndex = (selectorIndex + 1) % selectorFiles.count
            }
            VexScreenButton(label: "SPLASH", x: 170, y: 10, w: 90, h: 30, color: VexColor.green) {
                splashFile = file
            }
            VexScreenButton(label: "AUTON", x: 270, y: 10, w: 90, h: 30, color: VexColor.red) {
                autonFile = file
            }
            VexScreenButton(label: "DRIVER", x: 370, y: 10, w: 90, h: 30, color: VexColor.cyan) {
                driverFile = file
            }
            VexScreenButton(label: "SAVE", x: 10, y: 50, w: 140, h: 30, color: VexColor.yellow) {
                selectorStatus = "Saved image config (emulated)"
            }
            VexScreenButton(label: "REFRESH", x: 170, y: 50, w: 140, h: 30, color: VexColor.white) {
                refreshSelectorFiles()
                selectorStatus = "Refreshed image list"
            }

            if let image = loadSelectorImage(file) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 480, height: 240)
                    .opacity(0.18)
            }

            screenText("FILE: \(file)", x: 10, y: 100)
            screenText("SPLASH: \(splashFile)", x: 10, y: 130)
            screenText("AUTON: \(autonFile)", x: 10, y: 155)
            screenText("DRIVER: \(driverFile)", x: 10, y: 180)
            if !selectorStatus.isEmpty {
                screenText(selectorStatus, x: 10, y: 205)
            }
        }
    }

    private var basicBonkersScreen: some View {
        let history = basicBonkersHistory(maxLines: 8)
        return ZStack(alignment: .topLeading) {
            screenText("Basic Bonkers Logger", x: 10, y: 0)
            screenText("Tap screen to save", x: 10, y: 24)
            screenText(shortFileName(brain.vexRecordFileText), x: 10, y: 48)

            ForEach(history.indices, id: \.self) { idx in
                screenText(history[idx], x: 10, y: CGFloat(78 + (idx * 18)))
            }

            VexScreenButton(label: "SAVE TAP", x: 330, y: 200, w: 140, h: 30, color: VexColor.yellow) {
                if !brain.isRecording {
                    brain.startRecording()
                }
                brain.stopRecording(reason: "SCREEN_TAP")
            }
        }
    }

    private func basicBonkersHistory(maxLines: Int) -> [String] {
        var lines: [String] = []
        for entry in brain.inputActionLog {
            if lines.count >= maxLines {
                break
            }
            lines.append(normalizedBonkersEntry(entry))
        }
        return lines
    }

    private func normalizedBonkersEntry(_ entry: String) -> String {
        let prefix = "BUTTON "
        let marker = " PRESSED : "
        guard entry.hasPrefix(prefix), let range = entry.range(of: marker) else {
            return entry
        }

        let buttonStart = entry.index(entry.startIndex, offsetBy: prefix.count)
        let buttonName = String(entry[buttonStart..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        let action = String(entry[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        return "BTN_\(buttonName) : \(action)"
    }

    private func shortFileName(_ value: String) -> String {
        if value.isEmpty || value == "(none)" {
            return "(none)"
        }
        return URL(fileURLWithPath: value).lastPathComponent
    }

    private func currentSelectorFile() -> String {
        guard !selectorFiles.isEmpty else { return "(none)" }
        return selectorFiles[selectorIndex % selectorFiles.count]
    }

    private func refreshSelectorFiles() {
        selectorFiles = ["field.png", "tahera_logo.png", "v5_brain.png"]
        if selectorIndex >= selectorFiles.count {
            selectorIndex = 0
        }
        if splashFile.isEmpty {
            splashFile = selectorFiles.first ?? ""
        }
        if autonFile.isEmpty {
            autonFile = selectorFiles.first ?? ""
        }
        if driverFile.isEmpty {
            driverFile = selectorFiles.first ?? ""
        }
    }

    private func pulseTouchButton(_ button: ControllerButton) {
        brain.setTouchButton(button, pressed: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
            brain.setTouchButton(button, pressed: false)
        }
    }

    private func toggleClickHold(_ button: ControllerButton) {
        brain.setTouchButton(button, pressed: !brain.touchButtonIsPressed(button))
    }

    private func fieldCanvas(image: NSImage) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)

                fieldOverlay(in: size)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(max(image.size.width / max(image.size.height, 1), 0.1), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .animation(.linear(duration: 0.04), value: brain.simTimeSeconds)
    }

    @ViewBuilder
    private func fieldOverlay(in size: CGSize) -> some View {
        if brain.pathSamples.count > 1 {
            Path { path in
                let visible = brain.pathSamples.suffix(260)
                guard let first = visible.first else { return }
                path.move(to: fieldPoint(x: first.x, y: first.y, in: size))
                for sample in visible.dropFirst() {
                    path.addLine(to: fieldPoint(x: sample.x, y: sample.y, in: size))
                }
            }
            .stroke(Color(hex: 0x3EA9F5).opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }

        ForEach(brain.gameTubes) { tube in
            let pt = fieldPoint(x: tube.x, y: tube.y, in: size)
            ZStack {
                Capsule()
                    .fill(Color(hex: 0xD1D68E).opacity(0.85))
                    .frame(width: 20, height: 34)
                    .overlay(
                        Capsule()
                            .stroke(Color.black.opacity(0.4), lineWidth: 1)
                    )
                Text("\(tube.stored)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color.black.opacity(0.76))
            }
            .position(pt)
        }

        ForEach(brain.gameBlocks) { block in
            if block.state == .field || block.state == .carried {
                let pt = fieldPoint(x: block.x, y: block.y, in: size)
                Circle()
                    .fill(pieceColor(block.color))
                    .frame(width: block.state == .carried ? 12 : 10, height: block.state == .carried ? 12 : 10)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.5), lineWidth: 0.8)
                    )
                    .shadow(color: pieceColor(block.color).opacity(0.5), radius: 2)
                    .position(pt)
            }
        }

        let robotCenter = fieldPoint(x: displayPoseX, y: displayPoseY, in: size)
        let robotDiameter = max(9, min(26, 15 * brain.botSizeScale))
        let headingLen = max(15, size.width * 0.03) * CGFloat(max(0.6, min(2.2, brain.botSizeScale)))
        let headingRad = displayHeadingDegrees * .pi / 180.0
        let headingPoint = CGPoint(
            x: robotCenter.x + CGFloat(cos(headingRad)) * headingLen,
            y: robotCenter.y - CGFloat(sin(headingRad)) * headingLen
        )

        Circle()
            .fill(brain.robotVisualColor)
            .frame(width: robotDiameter, height: robotDiameter)
            .shadow(color: brain.robotVisualColor.opacity(0.55), radius: 5)
            .position(robotCenter)

        Path { path in
            path.move(to: robotCenter)
            path.addLine(to: headingPoint)
        }
        .stroke(Color(hex: 0xF2E9D5), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
    }

    private func fieldPoint(x: Double, y: Double, in size: CGSize) -> CGPoint {
        let fieldSize = 144.0
        let px = CGFloat(x / fieldSize) * size.width
        let py = CGFloat((fieldSize - y) / fieldSize) * size.height
        return CGPoint(x: px, y: py)
    }

    private func loadFieldImage() -> NSImage? {
        guard let url = Bundle.module.url(forResource: "field", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private func smoothFieldPose() {
        let alpha = brain.isRunning ? 0.32 : 0.2
        displayPoseX += (brain.poseXInches - displayPoseX) * alpha
        displayPoseY += (brain.poseYInches - displayPoseY) * alpha
        let delta = shortestHeadingDelta(from: displayHeadingDegrees, to: brain.headingDegrees)
        displayHeadingDegrees = normalizedHeading(displayHeadingDegrees + (delta * alpha))
    }

    private func shortestHeadingDelta(from: Double, to: Double) -> Double {
        var delta = to - from
        if delta > 180 {
            delta -= 360
        } else if delta < -180 {
            delta += 360
        }
        return delta
    }

    private func normalizedHeading(_ value: Double) -> Double {
        var out = value.truncatingRemainder(dividingBy: 360)
        if out < 0 {
            out += 360
        }
        return out
    }

    private func loadSelectorImage(_ name: String) -> NSImage? {
        guard !name.isEmpty, name != "(none)" else {
            return nil
        }
        let tokens = name.split(separator: ".", omittingEmptySubsequences: false)
        if tokens.count == 2,
           let url = Bundle.module.url(forResource: String(tokens[0]), withExtension: String(tokens[1])) {
            return NSImage(contentsOf: url)
        }
        return nil
    }

    private func pieceColor(_ color: VirtualGamePieceColor) -> Color {
        switch color {
        case .red:
            return Color(hex: 0xE24E4E)
        case .blue:
            return Color(hex: 0x4E76E2)
        }
    }

    private func portRow(top: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<10, id: \.self) { idx in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(hex: 0x10151B))
                    .frame(width: 24, height: 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .stroke(Color.white.opacity(0.09), lineWidth: 0.8)
                    )
                    .overlay(
                        Text("\(top ? idx + 1 : idx + 11)")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: 0xF14F4A).opacity(0.92))
                            .offset(y: top ? 10 : -10)
                    )
            }
        }
        .padding(.leading, 16)
    }

    private func screenText(_ text: String, x: CGFloat, y: CGFloat) -> some View {
        Text(text)
            .font(
                .system(
                    size: exactBrainMode ? 12.5 : 15.0,
                    weight: exactBrainMode ? .medium : .semibold,
                    design: .monospaced
                )
            )
            .foregroundColor(VexColor.white)
            .frame(width: vexScreenWidth - x - 4, alignment: .leading)
            .offset(x: x, y: y)
    }
}

private struct VexScreenButton: View {
    @AppStorage("Tahera.ExactBrainMode") private var exactBrainMode: Bool = true
    let label: String
    let x: CGFloat
    let y: CGFloat
    let w: CGFloat
    let h: CGFloat
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if !exactBrainMode {
                    Rectangle()
                        .fill(color.opacity(0.13))
                }
                Rectangle()
                    .stroke(color, lineWidth: exactBrainMode ? 1.4 : 2.0)
                Text(label)
                    .font(
                        .system(
                            size: exactBrainMode ? 12.0 : 14.0,
                            weight: exactBrainMode ? .semibold : .bold,
                            design: .monospaced
                        )
                    )
                    .foregroundColor(color)
            }
        }
        .frame(width: w, height: h)
        .position(x: x + (w / 2.0), y: y + (h / 2.0))
        .buttonStyle(.plain)
    }
}

private struct ClickToggleButton: View {
    let label: String
    let isOn: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(Theme.text)
                .frame(maxWidth: .infinity, minHeight: 42)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isOn ? tint.opacity(0.9) : tint.opacity(0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isOn ? tint.opacity(0.95) : Color.white.opacity(0.22), lineWidth: 1)
                )
            }
        .buttonStyle(.plain)
    }
}

private struct PulsePadButton: View {
    let label: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.opacity(0.45))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct ControlStatePill: View {
    let label: String
    let active: Bool
    let tint: Color

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(Theme.text)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(
                Capsule(style: .continuous)
                    .fill(active ? tint.opacity(0.78) : Color.white.opacity(0.09))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(active ? tint.opacity(0.95) : Color.white.opacity(0.16), lineWidth: 1)
            )
    }
}

private struct KeyboardCaptureView: NSViewRepresentable {
    let onKeyDown: (String) -> Void
    let onKeyUp: (String) -> Void

    func makeNSView(context: Context) -> CaptureNSView {
        let view = CaptureNSView()
        view.onKeyDown = onKeyDown
        view.onKeyUp = onKeyUp
        return view
    }

    func updateNSView(_ nsView: CaptureNSView, context: Context) {
        nsView.onKeyDown = onKeyDown
        nsView.onKeyUp = onKeyUp
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

private final class CaptureNSView: NSView {
    var onKeyDown: ((String) -> Void)?
    var onKeyUp: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard let token = token(for: event) else { return }
        onKeyDown?(token)
    }

    override func keyUp(with event: NSEvent) {
        guard let token = token(for: event) else { return }
        onKeyUp?(token)
    }

    private func token(for event: NSEvent) -> String? {
        switch event.keyCode {
        case 123: return "left"
        case 124: return "right"
        case 125: return "down"
        case 126: return "up"
        case 49: return "space"
        default:
            break
        }

        guard let chars = event.charactersIgnoringModifiers?.lowercased(), !chars.isEmpty else {
            return nil
        }

        let first = String(chars.prefix(1))
        if first == " " {
            return "space"
        }
        return first
    }
}

private final class GamepadBridge: ObservableObject {
    @Published var statusText: String = "No Controller"
    @Published var isPS5Connected: Bool = false
    @Published var pairingStatusText: String = "Not Paired"
    @Published var pairingDetailText: String = "Pair your DualSense in macOS Bluetooth settings."

    private weak var brain: VirtualBrainCore?
    private var connectedController: GCController?
    private var connectObserver: NSObjectProtocol?
    private var disconnectObserver: NSObjectProtocol?

    func connect(brain: VirtualBrainCore) {
        self.brain = brain
        setupObservers()
        attachFirstAvailableController()
        GCController.startWirelessControllerDiscovery {}
    }

    func refreshControllerScan() {
        attachFirstAvailableController()
        GCController.startWirelessControllerDiscovery {}
    }

    func disconnect() {
        if let connectObserver {
            NotificationCenter.default.removeObserver(connectObserver)
        }
        if let disconnectObserver {
            NotificationCenter.default.removeObserver(disconnectObserver)
        }
        connectObserver = nil
        disconnectObserver = nil

        if let controller = connectedController {
            controller.extendedGamepad?.valueChangedHandler = nil
            controller.microGamepad?.valueChangedHandler = nil
        }

        connectedController = nil
        setNoPS5Status(detail: "Pair your DualSense in macOS Bluetooth settings, then reconnect.")
    }

    private func setupObservers() {
        if connectObserver == nil {
            connectObserver = NotificationCenter.default.addObserver(
                forName: .GCControllerDidConnect,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let controller = note.object as? GCController else { return }
                self?.attach(controller)
            }
        }

        if disconnectObserver == nil {
            disconnectObserver = NotificationCenter.default.addObserver(
                forName: .GCControllerDidDisconnect,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let controller = note.object as? GCController else { return }
                self?.handleDisconnect(controller)
            }
        }
    }

    private func attachFirstAvailableController() {
        let controllers = GCController.controllers()
        if let preferred = controllers.first(where: Self.isPlayStationController) {
            attach(preferred)
            return
        }
        if let controller = controllers.first {
            attach(controller)
            return
        }

        setNoPS5Status(detail: "No controller detected. Pair a PS5 controller and press its PS button.")
    }

    private func attach(_ controller: GCController) {
        connectedController = controller
        let name = controller.vendorName ?? "Game Controller"
        let ps5 = Self.isPlayStationController(controller)
        if ps5 {
            statusText = "PS5: \(name)"
            isPS5Connected = true
            pairingStatusText = "Paired + Connected"
            pairingDetailText = "DualSense detected and active."
        } else {
            statusText = name
            isPS5Connected = false
            pairingStatusText = "Not Paired"
            pairingDetailText = "A controller is connected, but it is not a PS5 controller."
        }
        brain?.setGamepadConnection(name: statusText)

        if let pad = controller.extendedGamepad {
            pad.valueChangedHandler = { [weak self] gamepad, _ in
                self?.pushExtended(gamepad)
            }
            pushExtended(pad)
            return
        }

        if let pad = controller.microGamepad {
            pad.valueChangedHandler = { [weak self] gamepad, _ in
                self?.pushMicro(gamepad)
            }
            pushMicro(pad)
        }
    }

    private func handleDisconnect(_ controller: GCController) {
        guard connectedController === controller else {
            return
        }
        connectedController = nil
        setNoPS5Status(detail: "PS5 controller disconnected. Reconnect from Bluetooth if needed.")
        attachFirstAvailableController()
    }

    private func pushExtended(_ pad: GCExtendedGamepad) {
        brain?.updateGamepadAxes(
            axis1: pad.rightThumbstick.xAxis.value,
            axis2: pad.rightThumbstick.yAxis.value,
            axis3: pad.leftThumbstick.yAxis.value,
            axis4: pad.leftThumbstick.xAxis.value
        )

        brain?.updateGamepadButton(.l1, pressed: pad.leftShoulder.isPressed)
        brain?.updateGamepadButton(.l2, pressed: pad.leftTrigger.value > 0.2)
        brain?.updateGamepadButton(.r1, pressed: pad.rightShoulder.isPressed)
        brain?.updateGamepadButton(.r2, pressed: pad.rightTrigger.value > 0.2)

        brain?.updateGamepadButton(.a, pressed: pad.buttonA.isPressed)
        brain?.updateGamepadButton(.b, pressed: pad.buttonB.isPressed)
        brain?.updateGamepadButton(.x, pressed: pad.buttonX.isPressed)
        brain?.updateGamepadButton(.y, pressed: pad.buttonY.isPressed)

        brain?.updateGamepadButton(.up, pressed: pad.dpad.up.isPressed)
        brain?.updateGamepadButton(.down, pressed: pad.dpad.down.isPressed)
        brain?.updateGamepadButton(.left, pressed: pad.dpad.left.isPressed)
        brain?.updateGamepadButton(.right, pressed: pad.dpad.right.isPressed)
    }

    private func pushMicro(_ pad: GCMicroGamepad) {
        brain?.updateGamepadAxes(axis1: 0, axis2: 0, axis3: 0, axis4: 0)
        brain?.updateGamepadButton(.up, pressed: pad.dpad.up.isPressed)
        brain?.updateGamepadButton(.down, pressed: pad.dpad.down.isPressed)
        brain?.updateGamepadButton(.left, pressed: pad.dpad.left.isPressed)
        brain?.updateGamepadButton(.right, pressed: pad.dpad.right.isPressed)
        brain?.updateGamepadButton(.a, pressed: pad.buttonA.isPressed)
        brain?.updateGamepadButton(.b, pressed: pad.buttonX.isPressed)
    }

    private static func isPlayStationController(_ controller: GCController) -> Bool {
        let name = (controller.vendorName ?? "").lowercased()
        let category = controller.productCategory.lowercased()
        return name.contains("playstation")
            || name.contains("dualsense")
            || name.contains("wireless controller")
            || category.contains("playstation")
            || category.contains("dualsense")
    }

    private func setNoPS5Status(detail: String) {
        statusText = "No Controller"
        isPS5Connected = false
        pairingStatusText = "Not Paired"
        pairingDetailText = detail
        brain?.setGamepadConnection(name: nil)
    }
}
