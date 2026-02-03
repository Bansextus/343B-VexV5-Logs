#include "main.h"
#include "hot-cold-asset/asset.hpp"
#include "lemlib/motions/follow.hpp"
#include "units/Angle.hpp"

#include <cmath> 

ASSET(auton_path_txt);

namespace {
constexpr double kStartX_m = 1.60675; // 160.675 cm
constexpr double kStartY_m = 0.65846; // 65.846 cm
constexpr double kStartHeadingDeg = 25.4375; // first-segment heading in compass degrees
}

// ======================================================
// 1. MOTORS & SENSORS (PROS 4 Syntax)
// ======================================================
pros::MotorGroup left_motors({-1, 2, -3}, pros::v5::MotorGears::blue);
pros::MotorGroup right_motors({4, -5, 6}, pros::v5::MotorGears::blue);

pros::Motor intake_left(7, pros::v5::MotorGears::blue);
pros::Motor intake_right(-8, pros::v5::MotorGears::blue);
pros::Motor outtake_left(9, pros::v5::MotorGears::blue);
pros::Motor outtake_right(-12, pros::v5::MotorGears::blue);

pros::Controller master(pros::E_CONTROLLER_MASTER);
pros::Imu imu(11);
pros::Gps gps(10);

// ======================================================
// 2. HELPER FUNCTIONS
// ======================================================

void turn_to_heading(double target, int max_speed) {
    while (true) {
        double current = imu.get_heading();
        double error = target - current;

        if (error > 180) error -= 360;
        if (error < -180) error += 360;

        if (std::abs(error) < 2.0) break;

        double kp = 1.5; 
        int speed = error * kp;

        if (speed > max_speed) speed = max_speed;
        if (speed < -max_speed) speed = -max_speed;

        left_motors.move(speed);
        right_motors.move(-speed);
        pros::delay(20);
    }
    left_motors.brake();
    right_motors.brake();
}

// ======================================================
// 3. COMPETITION PHASES
// ======================================================

void initialize() {
    pros::lcd::initialize();
    imu.reset(true); 
}

void autonomous() {
    gps.set_position(kStartX_m, kStartY_m, kStartHeadingDeg);

    lemlib::follow(
        auton_path_txt,
        10_in,
        12_sec,
        {},
        {.poseGetter =
             [] -> units::Pose {
                 const auto position = gps.get_position();
                 return units::Pose(from_m(position.x), from_m(position.y), from_cDeg(gps.get_heading()));
             }});

    // TODO: add outtake action here once installed.
}

void opcontrol() {
    while (true) {
        // --- TANK DRIVE LOGIC ---
        // Left stick controls left side, Right stick controls right side
        int left_y = master.get_analog(ANALOG_LEFT_Y);
        int right_y = master.get_analog(ANALOG_RIGHT_Y);

        left_motors.move(left_y);
        right_motors.move(right_y);

        // --- INTAKE CONTROL (L1/L2) ---
        if (master.get_digital(DIGITAL_L1)) {
            intake_left.move(127);
            intake_right.move(127);
        } else if (master.get_digital(DIGITAL_L2)) {
            intake_left.move(-127);
            intake_right.move(-127);
        } else {
            intake_left.brake();
            intake_right.brake();
        }

        // --- OUTTAKE CONTROL (R1/R2) ---
        if (master.get_digital(DIGITAL_R1)) {
            outtake_left.move(127);
            outtake_right.move(127);
        } else if (master.get_digital(DIGITAL_R2)) {
            outtake_left.move(-127);
            outtake_right.move(-127);
        } else {
            outtake_left.brake();
            outtake_right.brake();
        }

        // --- GPS READOUT (BRAIN SCREEN) ---
        static uint32_t last_screen_ms = 0;
        const uint32_t now = pros::millis();
        if (now - last_screen_ms >= 200) {
            const auto position = gps.get_position();
            pros::screen::print(pros::TEXT_MEDIUM, 1, "GPS X: %.2f m", position.x);
            pros::screen::print(pros::TEXT_MEDIUM, 2, "GPS Y: %.2f m", position.y);
            pros::screen::print(pros::TEXT_MEDIUM, 3, "GPS H: %.2f deg", gps.get_heading() / 100.0);
            last_screen_ms = now;
        }

        pros::delay(20);
    }
}
