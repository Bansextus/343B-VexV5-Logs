using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Windows.Forms;

namespace BonkersFieldReplayWin;

public sealed class MainForm : Form
{
    private readonly FieldPanel fieldPanel = new();
    private readonly Button openButton = new();
    private readonly Button playButton = new();
    private readonly Button resetButton = new();
    private readonly ComboBox speedCombo = new();
    private readonly TrackBar scrubBar = new();
    private readonly Label titleLabel = new();
    private readonly Label fileLabel = new();
    private readonly Label readoutLabel = new();
    private readonly TextBox fieldSizeBox = new();
    private readonly TextBox trackWidthBox = new();
    private readonly TextBox maxSpeedBox = new();
    private readonly Button applyButton = new();
    private readonly Timer timer = new();

    private List<LogSample> samples = new();
    private List<Pose> poses = new();
    private int currentIndex = 0;
    private bool playing = false;
    private DateTime lastTick = DateTime.MinValue;
    private double playbackRate = 1.0;
    private string currentLogPath = string.Empty;

    public MainForm()
    {
        Text = "Bonkers Field Replay (Windows)";
        MinimumSize = new Size(920, 880);
        BackColor = Color.FromArgb(246, 239, 231);

        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 4,
            Padding = new Padding(16),
        };
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 70));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 130));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 90));
        Controls.Add(root);

        root.Controls.Add(BuildHeader(), 0, 0);
        root.Controls.Add(fieldPanel, 0, 1);
        root.Controls.Add(BuildControls(), 0, 2);
        root.Controls.Add(BuildReadout(), 0, 3);

        fieldPanel.Dock = DockStyle.Fill;

        timer.Interval = 16;
        timer.Tick += (_, _) => TickPlayback();
        timer.Start();

        UpdateUIState();
    }

    private Control BuildHeader()
    {
        var panel = new Panel { Dock = DockStyle.Fill, BackColor = Color.FromArgb(255, 250, 242) };
        panel.Padding = new Padding(12);

        titleLabel.Text = "Bonkers Field Replay";
        titleLabel.Font = new Font("Segoe UI", 14, FontStyle.Bold);

        fileLabel.Text = "No log loaded";
        fileLabel.Font = new Font("Segoe UI", 9, FontStyle.Regular);
        fileLabel.ForeColor = Color.DimGray;

        var leftStack = new FlowLayoutPanel
        {
            Dock = DockStyle.Left,
            FlowDirection = FlowDirection.TopDown,
            AutoSize = true,
            WrapContents = false,
        };
        leftStack.Controls.Add(titleLabel);
        leftStack.Controls.Add(fileLabel);

        openButton.Text = "Open Log";
        openButton.AutoSize = true;
        openButton.Padding = new Padding(6, 4, 6, 4);
        openButton.Click += (_, _) => OpenLog();

        var rightPanel = new Panel { Dock = DockStyle.Right, Width = 120 };
        rightPanel.Controls.Add(openButton);
        openButton.Dock = DockStyle.Fill;

        panel.Controls.Add(leftStack);
        panel.Controls.Add(rightPanel);

        panel.BorderStyle = BorderStyle.FixedSingle;
        return panel;
    }

    private Control BuildControls()
    {
        var panel = new Panel { Dock = DockStyle.Fill, BackColor = Color.FromArgb(255, 250, 242) };
        panel.Padding = new Padding(12);

        playButton.Text = "Play";
        playButton.AutoSize = true;
        playButton.Click += (_, _) => TogglePlay();

        resetButton.Text = "Reset";
        resetButton.AutoSize = true;
        resetButton.Click += (_, _) => ResetPlayback();

        speedCombo.DropDownStyle = ComboBoxStyle.DropDownList;
        speedCombo.Items.AddRange(new object[] { "0.5x", "1x", "2x", "4x" });
        speedCombo.SelectedIndex = 1;
        speedCombo.SelectedIndexChanged += (_, _) =>
        {
            playbackRate = speedCombo.SelectedIndex switch
            {
                0 => 0.5,
                1 => 1.0,
                2 => 2.0,
                3 => 4.0,
                _ => 1.0
            };
        };

        scrubBar.Dock = DockStyle.Bottom;
        scrubBar.Minimum = 0;
        scrubBar.Maximum = 0;
        scrubBar.TickStyle = TickStyle.None;
        scrubBar.Scroll += (_, _) =>
        {
            playing = false;
            currentIndex = scrubBar.Value;
            lastTick = DateTime.MinValue;
            fieldPanel.Index = currentIndex;
            fieldPanel.Invalidate();
            UpdateReadout();
            UpdateUIState();
        };

        fieldSizeBox.Text = "144";
        trackWidthBox.Text = "12";
        maxSpeedBox.Text = "60";

        applyButton.Text = "Apply";
        applyButton.AutoSize = true;
        applyButton.Click += (_, _) => ApplySettings();

        var row1 = new FlowLayoutPanel
        {
            Dock = DockStyle.Top,
            Height = 40,
            AutoSize = true,
            WrapContents = false
        };
        row1.Controls.Add(playButton);
        row1.Controls.Add(resetButton);
        row1.Controls.Add(new Label { Text = "Speed", AutoSize = true, Padding = new Padding(8, 8, 4, 4) });
        row1.Controls.Add(speedCombo);

        var row2 = new FlowLayoutPanel
        {
            Dock = DockStyle.Top,
            Height = 40,
            AutoSize = true,
            WrapContents = false
        };
        row2.Controls.Add(BuildLabeledField("Field Size", fieldSizeBox));
        row2.Controls.Add(BuildLabeledField("Track Width", trackWidthBox));
        row2.Controls.Add(BuildLabeledField("Max Speed", maxSpeedBox));
        row2.Controls.Add(applyButton);

        panel.Controls.Add(row2);
        panel.Controls.Add(row1);
        panel.Controls.Add(scrubBar);

        panel.BorderStyle = BorderStyle.FixedSingle;
        return panel;
    }

    private Control BuildReadout()
    {
        var panel = new Panel { Dock = DockStyle.Fill, BackColor = Color.FromArgb(255, 250, 242) };
        panel.Padding = new Padding(12);

        readoutLabel.Dock = DockStyle.Fill;
        readoutLabel.Font = new Font("Consolas", 9, FontStyle.Regular);
        readoutLabel.Text = "Load a log file (.txt or .csv) to begin.";

        panel.Controls.Add(readoutLabel);
        panel.BorderStyle = BorderStyle.FixedSingle;
        return panel;
    }

    private static Control BuildLabeledField(string label, TextBox box)
    {
        var panel = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.TopDown,
            AutoSize = true,
            WrapContents = false,
            Margin = new Padding(6, 0, 6, 0)
        };
        var lbl = new Label { Text = label, AutoSize = true };
        box.Width = 80;
        panel.Controls.Add(lbl);
        panel.Controls.Add(box);
        return panel;
    }

    private void OpenLog()
    {
        using var dialog = new OpenFileDialog
        {
            Filter = "Log Files (*.txt;*.csv)|*.txt;*.csv|All Files (*.*)|*.*",
            Multiselect = false,
        };

        if (dialog.ShowDialog(this) == DialogResult.OK)
        {
            LoadLog(dialog.FileName);
        }
    }

    private void LoadLog(string path)
    {
        try
        {
            samples = ReplayEngine.ParseLog(path);
            var settings = CurrentSettings();
            poses = ReplayEngine.Integrate(samples, settings);
            currentIndex = 0;
            fieldPanel.Poses = poses;
            fieldPanel.Index = 0;
            fieldPanel.FieldSizeIn = settings.FieldSizeIn;
            fieldPanel.Invalidate();

            currentLogPath = path;
            fileLabel.Text = Path.GetFileName(path);
            readoutLabel.Text = poses.Count == 0 ? "Log file has no data rows." : "";
            scrubBar.Maximum = poses.Count > 0 ? poses.Count - 1 : 0;
            scrubBar.Value = 0;

            playing = false;
            lastTick = DateTime.MinValue;
            UpdateReadout();
            UpdateUIState();
        }
        catch (Exception ex)
        {
            readoutLabel.Text = $"Failed to load log: {ex.Message}";
            poses.Clear();
            fieldPanel.Poses = poses;
            fieldPanel.Invalidate();
        }
    }

    private ReplaySettings CurrentSettings()
    {
        var settings = new ReplaySettings();
        if (double.TryParse(fieldSizeBox.Text, NumberStyles.Float, CultureInfo.InvariantCulture, out var fieldSize))
        {
            settings.FieldSizeIn = fieldSize;
        }
        if (double.TryParse(trackWidthBox.Text, NumberStyles.Float, CultureInfo.InvariantCulture, out var trackWidth))
        {
            settings.TrackWidthIn = trackWidth;
        }
        if (double.TryParse(maxSpeedBox.Text, NumberStyles.Float, CultureInfo.InvariantCulture, out var maxSpeed))
        {
            settings.MaxSpeedInPerS = maxSpeed;
        }
        return settings;
    }

    private void ApplySettings()
    {
        if (samples.Count == 0)
        {
            return;
        }
        var settings = CurrentSettings();
        poses = ReplayEngine.Integrate(samples, settings);
        fieldPanel.Poses = poses;
        fieldPanel.FieldSizeIn = settings.FieldSizeIn;
        currentIndex = Math.Min(currentIndex, Math.Max(poses.Count - 1, 0));
        fieldPanel.Index = currentIndex;
        scrubBar.Maximum = poses.Count > 0 ? poses.Count - 1 : 0;
        scrubBar.Value = currentIndex;
        fieldPanel.Invalidate();
        UpdateReadout();
    }

    private void TogglePlay()
    {
        if (poses.Count == 0)
        {
            return;
        }
        playing = !playing;
        lastTick = DateTime.MinValue;
        UpdateUIState();
    }

    private void ResetPlayback()
    {
        playing = false;
        currentIndex = 0;
        lastTick = DateTime.MinValue;
        scrubBar.Value = 0;
        fieldPanel.Index = 0;
        fieldPanel.Invalidate();
        UpdateReadout();
        UpdateUIState();
    }

    private void TickPlayback()
    {
        if (!playing || poses.Count == 0)
        {
            return;
        }

        if (lastTick == DateTime.MinValue)
        {
            lastTick = DateTime.Now;
            return;
        }

        var now = DateTime.Now;
        var dt = (now - lastTick).TotalSeconds * playbackRate;
        lastTick = now;

        var targetTime = poses[currentIndex].T + dt;
        while (currentIndex < poses.Count - 1 && poses[currentIndex + 1].T <= targetTime)
        {
            currentIndex++;
        }

        if (currentIndex >= poses.Count - 1)
        {
            playing = false;
        }

        fieldPanel.Index = currentIndex;
        scrubBar.Value = currentIndex;
        fieldPanel.Invalidate();
        UpdateReadout();
        UpdateUIState();
    }

    private void UpdateReadout()
    {
        if (poses.Count == 0)
        {
            return;
        }
        var pose = poses[Math.Max(0, Math.Min(currentIndex, poses.Count - 1))];
        readoutLabel.Text = string.Format(CultureInfo.InvariantCulture,
            "t={0:0.00}s  x={1:0.0}in  y={2:0.0}in\nleft={3:0}  right={4:0}\nA1={5:0} A2={6:0} A3={7:0} A4={8:0}\nlast={9}",
            pose.T, pose.X, pose.Y,
            pose.LeftCmd, pose.RightCmd,
            pose.Axis1, pose.Axis2, pose.Axis3, pose.Axis4,
            pose.Action);
    }

    private void UpdateUIState()
    {
        playButton.Text = playing ? "Pause" : "Play";
    }
}
