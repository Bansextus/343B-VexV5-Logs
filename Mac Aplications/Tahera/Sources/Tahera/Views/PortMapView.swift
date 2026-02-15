import SwiftUI
import AppKit

struct PortMapView: View {
    @EnvironmentObject var model: TaheraModel
    @State private var showSocketNumbers = false

    private let summaryColumns = [GridItem(.adaptive(minimum: 220), spacing: 12)]

    // Calibrated for the bundled v5_brain.png asset (265x190).
    private let topPortX: [CGFloat] = [0.162, 0.225, 0.289, 0.351, 0.414, 0.508, 0.571, 0.634, 0.697, 0.760]
    private let bottomPortX: [CGFloat] = [0.162, 0.225, 0.289, 0.351, 0.414, 0.508, 0.571, 0.634, 0.697, 0.760]
    private let topPortY: CGFloat = 0.086
    private let bottomPortY: CGFloat = 0.922

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PanelTitle(text: "Port Map", icon: "slider.horizontal.3")

                Card {
                    HStack(alignment: .center, spacing: 12) {
                        Text("V5 Brain Overview")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.text)
                        Spacer()
                        Toggle("Socket numbers", isOn: $showSocketNumbers)
                            .font(.system(size: 19, weight: .semibold, design: .rounded))
                            .tint(Theme.accent)
                    }

