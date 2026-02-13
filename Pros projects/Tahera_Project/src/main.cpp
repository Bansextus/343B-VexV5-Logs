#include "main.h"
#include <algorithm>
#include <cstddef>
#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <string>
#include <cmath>
#include <vector>
#include <cstring>

namespace {
constexpr char kLoadingIconName[] = "loading_icon.bmp";
constexpr int kScreenW = 480;
constexpr int kScreenH = 240;
constexpr int kSplashHoldMs = 2000;

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

// ======================================================
// 1. MOTORS & SENSORS (PROS 4 Syntax)
// ======================================================
// Use distinct names to avoid conflicts with LemLib's global motor groups.
// Outer motors are grouped; middle motors are controlled separately for 6WD toggle.
pros::MotorGroup left_drive({-1, -3}, pros::v5::MotorGears::blue);
pros::MotorGroup right_drive({4, 6}, pros::v5::MotorGears::blue);
pros::Motor left_middle(2, pros::v5::MotorGears::blue);
pros::Motor right_middle(-5, pros::v5::MotorGears::blue);

pros::Motor intake_left(7, pros::v5::MotorGears::blue);
pros::Motor intake_right(8, pros::v5::MotorGears::blue);

pros::Controller master(pros::E_CONTROLLER_MASTER);
pros::Imu imu(11);
pros::Gps gps(10);

enum class AutonMode {
    GPS_LEMLIB,
    NO_GPS
};

static AutonMode g_auton_mode = AutonMode::GPS_LEMLIB;
static bool g_sd_plans_loaded = false;
static bool g_manual_auton_request = false;
static bool g_auton_running = false;
static bool g_gps_drive_enabled = false;
static bool g_six_wheel_drive_enabled = true;
pros::Mutex g_auton_mutex;
constexpr int kSlotCount = 3;
constexpr char kSlot1File[] = "auton_plans_slot1.txt";
constexpr char kSlot2File[] = "auton_plans_slot2.txt";
constexpr char kSlot3File[] = "auton_plans_slot3.txt";
constexpr char kSlotIndexFile[] = "auton_slot.txt";
static int g_active_slot = 0;
constexpr char kUiConfigName[] = "ui_images.txt";
constexpr char kDefaultSplash[] = "loading_icon.bmp";
constexpr char kDefaultRun[] = "jerkbot.bmp";
constexpr int kAutonMaxMs = 15000;
std::string g_splash_image = kDefaultSplash;
std::string g_auton_image = kDefaultRun;
std::string g_driver_image;
std::string g_run_image = kDefaultRun;
bool g_ui_locked = false;
bool g_force_driver_image = false;
bool g_show_selection_ui = true;
std::uint32_t g_last_ui_ms = 0;
std::uint32_t g_auton_end_ms = 0;
bool g_auton_abort = false;
constexpr std::uint32_t kSelectionUiTimeoutMs = 5000;

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
    int value1;
    int value2;
    int value3;
};

static std::vector<Step> gps_plan_sd;
static std::vector<Step> basic_plan_sd;

void turn_to_heading(double target, int max_speed);
void run_simple_auton_fallback();

