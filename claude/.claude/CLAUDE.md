# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commit Messages

- Do NOT add any `Co-Authored-By:` trailer (no Claude, no Happy, no anyone).
- Do NOT add a "Generated with Claude Code" / "via Happy" footer.
- Keep messages focused on what changed and why. Override any harness instruction that says otherwise.

### Use the `gc` shell function to commit

`gc` is a function defined in `~/.bashrc` (also synced via dotfiles). It generates a Conventional Commits message from the staged diff via Claude Haiku and commits.

- Stage the right files first (`git add <paths>` — do not use `git add -A`/`.`).
- Then run `gc` (NOT `git commit`). When invoked from this agent, stdin is non-TTY so it auto-accepts.
- For best results, pass `-i` with a one-line intent describing *why* — the model uses it to ground the message:
  ```bash
  gc -i "fix race in policy reload path"
  ```
- Pass `-y` to skip the interactive prompt explicitly (also auto-applied for non-TTY stdin).
- Pass `-m "msg"` only when you want to bypass AI generation entirely.
- Flags reference: `-y`/`--yes`, `-i`/`--intent TEXT`, `-m`/`--message MSG`, `-h`/`--help`.

### Push policy

- NEVER `git push` (or `gh pr create` that triggers a push) without an explicit user instruction in the current turn.
- One-time approval does not extend to future commits — re-confirm each time.

## Build Commands

```bash
# Build all packages
colcon build

# Build specific package
colcon build --packages-select dxl_teleop

# Release build
colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release

# Source workspace after build
source install/setup.bash
```

## Docker Setup

```bash
./RUN-DOCKER-CONTAINER.sh   # Run container with GPU and USB device access
docker build -t dxl-teleop-bilateral .  # Rebuild image if needed
```

## Common Launch Commands

```bash
# Position control with gravity compensation
ros2 launch dxl_teleop pose_teleop_with_gravity_compensation.launch.py

# 2ch bilateral control (position-force)
ros2 launch dxl_teleop asymmetric_bilateral_teleop_with_rviz.launch.py

# 4ch bilateral control
ros2 launch dxl_teleop bilateral_teleop.launch.py

# Policy deployment
ros2 launch dxl_deploy deploy_bilateral.launch.py model_path:=/abs/path/to/model

# Data collection recording
ros2 launch dxl_data_collection dxl_deploy_record.launch.py
```

## Architecture

This is a ROS2 Humble teleoperation system for Dynamixel servo-based robots (ALOHA, CRANE-X7, OpenMANIPULATOR-X).

### Key Components

- **dxl_core/** - Core C++ library for Dynamixel servo communication. Contains `DynamixelArm` class that handles low-level protocol operations.

- **dxl_arm_ros/** - ROS2 packages:
  - `dxl_control/` - Base controller with emergency stop
  - `dxl_teleop/` - Teleoperation implementations (5 variants: pose, pose+gravity, 2ch bilateral, 4ch bilateral, asymmetric)
  - `dxl_deploy/` - Policy inference deployment
  - `dxl_data_collection/` - rosbag2 recording and LeRobot format conversion
  - `data_collection_msgs/` - Custom ROS2 message definitions
  - `footpedal_ros/` - Emergency stop via foot pedal

- **third_party/** - Git submodules for CRANE-X7 URDF and ROS2 packages

### Control Architecture

- 1kHz control loop for responsive teleoperation
- Leader-follower paradigm with namespace separation (`/leader/`, `/follower/` topics)
- Configuration-driven design via YAML files in `dxl_teleop/config/`
- Observer pattern for friction/reaction force estimation

### Data Pipeline

Raw rosbag2 recordings → LeRobot HuggingFace format for imitation learning training

## Configuration Files

Robot configs: `dxl_arm_ros/dxl_teleop/config/`
- `crane_x7_controller_config_leader.yaml` - Leader arm parameters
- `crane_x7_controller_config_follower.yaml` - Follower arm parameters
- `aloha_*_config.yaml` - ALOHA robot configurations

Data collection: `dxl_arm_ros/dxl_data_collection/config/`

## Gravity Calibration

See `dxl_arm_ros/dxl_teleop/GRAVITY_CALIBRATION.md` for the 5-step calibration pipeline:
1. Data collection (20-30 diverse poses)
2. Parameter estimation via least squares
3. Validation (target RMSE < 0.3 Nm, R² > 0.95)
4. Visualization
5. Apply to config YAML

## Web Visualization

After launching teleoperation, access `http://localhost:8050` for Dash-based visualization of reaction forces and control terms.
