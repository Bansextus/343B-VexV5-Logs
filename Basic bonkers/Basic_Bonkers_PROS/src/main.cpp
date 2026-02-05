#include "main.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <string>
#include <vector>

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

// Optional IMU for TURN_HEADING steps (update port if needed).
pros::Imu imu(11);

pros::Controller master(pros::E_CONTROLLER_MASTER);

// ======================================================
// AUTON PLAN SYSTEM (FROM TAHERA + AUTON CREATION TOOL)
// ======================================================
enum class AutonMode { GPS_MODE, BASIC_MODE };
static AutonMode g_auton_mode = AutonMode::GPS_MODE;

enum class StepType {
    DRIVE_MS,
    TURN_HEADING,
    WAIT_MS,
    INTAKE_ON,
    INTAKE_OFF,
    OUTTAKE_ON,
    OUTTAKE_OFF
};

struct Step {
    StepType type;
    int value1; // speed or heading or ms
    int value2; // duration for DRIVE_MS
};

static Step gps_plan[] = {
    {StepType::DRIVE_MS, 60, 1200},
    {StepType::TURN_HEADING, 90, 0},
    {StepType::DRIVE_MS, -40, 500},
    {StepType::WAIT_MS, 250, 0},
};

static Step basic_plan[] = {
    {StepType::DRIVE_MS, kAutonDrivePower, kAutonForwardMs},
    {StepType::TURN_HEADING, 90, 0},
    {StepType::DRIVE_MS, kAutonDrivePower, kAutonForwardMs / 2},
};

static std::vector<Step> gps_plan_sd;
static std::vector<Step> basic_plan_sd;
static bool g_sd_plans_loaded = false;

void update_auton_mode_from_controller() {
    if (master.get_digital(DIGITAL_A)) {
        g_auton_mode = AutonMode::GPS_MODE;
    } else if (master.get_digital(DIGITAL_B)) {
        g_auton_mode = AutonMode::BASIC_MODE;
    }
}

StepType parse_step_type(const std::string& token) {
    if (token == "DRIVE_MS") return StepType::DRIVE_MS;
    if (token == "TURN_HEADING") return StepType::TURN_HEADING;
    if (token == "WAIT_MS") return StepType::WAIT_MS;
    if (token == "INTAKE_ON") return StepType::INTAKE_ON;
    if (token == "INTAKE_OFF") return StepType::INTAKE_OFF;
    if (token == "OUTTAKE_ON") return StepType::OUTTAKE_ON;
    if (token == "OUTTAKE_OFF") return StepType::OUTTAKE_OFF;
    return StepType::WAIT_MS;
}

void load_sd_plans() {
    gps_plan_sd.clear();
    basic_plan_sd.clear();

    FILE* file = std::fopen("/usd/auton_plans.txt", "r");
    if (!file) {
        g_sd_plans_loaded = false;
        return;
    }

    enum class Section { NONE, GPS, BASIC };
    Section section = Section::NONE;

    char line[128];
    while (std::fgets(line, sizeof(line), file)) {
        std::string s(line);
        if (s.find("[GPS]") != std::string::npos) {
            section = Section::GPS;
            continue;
        }
        if (s.find("[BASIC]") != std::string::npos) {
            section = Section::BASIC;
            continue;
        }
        if (s.empty() || s[0] == '#') {
            continue;
        }

        char type_str[32];
        int v1 = 0;
        int v2 = 0;
        if (std::sscanf(s.c_str(), "%31[^,],%d,%d", type_str, &v1, &v2) == 3) {
            Step step{parse_step_type(type_str), v1, v2};
            if (section == Section::GPS) gps_plan_sd.push_back(step);
            if (section == Section::BASIC) basic_plan_sd.push_back(step);
        }
    }

    std::fclose(file);
    g_sd_plans_loaded = !(gps_plan_sd.empty() && basic_plan_sd.empty());
}

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

void turn_to_heading(double target, int max_speed) {
    while (true) {
        double current = imu.get_heading();
        double error = target - current;

        if (error > 180) error -= 360;
        if (error < -180) error += 360;

        if (std::abs(error) < 2.0) break;

        double kp = 1.5;
        int speed = static_cast<int>(error * kp);

        if (speed > max_speed) speed = max_speed;
        if (speed < -max_speed) speed = -max_speed;

        left_motors.move(speed);
        right_motors.move(-speed);
        pros::delay(20);
    }
    stop_drive();
}

void run_plan(const Step* plan, std::size_t count) {
    for (std::size_t i = 0; i < count; ++i) {
        const Step& step = plan[i];
        switch (step.type) {
            case StepType::DRIVE_MS:
                left_motors.move(step.value1);
                right_motors.move(step.value1);
                pros::delay(step.value2);
                stop_drive();
                break;
            case StepType::TURN_HEADING:
                turn_to_heading(step.value1, 60);
                break;
            case StepType::WAIT_MS:
                pros::delay(step.value1);
                break;
            case StepType::INTAKE_ON:
            case StepType::INTAKE_OFF:
            case StepType::OUTTAKE_ON:
            case StepType::OUTTAKE_OFF:
                // No intake/outtake in Basic Bonkers; ignore these steps.
                break;
        }
    }
}

// ======================================================
// INITIALIZE
// ======================================================
void initialize() {
    pros::lcd::initialize();
    imu.reset(true);
    while (imu.is_calibrating()) {
        pros::delay(10);
    }
    load_sd_plans();
}

// ======================================================
// AUTONOMOUS (Basic Bonkers)
// ======================================================
void autonomous() {
    update_auton_mode_from_controller();

    if (g_auton_mode == AutonMode::GPS_MODE) {
        if (g_sd_plans_loaded && !gps_plan_sd.empty()) {
            run_plan(gps_plan_sd.data(), gps_plan_sd.size());
        } else {
            run_plan(gps_plan, sizeof(gps_plan) / sizeof(gps_plan[0]));
        }
    } else {
        if (g_sd_plans_loaded && !basic_plan_sd.empty()) {
            run_plan(basic_plan_sd.data(), basic_plan_sd.size());
        } else {
            run_plan(basic_plan, sizeof(basic_plan) / sizeof(basic_plan[0]));
        }
    }
}

// ======================================================
// DRIVER CONTROL (Tank Drive)
// ======================================================
void opcontrol() {
    while (true) {
        int left_y = apply_deadband(master.get_analog(ANALOG_LEFT_Y));
        int right_y = apply_deadband(master.get_analog(ANALOG_RIGHT_Y));

        update_auton_mode_from_controller();

        left_motors.move(left_y);
        right_motors.move(right_y);

        pros::delay(20);
    }
}