bool draw_bmp_from_sd(const char* name, int x, int y) {
    FILE* file = sd_open(name, "rb");
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

    const bool compression_ok = (compression == 0) || (compression == 3 && bpp == 32);
    if ((bpp != 24 && bpp != 32) || !compression_ok || width <= 0 || height == 0) {
        std::fclose(file);
        return false;
    }

    const bool top_down = height < 0;
    const std::int32_t abs_height = std::abs(height);
    const std::uint32_t bytes_per_pixel = bpp / 8;
    const std::uint32_t row_size = ((bytes_per_pixel * width + 3) / 4) * 4;
    const int max_w = 480;
    const int max_h = 240;
    int target_w = width;
    int target_h = abs_height;
    bool scale = false;
    if (width > max_w || abs_height > max_h) {
        target_w = std::min(static_cast<int>(width), max_w);
        target_h = std::min(static_cast<int>(abs_height), max_h);
        scale = true;
    }

    std::vector<std::uint8_t> row(row_size);
    std::vector<std::uint32_t> row_buf(static_cast<std::size_t>(target_w));

    std::fseek(file, static_cast<long>(data_offset), SEEK_SET);

    int last_target_row = -1;
    for (std::int32_t row_idx = 0; row_idx < abs_height; ++row_idx) {
        if (std::fread(row.data(), 1, row_size, file) != row_size) {
            break;
        }

        const std::int32_t draw_y = top_down ? row_idx : (abs_height - 1 - row_idx);

        if (!scale) {
            for (std::int32_t col = 0; col < width; ++col) {
                const std::size_t idx = static_cast<std::size_t>(col * bytes_per_pixel);
                const std::uint8_t b = row[idx];
                const std::uint8_t g = row[idx + 1];
                const std::uint8_t r = row[idx + 2];
                row_buf[static_cast<std::size_t>(col)] = (static_cast<std::uint32_t>(r) << 16) |
                                                         (static_cast<std::uint32_t>(g) << 8) |
                                                         static_cast<std::uint32_t>(b);
            }

            const std::int16_t y_row = static_cast<std::int16_t>(y + draw_y);
            pros::screen::copy_area(x,
                                    y_row,
                                    static_cast<std::int16_t>(x + width - 1),
                                    y_row,
                                    row_buf.data(),
                                    width);
            continue;
        }

        const int target_row = (draw_y * target_h) / abs_height;
        if (target_row == last_target_row) {
            continue;
        }
        last_target_row = target_row;

        for (int col = 0; col < target_w; ++col) {
            const int src_x = (col * width) / target_w;
            const std::size_t idx = static_cast<std::size_t>(src_x * bytes_per_pixel);
            const std::uint8_t b = row[idx];
            const std::uint8_t g = row[idx + 1];
            const std::uint8_t r = row[idx + 2];
            row_buf[static_cast<std::size_t>(col)] = (static_cast<std::uint32_t>(r) << 16) |
                                                     (static_cast<std::uint32_t>(g) << 8) |
                                                     static_cast<std::uint32_t>(b);
        }

        const std::int16_t y_row = static_cast<std::int16_t>(y + target_row);
        if (y_row < 0 || y_row >= max_h) {
            continue;
        }
        pros::screen::copy_area(x,
                                y_row,
                                static_cast<std::int16_t>(x + target_w - 1),
                                y_row,
                                row_buf.data(),
                                target_w);
    }

    std::fclose(file);
    return true;
}

bool draw_loading_icon() {
    return draw_bmp_from_sd(kLoadingIconName, 0, 0);
}

void chomp_line(char* line) {
    if (!line) return;
    std::size_t len = std::strlen(line);
    while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r')) {
        line[len - 1] = '\0';
        --len;
    }
}

bool is_images_path(const std::string& path) {
    return starts_with(path.c_str(), "/usd/Images/") || starts_with(path.c_str(), "usd/Images/");
}

std::string coerce_images_path(const std::string& path) {
    if (path.empty()) {
        return "";
    }
    if (is_images_path(path)) {
        return path;
    }
    std::string name = path;
    const std::size_t pos = name.find_last_of('/');
    if (pos != std::string::npos) {
        name = name.substr(pos + 1);
    }
    if (name.empty()) {
        return "";
    }
    return std::string("/usd/Images/") + name;
}

void load_ui_images() {
    g_splash_image = coerce_images_path(kDefaultSplash);
    g_auton_image = coerce_images_path(kDefaultRun);
    g_driver_image.clear();
    g_run_image = g_auton_image;

    FILE* file = sd_open(kUiConfigName, "r");
    if (!file) {
        return;
    }

    bool have_auton = false;
    std::string legacy_run;
    char line[128];
    while (std::fgets(line, sizeof(line), file)) {
        chomp_line(line);
        if (std::strncmp(line, "SPLASH=", 7) == 0) {
            g_splash_image = coerce_images_path(line + 7);
        } else if (std::strncmp(line, "AUTON=", 6) == 0) {
            g_auton_image = coerce_images_path(line + 6);
            have_auton = true;
        } else if (std::strncmp(line, "DRIVER=", 7) == 0) {
            g_driver_image = coerce_images_path(line + 7);
        } else if (std::strncmp(line, "RUN=", 4) == 0) {
            legacy_run = line + 4;
            g_run_image = coerce_images_path(legacy_run);
        }
    }

    std::fclose(file);

    if (!have_auton && !legacy_run.empty()) {
        g_auton_image = coerce_images_path(legacy_run);
    }
    g_run_image = g_auton_image.empty() ? g_run_image : g_auton_image;
}

