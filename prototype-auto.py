#region VEXcode Generated Robot Configuration
from vex import *
import urandom
import math

# Brain should be defined by default
brain=Brain()

# Robot configuration code


# wait for rotation sensor to fully initialize
wait(30, MSEC)


# Make random actually random
def initializeRandomSeed():
    wait(100, MSEC)
    random = brain.battery.voltage(MV) + brain.battery.current(CurrentUnits.AMP) * 100 + brain.timer.system_high_res()
    urandom.seed(int(random))
      
# Set random seed 
initializeRandomSeed()


def play_vexcode_sound(sound_name):
    # Helper to make playing sounds from the V5 in VEXcode easier and
    # keeps the code cleaner by making it clear what is happening.
    print("VEXPlaySound:" + sound_name)
    wait(5, MSEC)

# add a small delay to make sure we don't print in the middle of the REPL header
wait(200, MSEC)
# clear the console to make sure we don't have the REPL in the console
print("\033[2J")

#endregion VEXcode Generated Robot Configuration

from vex import *
import math
import random  # Use standard random module

# ----------------------------
# Brain + Controller
# ----------------------------
brain = Brain()
controller = Controller(PRIMARY)

# wait for rotation sensor to fully initialize
wait(30, MSEC)

# ----------------------------
# Make random actually random
# ----------------------------
def initialize_random_seed():
    # Combine battery voltage, current, and timer for some entropy
    seed = int(brain.battery.voltage(MV) + brain.battery.current(CurrentUnits.AMP) * 100 + brain.timer.system_high_res())
    random.seed(seed)

initialize_random_seed()
#endregion# ----------------------------
# 6-Motor Drivetrain
# ----------------------------
left_drive = MotorGroup(
    Motor(Ports.PORT1, GearSetting.RATIO_36_1, False),
    Motor(Ports.PORT2, GearSetting.RATIO_36_1, False),
    Motor(Ports.PORT3, GearSetting.RATIO_36_1, False)
)

right_drive = MotorGroup(
    Motor(Ports.PORT15, GearSetting.RATIO_36_1, True),
    Motor(Ports.PORT13, GearSetting.RATIO_36_1, True),
    Motor(Ports.PORT14, GearSetting.RATIO_36_1, True)  # Make all right motors inverted
)

# ----------------------------
# Helper Functions
# ----------------------------
def apply_deadband(val, deadband=5):
    return 0 if abs(val) <= deadband else val

# ----------------------------
# Autonomous Helper Constants
# ----------------------------
WHEEL_DIAMETER_IN = 4.0
WHEEL_CIRCUMFERENCE = WHEEL_DIAMETER_IN * math.pi
ROBOT_TRACK_WIDTH_IN = 12.0  # distance between left and right wheels (adjust to your robot)

def inches_to_degrees(inches):
    """Convert linear inches to wheel degrees"""
    return (inches / WHEEL_CIRCUMFERENCE) * 360

def robot_turn_degrees(turn_deg):
    """Convert robot turn degrees to wheel degrees"""
    turning_circ = math.pi * ROBOT_TRACK_WIDTH_IN
    inches_per_wheel = (turn_deg / 360) * turning_circ
    return inches_to_degrees(inches_per_wheel)

# ----------------------------
# Autonomous Movement
# ----------------------------
def drive_inches(inches, speed=40):
    degrees = inches_to_degrees(abs(inches))

    left_drive.set_position(0, DEGREES)
    right_drive.set_position(0, DEGREES)

    direction = FORWARD if inches >= 0 else REVERSE

    left_drive.spin(direction, speed, PERCENT)
    right_drive.spin(direction, speed, PERCENT)

    while abs(left_drive.position(DEGREES)) < degrees or abs(right_drive.position(DEGREES)) < degrees:
        wait(10, MSEC)

    left_drive.stop(BRAKE)
    right_drive.stop(BRAKE)

def turn_degrees(deg, speed=30):
    degrees = robot_turn_degrees(abs(deg))
    left_drive.set_position(0, DEGREES)
    right_drive.set_position(0, DEGREES)

    if deg > 0:
        left_drive.spin(FORWARD, speed, PERCENT)
        right_drive.spin(REVERSE, speed, PERCENT)
    else:
        left_drive.spin(REVERSE, speed, PERCENT)
        right_drive.spin(FORWARD, speed, PERCENT)

    while abs(left_drive.position(DEGREES)) < degrees:
        wait(10, MSEC)

    left_drive.stop(BRAKE)
    right_drive.stop(BRAKE)

# ----------------------------
# Autonomous Routine
# ----------------------------
def autonomous():
    # Drive forward ~30 inches (~1.25 tiles)
    drive_inches(30, speed=40)
    wait(300, MSEC)

    # Turn ~120 degrees
    turn_degrees(120, speed=30)
    wait(200, MSEC)

    # Back up slightly
    drive_inches(-6, speed=35)

# ----------------------------
# User Control (Arcade Drive)
# ----------------------------
def usercontrol():
    DEAD = 5
    TURN_SCALE = 0.85

    while True:
        forward = -apply_deadband(controller.axis3.position(), DEAD)
        turn = apply_deadband(controller.axis1.position(), DEAD)

        turn = int(turn * TURN_SCALE)

        left_pct = forward + turn
        right_pct = forward - turn

        left_pct = max(-100, min(100, left_pct))
        right_pct = max(-100, min(100, right_pct))

        left_drive.spin(FORWARD if left_pct >= 0 else REVERSE, abs(left_pct), PERCENT)
        right_drive.spin(FORWARD if right_pct >= 0 else REVERSE, abs(right_pct), PERCENT)

        wait(20, MSEC)

# ----------------------------
# Competition Setup
# ----------------------------
comp = Competition(usercontrol, autonomous)

if __name__ == "__main__":
    comp.start()
