#include "main.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>

// =====================================================
// SIMPLE AUTON PLANNER (NO LEMLIB)
// =====================================================

pros::MotorGroup left_drive({-1, 2, -3}, pros::v5::MotorGears::blue);
pros::MotorGroup right_drive({4, -5, 6}, pros::v5::MotorGears::blue);

pros::Motor intake_left(7, pros::v5::MotorGears::blue);
pros::Motor intake_right(8, pros::v5::MotorGears::blue);

pros::Controller master(pros::E_CONTROLLER_MASTER);
pros::Imu imu(11);
pros::Gps gps(10);

namespace {
// Optional: SD image (place at /usd/Images/jerkbot.bmp or /usd/jerkbot.bmp)
constexpr char kJerkbotName[] = "jerkbot.bmp";

int g_step_index = 0;

bool starts_with(const char* str, const char* prefix) {
    if (!str || !prefix) {
        return false;
    }
    const std::size_t prefix_len = std::strlen(prefix);
    return std::strncmp(str, prefix, prefix_len) == 0;
}

bool try_mount_sd() {
    char buffer[64] = {0};
    errno = 0;
    return pros::usd::list_files("/", buffer, sizeof(buffer)) != PROS_ERR;
}

FILE* sd_open(const char* name, const char* mode) {
    if (!name || !mode) {
        return nullptr;
    }

    const char* prefixes[] = {
        "/usd/",
        "usd/",
        "/usd/Images/",
        "/usd/images/",
        "usd/Images/",
        "usd/images/",
    };

    for (int attempt = 0; attempt < 3; ++attempt) {
        FILE* file = std::fopen(name, mode);
        if (file) {
            return file;
        }

        if (starts_with(name, "usd/")) {
            char fixed[128];
            std::snprintf(fixed, sizeof(fixed), "/%s", name);
            file = std::fopen(fixed, mode);
            if (file) {
                return file;
            }
        }

        try_mount_sd();

        char path[128];
        for (const char* prefix : prefixes) {
            std::snprintf(path, sizeof(path), "%s%s", prefix, name);
            file = std::fopen(path, mode);
            if (file) {
                return file;
            }
        }

        pros::delay(50);
    }

    return nullptr;
}
}

// =====================================================
// AUTON MODE SELECTION
// =====================================================

enum class AutonMode { GPS_MODE, BASIC_MODE };
static AutonMode g_auton_mode = AutonMode::GPS_MODE;

void update_auton_mode_from_controller() {
    if (master.get_digital(DIGITAL_A)) {
        g_auton_mode = AutonMode::GPS_MODE;
    } else if (master.get_digital(DIGITAL_B)) {
        g_auton_mode = AutonMode::BASIC_MODE;
    }
}

// =====================================================
// BMP DRAW (24-bit uncompressed)
// =====================================================
bool draw_bmp_from_sd(const char* name, int x, int y) {
    FILE* file = sd_open(name, "rb");
    if (!file) return false;

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
    draw_bmp_from_sd(kJerkbotName, 0, 0);
}

// =====================================================
// SIMPLE HELPERS
// =====================================================

void stop_drive() {
    left_drive.brake();
    right_drive.brake();
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

        left_drive.move(speed);
        right_drive.move(-speed);
        pros::delay(20);
    }
    stop_drive();
}

// =====================================================
// AUTON STEP SYSTEM (EASY TO EDIT)
// =====================================================

enum class StepType {
    EMPTY,
    DRIVE_MS,
    TANK_MS,
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
    int value2; // duration for DRIVE_MS, right speed for TANK_MS
    int value3; // duration for TANK_MS
};

constexpr std::size_t kMaxSteps = 10;
constexpr int kSlotCount = 3;
constexpr char kSlot1File[] = "auton_plans_slot1.txt";
constexpr char kSlot2File[] = "auton_plans_slot2.txt";
constexpr char kSlot3File[] = "auton_plans_slot3.txt";
static int g_save_slot = 0;

