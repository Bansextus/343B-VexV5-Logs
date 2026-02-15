import Foundation
import SwiftUI

struct VirtualSDStorage {
    var rootPath: String

    func absolutePath(for relativePath: String) -> String {
        URL(fileURLWithPath: rootPath)
            .appendingPathComponent(relativePath)
            .path
    }

    func ensureRootDirectory() throws {
        if FileManager.default.fileExists(atPath: rootPath) {
            return
        }
        try FileManager.default.createDirectory(atPath: rootPath, withIntermediateDirectories: true)
    }

    func readTextFile(_ relativePath: String) throws -> String {
        try String(contentsOfFile: absolutePath(for: relativePath), encoding: .utf8)
    }

    func writeTextFile(_ relativePath: String, contents: String) throws {
        try ensureRootDirectory()
        try contents.write(toFile: absolutePath(for: relativePath), atomically: true, encoding: .utf8)
    }
}

struct VirtualBrainPlanSnapshot {
    let slot: Int
    let fileName: String
    let gpsSteps: [String]
    let basicSteps: [String]
}

struct VirtualPoseSample {
    let t: Double
    let x: Double
    let y: Double
    let headingDeg: Double
}

enum VirtualAutonSection: String, CaseIterable, Identifiable {
    case gps = "GPS"
    case basic = "BASIC"

    var id: String { rawValue }
}

enum VirtualAutonStepType: String {
    case empty = "EMPTY"
    case driveMs = "DRIVE_MS"
    case tankMs = "TANK_MS"
    case turnHeading = "TURN_HEADING"
    case waitMs = "WAIT_MS"
    case intakeOn = "INTAKE_ON"
    case intakeOff = "INTAKE_OFF"
    case outtakeOn = "OUTTAKE_ON"
    case outtakeOff = "OUTTAKE_OFF"
}

struct VirtualAutonStep: Identifiable {
    let id = UUID()
    let index: Int
    let type: VirtualAutonStepType
    let value1: Int
    let value2: Int
    let value3: Int
    let rawLine: String

    var shortDescription: String {
        switch type {
        case .empty:
            return "EMPTY"
        case .driveMs:
            return "DRIVE_MS \(value1),\(value2)"
        case .tankMs:
            return "TANK_MS \(value1),\(value2),\(value3)"
        case .turnHeading:
            return "TURN_HEADING \(value1)"
        case .waitMs:
            return "WAIT_MS \(value1)"
        case .intakeOn:
            return "INTAKE_ON"
        case .intakeOff:
            return "INTAKE_OFF"
        case .outtakeOn:
            return "OUTTAKE_ON"
        case .outtakeOff:
            return "OUTTAKE_OFF"
        }
    }
}

enum VirtualCompetitionPhase: String {
    case ready = "READY"
    case auton = "AUTON"
    case driver = "DRIVER"
    case ended = "ENDED"
}

enum VirtualRobotVisualState: String {
    case idle = "IDLE"
    case moving = "MOVING"
    case intake = "INTAKE"
    case outtake = "OUTTAKE"
    case auton = "AUTON"
}

enum VirtualGameBlockState: Equatable {
    case field
    case carried
    case tube(Int)
}

enum VirtualGamePieceColor: String {
    case red
    case blue
}

struct VirtualGameBlock: Identifiable {
    let id: UUID
    var color: VirtualGamePieceColor
    var x: Double
    var y: Double
    var state: VirtualGameBlockState
}

struct VirtualGameTube: Identifiable {
    let id = UUID()
    let index: Int
    var x: Double
    var y: Double
    var capacity: Int
    var stored: Int
}

enum KeyboardAxisRole: String, CaseIterable, Identifiable, Hashable {
    case axis1Left
    case axis1Right
    case axis2Up
    case axis2Down
    case axis3Up
    case axis3Down
    case axis4Left
    case axis4Right

    var id: String { rawValue }

    var label: String {
        switch self {
        case .axis1Left:
            return "Axis1 Left"
        case .axis1Right:
            return "Axis1 Right"
        case .axis2Up:
            return "Axis2 Up"
        case .axis2Down:
            return "Axis2 Down"
        case .axis3Up:
            return "Axis3 Up"
        case .axis3Down:
            return "Axis3 Down"
        case .axis4Left:
            return "Axis4 Left"
        case .axis4Right:
            return "Axis4 Right"
        }
    }
}

private struct VirtualTelemetryFrame {
    let timeSeconds: Double
    let axis1: Int
    let axis2: Int
    let axis3: Int
    let axis4: Int
    let intakeAction: String
    let outtakeAction: String
    let leftCommand: Int
    let rightCommand: Int
    let xInches: Double
    let yInches: Double
    let headingDeg: Double
    let autonSection: String
    let autonStep: String
}

private struct VirtualInputEvent {
    let uiText: String
    let recordType: String?
    let recordValue: String?
}

