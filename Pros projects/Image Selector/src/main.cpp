#include "main.h"

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstring>
#include <cmath>
#include <string>
#include <vector>

namespace {
constexpr char kUiConfigName[] = "ui_images.txt";
constexpr char kDefaultSplash[] = "loading_icon.bmp";
constexpr char kDefaultAuton[] = "jerkbot.bmp";

struct Rect {
    int x;
    int y;
    int w;
    int h;
};

bool hit_test(const Rect& r, int x, int y) {
    return x >= r.x && x <= (r.x + r.w) && y >= r.y && y <= (r.y + r.h);
}

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

    const char* prefixes[] = {
        "/usd/",
        "usd/",
        "/usd/Images/",
        "usd/Images/",
    };

    char path[128];
    for (const char* prefix : prefixes) {
        std::snprintf(path, sizeof(path), "%s%s", prefix, name);
        file = std::fopen(path, mode);
        if (file) {
            return file;
        }
    }

    return nullptr;
}

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

bool ends_with_bmp(const std::string& name) {
    if (name.size() < 4) return false;
    const std::string suffix = name.substr(name.size() - 4);
    return suffix == ".bmp" || suffix == ".BMP" || suffix == ".Bmp" || suffix == ".bMp" ||
           suffix == ".bmP" || suffix == ".bMP" || suffix == ".BmP" || suffix == ".BMP";
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
} // namespace

static std::vector<std::string> g_images;
static int g_index = 0;
static std::string g_splash_name = kDefaultSplash;
static std::string g_auton_name = kDefaultAuton;
static std::string g_driver_name;
static bool g_dirty = true;

void add_images_from_dir(const char* list_path, const char* store_prefix) {
    std::vector<char> buffer(16384, '\0');
    if (pros::usd::list_files(list_path, buffer.data(), static_cast<int>(buffer.size())) == PROS_ERR) {
        return;
    }
    buffer.back() = '\0';

    const char* start = buffer.data();
    while (*start) {
        const char* end = std::strchr(start, '\n');
        const std::size_t len = end ? static_cast<std::size_t>(end - start) : std::strlen(start);
        if (len > 0) {
            std::string name(start, len);
            if (ends_with_bmp(name)) {
                std::string full = store_prefix;
                if (!full.empty() && full.back() != '/') {
                    full += '/';
                }
                full += name;
                g_images.push_back(full);
            }
        }
        if (!end) break;
        start = end + 1;
    }
}

void refresh_image_list() {
    g_images.clear();
    add_images_from_dir("/Images", "/usd/Images");
    if (g_index >= static_cast<int>(g_images.size())) {
        g_index = 0;
    }
}

void load_config() {
    g_splash_name = coerce_images_path(kDefaultSplash);
    g_auton_name = coerce_images_path(kDefaultAuton);
    g_driver_name.clear();

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
            g_splash_name = coerce_images_path(line + 7);
        } else if (std::strncmp(line, "AUTON=", 6) == 0) {
            g_auton_name = coerce_images_path(line + 6);
            have_auton = true;
        } else if (std::strncmp(line, "DRIVER=", 7) == 0) {
            g_driver_name = coerce_images_path(line + 7);
        } else if (std::strncmp(line, "RUN=", 4) == 0) {
            legacy_run = line + 4;
        }
    }

    std::fclose(file);

    if (!have_auton && !legacy_run.empty()) {
        g_auton_name = coerce_images_path(legacy_run);
    }
}

void save_config() {
    FILE* file = sd_open(kUiConfigName, "w");
    if (!file) {
        return;
    }
    std::fprintf(file, "SPLASH=%s\n", g_splash_name.c_str());
    std::fprintf(file, "AUTON=%s\n", g_auton_name.c_str());
    if (!g_driver_name.empty()) {
        std::fprintf(file, "DRIVER=%s\n", g_driver_name.c_str());
    }
    std::fprintf(file, "RUN=%s\n", g_auton_name.c_str());
    std::fclose(file);
}

void draw_button(const Rect& r, const char* label, std::uint32_t color) {
    pros::screen::set_pen(color);
    pros::screen::draw_rect(r.x, r.y, r.x + r.w, r.y + r.h);
    pros::screen::print(TEXT_MEDIUM, r.x + 6, r.y + 8, label);
}

