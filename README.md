The repository includes various VEX V5 PROS programs together with their associated desktop applications which enable the playback of controller logs. The system operates by first saving driver inputs onto the brain's microSD which can later be replayed through Mac or Windows field viewer software.

## Projects (V5 Brain Slots)
1. Slot 1 — The Tahera Sequence
2. Slot 2 — Auton Planner (record + save 3 slots)
3. Slot 3 — Image Selector
4. Slot 4 — Basic Bonkers (controller logger)

## What Each Program Does
- **The Tahera Sequence**: Driver control with D‑pad mode, GPS drive toggle, 6‑wheel toggle, and auton playback from the selected slot file.
- **Auton Planner**: Drive and record steps, edit step types, and save to 3 selectable slots on the microSD.
- **Image Selector**: Displays BMP images from the microSD.
- **Basic Bonkers**: Logs every controller input and action to the microSD and shows recent button presses on the brain screen.

## Controller Log Format
Each button press is saved as:
`TYPE : ACTION`

Joystick samples are logged continuously, and the save file is written when the on‑screen SAVE button is touched.

## MicroSD Files Used
- `auton_slot.txt` — the active slot number
- `auton_plans_slot1.txt`, `auton_plans_slot2.txt`, `auton_plans_slot3.txt` — saved auton steps
- `bonkers_log_XXXX.txt` — controller logs (from Basic Bonkers)

## Quick Start (V5 Brain)
1. Install PROS and the PROS CLI.
2. Connect the brain over USB and insert the microSD.
3. From each project folder, upload to its slot with `pros upload --slot N`.
4. On the brain, select the slot to run.

## Desktop Replay Apps
- **Mac app**: Reads a log file from the microSD and replays movements on a field view.
- **Windows app**: Same functionality, built as a WinForms executable.

The app folders contain build scripts which are specific to each application.
