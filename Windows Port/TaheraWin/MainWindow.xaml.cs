using Microsoft.Win32;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Tahera {
    public partial class MainWindow : Window {
        private const string RepoSettingsPassword = "56Wrenches.782";
        private const double ReplayFieldSizeIn = 144.0;
        private const double ReplayTrackWidthIn = 12.0;
        private const double ReplayMaxSpeedInPerS = 60.0;
        private const double ReplayDtFallback = 0.02;
        private static readonly double[] TopPortX = { 0.162, 0.225, 0.289, 0.351, 0.414, 0.508, 0.571, 0.634, 0.697, 0.760 };
        private static readonly double[] BottomPortX = { 0.162, 0.225, 0.289, 0.351, 0.414, 0.508, 0.571, 0.634, 0.697, 0.760 };
        private const double TopPortY = 0.086;
        private const double BottomPortY = 0.922;

        private bool _repoUnlocked = false;
        private bool _suppressReplaySliderEvent = false;
        private int _repoBusyCount = 0;
        private readonly List<ReplayPose> _replayPoses = new();
        private readonly List<PortAssignment> _portAssignments = new() {
            new("L1", "Left Outer 1", 1, Color.FromRgb(64, 220, 198)),
            new("L2", "Left Outer 2", 3, Color.FromRgb(87, 200, 255)),
            new("LM", "Left Middle", 2, Color.FromRgb(124, 216, 255)),
            new("R1", "Right Outer 1", 4, Color.FromRgb(123, 255, 158)),
            new("R2", "Right Outer 2", 6, Color.FromRgb(155, 255, 131)),
            new("RM", "Right Middle", 5, Color.FromRgb(197, 255, 122)),
            new("IN", "Intake", 7, Color.FromRgb(255, 202, 111)),
            new("OUT", "Outake", 8, Color.FromRgb(255, 167, 106)),
            new("IMU", "Inertial", 11, Color.FromRgb(212, 194, 255)),
            new("GPS", "GPS", 10, Color.FromRgb(255, 193, 234))
        };

        private readonly Dictionary<string, (string path, int slot)> _projects = new() {
            { "The Tahera Sequence", ("Pros projects/Tahera_Project", 1) },
            { "Auton Planner", ("Pros projects/Auton_Planner_PROS", 2) },
            { "Image Selector", ("Pros projects/Jerkbot_Image_Test", 3) },
            { "Basic Bonkers", ("Pros projects/Basic_Bonkers_PROS", 4) }
        };

        public MainWindow() {
            InitializeComponent();
            RepoPathTextBox.Text = @"C:\Users\Public\GitHub\2026-Vex-V5-Pushback-Code-and-Desighn-";
            ProjectComboBox.ItemsSource = _projects.Keys;
            ProjectComboBox.SelectedIndex = 0;
            ShowSection("Home");

            LoadReadme();
            LoadReadmeLogo();
            LoadFieldImage();
            LoadPortBrainImage();
            RedrawPortMapOverlay();
            ResetReplayState("Load a replay log (.txt or .csv) to visualize path data.");
            UpdateRepoBusyUi();
        }

        private string RepoPath => RepoPathTextBox.Text.Trim();

        private async Task<(int code, string output)> RunCommandAsync(
            string fileName,
            IEnumerable<string> args,
            string? workingDirectory = null,
            int timeoutSeconds = 180,
            bool nonInteractive = false
        ) {
            var psi = new ProcessStartInfo(fileName) {
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                RedirectStandardInput = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            foreach (var arg in args) {
                psi.ArgumentList.Add(arg);
            }

            if (!string.IsNullOrWhiteSpace(workingDirectory)) {
                psi.WorkingDirectory = workingDirectory;
            }
            if (nonInteractive) {
                // Avoid hangs from credential/password prompts in GUI workflows.
                psi.Environment["GIT_TERMINAL_PROMPT"] = "0";
                psi.Environment["GCM_INTERACTIVE"] = "Never";
                psi.Environment["GH_PROMPT_DISABLED"] = "1";
                psi.Environment["CI"] = "1";
            }

            var sb = new StringBuilder();
            using var p = new Process { StartInfo = psi };
            p.OutputDataReceived += (_, e) => { if (e.Data != null) sb.AppendLine(e.Data); };
            p.ErrorDataReceived += (_, e) => { if (e.Data != null) sb.AppendLine(e.Data); };

            p.Start();
            p.StandardInput.Close();
            p.BeginOutputReadLine();
            p.BeginErrorReadLine();
            var waitTask = p.WaitForExitAsync();
            var completed = await Task.WhenAny(waitTask, Task.Delay(TimeSpan.FromSeconds(timeoutSeconds)));
            if (completed != waitTask) {
                try {
                    p.Kill(entireProcessTree: true);
                } catch {
                    // Best effort kill only.
                }
                sb.AppendLine($"Failed: command timed out after {timeoutSeconds}s.");
                return (-2, sb.ToString());
            }
            return (p.ExitCode, sb.ToString());
        }

        private void AppendOutput(string text) {
            OutputTextBox.AppendText(text + Environment.NewLine);
            OutputTextBox.ScrollToEnd();
        }

        private void AppendReleaseLog(string text) {
            var line = $"[{DateTimeOffset.Now:yyyy-MM-ddTHH:mm:sszzz}] {text}";
            ReleaseLogTextBox.AppendText(line + Environment.NewLine);
            ReleaseLogTextBox.ScrollToEnd();
        }

        private void SetReleaseStatus(bool? success, string message) {
            ReleaseStatusText.Text = message;
            if (success == true) {
                ReleaseStatusText.Foreground = new SolidColorBrush(Color.FromRgb(76, 215, 168));
            } else if (success == false) {
                ReleaseStatusText.Foreground = new SolidColorBrush(Color.FromRgb(255, 110, 110));
            } else {
                ReleaseStatusText.Foreground = (Brush)FindResource("SubBrush");
            }
        }

        private bool IsRepoBusy => _repoBusyCount > 0;

        private void BeginRepoAction() {
            _repoBusyCount++;
            UpdateRepoBusyUi();
        }

        private void EndRepoAction() {
            _repoBusyCount = Math.Max(0, _repoBusyCount - 1);
            UpdateRepoBusyUi();
        }

        private void UpdateRepoBusyUi() {
            var busy = IsRepoBusy;
            RepoBusyText.Visibility = busy ? Visibility.Visible : Visibility.Collapsed;
            GitCommitButton.IsEnabled = !busy;
            GitPushButton.IsEnabled = !busy;
            GitTagPushButton.IsEnabled = !busy;
            GitCreateReleaseButton.IsEnabled = !busy;
            GitLockButton.IsEnabled = !busy;
            ClearReleaseLogButton.IsEnabled = !busy;
        }

        private void ShowSection(string tag) {
            HomePanel.Visibility = Visibility.Collapsed;
            BuildPanel.Visibility = Visibility.Collapsed;
            PortPanel.Visibility = Visibility.Collapsed;
            SdPanel.Visibility = Visibility.Collapsed;
            FieldPanel.Visibility = Visibility.Collapsed;
            ReadmePanel.Visibility = Visibility.Collapsed;
            GitPanel.Visibility = Visibility.Collapsed;

            switch (tag) {
                case "Build":
                    BuildPanel.Visibility = Visibility.Visible;
                    break;
                case "Port":
                    PortPanel.Visibility = Visibility.Visible;
                    LoadPortBrainImage();
                    RedrawPortMapOverlay();
                    break;
                case "Sd":
                    SdPanel.Visibility = Visibility.Visible;
                    break;
                case "Field":
                    FieldPanel.Visibility = Visibility.Visible;
                    break;
                case "Readme":
                    ReadmePanel.Visibility = Visibility.Visible;
                    LoadReadme();
                    LoadReadmeLogo();
                    break;
                case "Git":
                    GitPanel.Visibility = Visibility.Visible;
                    break;
                default:
                    HomePanel.Visibility = Visibility.Visible;
                    break;
            }
        }

        private void SectionButton_Click(object sender, RoutedEventArgs e) {
            if (sender is FrameworkElement el && el.Tag is string tag) {
                ShowSection(tag);
            }
        }

        private (string name, string path, int slot)? SelectedProject() {
            if (ProjectComboBox.SelectedItem is not string name) return null;
            if (!_projects.TryGetValue(name, out var data)) return null;
            return (name, System.IO.Path.Combine(RepoPath, data.path), data.slot);
        }

        private async void Build_Click(object sender, RoutedEventArgs e) {
            var p = SelectedProject();
            if (p == null) return;
            AppendOutput($"$ pros make ({p.Value.name})");
            var result = await RunCommandAsync("pros", new[] { "make" }, p.Value.path, timeoutSeconds: 600);
            AppendOutput(result.output);
        }

        private async void Upload_Click(object sender, RoutedEventArgs e) {
            var p = SelectedProject();
            if (p == null) return;
            AppendOutput($"$ pros upload --slot {p.Value.slot} ({p.Value.name})");
            var result = await RunCommandAsync("pros", new[] { "upload", "--slot", p.Value.slot.ToString(CultureInfo.InvariantCulture) }, p.Value.path, timeoutSeconds: 600);
            AppendOutput(result.output);
        }

        private async void BuildUpload_Click(object sender, RoutedEventArgs e) {
            var p = SelectedProject();
            if (p == null) return;
            AppendOutput($"$ pros make ({p.Value.name})");
            var build = await RunCommandAsync("pros", new[] { "make" }, p.Value.path, timeoutSeconds: 600);
            AppendOutput(build.output);
            if (build.code == 0) {
                AppendOutput($"$ pros upload --slot {p.Value.slot} ({p.Value.name})");
                var upload = await RunCommandAsync("pros", new[] { "upload", "--slot", p.Value.slot.ToString(CultureInfo.InvariantCulture) }, p.Value.path, timeoutSeconds: 600);
                AppendOutput(upload.output);
            }
        }

        private void UnlockRepoSettings_Click(object sender, RoutedEventArgs e) {
            var entered = RepoSettingsPasswordBox.Password.Trim();
            if (entered == RepoSettingsPassword) {
                _repoUnlocked = true;
                GitLockedPanel.Visibility = Visibility.Collapsed;
                GitUnlockedPanel.Visibility = Visibility.Visible;
                AuthErrorText.Text = "";
                RepoSettingsPasswordBox.Password = "";
                AppendOutput("Repository settings unlocked");
            } else {
                AuthErrorText.Text = "Incorrect password";
            }
        }

        private void LockRepoSettings_Click(object sender, RoutedEventArgs e) {
            _repoUnlocked = false;
            GitUnlockedPanel.Visibility = Visibility.Collapsed;
            GitLockedPanel.Visibility = Visibility.Visible;
            AuthErrorText.Text = "";
        }

        private bool EnsureUnlocked() {
            if (_repoUnlocked) return true;
            MessageBox.Show("Repository settings are locked.");
            return false;
        }

        private async void GitCommit_Click(object sender, RoutedEventArgs e) {
            if (!EnsureUnlocked()) return;
            if (IsRepoBusy) return;
            var msg = CommitMessageTextBox.Text.Trim();
            if (msg.Length == 0) return;
            BeginRepoAction();
            try {
                AppendOutput("$ git add -A");
                var addRes = await RunCommandAsync("git", new[] { "add", "-A" }, RepoPath, timeoutSeconds: 60, nonInteractive: true);
                AppendOutput(addRes.output);
                if (addRes.code != 0) return;
                AppendOutput("$ git commit");
                var result = await RunCommandAsync("git", new[] { "commit", "-m", msg }, RepoPath, timeoutSeconds: 90, nonInteractive: true);
                AppendOutput(result.output);
            } finally {
                EndRepoAction();
            }
        }

        private async void GitPush_Click(object sender, RoutedEventArgs e) {
            if (!EnsureUnlocked()) return;
            if (IsRepoBusy) return;
            BeginRepoAction();
            try {
                AppendOutput("$ git push");
                var result = await RunCommandAsync("git", new[] { "push" }, RepoPath, timeoutSeconds: 90, nonInteractive: true);
                AppendOutput(result.output);
            } finally {
                EndRepoAction();
            }
        }

        private async void GitTagPush_Click(object sender, RoutedEventArgs e) {
            if (!EnsureUnlocked()) return;
            if (IsRepoBusy) return;
            var tag = TagTextBox.Text.Trim();
            if (tag.Length == 0) return;
            var msg = TagMessageTextBox.Text.Trim();
            if (msg.Length == 0) msg = tag;
            BeginRepoAction();
            try {
                AppendOutput("$ git tag");
                var tagRes = await RunCommandAsync("git", new[] { "tag", "-a", tag, "-m", msg }, RepoPath, timeoutSeconds: 60, nonInteractive: true);
                AppendOutput(tagRes.output);
                if (tagRes.code != 0) return;
                AppendOutput("$ git push --tags");
                var pushRes = await RunCommandAsync("git", new[] { "push", "--tags" }, RepoPath, timeoutSeconds: 90, nonInteractive: true);
                AppendOutput(pushRes.output);
            } finally {
                EndRepoAction();
            }
        }

        private async void GitRelease_Click(object sender, RoutedEventArgs e) {
            if (!EnsureUnlocked()) return;
            if (IsRepoBusy) return;
            var tag = TagTextBox.Text.Trim();
            if (tag.Length == 0) return;
            var title = ReleaseTitleTextBox.Text.Trim();
            if (title.Length == 0) title = tag;
            var notes = ReleaseNotesTextBox.Text;
            SetReleaseStatus(null, $"Starting release for tag {tag}...");
            AppendReleaseLog($"Starting release flow for tag {tag}.");

            BeginRepoAction();
            try {
                async Task<bool> RunReleaseCommandWithFallbackAsync(bool releaseExists) {
                    var primaryArgs = releaseExists
                        ? new[] { "release", "edit", tag, "--title", title, "--notes", notes }
                        : new[] { "release", "create", tag, "--title", title, "--notes", notes };
                    var primaryLabel = releaseExists ? "gh release edit" : "gh release create";

                    AppendOutput($"$ {primaryLabel}");
                    var primaryRes = await RunCommandAsync("gh", primaryArgs, RepoPath, timeoutSeconds: 120, nonInteractive: true);
                    AppendOutput(primaryRes.output);
                    if (primaryRes.code == 0) {
                        return true;
                    }

                    var shouldFallback = releaseExists
                        ? IsReleaseNotFoundError(primaryRes.output)
                        : IsReleaseAlreadyExistsError(primaryRes.output);

                    if (!shouldFallback) {
                        var fail = ReleaseFailureMessage($"Release failed during {primaryLabel} {tag}.", primaryRes.output);
                        AppendReleaseLog(fail);
                        SetReleaseStatus(false, fail);
                        MessageBox.Show(fail, "Release Failed", MessageBoxButton.OK, MessageBoxImage.Error);
                        return false;
                    }

                    var fallbackArgs = releaseExists
                        ? new[] { "release", "create", tag, "--title", title, "--notes", notes }
                        : new[] { "release", "edit", tag, "--title", title, "--notes", notes };
                    var fallbackLabel = releaseExists ? "gh release create" : "gh release edit";
                    AppendReleaseLog(releaseExists
                        ? "Edit reported release missing. Retrying create."
                        : "Create reported existing release. Retrying edit.");

                    AppendOutput($"$ {fallbackLabel}");
                    var fallbackRes = await RunCommandAsync("gh", fallbackArgs, RepoPath, timeoutSeconds: 120, nonInteractive: true);
                    AppendOutput(fallbackRes.output);
                    if (fallbackRes.code == 0) {
                        return true;
                    }

                    var fallbackFail = ReleaseFailureMessage($"Release failed during {fallbackLabel} {tag}.", fallbackRes.output);
                    AppendReleaseLog(fallbackFail);
                    SetReleaseStatus(false, fallbackFail);
                    MessageBox.Show(fallbackFail, "Release Failed", MessageBoxButton.OK, MessageBoxImage.Error);
                    return false;
                }

                async Task<string?> LookupReleaseUrlAsync(int attemptsRemaining) {
                    AppendOutput("$ gh release url");
                    var urlRes = await RunCommandAsync("gh", new[] { "release", "view", tag, "--json", "url", "--jq", ".url" }, RepoPath, timeoutSeconds: 30, nonInteractive: true);
                    AppendOutput(urlRes.output);
                    var releaseUrl = FirstNonEmptyLine(urlRes.output);
                    if (urlRes.code == 0 && !string.IsNullOrWhiteSpace(releaseUrl)) {
                        return releaseUrl;
                    }
                    if (attemptsRemaining > 1) {
                        await Task.Delay(1000);
                        return await LookupReleaseUrlAsync(attemptsRemaining - 1);
                    }
                    return null;
                }

                AppendOutput("$ git push --tags");
                var pushTags = await RunCommandAsync("git", new[] { "push", "--tags" }, RepoPath, timeoutSeconds: 90, nonInteractive: true);
                AppendOutput(pushTags.output);
                if (pushTags.code != 0) {
                    var fail = ReleaseFailureMessage("Release failed: unable to push tags to origin.", pushTags.output);
                    AppendOutput(fail);
                    AppendReleaseLog(fail);
                    SetReleaseStatus(false, fail);
                    MessageBox.Show(fail, "Release Failed", MessageBoxButton.OK, MessageBoxImage.Error);
                    return;
                }
                AppendReleaseLog("Tags pushed to origin.");

                AppendOutput("$ gh auth status");
                var auth = await RunCommandAsync("gh", new[] { "auth", "status", "--hostname", "github.com" }, RepoPath, timeoutSeconds: 30, nonInteractive: true);
                AppendOutput(auth.output);
                if (auth.code != 0) {
                    var fail = ReleaseFailureMessage("Release failed: GitHub CLI is not authenticated. Run gh auth login and retry.", auth.output);
                    AppendReleaseLog(fail);
                    SetReleaseStatus(false, fail);
                    MessageBox.Show(fail, "Release Failed", MessageBoxButton.OK, MessageBoxImage.Error);
                    return;
                }

                AppendOutput($"$ gh release view {tag} --json id");
                var existing = await RunCommandAsync("gh", new[] { "release", "view", tag, "--json", "id", "--jq", ".id" }, RepoPath, timeoutSeconds: 45, nonInteractive: true);
                AppendOutput(existing.output);
                var releaseExists = false;
                if (existing.code == 0) {
                    releaseExists = true;
                    AppendReleaseLog("Existing release detected. Editing release.");
                } else if (IsReleaseNotFoundError(existing.output)) {
                    AppendReleaseLog("No release detected. Creating release.");
                } else {
                    var fail = ReleaseFailureMessage("Release failed while checking whether the release exists.", existing.output);
                    AppendReleaseLog(fail);
                    SetReleaseStatus(false, fail);
                    MessageBox.Show(fail, "Release Failed", MessageBoxButton.OK, MessageBoxImage.Error);
                    return;
                }

                if (!await RunReleaseCommandWithFallbackAsync(releaseExists)) {
                    return;
                }

                AppendReleaseLog("Release command completed.");
                var releaseUrl = await LookupReleaseUrlAsync(3);
                var successMsg = !string.IsNullOrWhiteSpace(releaseUrl)
                    ? $"Release succeeded: {releaseUrl}"
                    : $"Release succeeded for tag {tag}, but URL lookup failed.";
                AppendReleaseLog(successMsg);
                SetReleaseStatus(true, successMsg);
                MessageBox.Show(successMsg, "Release Succeeded", MessageBoxButton.OK, MessageBoxImage.Information);
            } finally {
                EndRepoAction();
            }
        }

        private void ClearReleaseLog_Click(object sender, RoutedEventArgs e) {
            ReleaseLogTextBox.Clear();
        }

        private void ReadmeRefresh_Click(object sender, RoutedEventArgs e) {
            LoadReadme();
            LoadReadmeLogo();
        }

        private void OpenReadmeFile_Click(object sender, RoutedEventArgs e) {
            try {
                var readmePath = Path.Combine(RepoPath, "README.md");
                if (System.IO.File.Exists(readmePath)) {
                    Process.Start(new ProcessStartInfo(readmePath) { UseShellExecute = true });
                } else {
                    MessageBox.Show($"README not found:\n{readmePath}");
                }
            } catch (Exception ex) {
                MessageBox.Show($"Failed to open README: {ex.Message}");
            }
        }

        private void LoadReadme() {
            try {
                var readmePath = Path.Combine(RepoPath, "README.md");
                ReadmeTextBox.Text = File.Exists(readmePath)
                    ? System.IO.File.ReadAllText(readmePath)
                    : $"README.md not found:\n{readmePath}";
            } catch (Exception ex) {
                ReadmeTextBox.Text = $"Failed to load README:\n{ex.Message}";
            }
        }

        private void LoadReadmeLogo() {
            var fromDesign = System.IO.Path.Combine(RepoPath, "Developer Extras", "Designs", "tahera logo.png");
            var fromRepo = System.IO.Path.Combine(RepoPath, "Mac Aplications", "Tahera", "Sources", "Tahera", "Resources", "tahera_logo.png");
            var fromOutput = System.IO.Path.Combine(AppContext.BaseDirectory, "Resources", "tahera_logo.png");
            var logo = LoadBitmap(firstExisting(fromDesign, fromRepo, fromOutput));
            if (logo != null) {
                ReadmeLogoImage.Source = logo;
                SidebarLogoImage.Source = logo;
                Icon = logo;
            }
        }

        private void LoadFieldImage() {
            var fromRepo = System.IO.Path.Combine(RepoPath, "Developer Extras", "Designs", "Feild.png");
            var fromOutput = System.IO.Path.Combine(AppContext.BaseDirectory, "Resources", "field.png");
            var bitmap = LoadBitmap(firstExisting(fromRepo, fromOutput));
            if (bitmap != null) {
                FieldImage.Source = bitmap;
            }
        }

        private void LoadPortBrainImage() {
            var fromRepo = System.IO.Path.Combine(RepoPath, "Mac Aplications", "Tahera", "Sources", "Tahera", "Resources", "v5_brain.png");
            var fromOutput = System.IO.Path.Combine(AppContext.BaseDirectory, "Resources", "v5_brain.png");
            var bitmap = LoadBitmap(firstExisting(fromRepo, fromOutput));
            if (bitmap != null) {
                PortBrainImage.Source = bitmap;
            }
        }

        private void ShowPortNumbers_Changed(object sender, RoutedEventArgs e) {
            RedrawPortMapOverlay();
        }

        private void PortMapOverlay_SizeChanged(object sender, SizeChangedEventArgs e) {
            RedrawPortMapOverlay();
        }

        private void RedrawPortMapOverlay() {
            PortMapOverlay.Children.Clear();
            if (PortMapOverlay.ActualWidth < 2 || PortMapOverlay.ActualHeight < 2) return;

            var width = PortMapOverlay.ActualWidth;
            var height = PortMapOverlay.ActualHeight;

            if (ShowPortNumbersCheckBox.IsChecked == true) {
                for (var port = 1; port <= 20; port++) {
                    DrawPortNumber(port, SocketPoint(port, width, height));
                }
            }

            var grouped = _portAssignments
                .GroupBy(assignment => assignment.Port)
                .OrderBy(group => group.Key);

            foreach (var group in grouped) {
                var anchor = SocketPoint(group.Key, width, height);
                DrawAnchorDot(anchor);

                var list = group.ToList();
                for (var index = 0; index < list.Count; index++) {
                    var assignment = list[index];
                    var offset = MarkerOffset(index, list.Count);
                    var markerCenter = new Point(anchor.X + offset.X, anchor.Y + offset.Y);
                    DrawAssignmentMarker(assignment, markerCenter);
                }
            }
        }

        private void DrawPortNumber(int port, Point center) {
            var label = new Border {
                Background = new SolidColorBrush(Color.FromArgb(150, 0, 0, 0)),
                CornerRadius = new CornerRadius(10),
                Padding = new Thickness(6, 2, 6, 2)
            };
            label.Child = new TextBlock {
                Text = port.ToString(CultureInfo.InvariantCulture),
                Foreground = new SolidColorBrush(Color.FromRgb(231, 238, 247)),
                FontWeight = FontWeights.Bold,
                FontSize = 13
            };

            label.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
            var desired = label.DesiredSize;
            Canvas.SetLeft(label, center.X - desired.Width / 2.0);
            Canvas.SetTop(label, center.Y - desired.Height / 2.0);
            PortMapOverlay.Children.Add(label);
        }

        private void DrawAnchorDot(Point center) {
            var dot = new System.Windows.Shapes.Ellipse {
                Width = 8,
                Height = 8,
                Fill = new SolidColorBrush(Color.FromRgb(252, 239, 199))
            };
            Canvas.SetLeft(dot, center.X - dot.Width / 2.0);
            Canvas.SetTop(dot, center.Y - dot.Height / 2.0);
            PortMapOverlay.Children.Add(dot);
        }

        private void DrawAssignmentMarker(PortAssignment assignment, Point center) {
            var label = new Border {
                Background = new SolidColorBrush(assignment.Color),
                BorderBrush = new SolidColorBrush(Color.FromArgb(220, 255, 255, 255)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(12),
                Padding = new Thickness(10, 5, 10, 5)
            };
            label.Child = new TextBlock {
                Text = assignment.Short,
                Foreground = new SolidColorBrush(Color.FromRgb(18, 28, 40)),
                FontWeight = FontWeights.Bold,
                FontSize = 14
            };

            label.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
            var desired = label.DesiredSize;
            Canvas.SetLeft(label, center.X - desired.Width / 2.0);
            Canvas.SetTop(label, center.Y - desired.Height / 2.0);
            PortMapOverlay.Children.Add(label);
        }

        private static Point SocketPoint(int port, double width, double height) {
            var clampedPort = Math.Clamp(port, 1, 20);
            var index = (clampedPort - 1) % 10;
            var isTop = clampedPort <= 10;
            var xRatio = isTop ? TopPortX[index] : BottomPortX[index];
            var yRatio = isTop ? TopPortY : BottomPortY;
            return new Point(width * xRatio, height * yRatio);
        }

        private static Vector MarkerOffset(int index, int total) {
            if (total <= 1) return new Vector(0, 0);
            var radius = total == 2 ? 22.0 : 30.0;
            var angle = ((double)index / total) * Math.PI * 2.0 - (Math.PI / 2.0);
            return new Vector(Math.Cos(angle) * radius, Math.Sin(angle) * radius);
        }

        private void OpenReplayFile_Click(object sender, RoutedEventArgs e) {
            var dialog = new OpenFileDialog {
                Filter = "Log Files (*.txt;*.csv)|*.txt;*.csv|All Files (*.*)|*.*",
                Multiselect = false
            };
            if (dialog.ShowDialog(this) == true) {
                LoadReplayFile(dialog.FileName);
            }
        }

        private void ClearReplay_Click(object sender, RoutedEventArgs e) {
            ResetReplayState("Load a replay log (.txt or .csv) to visualize path data.");
            RedrawReplayOverlay();
        }

        private void ReplaySlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e) {
            if (_suppressReplaySliderEvent) return;
            if (_replayPoses.Count == 0) return;
            RedrawReplayOverlay();
            UpdateReplayReadout();
        }

        private void FieldOverlay_SizeChanged(object sender, SizeChangedEventArgs e) {
            RedrawReplayOverlay();
        }

        private void LoadReplayFile(string path) {
            try {
                var samples = ParseReplayLog(path);
                _replayPoses.Clear();
                _replayPoses.AddRange(IntegrateReplay(samples));

                ReplayFileText.Text = System.IO.Path.GetFileName(path);
                _suppressReplaySliderEvent = true;
                ReplaySlider.Minimum = 0;
                ReplaySlider.Maximum = Math.Max(_replayPoses.Count - 1, 0);
                ReplaySlider.Value = ReplaySlider.Maximum;
                _suppressReplaySliderEvent = false;

                RedrawReplayOverlay();
                UpdateReplayReadout();
            } catch (Exception ex) {
                ResetReplayState($"Failed to load replay file: {ex.Message}");
                RedrawReplayOverlay();
            }
        }

        private void ResetReplayState(string readout) {
            _replayPoses.Clear();
            ReplayFileText.Text = "No replay file loaded";
            _suppressReplaySliderEvent = true;
            ReplaySlider.Minimum = 0;
            ReplaySlider.Maximum = 0;
            ReplaySlider.Value = 0;
            _suppressReplaySliderEvent = false;
            ReplayReadoutText.Text = readout;
        }

        private void RedrawReplayOverlay() {
            FieldOverlay.Children.Clear();
            if (_replayPoses.Count == 0) return;
            if (FieldOverlay.ActualWidth < 2 || FieldOverlay.ActualHeight < 2) return;

            var idx = Math.Clamp((int)Math.Round(ReplaySlider.Value), 0, _replayPoses.Count - 1);
            var width = FieldOverlay.ActualWidth;
            var height = FieldOverlay.ActualHeight;

            var line = new System.Windows.Shapes.Polyline {
                Stroke = new SolidColorBrush(Color.FromRgb(76, 215, 168)),
                StrokeThickness = 2.4,
                StrokeLineJoin = PenLineJoin.Round
            };

            for (var i = 0; i <= idx; i++) {
                line.Points.Add(ToCanvasPoint(_replayPoses[i], width, height));
            }

            if (line.Points.Count > 1) {
                FieldOverlay.Children.Add(line);
            }

            var pose = _replayPoses[idx];
            var center = ToCanvasPoint(pose, width, height);
            var headingLen = Math.Max(12.0, width * 0.03);
            var heading = new Point(
                center.X + Math.Cos(pose.Theta) * headingLen,
                center.Y - Math.Sin(pose.Theta) * headingLen
            );

            var marker = new System.Windows.Shapes.Ellipse {
                Width = 10,
                Height = 10,
                Fill = new SolidColorBrush(Color.FromRgb(255, 109, 90))
            };
            Canvas.SetLeft(marker, center.X - marker.Width / 2.0);
            Canvas.SetTop(marker, center.Y - marker.Height / 2.0);
            FieldOverlay.Children.Add(marker);

            var headingLine = new System.Windows.Shapes.Line {
                X1 = center.X,
                Y1 = center.Y,
                X2 = heading.X,
                Y2 = heading.Y,
                Stroke = new SolidColorBrush(Color.FromRgb(252, 239, 199)),
                StrokeThickness = 2.0
            };
            FieldOverlay.Children.Add(headingLine);
        }

        private void UpdateReplayReadout() {
            if (_replayPoses.Count == 0) {
                ReplayReadoutText.Text = "No replay data loaded.";
                return;
            }

            var idx = Math.Clamp((int)Math.Round(ReplaySlider.Value), 0, _replayPoses.Count - 1);
            var pose = _replayPoses[idx];

            ReplayReadoutText.Text = string.Format(
                CultureInfo.InvariantCulture,
                "frame={0}/{1}  t={2:0.00}s  x={3:0.0}in  y={4:0.0}in\nleft={5:0} right={6:0}\na1={7:0} a2={8:0} a3={9:0} a4={10:0}\nlast={11}",
                idx + 1,
                _replayPoses.Count,
                pose.T,
                pose.X,
                pose.Y,
                pose.LeftCmd,
                pose.RightCmd,
                pose.Axis1,
                pose.Axis2,
                pose.Axis3,
                pose.Axis4,
                pose.Action
            );
        }

        private static string FirstNonEmptyLine(string output) {
            foreach (var line in output.Split(new[] { "\r\n", "\n" }, StringSplitOptions.None)) {
                var trimmed = line.Trim();
                if (trimmed.Length > 0) return trimmed;
            }
            return string.Empty;
        }

        private static bool IsReleaseNotFoundError(string output) {
            var lower = output.ToLowerInvariant();
            return lower.Contains("release not found") || (lower.Contains("not found") && lower.Contains("release"));
        }

        private static bool IsReleaseAlreadyExistsError(string output) {
            var lower = output.ToLowerInvariant();
            return lower.Contains("already exists") || lower.Contains("already a release");
        }

        private static string ReleaseFailureMessage(string defaultMessage, string output) {
            var detail = FirstNonEmptyLine(output);
            return detail.Length == 0 ? defaultMessage : $"{defaultMessage} {detail}";
        }

        private static string? firstExisting(params string[] candidates) {
            foreach (var candidate in candidates) {
                if (File.Exists(candidate)) return candidate;
            }
            return null;
        }

        private static BitmapImage? LoadBitmap(string? path) {
            if (string.IsNullOrWhiteSpace(path) || !System.IO.File.Exists(path)) return null;
            var image = new BitmapImage();
            image.BeginInit();
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.UriSource = new Uri(path, UriKind.Absolute);
            image.EndInit();
            image.Freeze();
            return image;
        }

        private static Point ToCanvasPoint(ReplayPose pose, double width, double height) {
            var x = (pose.X / ReplayFieldSizeIn) * width;
            var y = ((ReplayFieldSizeIn - pose.Y) / ReplayFieldSizeIn) * height;
            return new Point(x, y);
        }

        private static List<ReplaySample> ParseReplayLog(string path) {
            var lines = System.IO.File.ReadAllLines(path);
            if (lines.Length == 0) return new List<ReplaySample>();
            if (lines[0].Contains("time_s", StringComparison.OrdinalIgnoreCase)) {
                return ParseReplayCsv(lines);
            }
            return ParseReplayEvents(lines);
        }

        private static List<ReplaySample> ParseReplayCsv(string[] lines) {
            var headers = lines[0].Split(',');
            var index = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            for (var i = 0; i < headers.Length; i++) {
                index[headers[i].Trim()] = i;
            }

            string get(string[] cols, string key) {
                return index.TryGetValue(key, out var idx) && idx < cols.Length ? cols[idx].Trim() : string.Empty;
            }

            var result = new List<ReplaySample>();
            for (var i = 1; i < lines.Length; i++) {
                if (string.IsNullOrWhiteSpace(lines[i])) continue;
                var cols = lines[i].Split(',');
                var t = ParseDouble(get(cols, "time_s"));
                var a1 = ParseDouble(get(cols, "axis1"));
                var a2 = ParseDouble(get(cols, "axis2"));
                var a3 = ParseDouble(get(cols, "axis3"));
                var a4 = ParseDouble(get(cols, "axis4"));
                var intake = get(cols, "intake_action");
                var outtake = get(cols, "outtake_action");
                var action = string.Empty;
                if (intake.Length > 0 || outtake.Length > 0) {
                    action = $"INTAKE:{intake} OUT:{outtake}";
                }
                result.Add(new ReplaySample(t, a1, a2, a3, a4, action));
            }
            return result;
        }

        private static List<ReplaySample> ParseReplayEvents(string[] lines) {
            var result = new List<ReplaySample>();
            double? axis1 = null;
            double? axis2 = null;
            double? axis3 = null;
            double? axis4 = null;
            var lastAction = string.Empty;
            var t = 0.0;

            foreach (var raw in lines) {
                var line = raw.Trim();
                if (line.Length == 0) continue;
                var split = line.Split(':', 2);
                if (split.Length != 2) continue;

                var type = split[0].Trim().ToUpperInvariant();
                var value = split[1].Trim();

                if (type == "AXIS1") axis1 = ParseDouble(value);
                else if (type == "AXIS2") axis2 = ParseDouble(value);
                else if (type == "AXIS3") axis3 = ParseDouble(value);
                else if (type == "AXIS4") axis4 = ParseDouble(value);
                else lastAction = $"{type} : {value}";

                if (axis1.HasValue && axis2.HasValue && axis3.HasValue && axis4.HasValue) {
                    result.Add(new ReplaySample(t, axis1.Value, axis2.Value, axis3.Value, axis4.Value, lastAction));
                    axis1 = axis2 = axis3 = axis4 = null;
                    t += ReplayDtFallback;
                }
            }

            return result;
        }

        private static List<ReplayPose> IntegrateReplay(List<ReplaySample> samples) {
            var poses = new List<ReplayPose>();
            if (samples.Count == 0) return poses;

            var x = ReplayFieldSizeIn / 2.0;
            var y = ReplayFieldSizeIn / 2.0;
            var theta = 0.0;
            double? lastT = null;

            foreach (var sample in samples) {
                var dt = 0.0;
                if (lastT.HasValue) {
                    var diff = sample.Time - lastT.Value;
                    dt = diff > 0 ? diff : ReplayDtFallback;
                }

                var leftCmd = Math.Abs(sample.Axis3) < 5 ? 0.0 : sample.Axis3;
                var rightCmd = Math.Abs(sample.Axis2) < 5 ? 0.0 : sample.Axis2;

                var vL = (leftCmd / 100.0) * ReplayMaxSpeedInPerS;
                var vR = (rightCmd / 100.0) * ReplayMaxSpeedInPerS;
                var v = (vL + vR) / 2.0;
                var omega = (vR - vL) / ReplayTrackWidthIn;

                if (dt > 0) {
                    x += v * Math.Cos(theta) * dt;
                    y += v * Math.Sin(theta) * dt;
                    theta += omega * dt;
                }

                poses.Add(new ReplayPose(
                    sample.Time,
                    x,
                    y,
                    theta,
                    leftCmd,
                    rightCmd,
                    sample.Axis1,
                    sample.Axis2,
                    sample.Axis3,
                    sample.Axis4,
                    sample.Action
                ));

                lastT = sample.Time;
            }

            return poses;
        }

        private static double ParseDouble(string value) {
            if (double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var parsed)) {
                return parsed;
            }
            return 0.0;
        }

        private sealed record PortAssignment(string Short, string Title, int Port, Color Color);
        private sealed record ReplaySample(double Time, double Axis1, double Axis2, double Axis3, double Axis4, string Action);

        private sealed record ReplayPose(
            double T,
            double X,
            double Y,
            double Theta,
            double LeftCmd,
            double RightCmd,
            double Axis1,
            double Axis2,
            double Axis3,
            double Axis4,
            string Action
        );
    }
}