// --- GPS MODE PLAN (EDIT THIS) ---
static Step gps_plan[kMaxSteps] = {
    {StepType::DRIVE_MS, 60, 1200, 0},
    {StepType::TURN_HEADING, 90, 0, 0},
    {StepType::DRIVE_MS, -40, 500, 0},
    {StepType::WAIT_MS, 250, 0, 0},
};

// --- BASIC MODE PLAN (EDIT THIS) ---
static Step basic_plan[kMaxSteps] = {
    {StepType::DRIVE_MS, 50, 1000, 0},
    {StepType::TURN_HEADING, 45, 0, 0},
    {StepType::DRIVE_MS, 50, 500, 0},
};

void run_plan(const Step* plan, std::size_t count) {
    for (std::size_t i = 0; i < count; ++i) {
        const Step& step = plan[i];
        switch (step.type) {
            case StepType::EMPTY:
                break;
            case StepType::DRIVE_MS:
                left_drive.move(step.value1);
                right_drive.move(step.value1);
                pros::delay(step.value2);
                stop_drive();
                break;
            case StepType::TANK_MS:
                left_drive.move(step.value1);
                right_drive.move(step.value2);
                pros::delay(step.value3);
                stop_drive();
                break;
            case StepType::TURN_HEADING:
                turn_to_heading(step.value1, 60);
                break;
            case StepType::WAIT_MS:
                pros::delay(step.value1);
                break;
            case StepType::INTAKE_ON:
                intake_left.move(127);
                intake_right.move(127);
                break;
            case StepType::INTAKE_OFF:
                intake_left.brake();
                intake_right.brake();
                break;
            case StepType::OUTTAKE_ON:
                intake_left.move(-127);
                intake_right.move(-127);
                break;
            case StepType::OUTTAKE_OFF:
                intake_left.brake();
                intake_right.brake();
                break;
        }
    }
}

// =====================================================
// SCREEN MENU (TOUCH UI)
// =====================================================

constexpr int kScreenW = 480;
constexpr int kScreenH = 240;

struct Rect {
    int x;
    int y;
    int w;
    int h;
};

bool hit_test(const Rect& r, int x, int y) {
    return x >= r.x && x <= (r.x + r.w) && y >= r.y && y <= (r.y + r.h);
}

const char* step_type_name(StepType type) {
    switch (type) {
        case StepType::EMPTY: return "EMPTY";
        case StepType::DRIVE_MS: return "DRIVE_MS";
        case StepType::TANK_MS: return "TANK_MS";
        case StepType::TURN_HEADING: return "TURN_HEADING";
        case StepType::WAIT_MS: return "WAIT_MS";
        case StepType::INTAKE_ON: return "INTAKE_ON";
        case StepType::INTAKE_OFF: return "INTAKE_OFF";
        case StepType::OUTTAKE_ON: return "OUTTAKE_ON";
        case StepType::OUTTAKE_OFF: return "OUTTAKE_OFF";
        default: return "UNKNOWN";
    }
}

StepType prev_step_type(StepType type) {
    switch (type) {
        case StepType::EMPTY: return StepType::OUTTAKE_OFF;
        case StepType::DRIVE_MS: return StepType::EMPTY;
        case StepType::TANK_MS: return StepType::DRIVE_MS;
        case StepType::TURN_HEADING: return StepType::TANK_MS;
        case StepType::WAIT_MS: return StepType::TURN_HEADING;
        case StepType::INTAKE_ON: return StepType::WAIT_MS;
        case StepType::INTAKE_OFF: return StepType::INTAKE_ON;
        case StepType::OUTTAKE_ON: return StepType::INTAKE_OFF;
        case StepType::OUTTAKE_OFF: return StepType::OUTTAKE_ON;
        default: return StepType::DRIVE_MS;
    }
}

