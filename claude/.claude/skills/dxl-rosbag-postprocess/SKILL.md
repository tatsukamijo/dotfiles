---
name: dxl-rosbag-postprocess
description: After a rosbag2 collection session in dxl-teleop-bilateral, copy the recorded task directory from local_dataset/ into the canonical rosbags/ tree, run the rosbag2->LeRobot conversion via temporal_force_encoding's pixi task, and validate the resulting dataset (action present, videos present, frame counts consistent). Use this whenever the user has just finished collecting episodes and wants the LeRobot dataset built and sanity-checked.
---

# DXL rosbag → LeRobot post-processing

After a `dxl_data_collection` session, raw rosbags land under
`dxl-teleop-bilateral/dxl_arm_ros/dxl_data_collection/local_dataset/<task>-<robot>-<location>/`.
The downstream training pipeline expects them at
`/home/tatsuya.kamijo/dataset/bilateral_imitation/rosbags/<task>-<robot>-<location>/`
and the converted LeRobot output at
`/home/tatsuya.kamijo/dataset/bilateral_imitation/lerobot/<dataset_name>/`.

This skill takes a freshly recorded task directory through three deterministic
steps: **copy → convert → validate**.

## Inputs

Required from the user (or inferred):

- `<task_dir_name>` — e.g. `pose_teleop_test-crane-x7-kadokawa`. The directory
  under `local_dataset/`. The trailing `-<robot>-<location>` suffix is part of
  the convention created by `rosbag_manager.py`.
- `<dataset_name>` — short identifier for the LeRobot output dataset folder.
  Default to `<task_name without suffix>` (e.g. `pose_teleop_test`).
- `<conversion_config>` — relative path under
  `temporal_force_encoding/config/conversion/`. Default: `cube_position_v3.yaml`
  (the latest single-arm 24D state / 8D action config with
  `state_as_action: false`, action read from
  `/follower/arm_trajectory_controller/command`). Other usable configs:
  `single_position.yaml` (now also `state_as_action: false`).
- `<target_freq>` — Hz to resample to. Default: `50`. The pose_teleop launches
  publish at 50 Hz; conversion at 50 Hz keeps source resolution.

If the user just says "post-process", ask only for the task dir name and
default the rest. Don't pause for items where a sensible default exists.

## Step 1 — copy from local_dataset to dataset/rosbags

Pre-flight: confirm the source exists. If it does not, **stop here** and ask the
user to confirm the task name. Do NOT pick a near-name sibling
automatically — the `-<robot>-<location>` suffix and prefix are load-bearing
(the LeRobot output dir and downstream pixi tasks default off the prefix).

```bash
SRC=/home/tatsuya.kamijo/dxl-teleop-bilateral/dxl_arm_ros/dxl_data_collection/local_dataset/<task_dir_name>
DST=/home/tatsuya.kamijo/dataset/bilateral_imitation/rosbags/<task_dir_name>

if [ ! -d "$SRC" ]; then
    echo "Source not found: $SRC"
    echo "Available task dirs:"
    ls /home/tatsuya.kamijo/dxl-teleop-bilateral/dxl_arm_ros/dxl_data_collection/local_dataset/
    exit 1
fi

mkdir -p "$DST"
cp -rv "$SRC/." "$DST/"
ls -la "$DST"
```

Notes:

- `cp -r "$SRC/." "$DST/"` copies *contents* into DST without nesting; this
  matters when DST already has a `meta.json` from previous sessions.
- After the copy, files are owned by the host user (the rosbag_manager `umask
  0o000` change and the post-recording `chmod -R a+rwX` make this work even
  for files that were originally written by container root).
- Do not delete the source. Subsequent collection sessions append more
  episodes there; we sync, not move.

## Step 2 — convert rosbag → LeRobot

```bash
cd /home/tatsuya.kamijo/temporal_force_encoding
pixi run python scripts/rosbag2lerobot.py \
    /home/tatsuya.kamijo/dataset/bilateral_imitation/rosbags/<task_dir_name> \
    --config config/conversion/<conversion_config> \
    --output-dir /home/tatsuya.kamijo/dataset/bilateral_imitation/lerobot/<dataset_name> \
    --target-freq <target_freq>
```

Pre-flight: `LeRobotDataset.create` does `mkdir(exist_ok=False)` and will
crash with `FileExistsError` if the output directory already exists.

