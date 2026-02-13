import SwiftUI

struct GitHubView: View {
    @EnvironmentObject var model: TaheraModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PanelTitle(text: "Repository Settings", icon: "checkmark.shield.fill")

            if model.repoSettingsUnlocked {
                unlockedView
            } else {
                lockedView
            }
        }
        .buttonStyle(TaheraActionButtonStyle())
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var lockedView: some View {
        Card {
            Text("Locked")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.text)
            Text("Enter the password to access repository settings.")
                .foregroundColor(Theme.subtext)
                .font(.system(size: 19, weight: .medium))
            SecureField("Password", text: $model.repoSettingsPasswordInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .frame(maxWidth: 320)
            HStack {
                Button("Unlock") { model.unlockRepositorySettings() }
                if !model.repoSettingsAuthError.isEmpty {
                    Text(model.repoSettingsAuthError)
                        .foregroundColor(.red)
                }
            }
        }
    }

    private var unlockedView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Card {
                Text("Git Commit & Push")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.text)
                TextField("Commit message", text: $model.gitCommitMessage)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                HStack {
                    Button("Commit") { model.gitCommit() }
                    Button("Push") { model.gitPush() }
                }
                .disabled(model.isBusy)
            }

            Card {
                Text("Tag + Release")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.text)
                Text("GitHub Token (optional)")
                    .foregroundColor(Theme.subtext)
                    .font(.system(size: 16, weight: .semibold))
                SecureField("ghp_xxx...", text: $model.githubToken)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 16, weight: .regular, design: .monospaced))
                TextField("Tag", text: $model.gitTag)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                TextField("Tag message", text: $model.gitTagMessage)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                TextField("Release title", text: $model.gitReleaseTitle)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                TextEditor(text: $model.gitReleaseNotes)
                    .frame(height: 120)
                    .font(.system(size: 17, weight: .regular, design: .monospaced))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.15), lineWidth: 1))
                HStack {
                    Button("Tag + Push") { model.gitTagAndPush() }
                    Button("Create Release") { model.githubRelease() }
                    Button("Lock") { model.lockRepositorySettings() }
                }
                .disabled(model.isBusy)

                if model.isBusy {
                    Text("Running repository command...")
                        .foregroundColor(Theme.subtext)
                        .font(.system(size: 16, weight: .medium))
                }

                if !model.releaseStatusMessage.isEmpty {
                    Text(model.releaseStatusMessage)
                        .foregroundColor(model.releaseStatusIsSuccess ? Theme.accent : .red)
                        .font(.system(size: 17, weight: .semibold))
                }
            }

            Card {
                HStack {
                    Text("Release Log")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.text)
                    Spacer()
                    Button("Clear Log") { model.clearReleaseLog() }
                        .disabled(model.isBusy)
                }

                ScrollView {
                    Text(model.releaseLog.isEmpty ? "No release events yet." : model.releaseLog)
                        .foregroundColor(Theme.subtext)
                        .font(.system(size: 15, weight: .regular, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 150)
            }
        }
    }
}
