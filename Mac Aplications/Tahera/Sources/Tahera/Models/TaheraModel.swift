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
        ProsProject(name: "Image Selector", relativePath: "Pros projects/Jerkbot_Image_Test", slot: 3),
        ProsProject(name: "Basic Bonkers", relativePath: "Pros projects/Basic_Bonkers_PROS", slot: 4)
    ]

    @Published var sdPath: String = "/Volumes/MICROBONK"
    @Published var sdMounted: Bool = false

    @Published var brainDetected: Bool = false
    @Published var brainPort: String = ""

    @Published var portMap: PortMap = PortMap()

    // Password wall for repository settings/GitHub tools.
    @Published var repoSettingsUnlocked: Bool = false
    @Published var repoSettingsPasswordInput: String = ""
    @Published var repoSettingsAuthError: String = ""

    @Published var gitCommitMessage: String = ""
    @Published var gitTag: String = ""
    @Published var gitTagMessage: String = ""
    @Published var gitReleaseTitle: String = ""
    @Published var gitReleaseNotes: String = ""
    @Published var releaseLog: String = ""
    @Published var releaseStatusMessage: String = ""
    @Published var releaseStatusIsSuccess: Bool = false

    private let repoSettingsPassword = "56Wrenches.782"
    private let busyQueue = DispatchQueue(label: "TaheraModel.BusyQueue")
    private var busyCount = 0

    init() {
        refreshSDStatus()
        refreshBrainStatus()
        loadReadme()
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
        URL(fileURLWithPath: repoPath).appendingPathComponent(project.relativePath).path
    }

    func build(project: ProsProject) {
        runCommand(["/usr/bin/env", "pros", "make"], cwd: projectPath(project), label: "pros make (\(project.name))")
    }

    func upload(project: ProsProject) {
        runCommand(["/usr/bin/env", "pros", "upload", "--slot", String(project.slot)], cwd: projectPath(project), label: "pros upload --slot \(project.slot) (\(project.name))")
    }

    func buildAndUpload(project: ProsProject) {
        let path = projectPath(project)
        runCommand(["/usr/bin/env", "pros", "make"], cwd: path, label: "pros make (\(project.name))") { status in
            if status == 0 {
                self.runCommand(["/usr/bin/env", "pros", "upload", "--slot", String(project.slot)], cwd: path, label: "pros upload --slot \(project.slot) (\(project.name))")
            }
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

        func lookupReleaseURL(attemptsRemaining: Int, completion: @escaping (String?) -> Void) {
            self.runCommandCapture(
                ["/usr/bin/env", "gh", "release", "view", t, "--json", "url", "--jq", ".url"],
                cwd: self.repoPath,
                label: "gh release url \(t)",
                timeoutSeconds: 30,
                nonInteractive: true
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
                primaryCmd = ["/usr/bin/env", "gh", "release", "edit", t, "--title", title, "--notes", notes]
                primaryLabel = "gh release edit \(t)"
                fallbackCmd = ["/usr/bin/env", "gh", "release", "create", t, "--title", title, "--notes", notes]
                fallbackLabel = "gh release create \(t)"
            } else {
                primaryCmd = ["/usr/bin/env", "gh", "release", "create", t, "--title", title, "--notes", notes]
                primaryLabel = "gh release create \(t)"
                fallbackCmd = ["/usr/bin/env", "gh", "release", "edit", t, "--title", title, "--notes", notes]
                fallbackLabel = "gh release edit \(t)"
            }

            self.runCommandCapture(primaryCmd, cwd: self.repoPath, label: primaryLabel, timeoutSeconds: 120, nonInteractive: true) { status, output in
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

                self.runCommandCapture(fallbackCmd, cwd: self.repoPath, label: fallbackLabel, timeoutSeconds: 120, nonInteractive: true) { fallbackStatus, fallbackOutput in
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

            self.runCommandCapture(
                ["/usr/bin/env", "gh", "auth", "status", "--hostname", "github.com"],
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
                        message: "Release failed: GitHub CLI is not authenticated. Run gh auth login and retry.\(extra)"
                    )
                    return
                }

                self.runCommandCapture(
                    ["/usr/bin/env", "gh", "release", "view", t, "--json", "id", "--jq", ".id"],
                    cwd: self.repoPath,
                    label: "gh release view \(t) --json id",
                    timeoutSeconds: 45,
                    nonInteractive: true
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
}
