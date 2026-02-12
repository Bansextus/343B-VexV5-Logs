using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace BonkersFieldReplayWin;

internal sealed class FieldPanel : Panel
{
    public List<Pose> Poses { get; set; } = new();
    public int Index { get; set; } = 0;
    public double FieldSizeIn { get; set; } = 144.0;

    public FieldPanel()
    {
        DoubleBuffered = true;
        BackColor = Color.FromArgb(255, 253, 247);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;

        var size = Math.Min(ClientSize.Width, ClientSize.Height);
        if (size <= 0)
        {
            return;
        }

        var offsetX = (ClientSize.Width - size) / 2f;
        var offsetY = (ClientSize.Height - size) / 2f;
        var scale = size / FieldSizeIn;

        var fieldRect = new RectangleF(offsetX, offsetY, size, size);
        using var borderPen = new Pen(Color.FromArgb(199, 184, 164), 2);
        g.FillRectangle(new SolidBrush(Color.FromArgb(255, 253, 247)), fieldRect);
        g.DrawRectangle(borderPen, fieldRect.X, fieldRect.Y, fieldRect.Width, fieldRect.Height);

        using var gridPen = new Pen(Color.FromArgb(226, 215, 198), 1);
        for (var i = 0; i <= FieldSizeIn; i += 12)
        {
            var x = offsetX + (float)(i * scale);
            var y = offsetY + (float)(i * scale);
            g.DrawLine(gridPen, x, offsetY, x, offsetY + size);
            g.DrawLine(gridPen, offsetX, y, offsetX + size, y);
        }

        if (Poses.Count == 0)
        {
            return;
        }

        var idx = Math.Max(0, Math.Min(Index, Poses.Count - 1));

        using var pathPen = new Pen(Color.FromArgb(47, 79, 79), 2);
        var points = new List<PointF>();
        for (var i = 0; i <= idx; i++)
        {
            var p = Poses[i];
            points.Add(ToPoint(p.X, p.Y, offsetX, offsetY, scale));
        }
        if (points.Count > 1)
        {
            g.DrawLines(pathPen, points.ToArray());
        }

        var pose = Poses[idx];
        var robot = ToPoint(pose.X, pose.Y, offsetX, offsetY, scale);
        var robotSize = 12f;

        using var robotBrush = new SolidBrush(Color.FromArgb(195, 59, 34));
        using var headingPen = new Pen(Color.Black, 2);

        g.TranslateTransform(robot.X, robot.Y);
        g.RotateTransform((float)(-pose.Theta * 180.0 / Math.PI));
        g.FillRectangle(robotBrush, -robotSize, -robotSize, robotSize * 2, robotSize * 2);
        g.DrawLine(headingPen, 0, 0, robotSize * 1.4f, 0);
        g.ResetTransform();
    }

    private PointF ToPoint(double x, double y, float offsetX, float offsetY, double scale)
    {
        var cx = offsetX + (float)(x * scale);
        var cy = offsetY + (float)((FieldSizeIn - y) * scale);
        return new PointF(cx, cy);
    }
}
