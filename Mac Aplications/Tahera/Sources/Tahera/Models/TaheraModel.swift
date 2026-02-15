import Foundation
import SwiftUI
import Darwin

final class TaheraModel: ObservableObject {
    @Published var currentSection: AppSection = .home
    @Published var repoPath: String = "/Users/lorenzodiiorio/Documents/GitHub/2026-Vex-V5-Pushback-Code-and-Desighn-"
    @Published var outputLog: String = ""
    @Published var isBusy: Bool = false
    @Published var readmeContent: String = ""

    @Published var projects: [ProsProject] = [
        ProsProject(name: "The Tahera Sequence", relativePath: "Pros projects/Tahera_Project", slot: 1),
        ProsProject(name: "Auton Planner", relativePath: "Pros projects/Auton_Planner_PROS", slot: 2),
        ProsProject(name: "Image Selector", relativePath: "Pros projects/Image Selector", slot: 3),
        ProsProject(name: "Basic Bonkers", relativePath: "Pros projects/Basic_Bonkers_PROS", slot: 4)
    ]
    @Published var buildUploadStatusByPath: [String: ProjectBuildUploadStatus] = [:]

    @Published var sdPath: String = "/Volumes/MICROBONK"
    @Published var sdMounted: Bool = false

    @Published var brainDetected: Bool = false
    @Published var brainPort: String = ""

    @Published var portMap: PortMap = PortMap()
    @Published var portMapStatus: String = ""
    @Published var driveControlMode: DriveControlMode = .tank
    @Published var controllerMapping: [ControllerAction: ControllerButton] =
        Dictionary(uniqueKeysWithValues: ControllerAction.allCases.map { ($0, $0.defaultButton) })
    @Published var controllerMappingStatus: String = ""

    // Password wall for repository settings/GitHub tools.
    @Published var repoSettingsUnlocked: Bool = false
    @Published var repoSettingsPasswordInput: String = ""
    @Published var repoSettingsAuthError: String = ""

    @Published var gitCommitMessage: String = ""
    @Published var gitTag: String = ""
    @Published var gitTagMessage: String = ""
    @Published var gitReleaseTitle: String = ""
    @Published var gitReleaseNotes: String = ""
    @Published var githubToken: String = ""
    @Published var releaseLog: String = ""
    @Published var releaseStatusMessage: String = ""
    @Published var releaseStatusIsSuccess: Bool = false

    private let repoSettingsPassword = "56Wrenches.782"
    private let controllerMappingFileName = "controller_mapping.txt"
    private let portMapFileName = "port_map.json"
    private let busyQueue = DispatchQueue(label: "TaheraModel.BusyQueue")
    private var busyCount = 0
    let virtualBrain = VirtualBrainCore()

    init() {
        initializeBuildUploadStatus()
        refreshSDStatus()
        refreshBrainStatus()
        loadReadme()
        loadPortMapFromRepo()
        loadControllerMappingFromRepo()
        virtualBrain.setDefaultVirtualSDPath(for: repoPath)
    }

    func unlockRepositorySettings() {
        let entered = repoSettingsPasswordInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if entered == repoSettingsPassword {
            repoSettingsUnlocked = true
            repoSettingsAuthError = ""
            repoSettingsPasswordInput = ""
            appendLog("Repository settings unlocked")
        } else {
            repoSettingsUnlocked = false
            repoSettingsAuthError = "Incorrect password"
        }
    }

    func lockRepositorySettings() {
        repoSettingsUnlocked = false
        repoSettingsPasswordInput = ""
        repoSettingsAuthError = ""
    }

    func appendLog(_ text: String) {
        DispatchQueue.main.async {
            self.outputLog.append(text + "\n")
        }
    }

    func clearReleaseLog() {
        DispatchQueue.main.async {
            self.releaseLog = ""
        }
    }

    private func appendReleaseLog(_ text: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        DispatchQueue.main.async {
            self.releaseLog.append("[\(timestamp)] \(text)\n")
        }
    }

    private func updateReleaseStatus(success: Bool, message: String) {
        DispatchQueue.main.async {
            self.releaseStatusIsSuccess = success
            self.releaseStatusMessage = message
        }
        appendReleaseLog(message)
    }

    private func firstMeaningfulLine(_ text: String) -> String {
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }

