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
#include <cctype>

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

pros::Motor intake(7, pros::v5::MotorGears::blue);
pros::Motor outake(8, pros::v5::MotorGears::blue);

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
constexpr char kControllerMappingFile[] = "controller_mapping.txt";
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

enum class DriveControlMode {
    TANK = 0,
    ARCADE_2_STICK,
    DPAD
};

static DriveControlMode g_drive_mode = DriveControlMode::TANK;

constexpr char kRecordLogPrefix[] = "/usd/bonkers_log_";
constexpr int kRecordFlushThreshold = 25;
static bool g_drive_recording = false;
static FILE* g_record_file = nullptr;
static std::string g_record_path;
static std::vector<std::string> g_record_buffer;
pros::Mutex g_record_mutex;

enum class ControllerAction {
    INTAKE_IN = 0,
    INTAKE_OUT,
    OUTAKE_OUT,
    OUTAKE_IN,
    GPS_ENABLE,
    GPS_DISABLE,
    SIX_WHEEL_ON,
    SIX_WHEEL_OFF
};

constexpr int kControllerActionCount = 8;

pros::controller_digital_e_t g_controller_mapping[kControllerActionCount] = {
    DIGITAL_L1,
    DIGITAL_L2,
    DIGITAL_R1,
    DIGITAL_R2,
    DIGITAL_A,
    DIGITAL_B,
    DIGITAL_Y,
    DIGITAL_X
};

const char* controller_action_key(ControllerAction action) {
    switch (action) {
        case ControllerAction::INTAKE_IN: return "INTAKE_IN";
        case ControllerAction::INTAKE_OUT: return "INTAKE_OUT";
        case ControllerAction::OUTAKE_OUT: return "OUTAKE_OUT";
        case ControllerAction::OUTAKE_IN: return "OUTAKE_IN";
        case ControllerAction::GPS_ENABLE: return "GPS_ENABLE";
        case ControllerAction::GPS_DISABLE: return "GPS_DISABLE";
        case ControllerAction::SIX_WHEEL_ON: return "SIX_WHEEL_ON";
        case ControllerAction::SIX_WHEEL_OFF: return "SIX_WHEEL_OFF";
        default: return "";
    }
}

pros::controller_digital_e_t default_controller_button(ControllerAction action) {
    switch (action) {
        case ControllerAction::INTAKE_IN: return DIGITAL_L1;
        case ControllerAction::INTAKE_OUT: return DIGITAL_L2;
        case ControllerAction::OUTAKE_OUT: return DIGITAL_R1;
        case ControllerAction::OUTAKE_IN: return DIGITAL_R2;
        case ControllerAction::GPS_ENABLE: return DIGITAL_A;
        case ControllerAction::GPS_DISABLE: return DIGITAL_B;
        case ControllerAction::SIX_WHEEL_ON: return DIGITAL_Y;
        case ControllerAction::SIX_WHEEL_OFF: return DIGITAL_X;
        default: return DIGITAL_A;
    }
}

pros::controller_digital_e_t mapped_button(ControllerAction action) {
    return g_controller_mapping[static_cast<int>(action)];
}

const char* drive_mode_key(DriveControlMode mode) {
    switch (mode) {
        case DriveControlMode::TANK: return "TANK";
        case DriveControlMode::ARCADE_2_STICK: return "ARCADE_2_STICK";
        case DriveControlMode::DPAD: return "DPAD";
        default: return "TANK";
    }
}

const char* drive_mode_display(DriveControlMode mode) {
    switch (mode) {
        case DriveControlMode::TANK: return "TANK";
        case DriveControlMode::ARCADE_2_STICK: return "2STICK";
        case DriveControlMode::DPAD: return "DPAD";
        default: return "TANK";
    }
}

bool parse_drive_mode(const std::string& key, DriveControlMode* out_mode) {
    if (!out_mode) {
        return false;
    }
    if (key == "TANK") {
        *out_mode = DriveControlMode::TANK;
        return true;
    }
    if (key == "ARCADE_2_STICK" || key == "ARCADE2" || key == "ARCADE") {
        *out_mode = DriveControlMode::ARCADE_2_STICK;
        return true;
    }
    if (key == "DPAD") {
        *out_mode = DriveControlMode::DPAD;
        return true;
    }
    return false;
}

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

std::string trim_copy(const std::string& value) {
    std::size_t start = 0;
    while (start < value.size() && std::isspace(static_cast<unsigned char>(value[start]))) {
        ++start;
    }
    std::size_t end = value.size();
    while (end > start && std::isspace(static_cast<unsigned char>(value[end - 1]))) {
        --end;
    }
    return value.substr(start, end - start);
}

