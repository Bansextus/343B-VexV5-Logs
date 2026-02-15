import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FieldReplayView: View {
    @State private var poses: [ReplayPose] = []
    @State private var currentIndex: Int = 0
    @State private var playbackProgress: Double = 0
    @State private var selectedFileName: String = "No replay file loaded"
    @State private var statusText: String = "Load a replay log (.txt or .csv) to visualize path data."
    @State private var showingImporter: Bool = false

    private let settings = ReplaySettings(fieldSizeIn: 144.0, trackWidthIn: 12.0, maxSpeedInPerS: 60.0, dtFallback: 0.02)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PanelTitle(text: "Field Replay", icon: "location.viewfinder")

            Card {
                HStack(spacing: 10) {
                    Button("Open Replay File") {
                        showingImporter = true
                    }
                    Button("Clear") {
                        poses = []
                        currentIndex = 0
                        playbackProgress = 0
                        selectedFileName = "No replay file loaded"
                        statusText = "Load a replay log (.txt or .csv) to visualize path data."
                    }

                    Text(selectedFileName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Theme.subtext)
                        .lineLimit(1)

                    Spacer()

                    if !poses.isEmpty {
                        Text("Samples: \(poses.count)")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(Theme.subtext)
                    }
                }
            }

            Card {
                Text("Replay Overlay")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.text)

                if let image = loadFieldImage() {
                    replayCanvas(image: image)
                } else {
                    Text("Field image not found")
                        .foregroundColor(Theme.subtext)
                        .font(.system(size: 19, weight: .medium))
                }

                if !poses.isEmpty {
                    sliderRow
                }
            }

            Card {
                Text("Readout")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.text)
                Text(statusText)
                    .font(.system(size: 16, weight: .regular, design: .monospaced))
                    .foregroundColor(Theme.subtext)
                    .textSelection(.enabled)
            }
        }
        .buttonStyle(TaheraActionButtonStyle())
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.plainText, .commaSeparatedText, .text, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let first = urls.first else { return }
                loadReplay(from: first)
            case .failure(let error):
                statusText = "Failed to open file: \(error.localizedDescription)"
            }
        }
    }

    private var sliderRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Frame \(clampedFrameIndex(from: playbackProgress) + 1) / \(poses.count)")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Theme.subtext)
            Slider(
                value: $playbackProgress,
                in: 0...Double(max(poses.count - 1, 0)),
                step: 0.001
            )
            .tint(Theme.accent)
            .onChange(of: playbackProgress) { value in
                currentIndex = clampedFrameIndex(from: value)
                updateReadoutForCurrentFrame()
            }
        }
    }

    private func replayCanvas(image: NSImage) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)

                pathOverlay(in: size)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(max(image.size.width / max(image.size.height, 1), 0.1), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func pathOverlay(in size: CGSize) -> some View {
        let progress = clampedProgress(playbackProgress)
        let baseCount = min(max(Int(floor(progress)) + 1, 0), poses.count)
        let hasInterp = Int(floor(progress)) < (poses.count - 1)
        let interpPose = interpolatedPose(at: progress)
        let visible = Array(poses.prefix(baseCount))

        if visible.count > 1 || (visible.count == 1 && hasInterp) {
            Path { path in
                let first = fieldPoint(for: visible[0], in: size)
                path.move(to: first)
                for pose in visible.dropFirst() {
                    path.addLine(to: fieldPoint(for: pose, in: size))
                }
                if hasInterp, let interpPose {
                    path.addLine(to: fieldPoint(for: interpPose, in: size))
                }
            }
            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round))
            .shadow(color: Theme.accent.opacity(0.45), radius: 5)
        }

        if let pose = interpPose {
            let center = fieldPoint(for: pose, in: size)
            let headingLen = max(12, size.width * 0.03)
            let heading = CGPoint(
                x: center.x + CGFloat(cos(pose.theta)) * headingLen,
                y: center.y - CGFloat(sin(pose.theta)) * headingLen
            )

            Circle()
                .fill(Color(hex: 0xFF6D5A))
                .frame(width: 10, height: 10)
                .position(center)
                .shadow(color: Color(hex: 0xFF6D5A).opacity(0.55), radius: 4)

            Path { path in
                path.move(to: center)
                path.addLine(to: heading)
            }
            .stroke(Color(hex: 0xFCEFC7), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        }
    }

    private func fieldPoint(for pose: ReplayPose, in size: CGSize) -> CGPoint {
        let x = CGFloat(pose.x / settings.fieldSizeIn) * size.width
        let y = CGFloat((settings.fieldSizeIn - pose.y) / settings.fieldSizeIn) * size.height
        return CGPoint(x: x, y: y)
    }

    private func loadReplay(from url: URL) {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let lines = text.components(separatedBy: .newlines)
            let samples = ReplayParser.parseLog(lines: lines)
            let integrated = ReplayParser.integrate(samples: samples, settings: settings)

            poses = integrated
            playbackProgress = Double(max(integrated.count - 1, 0))
            currentIndex = clampedFrameIndex(from: playbackProgress)
            selectedFileName = url.lastPathComponent
            if integrated.isEmpty {
                statusText = "The selected file was loaded but no replay samples were parsed."
            } else {
                updateReadoutForCurrentFrame()
            }
        } catch {
            statusText = "Failed to load replay file: \(error.localizedDescription)"
        }
    }

    private func updateReadoutForCurrentFrame() {
        guard !poses.isEmpty else {
            return
        }
        let idx = clampedFrameIndex(from: playbackProgress)
        let pose = poses[idx]
        statusText = String(
            format: "t=%.2fs x=%.1fin y=%.1fin\nleft=%.0f right=%.0f\na1=%.0f a2=%.0f a3=%.0f a4=%.0f\nlast=%@",
            pose.t, pose.x, pose.y, pose.leftCmd, pose.rightCmd,
            pose.axis1, pose.axis2, pose.axis3, pose.axis4,
            pose.action
        )
    }

    private func clampedProgress(_ value: Double) -> Double {
        guard !poses.isEmpty else { return 0 }
        let maxProgress = Double(max(poses.count - 1, 0))
        return min(max(0, value), maxProgress)
    }

    private func clampedFrameIndex(from progress: Double) -> Int {
        guard !poses.isEmpty else { return 0 }
        let clamped = clampedProgress(progress)
        return min(max(Int(round(clamped)), 0), poses.count - 1)
    }

    private func interpolatedPose(at progress: Double) -> ReplayPose? {
        guard !poses.isEmpty else { return nil }
        let clamped = clampedProgress(progress)
        let lower = min(max(Int(floor(clamped)), 0), poses.count - 1)
        let upper = min(lower + 1, poses.count - 1)
        if lower == upper {
            return poses[lower]
        }

        let t = clamped - Double(lower)
        let start = poses[lower]
        let end = poses[upper]

        return ReplayPose(
            t: start.t + (end.t - start.t) * t,
            x: start.x + (end.x - start.x) * t,
            y: start.y + (end.y - start.y) * t,
            theta: interpolateHeading(start.theta, end.theta, t: t),
            leftCmd: start.leftCmd + (end.leftCmd - start.leftCmd) * t,
            rightCmd: start.rightCmd + (end.rightCmd - start.rightCmd) * t,
            axis1: start.axis1 + (end.axis1 - start.axis1) * t,
            axis2: start.axis2 + (end.axis2 - start.axis2) * t,
            axis3: start.axis3 + (end.axis3 - start.axis3) * t,
            axis4: start.axis4 + (end.axis4 - start.axis4) * t,
            action: end.action
        )
    }

    private func interpolateHeading(_ start: Double, _ end: Double, t: Double) -> Double {
        var delta = end - start
        if delta > .pi {
            delta -= (2 * .pi)
        } else if delta < -.pi {
            delta += (2 * .pi)
        }
        return start + delta * t
    }

    private func loadFieldImage() -> NSImage? {
        guard let url = Bundle.module.url(forResource: "field", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

private struct ReplaySample {
    let time: Double
    let axis1: Double
    let axis2: Double
    let axis3: Double
    let axis4: Double
    let action: String
}

private struct ReplayPose {
    let t: Double
    let x: Double
    let y: Double
    let theta: Double
    let leftCmd: Double
    let rightCmd: Double
    let axis1: Double
    let axis2: Double
    let axis3: Double
    let axis4: Double
    let action: String
}

private struct ReplaySettings {
    let fieldSizeIn: Double
    let trackWidthIn: Double
    let maxSpeedInPerS: Double
    let dtFallback: Double
}

private enum ReplayParser {
    static func parseLog(lines: [String]) -> [ReplaySample] {
        let trimmed = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard let first = trimmed.first else { return [] }
        if first.lowercased().contains("time_s") {
            return parseCsv(lines: trimmed)
        }
        return parseEvent(lines: trimmed)
    }

    static func integrate(samples: [ReplaySample], settings: ReplaySettings) -> [ReplayPose] {
        guard !samples.isEmpty else { return [] }

        var poses: [ReplayPose] = []
        var x = settings.fieldSizeIn / 2.0
        var y = settings.fieldSizeIn / 2.0
        var theta = 0.0
        var lastT: Double?

        for sample in samples {
            let dt: Double
            if let lastT {
                let diff = sample.time - lastT
                dt = diff > 0 ? diff : settings.dtFallback
            } else {
                dt = 0.0
            }

            let leftCmd = abs(sample.axis3) < 5 ? 0.0 : sample.axis3
            let rightCmd = abs(sample.axis2) < 5 ? 0.0 : sample.axis2

            let vL = (leftCmd / 100.0) * settings.maxSpeedInPerS
            let vR = (rightCmd / 100.0) * settings.maxSpeedInPerS
            let v = (vL + vR) / 2.0
            let omega = (vR - vL) / settings.trackWidthIn

            if dt > 0 {
                x += v * cos(theta) * dt
                y += v * sin(theta) * dt
                theta += omega * dt
            }

            poses.append(
                ReplayPose(
                    t: sample.time,
                    x: x,
                    y: y,
                    theta: theta,
                    leftCmd: leftCmd,
                    rightCmd: rightCmd,
                    axis1: sample.axis1,
                    axis2: sample.axis2,
                    axis3: sample.axis3,
                    axis4: sample.axis4,
                    action: sample.action
                )
            )

            lastT = sample.time
        }

        return poses
    }

    private static func parseCsv(lines: [String]) -> [ReplaySample] {
        guard !lines.isEmpty else { return [] }
        let headerParts = lines[0].split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        var index: [String: Int] = [:]
        for (idx, key) in headerParts.enumerated() {
            index[key] = idx
        }

        func read(_ key: String, from cols: [String]) -> String {
            guard let idx = index[key], idx < cols.count else { return "" }
            return cols[idx]
        }

        var samples: [ReplaySample] = []
        for line in lines.dropFirst() {
            let cols = line.split(separator: ",", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            let t = parseDouble(read("time_s", from: cols))
            let a1 = parseDouble(read("axis1", from: cols))
            let a2 = parseDouble(read("axis2", from: cols))
            let a3 = parseDouble(read("axis3", from: cols))
            let a4 = parseDouble(read("axis4", from: cols))
            let intake = read("intake_action", from: cols)
            let outtake = read("outtake_action", from: cols)
            var action = ""
            if !intake.isEmpty || !outtake.isEmpty {
                action = "INTAKE:\(intake) OUT:\(outtake)"
            }
            samples.append(ReplaySample(time: t, axis1: a1, axis2: a2, axis3: a3, axis4: a4, action: action))
        }
        return samples
    }

    private static func parseEvent(lines: [String]) -> [ReplaySample] {
        var samples: [ReplaySample] = []
        var axis1: Double?
        var axis2: Double?
        var axis3: Double?
        var axis4: Double?
        var lastAction = ""
        var t = 0.0

        for line in lines {
            let split = line.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard split.count == 2 else { continue }
            let kind = split[0].uppercased()
            let value = split[1]

            switch kind {
            case "AXIS1":
                axis1 = parseDouble(value)
            case "AXIS2":
                axis2 = parseDouble(value)
            case "AXIS3":
                axis3 = parseDouble(value)
            case "AXIS4":
                axis4 = parseDouble(value)
            default:
                lastAction = "\(kind) : \(value)"
            }

            if let a1 = axis1, let a2 = axis2, let a3 = axis3, let a4 = axis4 {
                samples.append(ReplaySample(time: t, axis1: a1, axis2: a2, axis3: a3, axis4: a4, action: lastAction))
                axis1 = nil
                axis2 = nil
                axis3 = nil
                axis4 = nil
                t += 0.02
            }
        }

        return samples
    }

    private static func parseDouble(_ value: String) -> Double {
        Double(value.replacingOccurrences(of: ",", with: ".")) ?? 0.0
    }
}
