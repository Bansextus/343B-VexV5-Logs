import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case build = "Build & Upload"
    case controls = "Controller Mapping"
    case portMap = "Port Map"
    case sdCard = "SD Card"
    case field = "Field Replay"
    case virtualBrain = "Virtual Brain"
    case vexOS = "VEX OS UI"
    case readme = "README"
    case github = "Repository Settings"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .home:
            return "house.fill"
        case .build:
            return "hammer.fill"
        case .controls:
            return "gamecontroller.fill"
        case .portMap:
            return "point.3.connected.trianglepath.dotted"
        case .sdCard:
            return "sdcard.fill"
        case .field:
            return "map.fill"
        case .virtualBrain:
            return "cpu.fill"
        case .vexOS:
            return "display.2"
        case .readme:
            return "book.closed.fill"
        case .github:
            return "lock.shield.fill"
        }
    }
}

struct ProsProject: Identifiable {
    let id = UUID()
    var name: String
    var relativePath: String
    var slot: Int
}

struct PortValue {
    var value: Int
    var reversed: Bool

    func signed() -> Int {
        reversed ? -abs(value) : abs(value)
    }
}

struct PortMap {
    var leftOuter1 = PortValue(value: 1, reversed: true)
    var leftOuter2 = PortValue(value: 3, reversed: true)
    var leftMiddle = PortValue(value: 2, reversed: false)
    var rightOuter1 = PortValue(value: 4, reversed: false)
    var rightOuter2 = PortValue(value: 6, reversed: false)
    var rightMiddle = PortValue(value: 5, reversed: true)
    var intakeLeft = PortValue(value: 7, reversed: false)
    var intakeRight = PortValue(value: 8, reversed: false)
    var imu = 11
    var gps = 10
}

enum ControllerButton: String, CaseIterable, Identifiable {
    case l1 = "L1"
    case l2 = "L2"
    case r1 = "R1"
    case r2 = "R2"
    case a = "A"
    case b = "B"
    case x = "X"
    case y = "Y"
    case up = "UP"
    case down = "DOWN"
    case left = "LEFT"
    case right = "RIGHT"

    var id: String { rawValue }
}

enum DriveControlMode: String, CaseIterable, Identifiable {
    case tank = "TANK"
    case arcade2 = "ARCADE_2_STICK"
    case dpad = "DPAD"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tank:
            return "Tank Drive"
        case .arcade2:
            return "2 Stick Arcade"
        case .dpad:
            return "D-Pad"
        }
    }
}

enum ControllerAction: String, CaseIterable, Identifiable {
    case intakeIn = "INTAKE_IN"
    case intakeOut = "INTAKE_OUT"
    case outakeOut = "OUTAKE_OUT"
    case outakeIn = "OUTAKE_IN"
    case gpsEnable = "GPS_ENABLE"
    case gpsDisable = "GPS_DISABLE"
    case sixWheelOn = "SIX_WHEEL_ON"
    case sixWheelOff = "SIX_WHEEL_OFF"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .intakeIn:
            return "Intake In"
        case .intakeOut:
            return "Intake Out"
        case .outakeOut:
            return "Outake Out"
        case .outakeIn:
            return "Outake In"
        case .gpsEnable:
            return "GPS Drive Enable"
        case .gpsDisable:
            return "GPS Drive Disable"
        case .sixWheelOn:
            return "6 Wheel On"
        case .sixWheelOff:
            return "6 Wheel Off"
        }
    }

    var defaultButton: ControllerButton {
        switch self {
        case .intakeIn:
            return .l1
        case .intakeOut:
            return .l2
        case .outakeOut:
            return .r1
        case .outakeIn:
            return .r2
        case .gpsEnable:
            return .a
        case .gpsDisable:
            return .b
        case .sixWheelOn:
            return .y
        case .sixWheelOff:
            return .x
        }
    }
}
