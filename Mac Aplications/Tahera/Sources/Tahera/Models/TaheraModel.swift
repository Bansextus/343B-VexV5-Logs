import Foundation
import SwiftUI

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

    private let repoSettingsPassword = "56Wrenches.782"

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

    private func runCommand(
        _ cmd: [String],
        cwd: String? = nil,
        label: String,
        timeoutSeconds: TimeInterval = 240,
        nonInteractive: Bool = false,
        completion: ((Int32) -> Void)? = nil
    ) {
        isBusy = true
        appendLog("$ \(label)")

        DispatchQueue.global(qos: .userInitiated).async {
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
                DispatchQueue.main.async { self.isBusy = false }
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
                    break
                }
                Thread.sleep(forTimeInterval: 0.15)
            }
            process.waitUntilExit()
            handle.readabilityHandler = nil
            if didTimeout {
                self.appendLog("Failed: command timed out after \(Int(timeoutSeconds))s")
            }
            DispatchQueue.main.async { self.isBusy = false }
            completion?(didTimeout ? -2 : process.terminationStatus)
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
        runCommand(["/usr/bin/env", "gh", "release", "create", t, "--title", title, "--notes", gitReleaseNotes], cwd: repoPath, label: "gh release create", timeoutSeconds: 120, nonInteractive: true)
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