```bash
OUT=/home/tatsuya.kamijo/dataset/bilateral_imitation/lerobot/<dataset_name>
if [ -d "$OUT" ]; then
    mv "$OUT" "${OUT}.bak_$(date +%Y%m%d_%H%M%S)"
fi
```

NEVER `rm -rf` the output dir. The user has a hard rule on never deleting
model/dataset output dirs — always rename to a `.bak_*` sibling and let them
clean up later. (See `~/.claude/projects/.../memory/feedback_never_delete_checkpoints.md`.)

## Step 3 — validate the LeRobot dataset

```bash
cd /home/tatsuya.kamijo/temporal_force_encoding
pixi run python scripts/validate_lerobot_dataset.py \
    --dataset /home/tatsuya.kamijo/dataset/bilateral_imitation/lerobot/<dataset_name>
```

Expected success line:
```
[validate] OK: <N> episodes, <F> frames, 2 video stream(s) per episode all present.
```

The validator checks (read it for the full list):
- per-episode parquet file exists
- per-episode video files exist for every `dtype: video` feature
- `action` column is not all-zero (catches the case where the chosen action
  topic was empty — e.g. picking `/leader/...` for a pose_teleop bag)
- `observation.state` is finite, not all-zero
- frame counts match `info.json`

If validation fails:
- "action all-zero" → wrong `action` topic in the conversion config (for
  pose_teleop bags, action lives on `/follower/arm_trajectory_controller/command`,
  *not* `/leader/...`).
- "video missing" → check the rosbag actually has the camera topic; pose_teleop
  launches both `usbcam_top` and `usbcam_right` — if either device was missing,
  the bag has no frames for that topic and the converter would have no
  images to encode.
- frame mismatch → don't paper over; surface to the user.

## After all three steps

Report a single short summary to the user:

```
copied:  <task_dir_name> -> rosbags/
converted: <N> episodes, <F> frames @ <target_freq> Hz
validated: OK
output: /home/tatsuya.kamijo/dataset/bilateral_imitation/lerobot/<dataset_name>
```

Do NOT proactively kick off training, replay, or further conversion variants
(e.g. `trim_state_to_pos_vel`). The user drives the next step.

## Conversion config quick reference

| Config | repo_id | state | action | state_as_action |
|---|---|---|---|---|
| `cube_position_v3.yaml` | `single_cube_v3` | **16D** (pos+vel × 8, no effort) | 8D follower pos | false (preferred for pose_teleop / bilateral collected after 2026-05; matches policy input layout directly — no `trim_state_to_pos_vel` follow-up needed) |
| `cube_position.yaml` | `single_cube` | 24D | 8D | true (legacy) |
| `single_position.yaml` | `single_position_control` | 24D | 8D | false (post 2026-05-05 edit; was `true` before) |

When in doubt and the data was collected with the current `pose_teleop.launch.py`
(which now publishes `/leader_follower_joint_states`), use
`cube_position_v3.yaml`.

### State layout knob

`rosbag2lerobot.py` reads `topics.state_layout` from the config:

- `pos_vel_eff` (default if absent): 24D — `[pos, vel, eff] × 8` per joint.
- `pos_vel`: 16D — `[pos, vel] × 8` per joint, effort dropped. The script
  auto-overrides `features.observation.state.shape` and `names` to match,
  so the user only flips the one knob. `cube_position_v3.yaml` already sets
  this; legacy configs default to `pos_vel_eff` for backward compat.

When `state_layout: pos_vel` is in effect, `trim_state_to_pos_vel.py` is no
longer needed as a downstream pass — the `_pos16` / `_16` dataset is what
the converter produces directly.

## Pre-existing failure modes worth checking up-front

- Source `local_dataset/<task_dir_name>` not found → halt at Step 1, list the
  candidate task dirs, and ask the user. Never auto-pick a near-name match.
- Output directory already exists → backup, don't delete.
- `local_dataset/` files owned by `root` from a pre-fix container run →
  workaround: `chmod -R a+rwX` from inside the container, *not* `sudo` from
  host (avoid escalating).
- `pose_teleop` bag has empty `/leader/arm_trajectory_controller/command`
  connection (pose_teleop never publishes leader effort). The validator's
  "action all-zero" check catches this when the conversion config wrongly
  selected the leader topic.
