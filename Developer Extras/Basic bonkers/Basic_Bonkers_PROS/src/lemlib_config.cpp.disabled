#include "lemlib/config.hpp"
#include "hardware/Motor/MotorGroup.hpp"
#include "units/units.hpp"

#include <vector>

namespace lemlib {
const PID angular_pid(0.05, 0.0, 0.0);
const PID lateral_pid(0.05, 0.0, 0.0);

const std::function<units::Pose()> pose_getter = [] {
    return units::Pose(0_in, 0_in, 0_stDeg);
};

MotorGroup left_motors({-1, 2, -3}, 360_rpm);
MotorGroup right_motors({4, -5, 6}, 360_rpm);

const ExitConditionGroup<AngleRange> angular_exit_conditions(
    std::vector<ExitCondition<AngleRange>>{ExitCondition<AngleRange>(1_stDeg, 200_msec)});
const ExitConditionGroup<Length> lateral_exit_conditions(
    std::vector<ExitCondition<Length>>{ExitCondition<Length>(0.5_in, 200_msec)});

const Length track_width = 11.5_in;
const Number drift_compensation = 1.0;
const Number angular_slew = 0.0;
const Number lateral_slew = 0.0;
} // namespace lemlib