StepType next_step_type(StepType type) {
    switch (type) {
        case StepType::EMPTY: return StepType::DRIVE_MS;
        case StepType::DRIVE_MS: return StepType::TANK_MS;
        case StepType::TANK_MS: return StepType::TURN_HEADING;
        case StepType::TURN_HEADING: return StepType::WAIT_MS;
        case StepType::WAIT_MS: return StepType::INTAKE_ON;
        case StepType::INTAKE_ON: return StepType::INTAKE_OFF;
        case StepType::INTAKE_OFF: return StepType::OUTTAKE_ON;
        case StepType::OUTTAKE_ON: return StepType::OUTTAKE_OFF;
        case StepType::OUTTAKE_OFF: return StepType::EMPTY;
        default: return StepType::DRIVE_MS;
    }
}

StepType parse_step_type(const std::string& token) {
    if (token == "EMPTY") return StepType::EMPTY;
    if (token == "DRIVE_MS") return StepType::DRIVE_MS;
    if (token == "TANK_MS") return StepType::TANK_MS;
    if (token == "TURN_HEADING") return StepType::TURN_HEADING;
    if (token == "WAIT_MS") return StepType::WAIT_MS;
    if (token == "INTAKE_ON") return StepType::INTAKE_ON;
    if (token == "INTAKE_OFF") return StepType::INTAKE_OFF;
    if (token == "OUTTAKE_ON") return StepType::OUTTAKE_ON;
    if (token == "OUTTAKE_OFF") return StepType::OUTTAKE_OFF;
    return StepType::EMPTY;
}

const char* slot_filename(int slot) {
    switch (slot) {
        case 0: return kSlot1File;
        case 1: return kSlot2File;
        case 2: return kSlot3File;
        default: return kSlot1File;
    }
}

int read_slot_file() {
    FILE* file = sd_open("auton_slot.txt", "r");
    if (!file) {
        return 0;
    }
    int slot = 1;
    if (std::fscanf(file, "%d", &slot) != 1) {
        std::fclose(file);
        return 0;
    }
    std::fclose(file);
    if (slot < 1 || slot > kSlotCount) {
        return 0;
    }
    return slot - 1;
}

void write_slot_file(int slot) {
    FILE* file = sd_open("auton_slot.txt", "w");
    if (!file) {
        return;
    }
    std::fprintf(file, "%d\n", slot + 1);
    std::fclose(file);
}

Step* active_plan(int* count) {
    if (g_auton_mode == AutonMode::GPS_MODE) {
        *count = static_cast<int>(kMaxSteps);
        return gps_plan;
    }
    *count = static_cast<int>(kMaxSteps);
    return basic_plan;
}

constexpr int kRecordSampleMs = 100;
constexpr int kRecordDeadband = 5;
constexpr int kRecordSnap = 5;

pros::Mutex g_plan_mutex;
bool g_recording = false;
bool g_record_full = false;
bool g_record_ui_dirty = false;
AutonMode g_record_mode = AutonMode::GPS_MODE;
int g_record_index = 0;

int snap_speed(int value) {
    if (std::abs(value) <= kRecordDeadband) {
        return 0;
    }
    const int snapped = static_cast<int>(std::round(static_cast<double>(value) / kRecordSnap)) * kRecordSnap;
    return std::max(-127, std::min(127, snapped));
}

void clear_plan(Step* plan, int count) {
    for (int i = 0; i < count; ++i) {
        plan[i] = {StepType::EMPTY, 0, 0, 0};
    }
}

