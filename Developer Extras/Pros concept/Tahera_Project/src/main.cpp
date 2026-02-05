#include "main.h"
#include "hot-cold-asset/asset.hpp"
#include "lemlib/motions/follow.hpp"
#include "units/Angle.hpp"

#include <cstdint>
#include <cstdio>
#include <cmath>
#include <vector>

ASSET(auton_path_txt);

namespace {
constexpr double kStartX_m = 1.60675; // 160.675 cm
constexpr double kStartY_m = 0.65846; // 65.846 cm
constexpr double kStartHeadingDeg = 25.4375; // first-segment heading in compass degrees

constexpr char kJerkbotPath[] = "/usd/images/jerkbot.bmp";
}

// ======================================================
// 1. MOTORS & SENSORS (PROS 4 Syntax)
// ======================================================
// Use distinct names to avoid conflicts with LemLib's global motor groups.
pros::MotorGroup left_drive({-1, 2, -3}, pros::v5::MotorGears::blue);
pros::MotorGroup right_drive({4, -5, 6}, pros::v5::MotorGears::blue);

pros::Motor intake_left(7, pros::v5::MotorGears::blue);
pros::Motor intake_right(-8, pros::v5::MotorGears::blue);
pros::Motor outtake_left(9, pros::v5::MotorGears::blue);
pros::Motor outtake_right(-12, pros::v5::MotorGears::blue);

pros::Controller master(pros::E_CONTROLLER_MASTER);
pros::Imu imu(11);
pros::Gps gps(10);

enum class AutonMode {
    GPS_LEMLIB,
    NO_GPS
};

static AutonMode g_auton_mode = AutonMode::GPS_LEMLIB;

bool draw_bmp_from_sd(const char* path, int x, int y) {
    FILE* file = std::fopen(path, "rb");
    if (!file) {
        return false;
    }

    std::uint8_t header[54];
    if (std::fread(header, 1, sizeof(header), file) != sizeof(header)) {
        std::fclose(file);
        return false;
    }

    const std::uint32_t data_offset = *reinterpret_cast<std::uint32_t*>(&header[10]);
    const std::int32_t width = *reinterpret_cast<std::int32_t*>(&header[18]);
    const std::int32_t height = *reinterpret_cast<std::int32_t*>(&header[22]);
    const std::uint16_t bpp = *reinterpret_cast<std::uint16_t*>(&header[28]);
    const std::uint32_t compression = *reinterpret_cast<std::uint32_t*>(&header[30]);

    if (bpp != 24 || compression != 0 || width <= 0 || height == 0) {
        std::fclose(file);
        return false;
    }

    const std::int32_t abs_height = std::abs(height);
    const std::uint32_t row_size = ((bpp * width + 31) / 32) * 4;
    std::vector<std::uint8_t> row(row_size);

    std::fseek(file, static_cast<long>(data_offset), SEEK_SET);

    for (std::int32_t row_idx = 0; row_idx < abs_height; ++row_idx) {
        if (std::fread(row.data(), 1, row_size, file) != row_size) {
            break;
        }

        const std::int32_t draw_y = height > 0 ? (abs_height - 1 - row_idx) : row_idx;
        for (std::int32_t col = 0; col < width; ++col) {
            const std::size_t idx = static_cast<std::size_t>(col * 3);
            const std::uint8_t b = row[idx];
            const std::uint8_t g = row[idx + 1];
            const std::uint8_t r = row[idx + 2];
            const std::uint32_t color = (static_cast<std::uint32_t>(r) << 16) |
                                        (static_cast<std::uint32_t>(g) << 8) |
                                        static_cast<std::uint32_t>(b);
            pros::screen::set_pen(color);
            pros::screen::draw_pixel(x + col, y + draw_y);
        }
    }

    std::fclose(file);
    return true;
}

void draw_jerkbot() {
    draw_bmp_from_sd(kJerkbotPath, 0, 0);
}

void update_auton_mode_from_controller() {
    if (master.get_digital(DIGITAL_A)) {
        g_auton_mode = AutonMode::GPS_LEMLIB;
    } else if (master.get_digital(DIGITAL_B)) {
        g_auton_mode = AutonMode::NO_GPS;
    }
}

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

        left_drive.move(speed);
        right_drive.move(-speed);
        pros::delay(20);
    }
    left_drive.brake();
    right_drive.brake();
}

// ======================================================
// 3. COMPETITION PHASES
// ======================================================

void initialize() {
    pros::lcd::initialize();
    imu.reset(true);
    while (imu.is_calibrating()) {
        pros::delay(10);
    }
    draw_jerkbot();
}

void autonomous() {
    update_auton_mode_from_controller();
    draw_jerkbot();

    if (g_auton_mode == AutonMode::GPS_LEMLIB) {
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
    } else {
        // Simple non-GPS auton
        left_drive.move(60);
        right_drive.move(60);
        pros::delay(1500);

        left_drive.brake();
        right_drive.brake();
        pros::delay(100);

        turn_to_heading(90, 60);

        left_drive.move(-40);
        right_drive.move(-40);
        pros::delay(500);

        left_drive.brake();
        right_drive.brake();
    }
}

void opcontrol() {
    while (true) {
        update_auton_mode_from_controller();
        // --- TANK DRIVE LOGIC ---
        // Left stick controls left side, Right stick controls right side
        int left_y = master.get_analog(ANALOG_LEFT_Y);
        int right_y = master.get_analog(ANALOG_RIGHT_Y);

        left_drive.move(left_y);
        right_drive.move(right_y);

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

        pros::delay(20);
    }
}
