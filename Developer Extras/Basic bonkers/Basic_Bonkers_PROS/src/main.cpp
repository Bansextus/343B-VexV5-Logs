#include "main.h"

#include <cmath>

namespace {
constexpr int kDeadband = 5;
constexpr int kAutonDrivePower = 50; // ~40%
constexpr int kAutonTurnPower = 38;  // ~30%
constexpr int kAutonForwardMs = 1500;
constexpr int kAutonTurnMs = 700;
}

// ======================================================
// MOTORS
// ======================================================
// Basic Bonkers port map (update if your robot differs):
// Left: 1,2,3  |  Right: 15,13,14 (reversed)
pros::MotorGroup left_motors({1, 2, 3}, pros::v5::MotorGears::red);
pros::MotorGroup right_motors({-15, -13, -14}, pros::v5::MotorGears::red);

pros::Controller master(pros::E_CONTROLLER_MASTER);

// ======================================================
// HELPERS
// ======================================================
int apply_deadband(int value) {
    return (std::abs(value) < kDeadband) ? 0 : value;
}

void stop_drive() {
    left_motors.move(0);
    right_motors.move(0);
}

// ======================================================
// INITIALIZE
// ======================================================
void initialize() {
    pros::lcd::initialize();
}

// ======================================================
// AUTONOMOUS (Basic Bonkers)
// ======================================================
void autonomous() {
    left_motors.move(kAutonDrivePower);
    right_motors.move(kAutonDrivePower);
    pros::delay(kAutonForwardMs);

    left_motors.move(-kAutonTurnPower);
    right_motors.move(kAutonTurnPower);
    pros::delay(kAutonTurnMs);

    stop_drive();
}

// ======================================================
// DRIVER CONTROL (Tank Drive)
// ======================================================
void opcontrol() {
    while (true) {
        int left_y = apply_deadband(master.get_analog(ANALOG_LEFT_Y));
        int right_y = apply_deadband(master.get_analog(ANALOG_RIGHT_Y));

        left_motors.move(left_y);
        right_motors.move(right_y);

        pros::delay(20);
    }
}
