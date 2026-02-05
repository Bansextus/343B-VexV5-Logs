#include "hardware/Motor/Motor.hpp"
#include "hardware/Motor/MotorGroup.hpp"
#include "units/Temperature.hpp"

#include <algorithm>
#include <cmath>

namespace lemlib {
namespace {
constexpr double kRadToDeg = 180.0 / M_PI;
constexpr double kDegToRad = M_PI / 180.0;

pros::Motor make_motor(ReversibleSmartPort port) {
    const int raw_port = static_cast<int>(port);
    const int abs_port = std::abs(raw_port);
    const bool reversed = raw_port < 0;
    pros::Motor motor(abs_port, pros::v5::MotorGears::blue);
    motor.set_reversed(reversed);
    return motor;
}

pros::v5::MotorBrake to_pros_brake(BrakeMode mode) {
    switch (mode) {
        case BrakeMode::BRAKE:
            return pros::v5::MotorBrake::brake;
        case BrakeMode::HOLD:
            return pros::v5::MotorBrake::hold;
        case BrakeMode::COAST:
        default:
            return pros::v5::MotorBrake::coast;
    }
}

BrakeMode from_pros_brake(pros::v5::MotorBrake mode) {
    switch (mode) {
        case pros::v5::MotorBrake::brake:
            return BrakeMode::BRAKE;
        case pros::v5::MotorBrake::hold:
            return BrakeMode::HOLD;
        case pros::v5::MotorBrake::coast:
        default:
            return BrakeMode::COAST;
    }
}
}

// ------------------------------
// Motor
// ------------------------------
Motor::Motor(ReversibleSmartPort port, AngularVelocity outputVelocity)
    : m_outputVelocity(outputVelocity), m_port(port) {}

Motor Motor::from_pros_motor(const pros::Motor motor, AngularVelocity outputVelocity) {
    const int port = motor.get_port();
    const int signed_port = motor.is_reversed() ? -port : port;
    return Motor(ReversibleSmartPort {signed_port, runtime_check_port}, outputVelocity);
}

int Motor::move(Number percent) {
    pros::Motor motor = make_motor(m_port);
    double p = static_cast<double>(percent);
    p = std::clamp(p, -1.0, 1.0);
    motor.move(static_cast<int>(p * 127));
    return 0;
}

int Motor::moveVelocity(AngularVelocity velocity) {
    pros::Motor motor = make_motor(m_port);
    const double rad_per_sec = velocity.internal();
    const double rpm = (rad_per_sec * 60.0) / (2.0 * M_PI);
    motor.move_velocity(static_cast<int>(rpm));
    return 0;
}

int Motor::brake() {
    pros::Motor motor = make_motor(m_port);
    motor.brake();
    return 0;
}

int Motor::setBrakeMode(BrakeMode mode) {
    pros::Motor motor = make_motor(m_port);
    motor.set_brake_mode(to_pros_brake(mode));
    return 0;
}

BrakeMode Motor::getBrakeMode() const {
    pros::Motor motor = make_motor(m_port);
    return from_pros_brake(motor.get_brake_mode());
}

int Motor::isConnected() {
    pros::Motor motor = make_motor(m_port);
    return motor.is_installed();
}

Angle Motor::getAngle() {
    pros::Motor motor = make_motor(m_port);
    const double deg = motor.get_position();
    return Angle(deg * kDegToRad) + m_offset;
}

int Motor::setAngle(Angle angle) {
    pros::Motor motor = make_motor(m_port);
    const double deg = motor.get_position();
    const Angle current(deg * kDegToRad);
    m_offset = Angle(angle.internal() - current.internal());
    return 0;
}

Angle Motor::getOffset() const {
    return m_offset;
}

int Motor::setOffset(Angle offset) {
    m_offset = offset;
    return 0;
}

MotorType Motor::getType() {
    return MotorType::V5;
}

int Motor::isReversed() const {
    pros::Motor motor = make_motor(m_port);
    return motor.is_reversed();
}

int Motor::setReversed(bool reversed) {
    pros::Motor motor = make_motor(m_port);
    motor.set_reversed(reversed);
    return 0;
}

ReversibleSmartPort Motor::getPort() const {
    return m_port;
}

Current Motor::getCurrentLimit() const {
    pros::Motor motor = make_motor(m_port);
    const double amps = motor.get_current_limit() / 1000.0;
    return Current(amps);
}

int Motor::setCurrentLimit(Current limit) {
    pros::Motor motor = make_motor(m_port);
    const int milliamps = static_cast<int>(limit.internal() * 1000.0);
    motor.set_current_limit(milliamps);
    return 0;
}

Temperature Motor::getTemperature() const {
    pros::Motor motor = make_motor(m_port);
    const double celsius = motor.get_temperature();
    return units::from_celsius(Number(celsius));
}

int Motor::setOutputVelocity(AngularVelocity outputVelocity) {
    m_outputVelocity = outputVelocity;
    return 0;
}

// ------------------------------
// MotorGroup
// ------------------------------
MotorGroup::MotorGroup(std::initializer_list<ReversibleSmartPort> ports, AngularVelocity outputVelocity)
    : m_outputVelocity(outputVelocity) {
    for (auto port : ports) {
        m_motors.push_back({port, true, 0_stDeg});
    }
}

MotorGroup MotorGroup::from_pros_group(const pros::MotorGroup group, AngularVelocity outputVelocity) {
    (void)group;
    return MotorGroup({}, outputVelocity);
}

int MotorGroup::move(Number percent) {
    double p = static_cast<double>(percent);
    p = std::clamp(p, -1.0, 1.0);
    for (const auto& info : m_motors) {
        pros::Motor motor = make_motor(info.port);
        motor.move(static_cast<int>(p * 127));
    }
    return 0;
}

int MotorGroup::moveVelocity(AngularVelocity velocity) {
    const double rad_per_sec = velocity.internal();
    const double rpm = (rad_per_sec * 60.0) / (2.0 * M_PI);
    for (const auto& info : m_motors) {
        pros::Motor motor = make_motor(info.port);
        motor.move_velocity(static_cast<int>(rpm));
    }
    return 0;
}

int MotorGroup::brake() {
    for (const auto& info : m_motors) {
        pros::Motor motor = make_motor(info.port);
        motor.brake();
    }
    return 0;
}

int MotorGroup::setBrakeMode(BrakeMode mode) {
    m_brakeMode = mode;
    for (const auto& info : m_motors) {
        pros::Motor motor = make_motor(info.port);
        motor.set_brake_mode(to_pros_brake(mode));
    }
    return 0;
}

BrakeMode MotorGroup::getBrakeMode() {
    return m_brakeMode;
}

int MotorGroup::isConnected() {
    for (const auto& info : m_motors) {
        pros::Motor motor = make_motor(info.port);
        if (motor.is_installed()) {
            return 1;
        }
    }
    return 0;
}

Angle MotorGroup::getAngle() {
    if (m_motors.empty()) {
        return Angle(INFINITY);
    }

    double sum = 0.0;
    for (const auto& info : m_motors) {
        pros::Motor motor = make_motor(info.port);
        const double deg = motor.get_position();
        sum += (deg * kDegToRad) + info.offset.internal();
    }

    return Angle(sum / static_cast<double>(m_motors.size()));
}

int MotorGroup::setAngle(Angle angle) {
    for (auto& info : m_motors) {
        pros::Motor motor = make_motor(info.port);
        const double deg = motor.get_position();
        const double current_rad = deg * kDegToRad;
        info.offset = Angle(angle.internal() - current_rad);
    }
    return 0;
}

int MotorGroup::addMotor(ReversibleSmartPort port) {
    for (const auto& info : m_motors) {
        if (info.port == port) {
            return 0;
        }
    }
    m_motors.push_back({port, true, 0_stDeg});
    return 0;
}

int MotorGroup::addMotor(Motor motor) {
    return addMotor(motor.getPort());
}

int MotorGroup::addMotor(Motor motor, bool reversed) {
    return addMotor(motor.getPort().set_reversed(reversed));
}

void MotorGroup::removeMotor(ReversibleSmartPort port) {
    m_motors.erase(
        std::remove_if(m_motors.begin(), m_motors.end(),
                       [port](const MotorInfo& info) { return info.port == port; }),
        m_motors.end());
}

void MotorGroup::removeMotor(Motor motor) {
    removeMotor(motor.getPort());
}

Angle MotorGroup::configureMotor(ReversibleSmartPort port) {
    (void)port;
    return 0_stDeg;
}

const std::vector<Motor> MotorGroup::getMotors() {
    std::vector<Motor> motors;
    motors.reserve(m_motors.size());
    for (const auto& info : m_motors) {
        Motor motor(info.port, m_outputVelocity);
        motor.setOffset(info.offset);
        motors.push_back(motor);
    }
    return motors;
}

} // namespace lemlib
