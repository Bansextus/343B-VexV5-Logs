using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;

namespace BonkersFieldReplayWin;

internal sealed record LogSample(double Time, double Axis1, double Axis2, double Axis3, double Axis4, string Action);

internal sealed record Pose(double T, double X, double Y, double Theta,
    double LeftCmd, double RightCmd, double Axis1, double Axis2, double Axis3, double Axis4, string Action);

internal sealed class ReplaySettings
{
    public double FieldSizeIn { get; set; } = 144.0;
    public double TrackWidthIn { get; set; } = 12.0;
    public double MaxSpeedInPerS { get; set; } = 60.0;
    public double DtFallback { get; set; } = 0.02;
}

internal static class ReplayEngine
{
    public static List<LogSample> ParseLog(string path)
    {
        var lines = File.ReadAllLines(path);
        if (lines.Length == 0)
        {
            return new List<LogSample>();
        }

        if (lines[0].Contains("time_s", StringComparison.OrdinalIgnoreCase))
        {
            return ParseCsv(lines);
        }

        return ParseEventLog(lines);
    }

    private static List<LogSample> ParseCsv(string[] lines)
    {
        var headers = lines[0].Split(',');
        var index = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        for (var i = 0; i < headers.Length; i++)
        {
            index[headers[i]] = i;
        }

        string Get(string[] cols, string key)
        {
            return index.TryGetValue(key, out var idx) && idx < cols.Length ? cols[idx] : string.Empty;
        }

        var results = new List<LogSample>();
        for (var i = 1; i < lines.Length; i++)
        {
            var cols = lines[i].Split(',');
            var t = ParseDouble(Get(cols, "time_s"));
            var axis1 = ParseDouble(Get(cols, "axis1"));
            var axis2 = ParseDouble(Get(cols, "axis2"));
            var axis3 = ParseDouble(Get(cols, "axis3"));
            var axis4 = ParseDouble(Get(cols, "axis4"));
            var intake = Get(cols, "intake_action");
            var outtake = Get(cols, "outtake_action");
            var action = string.Empty;
            if (!string.IsNullOrWhiteSpace(intake) || !string.IsNullOrWhiteSpace(outtake))
            {
                action = $"INTAKE:{intake} OUT:{outtake}";
            }
            results.Add(new LogSample(t, axis1, axis2, axis3, axis4, action));
        }

        return results;
    }

    private static List<LogSample> ParseEventLog(string[] lines)
    {
        var results = new List<LogSample>();
        double? axis1 = null;
        double? axis2 = null;
        double? axis3 = null;
        double? axis4 = null;
        var lastAction = string.Empty;
        var t = 0.0;

        foreach (var raw in lines)
        {
            var line = raw.Trim();
            if (line.Length == 0) continue;
            var split = line.Split(':', 2);
            if (split.Length != 2) continue;

            var type = split[0].Trim();
            var value = split[1].Trim();

            if (type.Equals("AXIS1", StringComparison.OrdinalIgnoreCase))
            {
                axis1 = ParseDouble(value);
            }
            else if (type.Equals("AXIS2", StringComparison.OrdinalIgnoreCase))
            {
                axis2 = ParseDouble(value);
            }
            else if (type.Equals("AXIS3", StringComparison.OrdinalIgnoreCase))
            {
                axis3 = ParseDouble(value);
            }
            else if (type.Equals("AXIS4", StringComparison.OrdinalIgnoreCase))
            {
                axis4 = ParseDouble(value);
            }
            else
            {
                lastAction = $"{type} : {value}";
            }

            if (axis1.HasValue && axis2.HasValue && axis3.HasValue && axis4.HasValue)
            {
                results.Add(new LogSample(t, axis1.Value, axis2.Value, axis3.Value, axis4.Value, lastAction));
                axis1 = axis2 = axis3 = axis4 = null;
                t += 0.02;
            }
        }

        return results;
    }

    public static List<Pose> Integrate(List<LogSample> samples, ReplaySettings settings)
    {
        var poses = new List<Pose>();
        if (samples.Count == 0)
        {
            return poses;
        }

        var x = settings.FieldSizeIn / 2.0;
        var y = settings.FieldSizeIn / 2.0;
        var theta = 0.0;
        double? lastT = null;

        foreach (var sample in samples)
        {
            var dt = 0.0;
            if (lastT.HasValue)
            {
                var diff = sample.Time - lastT.Value;
                dt = diff > 0 ? diff : settings.DtFallback;
            }

            var leftCmd = Math.Abs(sample.Axis3) < 5 ? 0.0 : sample.Axis3;
            var rightCmd = Math.Abs(sample.Axis2) < 5 ? 0.0 : sample.Axis2;

            var vL = (leftCmd / 100.0) * settings.MaxSpeedInPerS;
            var vR = (rightCmd / 100.0) * settings.MaxSpeedInPerS;
            var v = (vL + vR) / 2.0;
            var omega = (vR - vL) / settings.TrackWidthIn;

            if (dt > 0)
            {
                x += v * Math.Cos(theta) * dt;
                y += v * Math.Sin(theta) * dt;
                theta += omega * dt;
            }

            poses.Add(new Pose(sample.Time, x, y, theta,
                leftCmd, rightCmd,
                sample.Axis1, sample.Axis2, sample.Axis3, sample.Axis4,
                sample.Action));

            lastT = sample.Time;
        }

        return poses;
    }

    private static double ParseDouble(string value)
    {
        if (double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var result))
        {
            return result;
        }
        return 0.0;
    }
}