bool auton_time_up() {
    return g_auton_abort || (g_auton_end_ms != 0 && pros::millis() >= g_auton_end_ms);
}

bool delay_with_abort(int ms) {
    const int chunk = 20;
    int remaining = ms;
    while (remaining > 0) {
        if (auton_time_up()) {
            return false;
        }
        pros::delay(std::min(chunk, remaining));
        remaining -= chunk;
    }
    return true;
}

void drive_set(int left, int right) {
    left_drive.move(left);
    right_drive.move(right);
    if (g_six_wheel_drive_enabled) {
        left_middle.move(left);
        right_middle.move(right);
    } else {
        left_middle.brake();
        right_middle.brake();
    }
}

void drive_brake() {
    left_drive.brake();
    right_drive.brake();
    left_middle.brake();
    right_middle.brake();
}

void stop_all_motors() {
    drive_brake();
    intake_left.brake();
    intake_right.brake();
}

bool draw_named_image(const std::string& name) {
    return draw_bmp_from_sd(name.c_str(), 0, 0);
}

void show_run_image_once() {
    pros::screen::set_pen(0x00000000);
    pros::screen::fill_rect(0, 0, 479, 239);
    const std::string& img = g_auton_image.empty() ? g_run_image : g_auton_image;
    draw_named_image(img);
    pros::screen::set_pen(0x00000000);
    pros::screen::fill_rect(0, 220, 479, 239);
    pros::screen::set_pen(pros::c::COLOR_WHITE);
    pros::screen::print(TEXT_MEDIUM, 10, 222, "auto");
}

void show_driver_image_once() {
    if (g_driver_image.empty()) {
        return;
    }
    pros::screen::set_pen(0x00000000);
    pros::screen::fill_rect(0, 0, 479, 239);
    draw_named_image(g_driver_image);
    pros::screen::set_pen(0x00000000);
    pros::screen::fill_rect(0, 220, 479, 239);
    pros::screen::set_pen(pros::c::COLOR_WHITE);
    pros::screen::print(TEXT_MEDIUM, 10, 222, "driving");
}

void show_init_splash() {
    pros::screen::set_pen(0x00000000);
    pros::screen::fill_rect(0, 0, 479, 239);

    const bool loaded = draw_named_image(g_splash_image);
    pros::screen::set_pen(pros::c::COLOR_WHITE);
    if (!loaded) {
        pros::screen::print(TEXT_MEDIUM, 10, 100, "SD image missing");
    }
    pros::screen::print(TEXT_MEDIUM, 10, 210, "thanks tahera :)");
}

struct Rect {
    int x;
    int y;
    int w;
    int h;
};

bool hit_test(const Rect& r, int x, int y) {
    return x >= r.x && x <= (r.x + r.w) && y >= r.y && y <= (r.y + r.h);
}

void draw_button(const Rect& r, const char* label, std::uint32_t color) {
    pros::screen::set_pen(color);
    pros::screen::draw_rect(r.x, r.y, r.x + r.w, r.y + r.h);
    pros::screen::print(TEXT_MEDIUM, r.x + 6, r.y + 8, label);
}