bool load_plans_from_sd(const char* filename) {
    FILE* file = sd_open(filename, "r");
    if (!file) {
        return false;
    }

    g_plan_mutex.take();
    clear_plan(gps_plan, static_cast<int>(kMaxSteps));
    clear_plan(basic_plan, static_cast<int>(kMaxSteps));

    enum class Section { NONE, GPS, BASIC };
    Section section = Section::NONE;
    int gps_idx = 0;
    int basic_idx = 0;

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
        int v3 = 0;
        const int fields = std::sscanf(s.c_str(), "%31[^,],%d,%d,%d", type_str, &v1, &v2, &v3);
        if (fields >= 3) {
            Step step{parse_step_type(type_str), v1, v2, v3};
            if (section == Section::GPS && gps_idx < static_cast<int>(kMaxSteps)) {
                gps_plan[gps_idx++] = step;
            } else if (section == Section::BASIC && basic_idx < static_cast<int>(kMaxSteps)) {
                basic_plan[basic_idx++] = step;
            }
        }
    }

    std::fclose(file);
    g_plan_mutex.give();
    g_record_ui_dirty = true;
    return true;
}

void start_recording() {
    g_plan_mutex.take();
    g_record_mode = g_auton_mode;
    Step* plan = (g_record_mode == AutonMode::GPS_MODE) ? gps_plan : basic_plan;
    clear_plan(plan, static_cast<int>(kMaxSteps));
    g_record_index = 0;
    g_record_full = false;
    g_recording = true;
    g_record_ui_dirty = true;
    g_plan_mutex.give();
}

void stop_recording() {
    g_recording = false;
    g_record_ui_dirty = true;
}

void record_sample(int left_speed, int right_speed) {
    if (!g_recording) {
        return;
    }

    const int left = snap_speed(left_speed);
    const int right = snap_speed(right_speed);

    g_plan_mutex.take();
    Step* plan = (g_record_mode == AutonMode::GPS_MODE) ? gps_plan : basic_plan;

    if (g_record_index == 0 && plan[0].type == StepType::EMPTY) {
        plan[0] = {StepType::TANK_MS, left, right, kRecordSampleMs};
        g_record_index = 1;
        g_plan_mutex.give();
        return;
    }

    Step& last = plan[g_record_index - 1];
    if (last.type == StepType::TANK_MS && last.value1 == left && last.value2 == right) {
        last.value3 += kRecordSampleMs;
        g_plan_mutex.give();
        return;
    }

    if (g_record_index >= static_cast<int>(kMaxSteps)) {
        g_recording = false;
        g_record_full = true;
        g_record_ui_dirty = true;
        g_plan_mutex.give();
        return;
    }

    plan[g_record_index++] = {StepType::TANK_MS, left, right, kRecordSampleMs};
    g_plan_mutex.give();
}

void draw_button(const Rect& r, const char* label, std::uint32_t color) {
    pros::screen::set_pen(color);
    pros::screen::draw_rect(r.x, r.y, r.x + r.w, r.y + r.h);
    pros::screen::print(TEXT_MEDIUM, r.x + 6, r.y + 8, label);
}

Rect record_button_rect() {
    return {10, 180, 140, 30};
}

void draw_record_button() {
    const Rect rec_btn = record_button_rect();
    const bool recording = g_recording;
    const char* label = recording ? "STOP" : "REC";
    const std::uint32_t color = recording ? 0x00FF0000 : 0x0000FF00;

    pros::screen::set_pen(0x00000000);
    pros::screen::fill_rect(rec_btn.x, rec_btn.y, rec_btn.x + rec_btn.w, rec_btn.y + rec_btn.h);
    draw_button(rec_btn, label, color);
}

