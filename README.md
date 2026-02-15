The repository contains multiple VEX V5 PROS programs which come with their respective desktop software that supports controller log playback. The system saves driver inputs to the brain's microSD and later enables playback through Mac and Windows field viewer software.

## Projects (V5 Brain Slots)
1. Slot 1 — The Tahera Sequence
2. Slot 2 — Auton Planner (record + save 3 slots)
3. Slot 3 — Image Selector
4. Slot 4 — Basic Bonkers (controller logger)

## What Each Program Does
- **The Tahera Sequence**: Driver control with D‑pad mode, GPS drive toggle, 6‑wheel toggle, and auton playback from the selected slot file.
- **Auton Planner**: Drive and record steps, edit step types, and save to 3 selectable slots on the microSD.
- **Image Selector**: Displays BMP images from the microSD.
- **Basic Bonkers**: The system records all controller inputs and actions to the microSD while displaying the latest button presses on the brain screen.

## Controller Log Format
Each button press is saved as:
`TYPE : ACTION`

The system records joystick samples continuously while the save file creation starts when the user touches the on-screen SAVE button.

## MicroSD Files Used
- `auton_slot.txt` — the active slot number
- `auton_plans_slot1.txt`, `auton_plans_slot2.txt`, `auton_plans_slot3.txt` — saved auton steps
- `bonkers_log_XXXX.txt` — controller logs (from Basic Bonkers)
- `controller_mapping.txt` — custom Tahera button mapping (optional)

## Quick Start (V5 Brain)
1. The user needs to install both the PROS software and its command-line interface.
2. The user needs to connect the brain through USB while inserting the microSD.
3. From each project folder, upload to its slot with `pros upload --slot N`.
4. The user needs to choose which slot they want to execute on the brain.

## Desktop Replay Apps
- **Mac app**: The application retrieves a log file from the microSD to recreate movements in a field view.
- **Windows app**: The application offers identical features which operate as a WinForms executable.

The application directories contain multiple Python files which execute various functions through multiple application programs.

## Prototype Branch Workflow
- Ongoing development should happen on `codex/prototypes`.
- Release merges should land in `main` only when the prototype branch is stable.
- Helper script for release merge:
  - `tools/release_merge_from_prototypes.sh`
  - Default behavior merges `codex/prototypes` into `main` and pushes `main`.