void draw_brain_ui() {
    pros::screen::set_pen(0x00000000);
    pros::screen::fill_rect(0, 0, kScreenW - 1, kScreenH - 1);

    const Rect gps_btn{10, 10, 140, 30};
    const Rect basic_btn{170, 10, 140, 30};
    const Rect run_btn{330, 10, 140, 30};

    draw_button(gps_btn, "GPS", g_auton_mode == AutonMode::GPS_LEMLIB ? 0x0000FF00 : 0x00FFFFFF);
    draw_button(basic_btn, "BASIC", g_auton_mode == AutonMode::NO_GPS ? 0x0000FF00 : 0x00FFFFFF);
    draw_button(run_btn, g_auton_running ? "RUNNING" : "RUN", 0x00FF0000);

    pros::screen::set_pen(pros::c::COLOR_WHITE);
    pros::screen::print(TEXT_MEDIUM, 10, 70, "AUTON: %s",
                        g_auton_mode == AutonMode::GPS_LEMLIB ? "GPS" : "BASIC");
    pros::screen::print(TEXT_MEDIUM, 10, 95, "SOURCE: %s",
                        g_sd_plans_loaded ? "SD" : "BUILT-IN");
    pros::screen::print(TEXT_MEDIUM, 10, 120, "SD: %s", g_sd_plans_loaded ? "OK" : "MISSING");
    pros::screen::print(TEXT_MEDIUM, 10, 145, "SLOT: %d", g_active_slot + 1);
    pros::screen::print(TEXT_MEDIUM, 10, 210, "Tap RUN to start auton");
}

void brain_ui_loop() {
    draw_brain_ui();
    static int32_t last_release_count = -1;
    while (true) {
        if (g_ui_locked) {
            pros::delay(200);
            continue;
        }

        pros::screen_touch_status_s_t status = pros::screen::touch_status();
        if (status.touch_status == pros::E_TOUCH_RELEASED) {
            if (status.release_count == last_release_count) {
                pros::delay(50);
                continue;
            }
            last_release_count = status.release_count;
            g_last_ui_ms = pros::millis();
            g_show_selection_ui = true;
            const int x = status.x;
            const int y = status.y;

            const Rect gps_btn{10, 10, 140, 30};
            const Rect basic_btn{170, 10, 140, 30};
            const Rect run_btn{330, 10, 140, 30};

            if (hit_test(gps_btn, x, y)) g_auton_mode = AutonMode::GPS_LEMLIB;
            if (hit_test(basic_btn, x, y)) g_auton_mode = AutonMode::NO_GPS;
            if (hit_test(run_btn, x, y) && !g_auton_running) g_manual_auton_request = true;

            draw_brain_ui();
        }
        if (g_force_driver_image && g_show_selection_ui &&
            (pros::millis() - g_last_ui_ms) > kSelectionUiTimeoutMs) {
            g_show_selection_ui = false;
            if (!g_driver_image.empty()) {
                show_driver_image_once();
            }
        }
        pros::delay(50);
    }
}

void brain_ui_task_fn(void*) {
    brain_ui_loop();
}