    private func firstErrorLikeLine(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            if !trimmed.isEmpty && (lower.contains("error") || lower.contains("failed")) {
                return trimmed
            }
        }
        return firstMeaningfulLine(text)
    }

    private func isReleaseNotFoundError(_ output: String) -> Bool {
        let lower = output.lowercased()
        return lower.contains("release not found") || (lower.contains("not found") && lower.contains("release"))
    }

    private func isReleaseAlreadyExistsError(_ output: String) -> Bool {
        let lower = output.lowercased()
        return lower.contains("already exists") || lower.contains("already a release")
    }

    private func releaseFailureMessage(defaultMessage: String, output: String) -> String {
        let detail = firstMeaningfulLine(output)
        if detail.isEmpty {
            return defaultMessage
        }
        return "\(defaultMessage) \(detail)"
    }

    private func resolveExecutable(_ name: String, preferredPaths: [String]) -> String? {
        let fm = FileManager.default
        for path in preferredPaths where fm.isExecutableFile(atPath: path) {
            return path
        }
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for rawDir in pathEnv.components(separatedBy: ":") {
                let dir = rawDir.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !dir.isEmpty else { continue }
                let candidate = URL(fileURLWithPath: dir).appendingPathComponent(name).path
                if fm.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }
        return nil
    }

    private func ghExecutablePath() -> String? {
        resolveExecutable("gh", preferredPaths: [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh"
        ])
    }

    private func prosExecutablePath() -> String? {
        let home = NSHomeDirectory()
        return resolveExecutable("pros", preferredPaths: [
            "/opt/homebrew/bin/pros",
            "/usr/local/bin/pros",
            "\(home)/Library/Python/3.13/bin/pros",
            "\(home)/Library/Python/3.12/bin/pros",
            "\(home)/Library/Python/3.11/bin/pros",
            "\(home)/Library/Python/3.10/bin/pros",
            "\(home)/Library/Python/3.9/bin/pros"
        ])
    }

    private func beginBusy() {
        busyQueue.async {
            self.busyCount += 1
            let busy = self.busyCount > 0
            DispatchQueue.main.async {
                self.isBusy = busy
            }
        }
    }

    private func endBusy() {
        busyQueue.async {
            self.busyCount = max(0, self.busyCount - 1)
            let busy = self.busyCount > 0
            DispatchQueue.main.async {
                self.isBusy = busy
            }
        }
    }

    private func runCommand(
        _ cmd: [String],
        cwd: String? = nil,
        label: String,
        timeoutSeconds: TimeInterval = 240,
        nonInteractive: Bool = false,
        extraEnv: [String: String] = [:],
        completion: ((Int32) -> Void)? = nil
    ) {
        beginBusy()
        appendLog("$ \(label)")

        DispatchQueue.global(qos: .userInitiated).async {
            defer {
                self.endBusy()
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: cmd.first ?? "")
            process.arguments = Array(cmd.dropFirst())
            var env = ProcessInfo.processInfo.environment
            if nonInteractive {
                // Fail fast instead of waiting for interactive credentials/prompts.
                env["GIT_TERMINAL_PROMPT"] = "0"
                env["GCM_INTERACTIVE"] = "Never"
                env["GH_PROMPT_DISABLED"] = "1"
                env["CI"] = "1"
            }
            for (key, value) in extraEnv {
                env[key] = value
            }
            process.environment = env
            if let cwd {
                process.currentDirectoryURL = URL(fileURLWithPath: cwd)
            }

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            let inputPipe = Pipe()
            process.standardInput = inputPipe
            inputPipe.fileHandleForWriting.closeFile()

            do {
                try process.run()
            } catch {
                self.appendLog("Failed: \(error.localizedDescription)")
                completion?(-1)
                return
            }

            let handle = pipe.fileHandleForReading
            handle.readabilityHandler = { fh in
                let data = fh.availableData
                guard !data.isEmpty else { return }
                if let text = String(data: data, encoding: .utf8) {
                    self.appendLog(text.trimmingCharacters(in: .newlines))
                }
            }

            let started = Date()
            var didTimeout = false
            while process.isRunning {
                if Date().timeIntervalSince(started) > timeoutSeconds {
                    didTimeout = true
                    process.terminate()
                    let killDeadline = Date().addingTimeInterval(2.0)
                    while process.isRunning && Date() < killDeadline {
                        Thread.sleep(forTimeInterval: 0.05)
                    }
                    if process.isRunning {
                        _ = Darwin.kill(process.processIdentifier, SIGKILL)
                    }
                    break
                }
                Thread.sleep(forTimeInterval: 0.15)
            }
            process.waitUntilExit()
            handle.readabilityHandler = nil
            if didTimeout {
                self.appendLog("Failed: command timed out after \(Int(timeoutSeconds))s")
            }
            completion?(didTimeout ? -2 : process.terminationStatus)
        }
    }

    private func runCommandCapture(
        _ cmd: [String],
        cwd: String? = nil,
        label: String,
        timeoutSeconds: TimeInterval = 240,
        nonInteractive: Bool = false,
        extraEnv: [String: String] = [:],
        completion: @escaping (Int32, String) -> Void
    ) {
        beginBusy()
        appendLog("$ \(label)")

        DispatchQueue.global(qos: .userInitiated).async {
            defer {
                self.endBusy()
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: cmd.first ?? "")
            process.arguments = Array(cmd.dropFirst())
            var env = ProcessInfo.processInfo.environment
            if nonInteractive {
                env["GIT_TERMINAL_PROMPT"] = "0"
                env["GCM_INTERACTIVE"] = "Never"
                env["GH_PROMPT_DISABLED"] = "1"
                env["CI"] = "1"
            }
            for (key, value) in extraEnv {
                env[key] = value
            }
            process.environment = env
            if let cwd {
                process.currentDirectoryURL = URL(fileURLWithPath: cwd)
            }

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            let inputPipe = Pipe()
            process.standardInput = inputPipe
            inputPipe.fileHandleForWriting.closeFile()

            let outputLock = NSLock()
            var capturedOutput = ""

            do {
                try process.run()
            } catch {
                let text = "Failed: \(error.localizedDescription)"
                self.appendLog(text)
                completion(-1, text)
                return
            }

            let handle = pipe.fileHandleForReading
            handle.readabilityHandler = { fh in
                let data = fh.availableData
                guard !data.isEmpty else { return }
                guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
                outputLock.lock()
                capturedOutput.append(text)
                outputLock.unlock()
                self.appendLog(text.trimmingCharacters(in: .newlines))
            }

            let started = Date()
            var didTimeout = false
            while process.isRunning {
                if Date().timeIntervalSince(started) > timeoutSeconds {
                    didTimeout = true
                    process.terminate()
                    let killDeadline = Date().addingTimeInterval(2.0)
                    while process.isRunning && Date() < killDeadline {
                        Thread.sleep(forTimeInterval: 0.05)
                    }
                    if process.isRunning {
                        _ = Darwin.kill(process.processIdentifier, SIGKILL)
                    }
                    break
                }
                Thread.sleep(forTimeInterval: 0.15)
            }

            process.waitUntilExit()
            handle.readabilityHandler = nil
            if didTimeout {
                self.appendLog("Failed: command timed out after \(Int(timeoutSeconds))s")
            }

            outputLock.lock()
            let output = capturedOutput
            outputLock.unlock()
            completion(didTimeout ? -2 : process.terminationStatus, output)
        }
    }

    private func projectPath(_ project: ProsProject) -> String {
        let trimmedRepoPath = repoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(fileURLWithPath: trimmedRepoPath).appendingPathComponent(project.relativePath).path
    }

    private func validateProjectPath(_ path: String, for project: ProsProject, phaseOnFailure: BuildUploadPhase) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else {
            setBuildUploadStatus(
                for: project,
                phase: phaseOnFailure,
                message: "Project folder not found: \(path). Check Home -> Repository path."
            )
            return false
        }
        return true
    }

    private func requireProsExecutable(for project: ProsProject?, phaseOnFailure: BuildUploadPhase) -> String? {
        guard let prosPath = prosExecutablePath() else {
            let message = "PROS CLI not found. Install PROS CLI or add `pros` to PATH."
            if let project {
                setBuildUploadStatus(for: project, phase: phaseOnFailure, message: message)
            } else {
                appendLog("Failed: \(message)")
            }
            return nil
        }
        return prosPath
    }

    private struct V5UploadPorts {
        var system: [String] = []
        var user: [String] = []
    }

    private func initializeBuildUploadStatus() {
        var statusMap: [String: ProjectBuildUploadStatus] = [:]
        for project in projects {
            statusMap[project.relativePath] = ProjectBuildUploadStatus()
        }
        buildUploadStatusByPath = statusMap
    }

    func buildUploadStatus(for project: ProsProject) -> ProjectBuildUploadStatus {
        buildUploadStatusByPath[project.relativePath] ?? ProjectBuildUploadStatus()
    }

    private func setBuildUploadStatus(
        for project: ProsProject,
        phase: BuildUploadPhase,
        message: String,
        port: String? = nil
    ) {
        DispatchQueue.main.async {
            self.buildUploadStatusByPath[project.relativePath] = ProjectBuildUploadStatus(
                phase: phase,
                message: message,
                port: port,
                updatedAt: Date()
            )
        }
        appendLog("[\(project.name)] \(message)")
    }

    private func parseV5UploadPorts(from output: String) -> V5UploadPorts {
        enum Section {
            case none
            case system
            case user
        }

        var result = V5UploadPorts()
        var section: Section = .none

        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.contains("VEX EDR V5 System Ports") {
                section = .system
                continue
            }
            if line.contains("VEX EDR V5 User Ports") {
                section = .user
                continue
            }
            if line.hasPrefix("There are no connected") {
                continue
            }
            guard line.hasPrefix("/dev/"), let port = line.components(separatedBy: " ").first else {
                continue
            }
            switch section {
            case .system:
                result.system.append(port)
            case .user:
                result.user.append(port)
            case .none:
                break
            }
        }

        return result
    }

    private func preferredUploadPorts(from ports: V5UploadPorts) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for port in ports.system + ports.user {
            if seen.insert(port).inserted {
                ordered.append(port)
            }
        }
        return ordered
    }

    private func outputShowsUploadSuccess(_ output: String) -> Bool {
        let lower = output.lowercased()
        if lower.contains("finished uploading") {
            return true
        }
        if lower.contains("uploading slot_") || lower.contains("uploading program") {
            return true
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func detectUploadPorts(prosPath: String, completion: @escaping ([String]) -> Void) {
        runCommandCapture(
            [prosPath, "lsusb"],
            label: "pros lsusb",
            timeoutSeconds: 30
        ) { status, output in
            if status != 0 {
                if !self.brainPort.isEmpty {
                    completion([self.brainPort])
                } else {
                    completion([])
                }
                return
            }
            let parsed = self.parseV5UploadPorts(from: output)
            let preferred = self.preferredUploadPorts(from: parsed)
            if preferred.isEmpty, !self.brainPort.isEmpty {
                completion([self.brainPort])
                return
            }
            completion(preferred)
        }
    }

    private func attemptUpload(
        project: ProsProject,
        prosPath: String,
        projectPath: String,
        candidates: [String],
        index: Int
    ) {
        guard index < candidates.count else {
            setBuildUploadStatus(
                for: project,
                phase: .uploadFailed,
                message: "Upload failed: no usable V5 ports were found."
            )
            return
        }

        let port = candidates[index]
        let uploadLabel = "pros upload . \(port) --slot \(project.slot) (\(project.name))"
        setBuildUploadStatus(
            for: project,
            phase: .uploading,
            message: "Uploading to slot \(project.slot) on \(port)...",
            port: port
        )

        runCommandCapture(
            [prosPath, "upload", ".", port, "--slot", String(project.slot), "--name", project.name],
            cwd: projectPath,
            label: uploadLabel,
            timeoutSeconds: 600
        ) { status, output in
            if status == 0 && self.outputShowsUploadSuccess(output) {
                self.setBuildUploadStatus(
                    for: project,
                    phase: .uploadSucceeded,
                    message: "Upload complete on \(port).",
                    port: port
                )
                return
            }

            if index + 1 < candidates.count {
                self.setBuildUploadStatus(
                    for: project,
                    phase: .uploading,
                    message: "Upload failed on \(port); retrying...",
                    port: candidates[index + 1]
                )
                self.attemptUpload(project: project, prosPath: prosPath, projectPath: projectPath, candidates: candidates, index: index + 1)
                return
            }

            let detail = self.firstErrorLikeLine(output)
            let reason = detail.isEmpty ? "Upload failed on \(port) (exit \(status))." : "Upload failed on \(port): \(detail)"
            self.setBuildUploadStatus(
                for: project,
                phase: .uploadFailed,
                message: reason,
                port: port
            )
        }
    }

    private func uploadWithDetectedPort(project: ProsProject, projectPath: String) {
        guard let prosPath = requireProsExecutable(for: project, phaseOnFailure: .uploadFailed) else {
            return
        }
        guard validateProjectPath(projectPath, for: project, phaseOnFailure: .uploadFailed) else {
            return
        }
        setBuildUploadStatus(for: project, phase: .uploading, message: "Scanning V5 ports...")
        detectUploadPorts(prosPath: prosPath) { ports in
            guard !ports.isEmpty else {
                self.setBuildUploadStatus(
                    for: project,
                    phase: .uploadFailed,
                    message: "Upload failed: no connected V5 ports found."
                )
                return
            }
            self.attemptUpload(project: project, prosPath: prosPath, projectPath: projectPath, candidates: ports, index: 0)
        }
    }

    func build(project: ProsProject) {
        let path = projectPath(project)
        guard validateProjectPath(path, for: project, phaseOnFailure: .buildFailed) else {
            return
        }
        guard let prosPath = requireProsExecutable(for: project, phaseOnFailure: .buildFailed) else {
            return
        }
        setBuildUploadStatus(for: project, phase: .building, message: "Building project...")
        runCommandCapture(
            [prosPath, "make"],
            cwd: path,
            label: "pros make (\(project.name))",
            timeoutSeconds: 600
        ) { status, output in
            if status == 0 {
                self.setBuildUploadStatus(
                    for: project,
                    phase: .buildSucceeded,
                    message: "Build complete for slot \(project.slot)."
                )
                return
            }
            let detail = self.firstErrorLikeLine(output)
            let reason = detail.isEmpty ? "Build failed (exit \(status))." : "Build failed: \(detail)"
            self.setBuildUploadStatus(for: project, phase: .buildFailed, message: reason)
        }
    }

    func upload(project: ProsProject) {
        uploadWithDetectedPort(project: project, projectPath: projectPath(project))
    }

    func buildAndUpload(project: ProsProject) {
        let path = projectPath(project)
        guard validateProjectPath(path, for: project, phaseOnFailure: .buildFailed) else {
            return
        }
        guard let prosPath = requireProsExecutable(for: project, phaseOnFailure: .buildFailed) else {
            return
        }
        setBuildUploadStatus(for: project, phase: .building, message: "Building project...")
        runCommandCapture(
            [prosPath, "make"],
            cwd: path,
            label: "pros make (\(project.name))",
            timeoutSeconds: 600
        ) { status, output in
            if status == 0 {
                self.setBuildUploadStatus(
                    for: project,
                    phase: .buildSucceeded,
                    message: "Build complete. Starting upload..."
                )
                self.uploadWithDetectedPort(project: project, projectPath: path)
                return
            }
            let detail = self.firstErrorLikeLine(output)
            let reason = detail.isEmpty ? "Build failed (exit \(status))." : "Build failed: \(detail)"
            self.setBuildUploadStatus(for: project, phase: .buildFailed, message: reason)
        }
    }

    func refreshSDStatus() {
        sdMounted = FileManager.default.fileExists(atPath: sdPath)
    }

    func refreshBrainStatus() {
        let devs = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        let candidates = devs.filter {
            $0.hasPrefix("cu.usbmodem") || $0.hasPrefix("tty.usbmodem") || $0.hasPrefix("cu.usbserial") || $0.hasPrefix("tty.usbserial")
        }.sorted()
        if let first = candidates.first {
            brainDetected = true
            brainPort = "/dev/" + first
        } else {
            brainDetected = false
            brainPort = ""
        }
    }

    func gitCommit() {
        guard repoSettingsUnlocked else { return }
        let path = repoPath
        let msg = gitCommitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty else { return }
        runCommand(["/usr/bin/git", "add", "-A"], cwd: path, label: "git add -A", timeoutSeconds: 60, nonInteractive: true) { addStatus in
            guard addStatus == 0 else { return }
            self.runCommand(["/usr/bin/git", "commit", "-m", msg], cwd: path, label: "git commit", timeoutSeconds: 90, nonInteractive: true)
        }
    }

    func gitPush() {
        guard repoSettingsUnlocked else { return }
        runCommand(["/usr/bin/git", "push"], cwd: repoPath, label: "git push", timeoutSeconds: 90, nonInteractive: true)
    }

    func gitTagAndPush() {
        guard repoSettingsUnlocked else { return }
        let t = gitTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let msg = gitTagMessage.isEmpty ? t : gitTagMessage
        runCommand(["/usr/bin/git", "tag", "-a", t, "-m", msg], cwd: repoPath, label: "git tag", timeoutSeconds: 60, nonInteractive: true) { tagStatus in
            guard tagStatus == 0 else { return }
            self.runCommand(["/usr/bin/git", "push", "--tags"], cwd: self.repoPath, label: "git push --tags", timeoutSeconds: 90, nonInteractive: true)
        }
    }

    func githubRelease() {
        guard repoSettingsUnlocked else { return }
        let t = gitTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let title = gitReleaseTitle.isEmpty ? t : gitReleaseTitle
        let notes = gitReleaseNotes
        DispatchQueue.main.async {
            self.releaseStatusIsSuccess = false
            self.releaseStatusMessage = "Starting release for tag \(t)..."
        }
        appendReleaseLog("Starting release flow for tag \(t).")
        guard let ghPath = ghExecutablePath() else {
            updateReleaseStatus(
                success: false,
                message: "Release failed: GitHub CLI (gh) was not found. Install GitHub CLI and restart Tahera."
            )
            return
        }
        let token = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let ghEnv: [String: String] = token.isEmpty ? [:] : ["GH_TOKEN": token]
        if !token.isEmpty {
            appendReleaseLog("Using provided GitHub token for release authentication.")
        }

        func lookupReleaseURL(attemptsRemaining: Int, completion: @escaping (String?) -> Void) {
            self.runCommandCapture(
                [ghPath, "release", "view", t, "--json", "url", "--jq", ".url"],
                cwd: self.repoPath,
                label: "gh release url \(t)",
                timeoutSeconds: 30,
                nonInteractive: true,
                extraEnv: ghEnv
            ) { status, output in
                let url = self.firstMeaningfulLine(output)
                if status == 0 && !url.isEmpty {
                    completion(url)
                    return
                }
                if attemptsRemaining > 1 {
                    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1.0) {
                        lookupReleaseURL(attemptsRemaining: attemptsRemaining - 1, completion: completion)
                    }
                } else {
                    completion(nil)
                }
            }
        }

        func finalizeReleaseSuccess() {
            self.appendReleaseLog("Release command completed.")
            lookupReleaseURL(attemptsRemaining: 3) { url in
                if let url, !url.isEmpty {
                    self.updateReleaseStatus(success: true, message: "Release succeeded: \(url)")
                } else {
                    self.updateReleaseStatus(success: true, message: "Release succeeded for tag \(t), but URL lookup failed.")
                }
            }
        }

        func runReleaseCreateOrEdit(exists: Bool) {
            let primaryCmd: [String]
            let primaryLabel: String
            let fallbackCmd: [String]
            let fallbackLabel: String

            if exists {
                primaryCmd = [ghPath, "release", "edit", t, "--title", title, "--notes", notes]
                primaryLabel = "gh release edit \(t)"
                fallbackCmd = [ghPath, "release", "create", t, "--title", title, "--notes", notes]
                fallbackLabel = "gh release create \(t)"
            } else {
                primaryCmd = [ghPath, "release", "create", t, "--title", title, "--notes", notes]
                primaryLabel = "gh release create \(t)"
                fallbackCmd = [ghPath, "release", "edit", t, "--title", title, "--notes", notes]
                fallbackLabel = "gh release edit \(t)"
            }

            self.runCommandCapture(primaryCmd, cwd: self.repoPath, label: primaryLabel, timeoutSeconds: 120, nonInteractive: true, extraEnv: ghEnv) { status, output in
                if status == 0 {
                    finalizeReleaseSuccess()
                    return
                }

                let shouldFallback: Bool
                if exists {
                    shouldFallback = self.isReleaseNotFoundError(output)
                    if shouldFallback {
                        self.appendReleaseLog("Edit reported release missing. Retrying create.")
                    }
                } else {
                    shouldFallback = self.isReleaseAlreadyExistsError(output)
                    if shouldFallback {
                        self.appendReleaseLog("Create reported existing release. Retrying edit.")
                    }
                }

                guard shouldFallback else {
                    self.updateReleaseStatus(
                        success: false,
                        message: self.releaseFailureMessage(defaultMessage: "Release failed during \(primaryLabel).", output: output)
                    )
                    return
                }

                self.runCommandCapture(fallbackCmd, cwd: self.repoPath, label: fallbackLabel, timeoutSeconds: 120, nonInteractive: true, extraEnv: ghEnv) { fallbackStatus, fallbackOutput in
                    guard fallbackStatus == 0 else {
                        self.updateReleaseStatus(
                            success: false,
                            message: self.releaseFailureMessage(defaultMessage: "Release failed during \(fallbackLabel).", output: fallbackOutput)
                        )
                        return
                    }
                    finalizeReleaseSuccess()
                }
            }
        }

        // Keep tags in sync on origin so GitHub.com reflects the release state.
        runCommandCapture(["/usr/bin/git", "push", "--tags"], cwd: repoPath, label: "git push --tags", timeoutSeconds: 90, nonInteractive: true) { pushStatus, pushOutput in
            guard pushStatus == 0 else {
                self.appendLog("Release aborted: unable to push tags to origin.")
                self.updateReleaseStatus(
                    success: false,
                    message: self.releaseFailureMessage(defaultMessage: "Release failed: unable to push tags to origin.", output: pushOutput)
                )
                return
            }
            self.appendReleaseLog("Tags pushed to origin.")

            let continueWithReleaseCheck: () -> Void = {
                self.runCommandCapture(
                    [ghPath, "release", "view", t, "--json", "id", "--jq", ".id"],
                    cwd: self.repoPath,
                    label: "gh release view \(t) --json id",
                    timeoutSeconds: 45,
                    nonInteractive: true,
                    extraEnv: ghEnv
                ) { viewStatus, viewOutput in
                    if viewStatus == 0 {
                        self.appendReleaseLog("Existing release detected. Editing release.")
                        runReleaseCreateOrEdit(exists: true)
                        return
                    }
                    if self.isReleaseNotFoundError(viewOutput) {
                        self.appendReleaseLog("No release detected. Creating release.")
                        runReleaseCreateOrEdit(exists: false)
                        return
                    }

                    self.updateReleaseStatus(
                        success: false,
                        message: self.releaseFailureMessage(defaultMessage: "Release failed while checking whether the release exists.", output: viewOutput)
                    )
                }
            }

            if !token.isEmpty {
                continueWithReleaseCheck()
                return
            }

            self.runCommandCapture(
                [ghPath, "auth", "status", "--hostname", "github.com"],
                cwd: self.repoPath,
                label: "gh auth status",
                timeoutSeconds: 30,
                nonInteractive: true
            ) { authStatus, authOutput in
                guard authStatus == 0 else {
                    let detail = self.firstMeaningfulLine(authOutput)
                    let extra = detail.isEmpty ? "" : " (\(detail))"
                    self.updateReleaseStatus(
                        success: false,
                        message: "Release failed: GitHub CLI is not authenticated. Run gh auth login or paste a token in Tahera and retry.\(extra)"
                    )
                    return
                }
                continueWithReleaseCheck()
            }
        }
    }

    func loadReadme() {
        let readmePath = URL(fileURLWithPath: repoPath).appendingPathComponent("README.md").path
        do {
            let contents = try String(contentsOfFile: readmePath, encoding: .utf8)
            DispatchQueue.main.async {
                self.readmeContent = contents
            }
        } catch {
            DispatchQueue.main.async {
                self.readmeContent = "README.md could not be loaded from:\n\(readmePath)\n\n\(error.localizedDescription)"
            }
        }
    }

    private func controllerMappingRepoPath() -> String {
        URL(fileURLWithPath: repoPath)
            .appendingPathComponent("Pros projects/Tahera_Project")
            .appendingPathComponent(controllerMappingFileName)
            .path
    }

    private func portMapRepoPath() -> String {
        URL(fileURLWithPath: repoPath)
            .appendingPathComponent("Pros projects/Tahera_Project")
            .appendingPathComponent(portMapFileName)
            .path
    }

    private struct PortValuePayload: Codable {
        var value: Int
        var reversed: Bool
    }

    private struct PortMapPayload: Codable {
        var leftOuter1: PortValuePayload
        var leftOuter2: PortValuePayload
        var leftMiddle: PortValuePayload
        var rightOuter1: PortValuePayload
        var rightOuter2: PortValuePayload
        var rightMiddle: PortValuePayload
        var intakeLeft: PortValuePayload
        var intakeRight: PortValuePayload
        var imu: Int
        var gps: Int
    }

    private func payload(from map: PortMap) -> PortMapPayload {
        PortMapPayload(
            leftOuter1: PortValuePayload(value: map.leftOuter1.value, reversed: map.leftOuter1.reversed),
            leftOuter2: PortValuePayload(value: map.leftOuter2.value, reversed: map.leftOuter2.reversed),
            leftMiddle: PortValuePayload(value: map.leftMiddle.value, reversed: map.leftMiddle.reversed),
            rightOuter1: PortValuePayload(value: map.rightOuter1.value, reversed: map.rightOuter1.reversed),
            rightOuter2: PortValuePayload(value: map.rightOuter2.value, reversed: map.rightOuter2.reversed),
            rightMiddle: PortValuePayload(value: map.rightMiddle.value, reversed: map.rightMiddle.reversed),
            intakeLeft: PortValuePayload(value: map.intakeLeft.value, reversed: map.intakeLeft.reversed),
            intakeRight: PortValuePayload(value: map.intakeRight.value, reversed: map.intakeRight.reversed),
            imu: map.imu,
            gps: map.gps
        )
    }

    private func portMap(from payload: PortMapPayload) -> PortMap {
        PortMap(
            leftOuter1: PortValue(value: payload.leftOuter1.value, reversed: payload.leftOuter1.reversed),
            leftOuter2: PortValue(value: payload.leftOuter2.value, reversed: payload.leftOuter2.reversed),
            leftMiddle: PortValue(value: payload.leftMiddle.value, reversed: payload.leftMiddle.reversed),
            rightOuter1: PortValue(value: payload.rightOuter1.value, reversed: payload.rightOuter1.reversed),
            rightOuter2: PortValue(value: payload.rightOuter2.value, reversed: payload.rightOuter2.reversed),
            rightMiddle: PortValue(value: payload.rightMiddle.value, reversed: payload.rightMiddle.reversed),
            intakeLeft: PortValue(value: payload.intakeLeft.value, reversed: payload.intakeLeft.reversed),
            intakeRight: PortValue(value: payload.intakeRight.value, reversed: payload.intakeRight.reversed),
            imu: payload.imu,
            gps: payload.gps
        )
    }

    private func controllerMappingSDPath() -> String {
        URL(fileURLWithPath: sdPath)
            .appendingPathComponent(controllerMappingFileName)
            .path
    }

    private func parseControllerMapping(_ contents: String) -> (DriveControlMode, [ControllerAction: ControllerButton]) {
        var mode: DriveControlMode = .tank
        var mapping = Dictionary(uniqueKeysWithValues: ControllerAction.allCases.map { ($0, $0.defaultButton) })
        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            let parts = line.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            if parts.count != 2 {
                continue
            }
            if parts[0] == "DRIVE_MODE", let parsedMode = DriveControlMode(rawValue: parts[1]) {
                mode = parsedMode
                continue
            }
            guard let action = ControllerAction(rawValue: parts[0]),
                  let button = ControllerButton(rawValue: parts[1]) else {
                continue
            }
            mapping[action] = button
        }
        return (mode, mapping)
    }

    private func serializeControllerMapping() -> String {
        var lines: [String] = [
            "# Tahera controller mapping",
            "# Edit in Tahera app or manually. Format: ACTION=BUTTON (+ DRIVE_MODE)",
            "DRIVE_MODE=\(driveControlMode.rawValue)",
        ]
        for action in ControllerAction.allCases {
            let button = controllerMapping[action] ?? action.defaultButton
            lines.append("\(action.rawValue)=\(button.rawValue)")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private func loadControllerMapping(from path: String, sourceName: String) {
        do {
            let text = try String(contentsOfFile: path, encoding: .utf8)
            let parsed = parseControllerMapping(text)
            DispatchQueue.main.async {
                self.driveControlMode = parsed.0
                self.controllerMapping = parsed.1
                self.controllerMappingStatus = "Loaded from \(sourceName)"
            }
            appendLog("Controller mapping loaded from \(sourceName): \(path)")
        } catch {
            DispatchQueue.main.async {
                self.controllerMappingStatus = "Could not load from \(sourceName)"
            }
            appendLog("Controller mapping load failed (\(sourceName)): \(error.localizedDescription)")
        }
    }

    private func saveControllerMapping(to path: String, sourceName: String) {
        let payload = serializeControllerMapping()
        do {
            let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
            if !FileManager.default.fileExists(atPath: parent) {
                try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
            }
            try payload.write(toFile: path, atomically: true, encoding: .utf8)
            DispatchQueue.main.async {
                self.controllerMappingStatus = "Saved to \(sourceName)"
            }
            appendLog("Controller mapping saved to \(sourceName): \(path)")
        } catch {
            DispatchQueue.main.async {
                self.controllerMappingStatus = "Save failed for \(sourceName)"
            }
            appendLog("Controller mapping save failed (\(sourceName)): \(error.localizedDescription)")
        }
    }

    func resetControllerMappingDefaults() {
        DispatchQueue.main.async {
            self.driveControlMode = .tank
            self.controllerMapping = Dictionary(uniqueKeysWithValues: ControllerAction.allCases.map { ($0, $0.defaultButton) })
            self.controllerMappingStatus = "Reset to defaults"
        }
    }

    func loadControllerMappingFromRepo() {
        loadControllerMapping(from: controllerMappingRepoPath(), sourceName: "repo")
    }

    func saveControllerMappingToRepo() {
        saveControllerMapping(to: controllerMappingRepoPath(), sourceName: "repo")
    }

    func loadControllerMappingFromSD() {
        loadControllerMapping(from: controllerMappingSDPath(), sourceName: "SD")
    }

    func saveControllerMappingToSD() {
        saveControllerMapping(to: controllerMappingSDPath(), sourceName: "SD")
    }

    func loadPortMapFromRepo() {
        let path = portMapRepoPath()
        guard FileManager.default.fileExists(atPath: path) else {
            DispatchQueue.main.async {
                self.portMapStatus = "No saved port map found in repo"
            }
            return
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let decoded = try JSONDecoder().decode(PortMapPayload.self, from: data)
            DispatchQueue.main.async {
                self.portMap = self.portMap(from: decoded)
                self.portMapStatus = "Loaded from repo"
            }
            appendLog("Port map loaded from repo: \(path)")
        } catch {
            DispatchQueue.main.async {
                self.portMapStatus = "Load failed"
            }
            appendLog("Port map load failed: \(error.localizedDescription)")
        }
    }

    func savePortMapToRepo() {
        let path = portMapRepoPath()
        do {
            let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
            if !FileManager.default.fileExists(atPath: parent) {
                try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload(from: portMap))
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            DispatchQueue.main.async {
                self.portMapStatus = "Saved to repo"
            }
            appendLog("Port map saved to repo: \(path)")
        } catch {
            DispatchQueue.main.async {
                self.portMapStatus = "Save failed"
            }
            appendLog("Port map save failed: \(error.localizedDescription)")
        }
    }

    func controllerMappingConflicts() -> [(ControllerButton, [ControllerAction])] {
        var grouped: [ControllerButton: [ControllerAction]] = [:]
        for action in ControllerAction.allCases {
            let button = controllerMapping[action] ?? action.defaultButton
            grouped[button, default: []].append(action)
        }
        return grouped
            .filter { $0.value.count > 1 }
            .sorted { $0.key.rawValue < $1.key.rawValue }
    }

    func setControllerButton(_ button: ControllerButton, for action: ControllerAction) {
        var next = controllerMapping
        next[action] = button
        controllerMapping = next
    }
}