void draw_menu(AutonMode mode, int step_index, Step* plan, std::size_t count, int slot) {
    pros::screen::set_pen(0x00000000);
    pros::screen::fill_rect(0, 0, kScreenW - 1, kScreenH - 1);

    const Rect gps_btn{10, 10, 90, 30};
    const Rect basic_btn{110, 10, 90, 30};
    const Rect save_btn{210, 10, 90, 30};
    const Rect slot1_btn{310, 10, 50, 30};
    const Rect slot2_btn{365, 10, 50, 30};
    const Rect slot3_btn{420, 10, 50, 30};

    draw_button(gps_btn, "GPS", mode == AutonMode::GPS_MODE ? 0x0000FF00 : 0x00FFFFFF);
    draw_button(basic_btn, "BASIC", mode == AutonMode::BASIC_MODE ? 0x0000FF00 : 0x00FFFFFF);
    draw_button(save_btn, "SAVE", 0x00FFFF00);
    draw_button(slot1_btn, "S1", slot == 0 ? 0x0000FF00 : 0x00FFFFFF);
    draw_button(slot2_btn, "S2", slot == 1 ? 0x0000FF00 : 0x00FFFFFF);
    draw_button(slot3_btn, "S3", slot == 2 ? 0x0000FF00 : 0x00FFFFFF);

    const Rect prev_btn{10, 60, 70, 30};
    const Rect next_btn{90, 60, 70, 30};
    const Rect type_btn{170, 60, 140, 30};
    const Rect v1m_btn{320, 60, 50, 30};
    const Rect v1p_btn{380, 60, 50, 30};
    const Rect v2m_btn{320, 100, 50, 30};
    const Rect v2p_btn{380, 100, 50, 30};
    const Rect v3m_btn{320, 140, 50, 30};
    const Rect v3p_btn{380, 140, 50, 30};
    const Rect rec_btn = record_button_rect();
    const Rect clr_btn{170, 180, 140, 30};

    draw_button(prev_btn, "PREV", 0x00FFFFFF);
    draw_button(next_btn, "NEXT", 0x00FFFFFF);
    draw_button(type_btn, "TYPE", 0x00FFFFFF);
    draw_button(v1m_btn, "V1-", 0x00FFFFFF);
    draw_button(v1p_btn, "V1+", 0x00FFFFFF);
    draw_button(v2m_btn, "V2-", 0x00FFFFFF);
    draw_button(v2p_btn, "V2+", 0x00FFFFFF);
    draw_button(v3m_btn, "V3-", 0x00FFFFFF);
    draw_button(v3p_btn, "V3+", 0x00FFFFFF);
    draw_record_button();
    draw_button(clr_btn, "CLEAR", 0x00FFFFFF);

    if (step_index < 0) step_index = 0;
    if (step_index >= static_cast<int>(count)) step_index = static_cast<int>(count) - 1;

    const Step& step = plan[step_index];
    pros::screen::print(TEXT_MEDIUM, 10, 120, "STEP: %d / %d", step_index + 1, static_cast<int>(count));
    pros::screen::print(TEXT_MEDIUM, 10, 140, "TYPE: %s", step_type_name(step.type));
    pros::screen::print(TEXT_MEDIUM, 10, 160, "V1:%d  V2:%d  V3:%d", step.value1, step.value2, step.value3);
    pros::screen::print(TEXT_MEDIUM, 10, 95, "SLOT: %d", slot + 1);
}

bool save_plans_to_sd(const char* filename) {
    FILE* file = sd_open(filename, "w");
    if (!file) return false;

    g_plan_mutex.take();
    std::fprintf(file, "[GPS]\\n");
    for (const auto& step : gps_plan) {
        std::fprintf(file, "%s,%d,%d,%d\\n", step_type_name(step.type), step.value1, step.value2, step.value3);
    }

    std::fprintf(file, "[BASIC]\\n");
    for (const auto& step : basic_plan) {
        std::fprintf(file, "%s,%d,%d,%d\\n", step_type_name(step.type), step.value1, step.value2, step.value3);
    }

    g_plan_mutex.give();
    std::fclose(file);
    write_slot_file(g_save_slot);
    return true;
}