std::string uppercase_copy(std::string value) {
    for (char& ch : value) {
        ch = static_cast<char>(std::toupper(static_cast<unsigned char>(ch)));
    }
    return value;
}

bool parse_controller_action(const std::string& key, ControllerAction* out_action) {
    if (!out_action) {
        return false;
    }
    for (int idx = 0; idx < kControllerActionCount; ++idx) {
        const auto action = static_cast<ControllerAction>(idx);
        if (key == controller_action_key(action)) {
            *out_action = action;
            return true;
        }
    }
    return false;
}

bool parse_controller_button(const std::string& key, pros::controller_digital_e_t* out_button) {
    if (!out_button) {
        return false;
    }
    struct Entry {
        const char* name;
        pros::controller_digital_e_t button;
    };
    static constexpr Entry kEntries[] = {
        {"L1", DIGITAL_L1},
        {"L2", DIGITAL_L2},
        {"R1", DIGITAL_R1},
        {"R2", DIGITAL_R2},
        {"A", DIGITAL_A},
        {"B", DIGITAL_B},
        {"X", DIGITAL_X},
        {"Y", DIGITAL_Y},
        {"UP", DIGITAL_UP},
        {"DOWN", DIGITAL_DOWN},
        {"LEFT", DIGITAL_LEFT},
        {"RIGHT", DIGITAL_RIGHT},
    };
    for (const auto& entry : kEntries) {
        if (key == entry.name) {
            *out_button = entry.button;
            return true;
        }
    }
    return false;
}

void reset_controller_mapping_defaults() {
    g_drive_mode = DriveControlMode::TANK;
    for (int idx = 0; idx < kControllerActionCount; ++idx) {
        const auto action = static_cast<ControllerAction>(idx);
        g_controller_mapping[idx] = default_controller_button(action);
    }
}