final class VirtualBrainCore: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var tickCount: Int = 0
    @Published var simTimeSeconds: Double = 0
    @Published var activeSlot: Int = 1
    @Published var loadedSlotFile: String = ""
    @Published var gpsSteps: [String] = []
    @Published var basicSteps: [String] = []
    @Published var virtualSDPath: String = ""
    @Published var statusText: String = "Idle"
    @Published var runtimeLog: [String] = []

    @Published var driveMode: DriveControlMode = .tank
    @Published var axis1: Int = 0
    @Published var axis2: Int = 0
    @Published var axis3: Int = 0
    @Published var axis4: Int = 0

    @Published var buttonStates: [ControllerButton: Bool] = VirtualBrainCore.makeDefaultButtonState()
    @Published var inputActionLog: [String] = []
    @Published var keyboardControlEnabled: Bool = true
    @Published var keyboardButtonMap: [ControllerButton: String] = VirtualBrainCore.makeDefaultKeyboardButtonMap()
    @Published var keyboardAxisMap: [KeyboardAxisRole: String] = VirtualBrainCore.makeDefaultKeyboardAxisMap()
    @Published var gamepadConnected: Bool = false
    @Published var gamepadName: String = "No Controller"

    @Published var leftDriveCommand: Int = 0
    @Published var rightDriveCommand: Int = 0
    @Published var leftMiddleCommand: Int = 0
    @Published var rightMiddleCommand: Int = 0
    @Published var intakeCommand: Int = 0
    @Published var outakeCommand: Int = 0

    @Published var gpsDriveEnabled: Bool = false
    @Published var sixWheelDriveEnabled: Bool = true

    @Published var poseXInches: Double = 72
    @Published var poseYInches: Double = 72
    @Published var headingDegrees: Double = 0
    @Published var imuHeadingDegrees: Double = 0
    @Published var gpsHeadingDegrees: Double = 0
    @Published var pathSamples: [VirtualPoseSample] = []
    @Published var frameSummary: String = "No frame yet"

    @Published var selectedAutonSection: VirtualAutonSection = .gps
    @Published var parsedGpsAutonSteps: [VirtualAutonStep] = []
    @Published var parsedBasicAutonSteps: [VirtualAutonStep] = []
    @Published var isAutonRunning: Bool = false
    @Published var currentAutonStepIndex: Int = 0
    @Published var currentAutonStepText: String = "(idle)"
    @Published var autonRunLog: [String] = []
    @Published var completedAutonSteps: Int = 0
    @Published var competitionPhase: VirtualCompetitionPhase = .ready
    @Published var competitionTimeRemaining: Double = 120
    @Published var competitionSessionActive: Bool = false
    @Published var competitionSummaryText: String = "Press RUN on the digital brain UI to start match."

    @Published var isRecording: Bool = false
    @Published var recordingLineCount: Int = 0
    @Published var lastRecordingFileName: String = ""
    @Published var recordingPreview: [String] = []
    @Published var telemetryFrameCount: Int = 0
    @Published var lastTelemetryExportFileName: String = ""
    @Published var robotVisualState: VirtualRobotVisualState = .idle
    @Published var gameStatusText: String = "Field ready"
    @Published var gameBlocks: [VirtualGameBlock] = []
    @Published var gameTubes: [VirtualGameTube] = []
    @Published var carriedBlockCount: Int = 0
    @Published var scoredBlockCount: Int = 0
    @Published var botSpeedScale: Double = 1.0
    @Published var botSizeScale: Double = 1.0

    private let tickIntervalSeconds: Double = 0.02
    private let timerQueue = DispatchQueue(label: "Tahera.VirtualBrain.Timer")
    private var timer: DispatchSourceTimer?

    private let fieldSizeInches: Double = 144
    private let trackWidthInches: Double = 12
    private let maxSpeedInchesPerSecond: Double = 60
    private var headingRadians: Double = 0
    private var previousButtonStates: [ControllerButton: Bool] = VirtualBrainCore.makeDefaultButtonState()
    private var actionButtonMapping: [ControllerAction: ControllerButton] = VirtualBrainCore.makeDefaultActionMapping()
    private var recordingLines: [String] = []
    private var recordingFileNamePending: String = ""
    private var activeAutonSteps: [VirtualAutonStep] = []
    private var activeAutonSection: VirtualAutonSection = .gps
    private var currentAutonStepElapsedMs: Double = 0
    private var currentAutonStepInitialized: Bool = false
    private var telemetryFrames: [VirtualTelemetryFrame] = []
    private var activeKeyboardTokens: Set<String> = []
    private var keyboardAxis1: Int = 0
    private var keyboardAxis2: Int = 0
    private var keyboardAxis3: Int = 0
    private var keyboardAxis4: Int = 0
    private var gamepadAxis1: Int = 0
    private var gamepadAxis2: Int = 0
    private var gamepadAxis3: Int = 0
    private var gamepadAxis4: Int = 0
    private var touchAxis1: Int = 0
    private var touchAxis2: Int = 0
    private var touchAxis3: Int = 0
    private var touchAxis4: Int = 0
    private var gamepadButtonStates: [ControllerButton: Bool] = VirtualBrainCore.makeDefaultButtonState()
    private var touchButtonStates: [ControllerButton: Bool] = VirtualBrainCore.makeDefaultButtonState()
    private var carriedBlockID: UUID?
    private var previousIntakeActive: Bool = false
    private var previousOuttakeActive: Bool = false
    private let isoTimestampFormatter = ISO8601DateFormatter()

    init() {
        resetCompetitionFieldForNewMatch()
    }

    func setDefaultVirtualSDPath(for repoPath: String) {
        let defaultPath = URL(fileURLWithPath: repoPath)
            .appendingPathComponent("Developer Extras")
            .appendingPathComponent("VirtualBrainSD")
            .path
        virtualSDPath = defaultPath
        appendLog("Virtual SD path set to \(defaultPath)")
    }

    @discardableResult
    func ensureVirtualSDReady() -> Bool {
        guard !virtualSDPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusText = "Set a Virtual SD path first."
            return false
        }

        let sd = VirtualSDStorage(rootPath: virtualSDPath)
        do {
            try sd.ensureRootDirectory()
            statusText = "Virtual SD ready"
            appendLog("Virtual SD ready at \(virtualSDPath)")
            return true
        } catch {
            statusText = "Virtual SD error: \(error.localizedDescription)"
            appendLog(statusText)
            return false
        }
    }

    func loadActiveSlotFromVirtualSD() {
        guard !virtualSDPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusText = "Set a Virtual SD path first."
            return
        }

        let sd = VirtualSDStorage(rootPath: virtualSDPath)
        do {
            try sd.ensureRootDirectory()
            let snapshot = try loadSnapshot(from: sd)
            activeSlot = snapshot.slot
            loadedSlotFile = snapshot.fileName
            gpsSteps = snapshot.gpsSteps
            basicSteps = snapshot.basicSteps
            parseLoadedAutonSteps()
            statusText = "Loaded slot \(snapshot.slot) from \(snapshot.fileName)"
            appendLog(statusText)
        } catch {
            statusText = "Load failed: \(error.localizedDescription)"
            appendLog(statusText)
        }
    }

    func applyControlProfile(driveMode: DriveControlMode, mapping: [ControllerAction: ControllerButton]) {
        self.driveMode = driveMode
        actionButtonMapping = mapping
        appendLog("Control profile synced: mode=\(driveMode.rawValue)")
    }

    func buttonIsPressed(_ button: ControllerButton) -> Bool {
        buttonStates[button] ?? false
    }

    func setButton(_ button: ControllerButton, pressed: Bool) {
        buttonStates[button] = pressed
    }

    func toggleButton(_ button: ControllerButton) {
        let now = buttonIsPressed(button)
        buttonStates[button] = !now
    }

    func buttonForAction(_ action: ControllerAction) -> ControllerButton {
        actionButtonMapping[action] ?? action.defaultButton
    }

    func isActionHeld(_ action: ControllerAction) -> Bool {
        let button = buttonForAction(action)
        return buttonIsPressed(button)
    }

    func setAxis(_ axis: Int, value: Int) {
        let clamped = clamp(value, min: -127, max: 127)
        switch axis {
        case 1:
            axis1 = clamped
        case 2:
            axis2 = clamped
        case 3:
            axis3 = clamped
        case 4:
            axis4 = clamped
        default:
            break
        }
    }

    func axisValue(_ axis: Int) -> Int {
        switch axis {
        case 1: return axis1
        case 2: return axis2
        case 3: return axis3
        case 4: return axis4
        default: return 0
        }
    }

    func centerSticks() {
        axis1 = 0
        axis2 = 0
        axis3 = 0
        axis4 = 0
    }

    func releaseAllButtons() {
        buttonStates = Self.makeDefaultButtonState()
    }

    func visibleAutonSteps() -> [VirtualAutonStep] {
        switch selectedAutonSection {
        case .gps:
            return parsedGpsAutonSteps
        case .basic:
            return parsedBasicAutonSteps
        }
    }

    var keyboardTokenChoices: [String] {
        VirtualBrainCore.availableKeyboardTokens
    }

    func keyboardButtonToken(_ button: ControllerButton) -> String {
        keyboardButtonMap[button] ?? ""
    }

    func setKeyboardButtonToken(_ raw: String, for button: ControllerButton) {
        let token = normalizedKeyToken(raw)
        keyboardButtonMap[button] = token
        appendLog("Keyboard map \(button.rawValue) -> \(token)")
    }

    func keyboardAxisToken(_ role: KeyboardAxisRole) -> String {
        keyboardAxisMap[role] ?? ""
    }

    func setKeyboardAxisToken(_ raw: String, for role: KeyboardAxisRole) {
        let token = normalizedKeyToken(raw)
        keyboardAxisMap[role] = token
        appendLog("Keyboard axis map \(role.label) -> \(token)")
        updateAxesFromKeyboardTokens()
    }

    func handleKeyboardTokenDown(_ raw: String) {
        guard keyboardControlEnabled else {
            return
        }
        let token = normalizedKeyToken(raw)
        guard !token.isEmpty else {
            return
        }
        activeKeyboardTokens.insert(token)
        syncButtonsFromKeyboardTokens()
        updateAxesFromKeyboardTokens()
    }

    func handleKeyboardTokenUp(_ raw: String) {
        let token = normalizedKeyToken(raw)
        guard !token.isEmpty else {
            return
        }
        activeKeyboardTokens.remove(token)
        syncButtonsFromKeyboardTokens()
        updateAxesFromKeyboardTokens()
    }

    func clearKeyboardState() {
        activeKeyboardTokens.removeAll()
        updateAxesFromKeyboardTokens()
        syncButtonsFromKeyboardTokens()
    }

    var vexRunButtonText: String {
        switch competitionPhase {
        case .ready:
            return "RUN"
        case .auton:
            return "AUTO"
        case .driver:
            return "DRIVE"
        case .ended:
            return "RESTART"
        }
    }

    var vexRecButtonText: String {
        isRecording ? "STOP REC" : "REC"
    }

    var vexAutonModeText: String {
        selectedAutonSection.rawValue
    }

    var vexSourceText: String {
        loadedSlotFile.isEmpty ? "BUILT-IN" : "SD"
    }

    var vexSDStatusText: String {
        loadedSlotFile.isEmpty ? "MISSING" : "OK"
    }

    var vexDriveModeText: String {
        switch driveMode {
        case .tank:
            return "TANK"
        case .arcade2:
            return "ARCADE 2 STICK"
        case .dpad:
            return "DPAD"
        }
    }

    var vexRecordFileText: String {
        if !lastRecordingFileName.isEmpty {
            return lastRecordingFileName
        }
        return "(none)"
    }

    var competitionClockText: String {
        let totalSeconds = max(0, Int(competitionTimeRemaining.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var robotVisualColor: Color {
        switch robotVisualState {
        case .idle:
            return Color(hex: 0xDDE6F3)
        case .moving:
            return Color(hex: 0x3EA9F5)
        case .intake:
            return Color(hex: 0x3ED887)
        case .outtake:
            return Color(hex: 0xF58A3E)
        case .auton:
            return Color(hex: 0xA879F5)
        }
    }

    func setAutonSectionFromVex(_ section: VirtualAutonSection) {
        selectedAutonSection = section
        appendLog("VEX UI mode -> \(section.rawValue)")
    }

    func toggleAutonRunFromVex() {
        switch competitionPhase {
        case .ready:
            startCompetitionSession()
        case .auton, .driver:
            endCompetitionSession(reason: "USER_STOP")
        case .ended:
            startCompetitionSession()
        }
    }

    func toggleRecordingFromVex() {
        if isRecording {
            stopRecording(reason: "USER")
            return
        }
        startRecording()
    }

    func changeSlotFromVex(_ delta: Int) {
        guard delta != 0 else {
            return
        }
        guard ensureVirtualSDReady() else {
            return
        }

        var next = activeSlot + delta
        while next < 1 {
            next += 3
        }
        while next > 3 {
            next -= 3
        }

        do {
            let sd = VirtualSDStorage(rootPath: virtualSDPath)
            try sd.writeTextFile("auton_slot.txt", contents: "\(next)\n")
            activeSlot = next
            appendLog("VEX UI slot set to \(next)")
            loadActiveSlotFromVirtualSD()
        } catch {
            statusText = "Failed to set slot: \(error.localizedDescription)"
            appendLog(statusText)
        }
    }

    func setSlotFromVex(_ slot: Int) {
        guard (1...3).contains(slot) else {
            return
        }
        guard ensureVirtualSDReady() else {
            return
        }
        do {
            let sd = VirtualSDStorage(rootPath: virtualSDPath)
            try sd.writeTextFile("auton_slot.txt", contents: "\(slot)\n")
            activeSlot = slot
            appendLog("VEX UI slot set to \(slot)")
            loadActiveSlotFromVirtualSD()
        } catch {
            statusText = "Failed to set slot: \(error.localizedDescription)"
            appendLog(statusText)
        }
    }

    func setGamepadConnection(name: String?) {
        if let name, !name.isEmpty {
            gamepadConnected = true
            gamepadName = name
            appendLog("Gamepad connected: \(name)")
        } else {
            gamepadConnected = false
            gamepadName = "No Controller"
            clearGamepadInputs()
            appendLog("Gamepad disconnected")
        }
    }

    func updateGamepadAxes(axis1: Float, axis2: Float, axis3: Float, axis4: Float) {
        gamepadAxis1 = clamp(Int((Double(axis1) * 127.0).rounded()), min: -127, max: 127)
        gamepadAxis2 = clamp(Int((Double(axis2) * 127.0).rounded()), min: -127, max: 127)
        gamepadAxis3 = clamp(Int((Double(axis3) * 127.0).rounded()), min: -127, max: 127)
        gamepadAxis4 = clamp(Int((Double(axis4) * 127.0).rounded()), min: -127, max: 127)
        recomputeMergedAxes()
    }

    func updateGamepadButton(_ button: ControllerButton, pressed: Bool) {
        gamepadButtonStates[button] = pressed
        syncButtonsFromKeyboardTokens()
    }

    func clearGamepadInputs() {
        gamepadAxis1 = 0
        gamepadAxis2 = 0
        gamepadAxis3 = 0
        gamepadAxis4 = 0
        gamepadButtonStates = Self.makeDefaultButtonState()
        recomputeMergedAxes()
        syncButtonsFromKeyboardTokens()
    }

    func updateTouchAxes(axis1: Int, axis2: Int, axis3: Int, axis4: Int) {
        touchAxis1 = clamp(axis1, min: -127, max: 127)
        touchAxis2 = clamp(axis2, min: -127, max: 127)
        touchAxis3 = clamp(axis3, min: -127, max: 127)
        touchAxis4 = clamp(axis4, min: -127, max: 127)
        recomputeMergedAxes()
    }

    func setTouchButton(_ button: ControllerButton, pressed: Bool) {
        touchButtonStates[button] = pressed
        syncButtonsFromKeyboardTokens()
    }

    func touchButtonIsPressed(_ button: ControllerButton) -> Bool {
        touchButtonStates[button] ?? false
    }

    func clearTouchInputs() {
        touchAxis1 = 0
        touchAxis2 = 0
        touchAxis3 = 0
        touchAxis4 = 0
        touchButtonStates = Self.makeDefaultButtonState()
        recomputeMergedAxes()
        syncButtonsFromKeyboardTokens()
    }

    func startCompetitionSession() {
        if !isRunning {
            startSimulation()
        }
        guard isRunning else {
            return
        }

        clearKeyboardState()
        releaseAllButtons()
        centerSticks()
        clearTouchInputs()
        inputActionLog = []
        resetCompetitionFieldForNewMatch()
        competitionSessionActive = true
        competitionPhase = .auton
        competitionTimeRemaining = 120.0
        competitionSummaryText = "AUTON period running"
        statusText = "Competition match started"
        appendLog("Competition start -> AUTON")

        startAutonExecution()
    }

    func endCompetitionSession(reason: String) {
        if isAutonRunning {
            stopAutonExecution(reason: reason)
        }
        competitionSessionActive = true
        competitionPhase = .ended
        competitionSummaryText = "Match ended (\(reason))"
        leftDriveCommand = 0
        rightDriveCommand = 0
        intakeCommand = 0
        outakeCommand = 0
        statusText = "Competition ended"
        appendLog("Competition ended (\(reason))")
    }

    func startAutonExecution() {
        if !isRunning {
            startSimulation()
        }
        guard isRunning else {
            return
        }

        if parsedGpsAutonSteps.isEmpty && parsedBasicAutonSteps.isEmpty {
            loadActiveSlotFromVirtualSD()
        }

        let steps = selectedAutonSection == .gps ? parsedGpsAutonSteps : parsedBasicAutonSteps
        guard !steps.isEmpty else {
            statusText = "No \(selectedAutonSection.rawValue) steps loaded."
            appendLog(statusText)
            return
        }

        stopAutonExecution(reason: "RESTART")
        activeAutonSection = selectedAutonSection
        activeAutonSteps = steps
        isAutonRunning = true
        currentAutonStepIndex = 0
        completedAutonSteps = 0
        currentAutonStepInitialized = false
        currentAutonStepElapsedMs = 0
        currentAutonStepText = "(preparing)"
        statusText = "Auton running (\(activeAutonSection.rawValue))"
        appendAutonLog("Auton started (\(activeAutonSection.rawValue), \(steps.count) steps)")
        if isRecording {
            recordingLines.append("AUTON_START:\(activeAutonSection.rawValue)")
            recordingLineCount = recordingLines.count
            recordingPreview = Array(recordingLines.suffix(18))
        }
    }

    func stopAutonExecution(reason: String = "USER") {
        guard isAutonRunning else {
            return
        }
        isAutonRunning = false
        activeAutonSteps = []
        currentAutonStepInitialized = false
        currentAutonStepElapsedMs = 0
        leftDriveCommand = 0
        rightDriveCommand = 0
        leftMiddleCommand = 0
        rightMiddleCommand = 0
        intakeCommand = 0
        outakeCommand = 0
        currentAutonStepText = "(stopped)"
        statusText = "Auton stopped"
        appendAutonLog("Auton stopped (\(reason))")
        if isRecording {
            recordingLines.append("AUTON_STOP:\(reason)")
            recordingLineCount = recordingLines.count
            recordingPreview = Array(recordingLines.suffix(18))
        }
    }

    func startSimulation() {
        if isRunning {
            return
        }
        guard ensureVirtualSDReady() else {
            return
        }

        let source = DispatchSource.makeTimerSource(queue: timerQueue)
        source.schedule(deadline: .now(), repeating: tickIntervalSeconds)
        source.setEventHandler { [weak self] in
            self?.tick()
        }
        timer = source
        source.resume()

        isRunning = true
        statusText = "Running"
        appendLog("Simulation started")
    }

    func pauseSimulation() {
        timer?.cancel()
        timer = nil
        if isRunning {
            appendLog("Simulation paused")
        }
        isRunning = false
        statusText = "Paused"
    }

    func resetSimulation() {
        pauseSimulation()
        if isAutonRunning {
            stopAutonExecution(reason: "RESET")
        }
        if isRecording {
            stopRecording(reason: "RESET")
        }

        tickCount = 0
        simTimeSeconds = 0
        axis1 = 0
        axis2 = 0
        axis3 = 0
        axis4 = 0
        releaseAllButtons()
        previousButtonStates = Self.makeDefaultButtonState()
        activeKeyboardTokens.removeAll()
        keyboardAxis1 = 0
        keyboardAxis2 = 0
        keyboardAxis3 = 0
        keyboardAxis4 = 0
        clearGamepadInputs()
        clearTouchInputs()

        leftDriveCommand = 0
        rightDriveCommand = 0
        leftMiddleCommand = 0
        rightMiddleCommand = 0
        intakeCommand = 0
        outakeCommand = 0
        gpsDriveEnabled = false
        sixWheelDriveEnabled = true
        botSpeedScale = 1.0
        botSizeScale = 1.0
        poseXInches = fieldSizeInches / 2
        poseYInches = fieldSizeInches / 2
        headingRadians = 0
        headingDegrees = 0
        imuHeadingDegrees = 0
        gpsHeadingDegrees = 0
        pathSamples = []
        frameSummary = "No frame yet"
        telemetryFrames = []
        telemetryFrameCount = 0
        lastTelemetryExportFileName = ""
        currentAutonStepIndex = 0
        completedAutonSteps = 0
        currentAutonStepText = "(idle)"
        competitionPhase = .ready
        competitionSessionActive = false
        competitionTimeRemaining = 120
        competitionSummaryText = "Press RUN on the digital brain UI to start match."
        robotVisualState = .idle
        carriedBlockID = nil
        previousIntakeActive = false
        previousOuttakeActive = false
        resetCompetitionFieldForNewMatch()

        statusText = "Reset"
        appendLog("Simulation reset")
    }

    func startRecording() {
        guard !isRecording else {
            return
        }
        guard ensureVirtualSDReady() else {
            return
        }

        recordingFileNamePending = "bonkers_log_virtual_\(timestampForFileName()).txt"
        recordingLines = []
        recordingLines.reserveCapacity(4096)
        recordingLines.append("REC_START:TAHERA_VIRTUAL")
        recordingLines.append("DRIVE_MODE:\(driveMode.rawValue)")
        isRecording = true
        recordingLineCount = recordingLines.count
        recordingPreview = Array(recordingLines.suffix(18))
        appendLog("Recording started -> \(recordingFileNamePending)")
    }

    func stopRecording(reason: String = "USER") {
        guard isRecording else {
            return
        }
        isRecording = false

        if !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            recordingLines.append("REC_STOP:\(reason)")
        }
        recordingLineCount = recordingLines.count
        recordingPreview = Array(recordingLines.suffix(18))

        let fileName = recordingFileNamePending.isEmpty
            ? "bonkers_log_virtual_\(timestampForFileName()).txt"
            : recordingFileNamePending

        do {
            let sd = VirtualSDStorage(rootPath: virtualSDPath)
            let payload = recordingLines.joined(separator: "\n") + "\n"
            try sd.writeTextFile(fileName, contents: payload)
            lastRecordingFileName = fileName
            appendLog("Recording saved (\(recordingLines.count) lines) -> \(fileName)")
            statusText = "Recording saved to \(fileName)"
        } catch {
            statusText = "Recording save failed: \(error.localizedDescription)"
            appendLog(statusText)
        }
    }

    func clearTelemetry() {
        telemetryFrames = []
        telemetryFrameCount = 0
        lastTelemetryExportFileName = ""
        appendLog("Telemetry cleared")
    }

    func exportTelemetryToFieldReplayCSV() {
        guard ensureVirtualSDReady() else {
            return
        }
        guard !telemetryFrames.isEmpty else {
            statusText = "No telemetry to export."
            appendLog(statusText)
            return
        }

        let fileName = "virtual_fieldreplay_\(timestampForFileName()).csv"
        let header = "time_s,axis1,axis2,axis3,axis4,intake_action,outtake_action,left_cmd,right_cmd,x_in,y_in,heading_deg,auton_section,auton_step"
        var rows: [String] = [header]
        rows.reserveCapacity(telemetryFrames.count + 1)

        for frame in telemetryFrames {
            let line = String(
                format: "%.3f,%d,%d,%d,%d,%@,%@,%d,%d,%.2f,%.2f,%.2f,%@,%@",
                frame.timeSeconds,
                frame.axis1, frame.axis2, frame.axis3, frame.axis4,
                csvEscape(frame.intakeAction),
                csvEscape(frame.outtakeAction),
                frame.leftCommand, frame.rightCommand,
                frame.xInches, frame.yInches, frame.headingDeg,
                csvEscape(frame.autonSection),
                csvEscape(frame.autonStep)
            )
            rows.append(line)
        }

        do {
            let sd = VirtualSDStorage(rootPath: virtualSDPath)
            try sd.writeTextFile(fileName, contents: rows.joined(separator: "\n") + "\n")
            lastTelemetryExportFileName = fileName
            statusText = "Telemetry exported to \(fileName)"
            appendLog("Telemetry export complete (\(telemetryFrames.count) frames) -> \(fileName)")
        } catch {
            statusText = "Telemetry export failed: \(error.localizedDescription)"
            appendLog(statusText)
        }
    }

    private func tick() {
        DispatchQueue.main.async { [weak self] in
            self?.performTick()
        }
    }

    private func performTick() {
        tickCount += 1
        simTimeSeconds = Double(tickCount) * tickIntervalSeconds
        tickCompetitionClock()

        let pressedEdges = collectPressedButtonEdges()
        let events = buildInputEvents(forPressedButtons: pressedEdges)
        applyToggleActions(from: events)

        let dpadUp = buttonIsPressed(.up)
        let dpadDown = buttonIsPressed(.down)
        let dpadLeft = buttonIsPressed(.left)
        let dpadRight = buttonIsPressed(.right)
        let manualControlsAllowed = competitionPhase != .auton && competitionPhase != .ended

        if isAutonRunning {
            tickAutonRunner()
        } else if manualControlsAllowed {
            if competitionPhase == .driver {
                competitionSummaryText = "DRIVER period running"
            }
            let commands = computeDriveCommands(
                dpadUp: dpadUp,
                dpadDown: dpadDown,
                dpadLeft: dpadLeft,
                dpadRight: dpadRight
            )
            leftDriveCommand = commands.left
            rightDriveCommand = commands.right

            let intakeIn = isActionHeld(.intakeIn)
            let intakeOut = isActionHeld(.intakeOut)
            let outakeOut = isActionHeld(.outakeOut)
            let outakeIn = isActionHeld(.outakeIn)

            if intakeIn {
                intakeCommand = 127
            } else if intakeOut {
                intakeCommand = -127
            } else {
                intakeCommand = 0
            }

            if outakeOut {
                outakeCommand = 127
            } else if outakeIn {
                outakeCommand = -127
            } else {
                outakeCommand = 0
            }
        } else {
            leftDriveCommand = 0
            rightDriveCommand = 0
            intakeCommand = 0
            outakeCommand = 0
        }

        if sixWheelDriveEnabled {
            leftMiddleCommand = leftDriveCommand
            rightMiddleCommand = rightDriveCommand
        } else {
            leftMiddleCommand = 0
            rightMiddleCommand = 0
        }

        integratePose(left: leftDriveCommand, right: rightDriveCommand)
        frameSummary = String(
            format: "A1:%d A2:%d A3:%d A4:%d | Drive L:%d R:%d | Intake:%d Outake:%d | GPS:%@ 6WD:%@",
            axis1, axis2, axis3, axis4,
            leftDriveCommand, rightDriveCommand,
            intakeCommand, outakeCommand,
            gpsDriveEnabled ? "ON" : "OFF",
            sixWheelDriveEnabled ? "ON" : "OFF"
        )

        updateRobotVisualState()
        processGameActions()
        appendTelemetryFrame()
        appendInputEvents(events)
        if isRecording {
            appendRecordingFrame(events: events)
        }
    }

    private func loadSnapshot(from sd: VirtualSDStorage) throws -> VirtualBrainPlanSnapshot {
        let slotText = try? sd.readTextFile("auton_slot.txt")
        let slot = parseSlot(slotText) ?? 1
        let slotFileName = "auton_plans_slot\(slot).txt"

        let planText: String
        if let text = try? sd.readTextFile(slotFileName) {
            planText = text
        } else if let fallback = try? sd.readTextFile("auton_plans.txt") {
            planText = fallback
        } else {
            throw NSError(domain: "VirtualBrain", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "No auton plan file found for slot \(slot)."
            ])
        }

        let parsed = parsePlanSections(planText)
        return VirtualBrainPlanSnapshot(
            slot: slot,
            fileName: slotFileName,
            gpsSteps: parsed.gps,
            basicSteps: parsed.basic
        )
    }

    private func parseSlot(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), (1...3).contains(value) else {
            return nil
        }
        return value
    }

    private func parsePlanSections(_ text: String) -> (gps: [String], basic: [String]) {
        var gps: [String] = []
        var basic: [String] = []
        enum Section {
            case none
            case gps
            case basic
        }
        var section: Section = .none

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            if line == "[GPS]" {
                section = .gps
                continue
            }
            if line == "[BASIC]" {
                section = .basic
                continue
            }

            switch section {
            case .gps:
                gps.append(line)
            case .basic:
                basic.append(line)
            case .none:
                break
            }
        }

        return (gps, basic)
    }

    private func parseLoadedAutonSteps() {
        parsedGpsAutonSteps = parseAutonLines(gpsSteps, section: .gps)
        parsedBasicAutonSteps = parseAutonLines(basicSteps, section: .basic)
        appendLog(
            "Parsed auton steps -> GPS: \(parsedGpsAutonSteps.count), BASIC: \(parsedBasicAutonSteps.count)"
        )
    }

    private func parseAutonLines(_ lines: [String], section: VirtualAutonSection) -> [VirtualAutonStep] {
        var parsed: [VirtualAutonStep] = []
        for (index, line) in lines.enumerated() {
            if let step = parseAutonLine(line, index: index) {
                parsed.append(step)
            } else {
                appendLog("Skipped invalid \(section.rawValue) step line: \(line)")
            }
        }
        return parsed
    }

    private func parseAutonLine(_ line: String, index: Int) -> VirtualAutonStep? {
        let parts = line
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count >= 3 else {
            return nil
        }

        let typeToken = parts[0].uppercased()
        guard let type = VirtualAutonStepType(rawValue: typeToken) else {
            return nil
        }

        let v1 = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        let v2 = parts.count > 2 ? (Int(parts[2]) ?? 0) : 0
        let v3 = parts.count > 3 ? (Int(parts[3]) ?? 0) : 0
        return VirtualAutonStep(
            index: index,
            type: type,
            value1: v1,
            value2: v2,
            value3: v3,
            rawLine: line
        )
    }

    private func tickCompetitionClock() {
        guard competitionSessionActive else {
            return
        }

        if competitionPhase == .auton || competitionPhase == .driver {
            competitionTimeRemaining = max(0, competitionTimeRemaining - tickIntervalSeconds)
        }

        if competitionPhase == .auton && competitionTimeRemaining <= 105.0 {
            competitionPhase = .driver
            competitionSummaryText = "DRIVER period running"
            if isAutonRunning {
                stopAutonExecution(reason: "AUTO_END")
            }
            appendLog("Competition transition -> DRIVER")
        }

        if competitionTimeRemaining <= 0, competitionPhase != .ended {
            competitionPhase = .ended
            competitionSummaryText = "Match complete"
            leftDriveCommand = 0
            rightDriveCommand = 0
            intakeCommand = 0
            outakeCommand = 0
            if isAutonRunning {
                stopAutonExecution(reason: "TIME_UP")
            }
            appendLog("Competition complete")
        }
    }

    private func updateRobotVisualState() {
        if isAutonRunning {
            robotVisualState = .auton
            return
        }
        if outakeCommand != 0 {
            robotVisualState = .outtake
            return
        }
        if intakeCommand != 0 {
            robotVisualState = .intake
            return
        }
        if abs(leftDriveCommand) > 10 || abs(rightDriveCommand) > 10 {
            robotVisualState = .moving
            return
        }
        robotVisualState = .idle
    }

    private func processGameActions() {
        if let carriedID = carriedBlockID,
           let idx = gameBlocks.firstIndex(where: { $0.id == carriedID }) {
            gameBlocks[idx].x = poseXInches
            gameBlocks[idx].y = poseYInches
        }

        let intakeActive = intakeCommand > 0
        let outtakeActive = outakeCommand > 0
        let intakeRising = intakeActive && !previousIntakeActive
        let outtakeRising = outtakeActive && !previousOuttakeActive

        if intakeRising {
            pickupNearestBlock()
        }
        if outtakeRising {
            dropOrScoreCarriedBlock()
        }

        previousIntakeActive = intakeActive
        previousOuttakeActive = outtakeActive
    }

    private func pickupNearestBlock() {
        guard carriedBlockID == nil else {
            return
        }
        let maxDistance = 9.5
        var bestIndex: Int?
        var bestDistance = Double.greatestFiniteMagnitude

        for idx in gameBlocks.indices {
            if gameBlocks[idx].state != .field {
                continue
            }
            let dx = gameBlocks[idx].x - poseXInches
            let dy = gameBlocks[idx].y - poseYInches
            let d = hypot(dx, dy)
            if d < bestDistance && d <= maxDistance {
                bestDistance = d
                bestIndex = idx
            }
        }

        guard let index = bestIndex else {
            return
        }
        let color = gameBlocks[index].color
        carriedBlockID = gameBlocks[index].id
        gameBlocks[index].state = .carried
        gameBlocks[index].x = poseXInches
        gameBlocks[index].y = poseYInches
        carriedBlockCount = 1
        gameStatusText = "Picked up \(color.rawValue) ball"
        appendLog("Game action: pickup \(color.rawValue) ball")
    }

    private func dropOrScoreCarriedBlock() {
        guard let carriedID = carriedBlockID,
              let blockIndex = gameBlocks.firstIndex(where: { $0.id == carriedID }) else {
            return
        }

        let maxTubeDistance = 12.0
        var bestTubeIndex: Int?
        var bestTubeDistance = Double.greatestFiniteMagnitude

        for idx in gameTubes.indices {
            let tube = gameTubes[idx]
            let dx = tube.x - poseXInches
            let dy = tube.y - poseYInches
            let d = hypot(dx, dy)
            if d < bestTubeDistance && d <= maxTubeDistance {
                bestTubeDistance = d
                bestTubeIndex = idx
            }
        }

        if let tubeIndex = bestTubeIndex, gameTubes[tubeIndex].stored < gameTubes[tubeIndex].capacity {
            let color = gameBlocks[blockIndex].color
            gameBlocks[blockIndex].state = .tube(gameTubes[tubeIndex].index)
            gameBlocks[blockIndex].x = gameTubes[tubeIndex].x
            gameBlocks[blockIndex].y = gameTubes[tubeIndex].y
            gameTubes[tubeIndex].stored += 1
            carriedBlockID = nil
            carriedBlockCount = 0
            scoredBlockCount += 1
            gameStatusText = "Scored \(color.rawValue) ball in tube \(gameTubes[tubeIndex].index)"
            appendLog("Game action: score \(color.rawValue) in tube \(gameTubes[tubeIndex].index)")
            return
        }

        // Drop near the robot if not near a tube.
        let heading = headingDegrees * .pi / 180.0
        gameBlocks[blockIndex].state = .field
        gameBlocks[blockIndex].x = min(fieldSizeInches, max(0, poseXInches + cos(heading) * 6))
        gameBlocks[blockIndex].y = min(fieldSizeInches, max(0, poseYInches + sin(heading) * 6))
        carriedBlockID = nil
        carriedBlockCount = 0
        gameStatusText = "Dropped carried ball"
        appendLog("Game action: drop ball")
    }

    private func resetCompetitionFieldForNewMatch() {
        poseXInches = 24
        poseYInches = 24
        headingRadians = 0
        headingDegrees = 0
        imuHeadingDegrees = 0
        gpsHeadingDegrees = 0
        pathSamples = []

        gameTubes = [
            VirtualGameTube(index: 1, x: 124, y: 24, capacity: 4, stored: 0),
            VirtualGameTube(index: 2, x: 124, y: 52, capacity: 4, stored: 0),
            VirtualGameTube(index: 3, x: 124, y: 80, capacity: 4, stored: 0),
            VirtualGameTube(index: 4, x: 124, y: 108, capacity: 4, stored: 0)
        ]

        gameBlocks = [
            VirtualGameBlock(id: UUID(), color: .red,  x: 64, y: 64, state: .field),
            VirtualGameBlock(id: UUID(), color: .blue, x: 72, y: 64, state: .field),
            VirtualGameBlock(id: UUID(), color: .red,  x: 80, y: 64, state: .field),
            VirtualGameBlock(id: UUID(), color: .blue, x: 64, y: 72, state: .field),
            VirtualGameBlock(id: UUID(), color: .red,  x: 72, y: 72, state: .field),
            VirtualGameBlock(id: UUID(), color: .blue, x: 80, y: 72, state: .field),
            VirtualGameBlock(id: UUID(), color: .red,  x: 64, y: 80, state: .field),
            VirtualGameBlock(id: UUID(), color: .blue, x: 72, y: 80, state: .field),
            VirtualGameBlock(id: UUID(), color: .red,  x: 80, y: 80, state: .field)
        ]

        carriedBlockID = nil
        carriedBlockCount = 0
        scoredBlockCount = 0
        gameStatusText = "Center red/blue balls ready"
        previousIntakeActive = false
        previousOuttakeActive = false
    }

    private func syncButtonsFromKeyboardTokens() {
        for button in ControllerButton.allCases {
            let keyboardPressed = keyboardControlEnabled ? isKeyboardMappedButtonPressed(button) : false
            let gamepadPressed = gamepadButtonStates[button] ?? false
            let touchPressed = touchButtonStates[button] ?? false
            buttonStates[button] = keyboardPressed || gamepadPressed || touchPressed
        }
    }

    private func updateAxesFromKeyboardTokens() {
        if !keyboardControlEnabled {
            keyboardAxis1 = 0
            keyboardAxis2 = 0
            keyboardAxis3 = 0
            keyboardAxis4 = 0
            recomputeMergedAxes()
            return
        }
        let tokenFor = { (role: KeyboardAxisRole) -> String in
            self.keyboardAxisMap[role] ?? ""
        }

        func axisValue(pos: KeyboardAxisRole, neg: KeyboardAxisRole, tokens: Set<String>) -> Int {
            let positive = tokenFor(pos)
            let negative = tokenFor(neg)
            let posHeld = !positive.isEmpty && tokens.contains(positive)
            let negHeld = !negative.isEmpty && tokens.contains(negative)
            if posHeld && !negHeld { return 127 }
            if negHeld && !posHeld { return -127 }
            return 0
        }

        keyboardAxis1 = axisValue(pos: .axis1Right, neg: .axis1Left, tokens: activeKeyboardTokens)
        keyboardAxis2 = axisValue(pos: .axis2Up, neg: .axis2Down, tokens: activeKeyboardTokens)
        keyboardAxis3 = axisValue(pos: .axis3Up, neg: .axis3Down, tokens: activeKeyboardTokens)
        keyboardAxis4 = axisValue(pos: .axis4Right, neg: .axis4Left, tokens: activeKeyboardTokens)
        recomputeMergedAxes()
    }

    private func isKeyboardMappedButtonPressed(_ button: ControllerButton) -> Bool {
        let token = keyboardButtonMap[button] ?? ""
        return !token.isEmpty && activeKeyboardTokens.contains(token)
    }

    private func recomputeMergedAxes() {
        axis1 = strongestAxisValue([gamepadAxis1, keyboardAxis1, touchAxis1])
        axis2 = strongestAxisValue([gamepadAxis2, keyboardAxis2, touchAxis2])
        axis3 = strongestAxisValue([gamepadAxis3, keyboardAxis3, touchAxis3])
        axis4 = strongestAxisValue([gamepadAxis4, keyboardAxis4, touchAxis4])
    }

    private func strongestAxisValue(_ values: [Int]) -> Int {
        var strongest = 0
        var magnitude = -1
        for value in values {
            let current = abs(value)
            if current > magnitude {
                strongest = value
                magnitude = current
            }
        }
        return strongest
    }

    private func tickAutonRunner() {
        guard isAutonRunning else {
            return
        }
        guard currentAutonStepIndex < activeAutonSteps.count else {
            completeAutonExecution(reason: "DONE")
            return
        }

        let step = activeAutonSteps[currentAutonStepIndex]
        if !currentAutonStepInitialized {
            startAutonStep(step)
        }

        switch step.type {
        case .empty:
            advanceAutonStep()
        case .driveMs:
            leftDriveCommand = clamp(step.value1, min: -127, max: 127)
            rightDriveCommand = clamp(step.value1, min: -127, max: 127)
            currentAutonStepElapsedMs += tickIntervalSeconds * 1000
            if currentAutonStepElapsedMs >= Double(max(0, step.value2)) {
                leftDriveCommand = 0
                rightDriveCommand = 0
                advanceAutonStep()
            }
        case .tankMs:
            leftDriveCommand = clamp(step.value1, min: -127, max: 127)
            rightDriveCommand = clamp(step.value2, min: -127, max: 127)
            currentAutonStepElapsedMs += tickIntervalSeconds * 1000
            if currentAutonStepElapsedMs >= Double(max(0, step.value3)) {
                leftDriveCommand = 0
                rightDriveCommand = 0
                advanceAutonStep()
            }
        case .turnHeading:
            let targetHeading = normalizedDegrees(Double(step.value1))
            let error = shortestHeadingError(target: targetHeading, current: headingDegrees)
            let turnCommand = clamp(Int(error * 1.2), min: -60, max: 60)
            leftDriveCommand = -turnCommand
            rightDriveCommand = turnCommand
            currentAutonStepElapsedMs += tickIntervalSeconds * 1000
            let timeoutMs = max(500, step.value2 == 0 ? 2500 : step.value2)
            if abs(error) < 1.8 || currentAutonStepElapsedMs >= Double(timeoutMs) {
                leftDriveCommand = 0
                rightDriveCommand = 0
                advanceAutonStep()
            }
        case .waitMs:
            leftDriveCommand = 0
            rightDriveCommand = 0
            currentAutonStepElapsedMs += tickIntervalSeconds * 1000
            if currentAutonStepElapsedMs >= Double(max(0, step.value1)) {
                advanceAutonStep()
            }
        case .intakeOn:
            intakeCommand = 127
            outakeCommand = 127
            advanceAutonStep()
        case .intakeOff:
            intakeCommand = 0
            outakeCommand = 0
            advanceAutonStep()
        case .outtakeOn:
            intakeCommand = -127
            outakeCommand = -127
            advanceAutonStep()
        case .outtakeOff:
            intakeCommand = 0
            outakeCommand = 0
            advanceAutonStep()
        }
    }

    private func startAutonStep(_ step: VirtualAutonStep) {
        currentAutonStepInitialized = true
        currentAutonStepElapsedMs = 0
        currentAutonStepText = step.shortDescription
        appendAutonLog(
            "Step \(currentAutonStepIndex + 1)/\(activeAutonSteps.count): \(step.shortDescription)"
        )
        if isRecording {
            recordingLines.append("AUTON_STEP:\(step.shortDescription)")
            recordingLineCount = recordingLines.count
            recordingPreview = Array(recordingLines.suffix(18))
        }
    }

    private func advanceAutonStep() {
        completedAutonSteps = min(currentAutonStepIndex + 1, activeAutonSteps.count)
        currentAutonStepIndex += 1
        currentAutonStepInitialized = false
        currentAutonStepElapsedMs = 0
        if currentAutonStepIndex >= activeAutonSteps.count {
            completeAutonExecution(reason: "DONE")
        }
    }

    private func completeAutonExecution(reason: String) {
        isAutonRunning = false
        activeAutonSteps = []
        currentAutonStepInitialized = false
        currentAutonStepElapsedMs = 0
        leftDriveCommand = 0
        rightDriveCommand = 0
        leftMiddleCommand = 0
        rightMiddleCommand = 0
        intakeCommand = 0
        outakeCommand = 0
        currentAutonStepText = reason == "DONE" ? "(complete)" : "(stopped)"
        statusText = reason == "DONE" ? "Auton complete" : "Auton stopped"
        appendAutonLog("Auton \(reason.lowercased())")
        if isRecording {
            recordingLines.append("AUTON_STOP:\(reason)")
            recordingLineCount = recordingLines.count
            recordingPreview = Array(recordingLines.suffix(18))
        }
    }

    private func appendAutonLog(_ line: String) {
        autonRunLog.append(line)
        if autonRunLog.count > 120 {
            autonRunLog.removeFirst(autonRunLog.count - 120)
        }
        appendLog(line)
    }

    private func shortestHeadingError(target: Double, current: Double) -> Double {
        var error = target - current
        if error > 180 {
            error -= 360
        } else if error < -180 {
            error += 360
        }
        return error
    }

    private func collectPressedButtonEdges() -> [ControllerButton] {
        var edges: [ControllerButton] = []
        for button in ControllerButton.allCases {
            let now = buttonStates[button] ?? false
            let previous = previousButtonStates[button] ?? false
            if now && !previous {
                edges.append(button)
            }
            previousButtonStates[button] = now
        }
        return edges
    }

    private func buildInputEvents(forPressedButtons buttons: [ControllerButton]) -> [VirtualInputEvent] {
        var events: [VirtualInputEvent] = []

        for button in buttons {
            for action in ControllerAction.allCases where buttonForAction(action) == button {
                events.append(eventForMappedAction(button: button, action: action))
            }

            if let dpadEvent = eventForDpadPress(button: button) {
                events.append(dpadEvent)
            } else if ControllerAction.allCases.allSatisfy({ buttonForAction($0) != button }) {
                events.append(
                    VirtualInputEvent(
                        uiText: "BUTTON \(button.rawValue) PRESSED : NO_ACTION",
                        recordType: "BTN_\(button.rawValue)",
                        recordValue: "NO_ACTION"
                    )
                )
            }
        }

        return events
    }

    private func eventForMappedAction(button: ControllerButton, action: ControllerAction) -> VirtualInputEvent {
        switch action {
        case .intakeIn:
            return VirtualInputEvent(
                uiText: "BUTTON \(button.rawValue) PRESSED : INTAKE_IN",
                recordType: "BTN_INTAKE_IN",
                recordValue: "INTAKE_IN"
            )
        case .intakeOut:
            return VirtualInputEvent(
                uiText: "BUTTON \(button.rawValue) PRESSED : INTAKE_OUT",
                recordType: "BTN_INTAKE_OUT",
                recordValue: "INTAKE_OUT"
            )
        case .outakeOut:
            return VirtualInputEvent(
                uiText: "BUTTON \(button.rawValue) PRESSED : OUTAKE_OUT",
                recordType: "BTN_OUTAKE_OUT",
                recordValue: "OUTAKE_OUT"
            )
        case .outakeIn:
            return VirtualInputEvent(
                uiText: "BUTTON \(button.rawValue) PRESSED : OUTAKE_IN",
                recordType: "BTN_OUTAKE_IN",
                recordValue: "OUTAKE_IN"
            )
        case .gpsEnable:
            return VirtualInputEvent(
                uiText: "BUTTON \(button.rawValue) PRESSED : GPS_ENABLE",
                recordType: "BTN_GPS_ENABLE",
                recordValue: "GPS_ENABLE"
            )
        case .gpsDisable:
            return VirtualInputEvent(
                uiText: "BUTTON \(button.rawValue) PRESSED : GPS_DISABLE",
                recordType: "BTN_GPS_DISABLE",
                recordValue: "GPS_DISABLE"
            )
        case .sixWheelOn:
            return VirtualInputEvent(
                uiText: "BUTTON \(button.rawValue) PRESSED : SIX_WHEEL_ON",
                recordType: "BTN_SIX_ON",
                recordValue: "SIX_WHEEL_ON"
            )
        case .sixWheelOff:
            return VirtualInputEvent(
                uiText: "BUTTON \(button.rawValue) PRESSED : SIX_WHEEL_OFF",
                recordType: "BTN_SIX_OFF",
                recordValue: "SIX_WHEEL_OFF"
            )
        }
    }

    private func eventForDpadPress(button: ControllerButton) -> VirtualInputEvent? {
        switch button {
        case .up:
            return VirtualInputEvent(
                uiText: "BUTTON UP PRESSED : DPAD_UP",
                recordType: "BTN_DPAD_UP",
                recordValue: "DPAD_UP"
            )
        case .down:
            return VirtualInputEvent(
                uiText: "BUTTON DOWN PRESSED : DPAD_DOWN",
                recordType: "BTN_DPAD_DOWN",
                recordValue: "DPAD_DOWN"
            )
        case .left:
            return VirtualInputEvent(
                uiText: "BUTTON LEFT PRESSED : DPAD_LEFT",
                recordType: "BTN_DPAD_LEFT",
                recordValue: "DPAD_LEFT"
            )
        case .right:
            return VirtualInputEvent(
                uiText: "BUTTON RIGHT PRESSED : DPAD_RIGHT",
                recordType: "BTN_DPAD_RIGHT",
                recordValue: "DPAD_RIGHT"
            )
        default:
            return nil
        }
    }

    private func applyToggleActions(from events: [VirtualInputEvent]) {
        for event in events {
            switch event.recordValue {
            case "GPS_ENABLE":
                gpsDriveEnabled = true
            case "GPS_DISABLE":
                gpsDriveEnabled = false
            case "SIX_WHEEL_ON":
                sixWheelDriveEnabled = true
            case "SIX_WHEEL_OFF":
                sixWheelDriveEnabled = false
            default:
                break
            }
        }
    }

    private func computeDriveCommands(
        dpadUp: Bool,
        dpadDown: Bool,
        dpadLeft: Bool,
        dpadRight: Bool
    ) -> (left: Int, right: Int) {
        switch driveMode {
        case .tank:
            return (
                clamp(axis3, min: -127, max: 127),
                clamp(axis2, min: -127, max: 127)
            )
        case .arcade2:
            let throttle = axis3
            let turn = axis1
            return (
                clamp(throttle + turn, min: -127, max: 127),
                clamp(throttle - turn, min: -127, max: 127)
            )
        case .dpad:
            guard dpadUp || dpadDown || dpadLeft || dpadRight else {
                return (0, 0)
            }

            let dpadSpeed = 80
            let scaledDpadSpeed = clamp(Int((Double(dpadSpeed) * botSpeedScale).rounded()), min: 25, max: 127)
            if gpsDriveEnabled {
                var target = 0.0
                if dpadUp {
                    target = 0.0
                } else if dpadRight {
                    target = 90.0
                } else if dpadDown {
                    target = 180.0
                } else if dpadLeft {
                    target = 270.0
                }

                var error = target - headingDegrees
                if error > 180 {
                    error -= 360
                } else if error < -180 {
                    error += 360
                }

                var turn = error * 1.2
                turn = min(60, max(-60, turn))
                return (
                    clamp(Int(Double(scaledDpadSpeed) - turn), min: -127, max: 127),
                    clamp(Int(Double(scaledDpadSpeed) + turn), min: -127, max: 127)
                )
            }

            if dpadUp {
                return (scaledDpadSpeed, scaledDpadSpeed)
            }
            if dpadDown {
                return (-scaledDpadSpeed, -scaledDpadSpeed)
            }
            if dpadLeft {
                return (-scaledDpadSpeed, scaledDpadSpeed)
            }
            return (scaledDpadSpeed, -scaledDpadSpeed)
        }
    }

    private func integratePose(left: Int, right: Int) {
        let speed = max(8.0, maxSpeedInchesPerSecond * botSpeedScale)
        let leftVelocity = (Double(left) / 127.0) * speed
        let rightVelocity = (Double(right) / 127.0) * speed
        let linearVelocity = (leftVelocity + rightVelocity) / 2.0
        let angularVelocity = (rightVelocity - leftVelocity) / trackWidthInches

        headingRadians += angularVelocity * tickIntervalSeconds
        poseXInches += linearVelocity * cos(headingRadians) * tickIntervalSeconds
        poseYInches += linearVelocity * sin(headingRadians) * tickIntervalSeconds
        poseXInches = min(fieldSizeInches, max(0, poseXInches))
        poseYInches = min(fieldSizeInches, max(0, poseYInches))

        headingDegrees = normalizedDegrees(headingRadians * 180.0 / .pi)
        imuHeadingDegrees = headingDegrees
        gpsHeadingDegrees = headingDegrees

        pathSamples.append(
            VirtualPoseSample(
                t: simTimeSeconds,
                x: poseXInches,
                y: poseYInches,
                headingDeg: headingDegrees
            )
        )
        if pathSamples.count > 2200 {
            pathSamples.removeFirst(pathSamples.count - 2200)
        }
    }

    private func appendTelemetryFrame() {
        let frame = VirtualTelemetryFrame(
            timeSeconds: simTimeSeconds,
            axis1: axis1,
            axis2: isAutonRunning ? rightDriveCommand : axis2,
            axis3: isAutonRunning ? leftDriveCommand : axis3,
            axis4: axis4,
            intakeAction: actionLabel(forCommand: intakeCommand),
            outtakeAction: actionLabel(forCommand: outakeCommand),
            leftCommand: leftDriveCommand,
            rightCommand: rightDriveCommand,
            xInches: poseXInches,
            yInches: poseYInches,
            headingDeg: headingDegrees,
            autonSection: isAutonRunning ? activeAutonSection.rawValue : "MANUAL",
            autonStep: isAutonRunning ? currentAutonStepText : "MANUAL_DRIVE"
        )
        telemetryFrames.append(frame)
        if telemetryFrames.count > 20000 {
            telemetryFrames.removeFirst(telemetryFrames.count - 20000)
        }
        telemetryFrameCount = telemetryFrames.count
    }

    private func appendInputEvents(_ events: [VirtualInputEvent]) {
        guard !events.isEmpty else {
            return
        }
        for event in events {
            inputActionLog.append(event.uiText)
            appendLog(event.uiText)
        }
        if inputActionLog.count > 220 {
            inputActionLog.removeFirst(inputActionLog.count - 220)
        }
    }

    private func appendRecordingFrame(events: [VirtualInputEvent]) {
        let recordAxis1 = axis1
        let recordAxis2 = isAutonRunning ? rightDriveCommand : axis2
        let recordAxis3 = isAutonRunning ? leftDriveCommand : axis3
        let recordAxis4 = axis4
        recordingLines.append("AXIS1:\(recordAxis1)")
        recordingLines.append("AXIS2:\(recordAxis2)")
        recordingLines.append("AXIS3:\(recordAxis3)")
        recordingLines.append("AXIS4:\(recordAxis4)")

        for event in events {
            guard let type = event.recordType, let value = event.recordValue else {
                continue
            }
            recordingLines.append("\(type):\(value)")
        }

        recordingLineCount = recordingLines.count
        recordingPreview = Array(recordingLines.suffix(18))
    }

    private func actionLabel(forCommand command: Int) -> String {
        if command > 0 {
            return "FORWARD"
        }
        if command < 0 {
            return "REVERSE"
        }
        return "OFF"
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }

    private func timestampForFileName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }

    private func normalizedDegrees(_ value: Double) -> Double {
        var out = value.truncatingRemainder(dividingBy: 360)
        if out < 0 {
            out += 360
        }
        return out
    }

    private func appendLog(_ line: String) {
        let timestamp = isoTimestampFormatter.string(from: Date())
        runtimeLog.append("[\(timestamp)] \(line)")
        if runtimeLog.count > 180 {
            runtimeLog.removeFirst(runtimeLog.count - 180)
        }
    }

    private func clamp(_ value: Int, min low: Int, max high: Int) -> Int {
        Swift.max(low, Swift.min(high, value))
    }

    private func normalizedKeyToken(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed == "arrowup" { return "up" }
        if trimmed == "arrowdown" { return "down" }
        if trimmed == "arrowleft" { return "left" }
        if trimmed == "arrowright" { return "right" }
        if trimmed == " " { return "space" }
        return String(trimmed.prefix(12))
    }

    private static func makeDefaultButtonState() -> [ControllerButton: Bool] {
        Dictionary(uniqueKeysWithValues: ControllerButton.allCases.map { ($0, false) })
    }

    private static func makeDefaultActionMapping() -> [ControllerAction: ControllerButton] {
        Dictionary(uniqueKeysWithValues: ControllerAction.allCases.map { ($0, $0.defaultButton) })
    }

    private static let availableKeyboardTokens: [String] = [
        "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
        "q", "w", "e", "r", "t", "y", "u", "i", "o", "p",
        "a", "s", "d", "f", "g", "h", "j", "k", "l",
        "z", "x", "c", "v", "b", "n", "m",
        "up", "down", "left", "right", "space"
    ]

    private static func makeDefaultKeyboardButtonMap() -> [ControllerButton: String] {
        [
            .l1: "1",
            .l2: "2",
            .r1: "3",
            .r2: "4",
            .a: "z",
            .b: "x",
            .x: "c",
            .y: "v",
            .up: "up",
            .down: "down",
            .left: "left",
            .right: "right"
        ]
    }

    private static func makeDefaultKeyboardAxisMap() -> [KeyboardAxisRole: String] {
        [
            .axis1Left: "a",
            .axis1Right: "d",
            .axis2Up: "i",
            .axis2Down: "k",
            .axis3Up: "w",
            .axis3Down: "s",
            .axis4Left: "j",
            .axis4Right: "l"
        ]
    }
}