void menu_loop() {
    int step_index = 0;
    draw_menu(g_auton_mode, step_index,
              g_auton_mode == AutonMode::GPS_MODE ? gps_plan : basic_plan,
              static_cast<int>(kMaxSteps), g_save_slot);

    bool touch_armed = false;

    while (true) {
        if (g_record_ui_dirty) {
            Step* plan = g_auton_mode == AutonMode::GPS_MODE ? gps_plan : basic_plan;
            draw_menu(g_auton_mode, step_index, plan, kMaxSteps, g_save_slot);
            g_record_ui_dirty = false;
        }

        pros::screen_touch_status_s_t status = pros::screen::touch_status();
        if (status.touch_status == pros::E_TOUCH_PRESSED || status.touch_status == pros::E_TOUCH_HELD) {
            touch_armed = true;
        }

        if (status.touch_status == pros::E_TOUCH_RELEASED && touch_armed) {
            touch_armed = false;
            const int x = status.x;
            const int y = status.y;

            const Rect gps_btn{10, 10, 90, 30};
            const Rect basic_btn{110, 10, 90, 30};
            const Rect save_btn{210, 10, 90, 30};
            const Rect slot1_btn{310, 10, 50, 30};
            const Rect slot2_btn{365, 10, 50, 30};
            const Rect slot3_btn{420, 10, 50, 30};
            const Rect prev_btn{10, 60, 70, 30};
            const Rect next_btn{90, 60, 70, 30};
            const Rect type_btn{170, 60, 140, 30};
            const Rect v1m_btn{320, 60, 50, 30};
            const Rect v1p_btn{380, 60, 50, 30};
            const Rect v2m_btn{320, 100, 50, 30};
            const Rect v2p_btn{380, 100, 50, 30};
            const Rect v3m_btn{320, 140, 50, 30};
            const Rect v3p_btn{380, 140, 50, 30};
            const Rect rec_btn = record_button_rect();
            const Rect clr_btn{170, 180, 140, 30};

            if (hit_test(rec_btn, x, y)) {
                if (g_recording) {
                    stop_recording();
                } else {
                    start_recording();
                }
                Step* plan = g_auton_mode == AutonMode::GPS_MODE ? gps_plan : basic_plan;
                draw_menu(g_auton_mode, step_index, plan, kMaxSteps, g_save_slot);
                pros::delay(50);
                continue;
            }

            if (hit_test(clr_btn, x, y)) {
                stop_recording();
                g_plan_mutex.take();
                Step* plan = g_auton_mode == AutonMode::GPS_MODE ? gps_plan : basic_plan;
                clear_plan(plan, static_cast<int>(kMaxSteps));
                g_plan_mutex.give();
                step_index = 0;
                draw_menu(g_auton_mode, step_index, plan, kMaxSteps, g_save_slot);
                pros::delay(50);
                continue;
            }

            if (g_recording) {
                draw_menu(g_auton_mode, step_index,
                          g_auton_mode == AutonMode::GPS_MODE ? gps_plan : basic_plan,
                          kMaxSteps, g_save_slot);
                pros::delay(50);
                continue;
            }

            if (hit_test(gps_btn, x, y)) g_auton_mode = AutonMode::GPS_MODE;
            if (hit_test(basic_btn, x, y)) g_auton_mode = AutonMode::BASIC_MODE;
            if (hit_test(save_btn, x, y)) save_plans_to_sd(slot_filename(g_save_slot));

            if (hit_test(slot1_btn, x, y)) {
                g_save_slot = 0;
                write_slot_file(g_save_slot);
                if (!load_plans_from_sd(slot_filename(g_save_slot))) {
                    g_plan_mutex.take();
                    clear_plan(gps_plan, static_cast<int>(kMaxSteps));
                    clear_plan(basic_plan, static_cast<int>(kMaxSteps));
                    g_plan_mutex.give();
                    g_record_ui_dirty = true;
                }
            }
            if (hit_test(slot2_btn, x, y)) {
                g_save_slot = 1;
                write_slot_file(g_save_slot);
                if (!load_plans_from_sd(slot_filename(g_save_slot))) {
                    g_plan_mutex.take();
                    clear_plan(gps_plan, static_cast<int>(kMaxSteps));
                    clear_plan(basic_plan, static_cast<int>(kMaxSteps));
                    g_plan_mutex.give();
                    g_record_ui_dirty = true;
                }
            }
            if (hit_test(slot3_btn, x, y)) {
                g_save_slot = 2;
                write_slot_file(g_save_slot);
                if (!load_plans_from_sd(slot_filename(g_save_slot))) {
                    g_plan_mutex.take();
                    clear_plan(gps_plan, static_cast<int>(kMaxSteps));
                    clear_plan(basic_plan, static_cast<int>(kMaxSteps));
                    g_plan_mutex.give();
                    g_record_ui_dirty = true;
                }
            }

            Step* plan = g_auton_mode == AutonMode::GPS_MODE ? gps_plan : basic_plan;
            const int count = static_cast<int>(kMaxSteps);

            if (hit_test(prev_btn, x, y)) step_index = std::max(0, step_index - 1);
            if (hit_test(next_btn, x, y)) step_index = std::min(count - 1, step_index + 1);

            g_plan_mutex.take();
            if (hit_test(type_btn, x, y)) plan[step_index].type = next_step_type(plan[step_index].type);
            if (hit_test(v1m_btn, x, y)) plan[step_index].value1 -= 5;
            if (hit_test(v1p_btn, x, y)) plan[step_index].value1 += 5;
            if (hit_test(v2m_btn, x, y)) plan[step_index].value2 -= 50;
            if (hit_test(v2p_btn, x, y)) plan[step_index].value2 += 50;
            if (hit_test(v3m_btn, x, y)) plan[step_index].value3 -= 50;
            if (hit_test(v3p_btn, x, y)) plan[step_index].value3 += 50;
            g_plan_mutex.give();

            draw_menu(g_auton_mode, step_index, plan, count, g_save_slot);
        }

        pros::delay(50);
    }
}