void load_controller_mapping_from_sd() {
    reset_controller_mapping_defaults();

    FILE* file = sd_open(kControllerMappingFile, "r");
    if (!file) {
        return;
    }

    char line[96];
    while (std::fgets(line, sizeof(line), file)) {
        chomp_line(line);
        std::string entry = trim_copy(line);
        if (entry.empty() || entry[0] == '#') {
            continue;
        }

        const std::size_t eq = entry.find('=');
        if (eq == std::string::npos) {
            continue;
        }

        const std::string action_key = uppercase_copy(trim_copy(entry.substr(0, eq)));
        const std::string button_key = uppercase_copy(trim_copy(entry.substr(eq + 1)));

        if (action_key == "DRIVE_MODE") {
            DriveControlMode mode = DriveControlMode::TANK;
            if (parse_drive_mode(button_key, &mode)) {
                g_drive_mode = mode;
            }
            continue;
        }

        ControllerAction action = ControllerAction::INTAKE_IN;
        pros::controller_digital_e_t button = DIGITAL_L1;
        if (!parse_controller_action(action_key, &action) || !parse_controller_button(button_key, &button)) {
            continue;
        }

        g_controller_mapping[static_cast<int>(action)] = button;
    }

    std::fclose(file);
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

std::string make_record_log_path() {
    char path[128];
    std::snprintf(path, sizeof(path), "%s%u.txt", kRecordLogPrefix, pros::millis());
    return std::string(path);
}

void record_flush_locked() {
    if (!g_record_file || g_record_buffer.empty()) {
        return;
    }
    for (const auto& line : g_record_buffer) {
        std::fwrite(line.data(), 1, line.size(), g_record_file);
    }
    std::fflush(g_record_file);
    g_record_buffer.clear();
}

void record_append_locked(const char* type, const char* value) {
    if (!g_record_file || !type || !value) {
        return;
    }
    char row[96];
    const int written = std::snprintf(row, sizeof(row), "%s : %s\n", type, value);
    if (written > 0) {
        g_record_buffer.emplace_back(row, static_cast<std::size_t>(written));
    }
}

void record_append_locked(const char* type, int value) {
    char text[16];
    std::snprintf(text, sizeof(text), "%d", value);
    record_append_locked(type, text);
}

bool start_drive_recording() {
    g_record_mutex.take();
    if (g_drive_recording && g_record_file) {
        g_record_mutex.give();
        return true;
    }

    g_record_path = make_record_log_path();
    g_record_file = sd_open(g_record_path.c_str(), "w");
    if (!g_record_file) {
        g_drive_recording = false;
        g_record_path.clear();
        g_record_mutex.give();
        return false;
    }

    g_record_buffer.clear();
    g_record_buffer.reserve(kRecordFlushThreshold);
    g_drive_recording = true;
    record_append_locked("REC_START", "TAHERA");
    record_append_locked("DRIVE_MODE", drive_mode_key(g_drive_mode));
    record_flush_locked();
    g_record_mutex.give();
    return true;
}

void stop_drive_recording(const char* reason) {
    g_record_mutex.take();
    if (!g_record_file) {
        g_drive_recording = false;
        g_record_mutex.give();
        return;
    }

    if (reason && reason[0] != '\0') {
        record_append_locked("REC_STOP", reason);
    }
    record_flush_locked();
    std::fclose(g_record_file);
    g_record_file = nullptr;
    g_drive_recording = false;
    g_record_mutex.give();
}

void record_status_snapshot(bool* active, std::string* path) {
    g_record_mutex.take();
    if (active) {
        *active = g_drive_recording;
    }
    if (path) {
        *path = g_record_path;
    }
    g_record_mutex.give();
}

void record_drive_frame(int axis1,
                        int axis2,
                        int axis3,
                        int axis4,
                        bool intake_in_pressed,
                        bool intake_out_pressed,
                        bool outake_out_pressed,
                        bool outake_in_pressed,
                        bool gps_enable_pressed,
                        bool gps_disable_pressed,
                        bool six_on_pressed,
                        bool six_off_pressed,
                        bool dpad_up_pressed,
                        bool dpad_down_pressed,
                        bool dpad_left_pressed,
                        bool dpad_right_pressed) {
    g_record_mutex.take();
    if (!g_drive_recording || !g_record_file) {
        g_record_mutex.give();
        return;
    }

    record_append_locked("AXIS1", axis1);
    record_append_locked("AXIS2", axis2);
    record_append_locked("AXIS3", axis3);
    record_append_locked("AXIS4", axis4);

    if (intake_in_pressed) record_append_locked("BTN_INTAKE_IN", "INTAKE_IN");
    if (intake_out_pressed) record_append_locked("BTN_INTAKE_OUT", "INTAKE_OUT");
    if (outake_out_pressed) record_append_locked("BTN_OUTAKE_OUT", "OUTAKE_OUT");
    if (outake_in_pressed) record_append_locked("BTN_OUTAKE_IN", "OUTAKE_IN");
    if (gps_enable_pressed) record_append_locked("BTN_GPS_ENABLE", "GPS_ENABLE");
    if (gps_disable_pressed) record_append_locked("BTN_GPS_DISABLE", "GPS_DISABLE");
    if (six_on_pressed) record_append_locked("BTN_SIX_ON", "SIX_WHEEL_ON");
    if (six_off_pressed) record_append_locked("BTN_SIX_OFF", "SIX_WHEEL_OFF");
    if (dpad_up_pressed) record_append_locked("BTN_DPAD_UP", "DPAD_UP");
    if (dpad_down_pressed) record_append_locked("BTN_DPAD_DOWN", "DPAD_DOWN");
    if (dpad_left_pressed) record_append_locked("BTN_DPAD_LEFT", "DPAD_LEFT");
    if (dpad_right_pressed) record_append_locked("BTN_DPAD_RIGHT", "DPAD_RIGHT");

    if (static_cast<int>(g_record_buffer.size()) >= kRecordFlushThreshold) {
        record_flush_locked();
    }
    g_record_mutex.give();
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
    intake.brake();
    outake.brake();
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
    const Rect rec_btn{330, 50, 140, 30};

    bool recording = false;
    std::string record_path;
    record_status_snapshot(&recording, &record_path);

    draw_button(gps_btn, "GPS", g_auton_mode == AutonMode::GPS_LEMLIB ? 0x0000FF00 : 0x00FFFFFF);
    draw_button(basic_btn, "BASIC", g_auton_mode == AutonMode::NO_GPS ? 0x0000FF00 : 0x00FFFFFF);
    draw_button(run_btn, g_auton_running ? "RUNNING" : "RUN", 0x00FF0000);
    draw_button(rec_btn, recording ? "STOP REC" : "REC", recording ? 0x00FF0000 : 0x0000FF00);

    pros::screen::set_pen(pros::c::COLOR_WHITE);
    pros::screen::print(TEXT_MEDIUM, 10, 70, "AUTON: %s",
                        g_auton_mode == AutonMode::GPS_LEMLIB ? "GPS" : "BASIC");
    pros::screen::print(TEXT_MEDIUM, 10, 95, "SOURCE: %s",
                        g_sd_plans_loaded ? "SD" : "BUILT-IN");
    pros::screen::print(TEXT_MEDIUM, 10, 120, "SD: %s", g_sd_plans_loaded ? "OK" : "MISSING");
    pros::screen::print(TEXT_MEDIUM, 10, 145, "SLOT: %d", g_active_slot + 1);
    pros::screen::print(TEXT_MEDIUM, 10, 170, "DRIVE: %s", drive_mode_display(g_drive_mode));
    pros::screen::print(TEXT_MEDIUM, 10, 195, "REC: %s", recording ? "ON" : "OFF");

    std::string display_file = "(none)";
    if (!record_path.empty()) {
        const std::size_t slash = record_path.find_last_of('/');
        display_file = (slash == std::string::npos) ? record_path : record_path.substr(slash + 1);
    }
    pros::screen::print(TEXT_MEDIUM, 170, 195, "FILE: %s", display_file.c_str());
    pros::screen::print(TEXT_MEDIUM, 10, 220, "Tap RUN for auton / REC for driving log");
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
            const Rect rec_btn{330, 50, 140, 30};

            if (hit_test(gps_btn, x, y)) g_auton_mode = AutonMode::GPS_LEMLIB;
            if (hit_test(basic_btn, x, y)) g_auton_mode = AutonMode::NO_GPS;
            if (hit_test(run_btn, x, y) && !g_auton_running) g_manual_auton_request = true;
            if (hit_test(rec_btn, x, y)) {
                bool recording = false;
                record_status_snapshot(&recording, nullptr);
                if (recording) {
                    stop_drive_recording("USER");
                } else {
                    start_drive_recording();
                }
            }

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
    stop_drive_recording("AUTON");
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
                        intake.move(127);
                        outake.move(127);
                        break;
                    case StepType::INTAKE_OFF:
                        intake.brake();
                        outake.brake();
                        break;
                    case StepType::OUTTAKE_ON:
                        intake.move(-127);
                        outake.move(-127);
                        break;
                    case StepType::OUTTAKE_OFF:
                        intake.brake();
                        outake.brake();
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
                        intake.move(127);
                        outake.move(127);
                        break;
                    case StepType::INTAKE_OFF:
                        intake.brake();
                        outake.brake();
                        break;
                    case StepType::OUTTAKE_ON:
                        intake.move(-127);
                        outake.move(-127);
                        break;
                    case StepType::OUTTAKE_OFF:
                        intake.brake();
                        outake.brake();
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

void update_auton_mode_from_controller(bool gps_enable_pressed,
                                       bool gps_disable_pressed,
                                       bool six_on_pressed,
                                       bool six_off_pressed) {
    if (gps_enable_pressed) {
        g_gps_drive_enabled = true;
    } else if (gps_disable_pressed) {
        g_gps_drive_enabled = false;
    }

    if (six_on_pressed) {
        g_six_wheel_drive_enabled = true;
    } else if (six_off_pressed) {
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
    load_controller_mapping_from_sd();
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

    bool prev_intake_in = false;
    bool prev_intake_out = false;
    bool prev_outake_out = false;
    bool prev_outake_in = false;
    bool prev_gps_enable = false;
    bool prev_gps_disable = false;
    bool prev_six_on = false;
    bool prev_six_off = false;
    bool prev_dpad_up = false;
    bool prev_dpad_down = false;
    bool prev_dpad_left = false;
    bool prev_dpad_right = false;

    while (true) {
        const bool intake_in_now = master.get_digital(mapped_button(ControllerAction::INTAKE_IN));
        const bool intake_out_now = master.get_digital(mapped_button(ControllerAction::INTAKE_OUT));
        const bool outake_out_now = master.get_digital(mapped_button(ControllerAction::OUTAKE_OUT));
        const bool outake_in_now = master.get_digital(mapped_button(ControllerAction::OUTAKE_IN));
        const bool gps_enable_now = master.get_digital(mapped_button(ControllerAction::GPS_ENABLE));
        const bool gps_disable_now = master.get_digital(mapped_button(ControllerAction::GPS_DISABLE));
        const bool six_on_now = master.get_digital(mapped_button(ControllerAction::SIX_WHEEL_ON));
        const bool six_off_now = master.get_digital(mapped_button(ControllerAction::SIX_WHEEL_OFF));
        const bool dpad_up = master.get_digital(DIGITAL_UP);
        const bool dpad_down = master.get_digital(DIGITAL_DOWN);
        const bool dpad_left = master.get_digital(DIGITAL_LEFT);
        const bool dpad_right = master.get_digital(DIGITAL_RIGHT);

        const bool intake_in_pressed = intake_in_now && !prev_intake_in;
        const bool intake_out_pressed = intake_out_now && !prev_intake_out;
        const bool outake_out_pressed = outake_out_now && !prev_outake_out;
        const bool outake_in_pressed = outake_in_now && !prev_outake_in;
        const bool gps_enable_pressed = gps_enable_now && !prev_gps_enable;
        const bool gps_disable_pressed = gps_disable_now && !prev_gps_disable;
        const bool six_on_pressed = six_on_now && !prev_six_on;
        const bool six_off_pressed = six_off_now && !prev_six_off;
        const bool dpad_up_pressed = dpad_up && !prev_dpad_up;
        const bool dpad_down_pressed = dpad_down && !prev_dpad_down;
        const bool dpad_left_pressed = dpad_left && !prev_dpad_left;
        const bool dpad_right_pressed = dpad_right && !prev_dpad_right;

        update_auton_mode_from_controller(gps_enable_pressed, gps_disable_pressed,
                                          six_on_pressed, six_off_pressed);

        if (g_manual_auton_request) {
            g_manual_auton_request = false;
            run_selected_auton();
        }

        if (g_auton_running) {
            prev_intake_in = intake_in_now;
            prev_intake_out = intake_out_now;
            prev_outake_out = outake_out_now;
            prev_outake_in = outake_in_now;
            prev_gps_enable = gps_enable_now;
            prev_gps_disable = gps_disable_now;
            prev_six_on = six_on_now;
            prev_six_off = six_off_now;
            prev_dpad_up = dpad_up;
            prev_dpad_down = dpad_down;
            prev_dpad_left = dpad_left;
            prev_dpad_right = dpad_right;
            pros::delay(20);
            continue;
        }

        if (g_force_driver_image && g_show_selection_ui &&
            (pros::millis() - g_last_ui_ms) > kSelectionUiTimeoutMs) {
            g_show_selection_ui = false;
            show_driver_image_once();
        }

        int left_cmd = 0;
        int right_cmd = 0;
        const int left_y = master.get_analog(ANALOG_LEFT_Y);
        const int right_y = master.get_analog(ANALOG_RIGHT_Y);
        const int right_x = master.get_analog(ANALOG_RIGHT_X);
        const int left_x = master.get_analog(ANALOG_LEFT_X);
        const auto clamp_cmd = [](int value) {
            return std::max(-127, std::min(127, value));
        };

        switch (g_drive_mode) {
            case DriveControlMode::TANK:
                left_cmd = left_y;
                right_cmd = right_y;
                break;
            case DriveControlMode::ARCADE_2_STICK: {
                const int throttle = left_y;
                const int turn = right_x;
                left_cmd = clamp_cmd(throttle + turn);
                right_cmd = clamp_cmd(throttle - turn);
                break;
            }
            case DriveControlMode::DPAD:
            default: {
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
                    left_cmd = 0;
                    right_cmd = 0;
                }
                break;
            }
        }

        drive_set(left_cmd, right_cmd);

        if (intake_in_now) {
            intake.move(127);
        } else if (intake_out_now) {
            intake.move(-127);
        } else {
            intake.brake();
        }

        if (outake_out_now) {
            outake.move(127);
        } else if (outake_in_now) {
            outake.move(-127);
        } else {
            outake.brake();
        }

        // Replay integration expects AXIS3=left command and AXIS2=right command.
        record_drive_frame(right_x, right_cmd, left_cmd, left_x,
                           intake_in_pressed, intake_out_pressed,
                           outake_out_pressed, outake_in_pressed,
                           gps_enable_pressed, gps_disable_pressed,
                           six_on_pressed, six_off_pressed,
                           dpad_up_pressed, dpad_down_pressed,
                           dpad_left_pressed, dpad_right_pressed);

        prev_intake_in = intake_in_now;
        prev_intake_out = intake_out_now;
        prev_outake_out = outake_out_now;
        prev_outake_in = outake_in_now;
        prev_gps_enable = gps_enable_now;
        prev_gps_disable = gps_disable_now;
        prev_six_on = six_on_now;
        prev_six_off = six_off_now;
        prev_dpad_up = dpad_up;
        prev_dpad_down = dpad_down;
        prev_dpad_left = dpad_left;
        prev_dpad_right = dpad_right;

        pros::delay(20);
    }
}