void run_selected_auton() {
    g_auton_mutex.take();
    if (g_auton_running) {
        g_auton_mutex.give();
        return;
    }
    g_auton_running = true;
    g_auton_end_ms = pros::millis() + kAutonMaxMs;
    g_auton_abort = false;
    g_auton_mutex.give();
    g_ui_locked = true;
    show_run_image_once();

    if (g_auton_mode == AutonMode::GPS_LEMLIB) {
        if (g_sd_plans_loaded && !gps_plan_sd.empty()) {
            for (const auto& step : gps_plan_sd) {
                if (auton_time_up()) break;
                switch (step.type) {
                    case StepType::EMPTY:
                        break;
                    case StepType::DRIVE_MS:
                        drive_set(step.value1, step.value1);
                        if (!delay_with_abort(step.value2)) {
                            stop_all_motors();
                            break;
                        }
                        drive_brake();
                        break;
                    case StepType::TANK_MS:
                        drive_set(step.value1, step.value2);
                        if (!delay_with_abort(step.value3)) {
                            stop_all_motors();
                            break;
                        }
                        drive_brake();
                        break;
                    case StepType::TURN_HEADING:
                        turn_to_heading(step.value1, 60);
                        break;
                    case StepType::WAIT_MS:
                        if (!delay_with_abort(step.value1)) {
                            stop_all_motors();
                            break;
                        }
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
                if (auton_time_up()) break;
            }
        } else {
            run_simple_auton_fallback();
        }
    } else {
        if (g_sd_plans_loaded && !basic_plan_sd.empty()) {
            for (const auto& step : basic_plan_sd) {
                if (auton_time_up()) break;
                switch (step.type) {
                    case StepType::EMPTY:
                        break;
                    case StepType::DRIVE_MS:
                        drive_set(step.value1, step.value1);
                        if (!delay_with_abort(step.value2)) {
                            stop_all_motors();
                            break;
                        }
                        drive_brake();
                        break;
                    case StepType::TANK_MS:
                        drive_set(step.value1, step.value2);
                        if (!delay_with_abort(step.value3)) {
                            stop_all_motors();
                            break;
                        }
                        drive_brake();
                        break;
                    case StepType::TURN_HEADING:
                        turn_to_heading(step.value1, 60);
                        break;
                    case StepType::WAIT_MS:
                        if (!delay_with_abort(step.value1)) {
                            stop_all_motors();
                            break;
                        }
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
                if (auton_time_up()) break;
            }
        } else {
            run_simple_auton_fallback();
        }
    }

    stop_all_motors();
    g_auton_mutex.take();
    g_auton_running = false;
    g_auton_end_ms = 0;
    g_auton_abort = false;
    g_auton_mutex.give();
    g_ui_locked = false;
    if (g_force_driver_image && !g_driver_image.empty()) {
        g_show_selection_ui = false;
        show_driver_image_once();
    } else {
        g_show_selection_ui = true;
        draw_brain_ui();
    }
}

void auton_watchdog_task_fn(void*) {
    while (true) {
        if (g_auton_running && g_auton_end_ms != 0 && pros::millis() >= g_auton_end_ms) {
            g_auton_abort = true;
            stop_all_motors();
        }
        pros::delay(20);
    }
}

void update_auton_mode_from_controller() {
    if (master.get_digital_new_press(DIGITAL_A)) {
        g_gps_drive_enabled = true;
    } else if (master.get_digital_new_press(DIGITAL_B)) {
        g_gps_drive_enabled = false;
    }

    if (master.get_digital_new_press(DIGITAL_Y)) {
        g_six_wheel_drive_enabled = true;
    } else if (master.get_digital_new_press(DIGITAL_X)) {
        g_six_wheel_drive_enabled = false;
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

int read_slot_from_sd() {
    FILE* file = sd_open(kSlotIndexFile, "r");
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

bool load_sd_plans_from(const char* filename) {
    gps_plan_sd.clear();
    basic_plan_sd.clear();

    FILE* file = sd_open(filename, "r");
    if (!file) {
        return false;
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
        int v3 = 0;
        const int fields = std::sscanf(s.c_str(), "%31[^,],%d,%d,%d", type_str, &v1, &v2, &v3);
        if (fields >= 3) {
            Step step{parse_step_type(type_str), v1, v2, v3};
            if (section == Section::GPS) gps_plan_sd.push_back(step);
            if (section == Section::BASIC) basic_plan_sd.push_back(step);
        }
    }

    std::fclose(file);
    return !(gps_plan_sd.empty() && basic_plan_sd.empty());
}

void load_sd_plans() {
    g_active_slot = read_slot_from_sd();
    const char* slot_file = slot_filename(g_active_slot);
    if (load_sd_plans_from(slot_file)) {
        g_sd_plans_loaded = true;
        return;
    }
    if (load_sd_plans_from("auton_plans.txt")) {
        g_sd_plans_loaded = true;
        return;
    }
    g_sd_plans_loaded = false;
}

// ======================================================
// 2. HELPER FUNCTIONS
// ======================================================

void turn_to_heading(double target, int max_speed) {
    while (true) {
        if (auton_time_up()) break;
        double current = imu.get_heading();
        double error = target - current;

        if (error > 180) error -= 360;
        if (error < -180) error += 360;

        if (std::abs(error) < 2.0) break;

        double kp = 1.5; 
        int speed = error * kp;

        if (speed > max_speed) speed = max_speed;
        if (speed < -max_speed) speed = -max_speed;

        drive_set(speed, -speed);
        pros::delay(20);
    }
    drive_brake();
}

void run_simple_auton_fallback() {
    drive_set(60, 60);
    if (!delay_with_abort(1500)) {
        stop_all_motors();
        return;
    }

    drive_brake();
    if (!delay_with_abort(100)) {
        stop_all_motors();
        return;
    }

    turn_to_heading(90, 60);

    drive_set(-40, -40);
    if (!delay_with_abort(500)) {
        stop_all_motors();
        return;
    }

    drive_brake();
}

// ======================================================
// 3. COMPETITION PHASES
// ======================================================

void initialize() {
    pros::lcd::initialize();
    load_ui_images();
    show_init_splash();
    pros::delay(kSplashHoldMs);
    imu.reset(true);
    while (imu.is_calibrating()) {
        pros::delay(10);
    }
    load_sd_plans();
    if (!g_sd_plans_loaded) {
        pros::lcd::print(0, "SD plans: MISSING");
    } else {
        pros::lcd::print(0, "SD plans: OK");
    }
    static pros::Task brain_ui_task(brain_ui_task_fn, nullptr, TASK_PRIORITY_DEFAULT,
                                    TASK_STACK_DEPTH_DEFAULT, "TaheraUI");
    static pros::Task auton_watchdog(auton_watchdog_task_fn, nullptr, TASK_PRIORITY_DEFAULT,
                                     TASK_STACK_DEPTH_DEFAULT, "TaheraWatch");
}

void autonomous() {
    g_force_driver_image = false;
    run_selected_auton();
}

void opcontrol() {
    g_force_driver_image = !g_driver_image.empty();
    g_ui_locked = false;
    g_show_selection_ui = true;
    g_last_ui_ms = pros::millis();
    draw_brain_ui();
    while (true) {
        update_auton_mode_from_controller();

        if (g_manual_auton_request) {
            g_manual_auton_request = false;
            run_selected_auton();
        }

        if (g_auton_running) {
            pros::delay(20);
            continue;
        }
        if (g_force_driver_image && g_show_selection_ui &&
            (pros::millis() - g_last_ui_ms) > kSelectionUiTimeoutMs) {
            g_show_selection_ui = false;
            show_driver_image_once();
        }
        // --- DRIVE LOGIC (D-PAD OVERRIDE + TANK) ---
        const bool dpad_up = master.get_digital(DIGITAL_UP);
        const bool dpad_down = master.get_digital(DIGITAL_DOWN);
        const bool dpad_left = master.get_digital(DIGITAL_LEFT);
        const bool dpad_right = master.get_digital(DIGITAL_RIGHT);

        int left_cmd = 0;
        int right_cmd = 0;

        if (dpad_up || dpad_down || dpad_left || dpad_right) {
            constexpr int kDpadSpeed = 80;
            if (g_gps_drive_enabled) {
                double target = 0.0;
                if (dpad_up) {
                    target = 0.0;
                } else if (dpad_right) {
                    target = 90.0;
                } else if (dpad_down) {
                    target = 180.0;
                } else if (dpad_left) {
                    target = 270.0;
                }

                double heading = gps.get_heading() / 100.0;
                double error = target - heading;
                if (error > 180.0) error -= 360.0;
                if (error < -180.0) error += 360.0;

                const double kp = 1.2;
                double turn = error * kp;
                if (turn > 60.0) turn = 60.0;
                if (turn < -60.0) turn = -60.0;

                left_cmd = static_cast<int>(kDpadSpeed - turn);
                right_cmd = static_cast<int>(kDpadSpeed + turn);
            } else {
                if (dpad_up) {
                    left_cmd = kDpadSpeed;
                    right_cmd = kDpadSpeed;
                } else if (dpad_down) {
                    left_cmd = -kDpadSpeed;
                    right_cmd = -kDpadSpeed;
                } else if (dpad_left) {
                    left_cmd = -kDpadSpeed;
                    right_cmd = kDpadSpeed;
                } else if (dpad_right) {
                    left_cmd = kDpadSpeed;
                    right_cmd = -kDpadSpeed;
                }
            }
        } else {
            // Left stick controls left side, Right stick controls right side
            int left_y = master.get_analog(ANALOG_LEFT_Y);
            int right_y = master.get_analog(ANALOG_RIGHT_Y);
            left_cmd = left_y;
            right_cmd = right_y;
        }

        drive_set(left_cmd, right_cmd);

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