void menu_task_fn(void*) {
    menu_loop();
}

// =====================================================
// PROS LIFECYCLE
// =====================================================

void initialize() {
    pros::lcd::initialize();
    imu.reset(true);
    while (imu.is_calibrating()) {
        pros::delay(10);
    }
    g_save_slot = read_slot_file();
    load_plans_from_sd(slot_filename(g_save_slot));
    static pros::Task menu_task(menu_task_fn, nullptr, TASK_PRIORITY_DEFAULT,
                                TASK_STACK_DEPTH_DEFAULT, "AutonMenu");
}

void autonomous() {
    update_auton_mode_from_controller();

    if (g_auton_mode == AutonMode::GPS_MODE) {
        run_plan(gps_plan, sizeof(gps_plan) / sizeof(gps_plan[0]));
    } else {
        run_plan(basic_plan, sizeof(basic_plan) / sizeof(basic_plan[0]));
    }
}

void opcontrol() {
    int record_timer_ms = 0;
    while (true) {
        update_auton_mode_from_controller();

        int left_y = master.get_analog(ANALOG_LEFT_Y);
        int right_y = master.get_analog(ANALOG_RIGHT_Y);

        record_timer_ms += 20;
        if (record_timer_ms >= kRecordSampleMs) {
            record_timer_ms = 0;
            record_sample(left_y, right_y);
        }

        left_drive.move(left_y);
        right_drive.move(right_y);

        // --- LEFT SIDE INTAKE + OUTTAKE (L1/L2) ---
        if (master.get_digital(DIGITAL_L1)) {
            intake_left.move(127);
        } else if (master.get_digital(DIGITAL_L2)) {
            intake_left.move(-127);
        } else {
            intake_left.brake();
        }

        // --- RIGHT SIDE INTAKE + OUTTAKE (R1/R2) ---
        if (master.get_digital(DIGITAL_R1)) {
            intake_right.move(127);
        } else if (master.get_digital(DIGITAL_R2)) {
            intake_right.move(-127);
        } else {
            intake_right.brake();
        }

        pros::delay(20);
    }
}