                    if !duplicatePorts.isEmpty {
                        Text("Port conflict: \(duplicatePorts.map { String($0) }.joined(separator: ", ")) are assigned to multiple devices.")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(hex: 0xFFB17A))
                    }

                    if let image = loadBrainImage() {
                        brainOverlay(for: image)
                    } else {
                        Text("v5_brain.png was not found in Tahera resources.")
                            .foregroundColor(Theme.subtext)
                            .font(.system(size: 19, weight: .medium))
                    }

                    LazyVGrid(columns: summaryColumns, spacing: 10) {
                        ForEach(assignments) { assignment in
                            assignmentChip(assignment)
                        }
                    }
                }

                Card {
                    Text("Edit Assignments")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.text)

                    HStack(alignment: .top, spacing: 14) {
                        groupedCard(title: "Left Drive") {
                            assignmentRow("Left Outer 1", value: $model.portMap.leftOuter1.value, reversed: $model.portMap.leftOuter1.reversed)
                            assignmentRow("Left Outer 2", value: $model.portMap.leftOuter2.value, reversed: $model.portMap.leftOuter2.reversed)
                            assignmentRow("Left Middle", value: $model.portMap.leftMiddle.value, reversed: $model.portMap.leftMiddle.reversed)
                        }

                        groupedCard(title: "Right Drive") {
                            assignmentRow("Right Outer 1", value: $model.portMap.rightOuter1.value, reversed: $model.portMap.rightOuter1.reversed)
                            assignmentRow("Right Outer 2", value: $model.portMap.rightOuter2.value, reversed: $model.portMap.rightOuter2.reversed)
                            assignmentRow("Right Middle", value: $model.portMap.rightMiddle.value, reversed: $model.portMap.rightMiddle.reversed)
                        }
                    }

                    groupedCard(title: "Mechanisms") {
                        assignmentRow("Intake", value: $model.portMap.intakeLeft.value, reversed: $model.portMap.intakeLeft.reversed)
                        assignmentRow("Outake", value: $model.portMap.intakeRight.value, reversed: $model.portMap.intakeRight.reversed)
                    }

                    groupedCard(title: "Sensors") {
                        sensorRow("IMU", value: $model.portMap.imu)
                        sensorRow("GPS", value: $model.portMap.gps)
                    }

                    HStack(spacing: 12) {
                        Button("Save Port Map") {
                            model.savePortMapToRepo()
                        }
                        if !model.portMapStatus.isEmpty {
                            Text(model.portMapStatus)
                                .foregroundColor(Theme.subtext)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                        }
                        Spacer()
                    }
                    .padding(.top, 4)

                    Text("These values are applied to Tahera and Auton Planner during build/upload.")
                        .foregroundColor(Theme.subtext)
                        .font(.system(size: 18, weight: .medium))
                        .padding(.top, 4)
                }
            }
            .buttonStyle(TaheraActionButtonStyle())
        }
    }

    @ViewBuilder
    private func groupedCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.text)

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.16))
        )
    }

    @ViewBuilder
    private func assignmentChip(_ assignment: PortAssignment) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(assignment.color)
                .frame(width: 14, height: 14)
            Text("P\(assignment.port)")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(Theme.text)
            Text(assignment.title)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundColor(Theme.subtext)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.22))
        )
    }

    @ViewBuilder
    private func assignmentRow(_ name: String, value: Binding<Int>, reversed: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Text(name)
                .foregroundColor(Theme.subtext)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            Spacer()
            Stepper("P\(value.wrappedValue)", value: value, in: 1...21)
                .frame(width: 165)
                .font(.system(size: 19, weight: .bold, design: .rounded))
            Toggle("Reverse", isOn: reversed)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .tint(Theme.accent)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.14))
        )
    }

    @ViewBuilder
    private func sensorRow(_ name: String, value: Binding<Int>) -> some View {
        HStack(spacing: 14) {
            Text(name)
                .foregroundColor(Theme.subtext)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            Spacer()
            Stepper("P\(value.wrappedValue)", value: value, in: 1...21)
                .frame(width: 165)
                .font(.system(size: 19, weight: .bold, design: .rounded))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.14))
        )
    }

    private func loadBrainImage() -> NSImage? {
        guard let url = Bundle.module.url(forResource: "v5_brain", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private func brainOverlay(for image: NSImage) -> some View {
        ZStack {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()

            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    if showSocketNumbers {
                        ForEach(1...20, id: \.self) { port in
                            let anchor = socketPoint(for: port, in: size)
                            Text("\(port)")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.text.opacity(0.95))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.black.opacity(0.46))
                                )
                                .position(anchor)
                        }
                    }

                    ForEach(assignmentsByPort.keys.sorted(), id: \.self) { port in
                        if let grouped = assignmentsByPort[port] {
                            ForEach(Array(grouped.enumerated()), id: \.element.id) { index, assignment in
                                let anchor = socketPoint(for: port, in: size)
                                let offset = markerOffset(index: index, total: grouped.count)
                                assignmentMarker(
                                    assignment: assignment,
                                    center: CGPoint(
                                        x: anchor.x + offset.width,
                                        y: anchor.y + offset.height
                                    )
                                )
                            }
                        }
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .aspectRatio(max(image.size.width / max(image.size.height, 1), 0.1), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func assignmentMarker(assignment: PortAssignment, center: CGPoint) -> some View {
        ZStack {
            Circle()
                .fill(assignment.color)
                .frame(width: 30, height: 30)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.78), lineWidth: 1.2)
                )
                .shadow(color: assignment.color.opacity(0.45), radius: 7, x: 0, y: 3)

            Text(assignment.short)
                .font(.system(size: assignment.short.count > 2 ? 9.0 : 11.0, weight: .black, design: .rounded))
                .foregroundColor(Color.black.opacity(0.78))
        }
        .position(center)
    }

    private func markerOffset(index: Int, total: Int) -> CGSize {
        guard total > 1 else { return .zero }
        let radius: CGFloat = total == 2 ? 18 : 24
        let angle = (Double(index) / Double(total)) * (.pi * 2.0) - (.pi / 2.0)
        return CGSize(width: CGFloat(cos(angle)) * radius, height: CGFloat(sin(angle)) * radius)
    }

    private func socketPoint(for port: Int, in size: CGSize) -> CGPoint {
        let clampedPort = min(max(port, 1), 20)
        let index = (clampedPort - 1) % 10
        let isTop = clampedPort <= 10
        let xRatio = (isTop ? topPortX : bottomPortX)[index]
        let yRatio = isTop ? topPortY : bottomPortY
        return CGPoint(x: size.width * xRatio, y: size.height * yRatio)
    }

    private var assignmentsByPort: [Int: [PortAssignment]] {
        Dictionary(grouping: assignments, by: \.port)
    }

    private var duplicatePorts: [Int] {
        assignmentsByPort
            .filter { $0.value.count > 1 }
            .map(\.key)
            .sorted()
    }

    private var assignments: [PortAssignment] {
        [
            PortAssignment(id: "L1", short: "L1", title: "Left Outer 1", port: model.portMap.leftOuter1.value, color: Color(hex: 0x40DCC6)),
            PortAssignment(id: "L2", short: "L2", title: "Left Outer 2", port: model.portMap.leftOuter2.value, color: Color(hex: 0x57C8FF)),
            PortAssignment(id: "LM", short: "LM", title: "Left Middle", port: model.portMap.leftMiddle.value, color: Color(hex: 0x7CD8FF)),
            PortAssignment(id: "R1", short: "R1", title: "Right Outer 1", port: model.portMap.rightOuter1.value, color: Color(hex: 0x7BFF9E)),
            PortAssignment(id: "R2", short: "R2", title: "Right Outer 2", port: model.portMap.rightOuter2.value, color: Color(hex: 0x9BFF83)),
            PortAssignment(id: "RM", short: "RM", title: "Right Middle", port: model.portMap.rightMiddle.value, color: Color(hex: 0xC5FF7A)),
            PortAssignment(id: "IN", short: "IN", title: "Intake", port: model.portMap.intakeLeft.value, color: Color(hex: 0xFFCA6F)),
            PortAssignment(id: "OUT", short: "OUT", title: "Outake", port: model.portMap.intakeRight.value, color: Color(hex: 0xFFA76A)),
            PortAssignment(id: "IMU", short: "IMU", title: "Inertial Sensor", port: model.portMap.imu, color: Color(hex: 0xD4C2FF)),
            PortAssignment(id: "GPS", short: "GPS", title: "GPS Sensor", port: model.portMap.gps, color: Color(hex: 0xFFC1EA))
        ]
    }
}

private struct PortAssignment: Identifiable {
    let id: String
    let short: String
    let title: String
    let port: Int
    let color: Color
}
