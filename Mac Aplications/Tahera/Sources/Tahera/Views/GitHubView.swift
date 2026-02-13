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
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.text)
            Text("Enter the password to access repository settings.")
                .foregroundColor(Theme.subtext)
                .font(.system(size: 16, weight: .medium))
            SecureField("Password", text: $model.repoSettingsPasswordInput)
                .textFieldStyle(.roundedBorder)
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
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.text)
                TextField("Commit message", text: $model.gitCommitMessage)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Commit") { model.gitCommit() }
                    Button("Push") { model.gitPush() }
                }
                .disabled(model.isBusy)
            }

            Card {
                Text("Tag + Release")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.text)
                TextField("Tag", text: $model.gitTag)
                    .textFieldStyle(.roundedBorder)
                TextField("Tag message", text: $model.gitTagMessage)
                    .textFieldStyle(.roundedBorder)
                TextField("Release title", text: $model.gitReleaseTitle)
                    .textFieldStyle(.roundedBorder)
                TextEditor(text: $model.gitReleaseNotes)
                    .frame(height: 120)
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
                        .font(.system(size: 13, weight: .medium))
                }
            }
        }
    }
}