void draw_ui() {
    pros::screen::set_pen(0x00000000);
    pros::screen::fill_rect(0, 0, 479, 239);

    if (!g_images.empty()) {
        draw_bmp_from_sd(g_images[g_index].c_str(), 0, 0);
    }

    const Rect prev_btn{10, 10, 70, 30};
    const Rect next_btn{90, 10, 70, 30};
    const Rect splash_btn{170, 10, 90, 30};
    const Rect auton_btn{270, 10, 90, 30};
    const Rect driver_btn{370, 10, 90, 30};
    const Rect save_btn{10, 50, 140, 30};
    const Rect refresh_btn{170, 50, 140, 30};

    draw_button(prev_btn, "PREV", 0x00FFFFFF);
    draw_button(next_btn, "NEXT", 0x00FFFFFF);
    draw_button(splash_btn, "SPLASH", 0x0000FF00);
    draw_button(auton_btn, "AUTON", 0x00FF0000);
    draw_button(driver_btn, "DRIVER", 0x0000FFFF);
    draw_button(save_btn, "SAVE", 0x00FFFF00);
    draw_button(refresh_btn, "REFRESH", 0x00FFFFFF);

    pros::screen::set_pen(pros::c::COLOR_WHITE);
    if (g_images.empty()) {
        pros::screen::print(TEXT_MEDIUM, 10, 100, "No BMPs found on SD");
    } else {
        std::string name = g_images[g_index];
        const std::size_t pos = name.find_last_of('/');
        if (pos != std::string::npos) {
            name = name.substr(pos + 1);
        }
        pros::screen::print(TEXT_MEDIUM, 10, 100, "FILE: %s", name.c_str());
    }
    pros::screen::print(TEXT_MEDIUM, 10, 130, "SPLASH: %s", g_splash_name.c_str());
    pros::screen::print(TEXT_MEDIUM, 10, 155, "AUTON: %s", g_auton_name.c_str());
    pros::screen::print(TEXT_MEDIUM, 10, 180, "DRIVER: %s",
                        g_driver_name.empty() ? "(none)" : g_driver_name.c_str());
}

bool handle_touch() {
    static int32_t last_release_count = -1;
    pros::screen_touch_status_s_t status = pros::screen::touch_status();
    if (status.touch_status != pros::E_TOUCH_RELEASED) {
        return false;
    }
    if (status.release_count == last_release_count) {
        return false;
    }
    last_release_count = status.release_count;

    const int x = status.x;
    const int y = status.y;

    const Rect prev_btn{10, 10, 70, 30};
    const Rect next_btn{90, 10, 70, 30};
    const Rect splash_btn{170, 10, 90, 30};
    const Rect auton_btn{270, 10, 90, 30};
    const Rect driver_btn{370, 10, 90, 30};
    const Rect save_btn{10, 50, 140, 30};
    const Rect refresh_btn{170, 50, 140, 30};

    bool changed = false;
    if (hit_test(prev_btn, x, y) && !g_images.empty()) {
        g_index = (g_index - 1 + static_cast<int>(g_images.size())) % static_cast<int>(g_images.size());
        changed = true;
    } else if (hit_test(next_btn, x, y) && !g_images.empty()) {
        g_index = (g_index + 1) % static_cast<int>(g_images.size());
        changed = true;
    } else if (hit_test(splash_btn, x, y) && !g_images.empty()) {
        g_splash_name = g_images[g_index];
        changed = true;
    } else if (hit_test(auton_btn, x, y) && !g_images.empty()) {
        g_auton_name = g_images[g_index];
        changed = true;
    } else if (hit_test(driver_btn, x, y) && !g_images.empty()) {
        g_driver_name = g_images[g_index];
        changed = true;
    } else if (hit_test(save_btn, x, y)) {
        save_config();
        changed = true;
    } else if (hit_test(refresh_btn, x, y)) {
        refresh_image_list();
        changed = true;
    }

    return changed;
}

void initialize() {
    pros::lcd::initialize();
    refresh_image_list();
    load_config();
    draw_ui();
    g_dirty = false;
}

void disabled() {}
void competition_initialize() {}
void autonomous() {}

void opcontrol() {
    while (true) {
        if (handle_touch()) {
            g_dirty = true;
        }
        if (g_dirty) {
            draw_ui();
            g_dirty = false;
        }
        pros::delay(50);
    }
}
