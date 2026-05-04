---
name: genie-sim-project
description: Guide for building projects on top of genie_sim without modifying its source. Use when setting up a new project, extending genie_sim, creating configs/scenes, or debugging Isaac Sim integration issues.
---

# genie_sim Project Guide

genie_sim (github.com/AgibotTech/genie_sim) is a simulation framework on Isaac Sim for robot manipulation. This skill guides you in building projects on top of it **without modifying its source**.

## Repo Structure: Submodule + Overlay

```
your_project/
├── genie_sim/               # git submodule (NEVER modify)
├── configs/
│   ├── app.yaml             # your app config (like vitra_demo.yaml)
│   └── eval_tasks/          # task definition JSONs
├── scenes/
│   └── my_task/
│       └── 0/
│           ├── scene.usda   # object placement (USD)
│           └── instructions.json
├── src/
│   ├── app.py               # your entrypoint (imports genie_sim)
│   ├── publishers/          # custom ROS publishers
│   ├── policies/            # custom policies
│   └── envs/                # custom env subclasses
├── scripts/
│   ├── start.sh
│   └── stop.sh
├── docker/
│   └── docker-compose.yml   # mounts genie_sim + your project
└── .gitmodules
```

### Setup

```bash
git submodule add git@github.com:AgibotTech/genie_sim.git genie_sim
git submodule update --init
```

## Extension Patterns (No Source Modification)

### 1. Custom Entrypoint

Instead of modifying `api_core.py`, create your own `app.py` that imports and wraps genie_sim:

```python
# src/app.py
import sys
sys.path.insert(0, "genie_sim/source")

from geniesim.app.controllers.api_core import APICore
from your_project.publishers.obs_publisher import MyObsPublisher

# After APICore init, attach your publisher externally
api_core = APICore(config)
publisher = MyObsPublisher(api_core)
```

### 2. Object Placement via sub_task (scene.usda)

**DO NOT** modify `task_benchmark.py` to inject objects. Use the existing `sub_task` mechanism:

```usda
#usda 1.0
(
    defaultPrim = "World"
    metersPerUnit = 1
    upAxis = "Z"
)

def "World"
{
    def "Objects"
    {
        def Xform "my_bowl" (
            prepend payload = @path/to/assets/objects/benchmark/bowl/benchmark_bowl_000/Aligned.usda@
        )
        {
            quatf xformOp:orient = (1.0, 0, 0, 0)
            float3 xformOp:scale = (1, 1, 1)
            double3 xformOp:translate = (0.84, -0.02, 0.898)
            uniform token[] xformOpOrder = ["xformOp:translate", "xformOp:orient", "xformOp:scale"]
        }
    }
}
```

Launch with `sub_task_name` pointing to the directory containing this `scene.usda`.

**IMPORTANT**: Positions in `scene.usda` are **world coordinates** (under `/Workspace`), NOT `/World` local coordinates.

### 3. Custom Policy

Subclass `BasePolicy` or `DemoPolicy`:

```python
from geniesim.benchmark.policy.base import BasePolicy

class MyPolicy(BasePolicy):
    def act(self, observation, step_num=0, task_instruction=""):
        # your inference logic
        return action
```

### 4. Custom Env

Subclass `DummyEnv` or `BaseEnv`:

```python
from geniesim.benchmark.envs.dummy_env import DummyEnv

class MyEnv(DummyEnv):
    def reset(self):
        obs = super().reset()
        # additional setup
        return obs
```

## Coordinate Systems

### Critical: Two Prim Hierarchies

| Prim Path | Loaded By | Coordinate Frame | Use Case |
|-----------|-----------|-------------------|----------|
| `/World/...` | `add_reference_to_stage(scene_usd, "/World")` | Scene-local (kitchen USD internal coords) | Background scene geometry |
| `/Workspace/...` | `_reload_scenes(sub_usd_path)` → `/Workspace` | World coordinates | sub_task objects (scene.usda) |
| `/World/Objects/...` | `api_core.add_usd_obj()` | `/World`-local | Objects from TaskGenerator |

**Rule of thumb**:
- Objects in `scene.usda` (sub_task) → **world coordinates** (e.g., `[0.84, -0.02, 0.898]`)
- Objects added via `add_usd_obj()` → **`/World` local coordinates** (e.g., `[-4.03, -0.032, 0.9]`)
- `function_space_objects.workspace_00.position` tells you where the workspace is in `/World` local coords

### Camera Frame Conventions

- Isaac Sim cameras: **OpenGL** (X-right, Y-up, Z-toward-viewer)
- Most ML models expect: **OpenCV** (X-right, Y-down, Z-away)
- Conversion: 180-degree rotation around X-axis

```python
R_x180 = np.diag([1.0, -1.0, -1.0, 1.0])  # 4x4
T_cam_cv = T_cam_gl @ R_x180
```

### Quaternion Conventions

| System | Order |
|--------|-------|
| Isaac Sim (`get_world_pose`) | `[w, x, y, z]` |
| ROS (`PoseStamped`) | `[x, y, z, w]` |
| scipy (`R.from_quat`) | `[x, y, z, w]` |

## Config Reference

### eval_task JSON Structure

```json
{
  "task": "task_name",
  "generalization": {
    "init_base": { "num": 1, "x_thresh": 0.0, "y_thresh": 0.0 },
    "init_joint": { "num": 1, "thresh": 0.0 },
    "lights": { "intensity": [8000], "num": 1, "temperature": [6500] },
    "num_material": 1
  },
  "objects": {
    "constraints": null,
    "extra_objects": [],
    "fix_objects": [],
    "task_related_objects": []
  },
  "robot": {
    "arm": "right",
    "robot_cfg": "G2_omnipicker.json",
    "robot_id": "G2",
    "robot_init_pose": {
      "workspace_00": {
        "position": [x, y, z],
        "quaternion": [w, x, y, z]
      }
    }
  },
  "scene": {
    "function_space_objects": { "workspace_00": { "position": [...], "size": [...] } },
    "scene_id": "workspace_00",
    "scene_info_dir": "background/...",
    "scene_usd": "background/.../scene.usd"
  },
  "stages": [...]
}
```

**Gotcha**: `scene_id.split("/")[-1]` must match a key in `robot_init_pose`. If `scene_id` is `"G2_Popcorn"` but `robot_init_pose` has `"workspace_00"`, you get `KeyError: 'position'`.

### add_object() Expected Format

`base_env.add_object()` expects:

```json
{
  "object_id": "unique_name",
  "model_path": "relative/to/assets/Aligned.usd",
  "position": [x, y, z],
  "quaternion": [w, x, y, z],
  "mass": 0.1,
  "scale": [1, 1, 1]
}
```

### Available Scenes (G2)

| Scene | scene_usd | Robot Position |
|-------|-----------|----------------|
| kitchen | `background/opensource_kitchen/kitchen.usd` | `[0.345, 0.133, 0.0]` |
| home | `background/opensource_home/home_02.usd` | `[-0.1, 0.0, 0.0]` |
| home_00 | `background/home_04/home_04.usda` | `[1.537, -0.051, 0.171]` |
| home_b | `background/home_b/home_b_00.usda` | `[2.25, 0.76, 0.0]` |
| study_room | `background/opensource_study_room/study_00.usd` | `[-0.074, -0.061, 0.0]` |
| laboratory | `background/laboratory_00/laboratory_06.usda` | `[-1.28, 2.26, 0.0]` |
| market | `background/market_00/market_00.usda` | `[0.53, -0.65, 0.0]` |
| warehouse | `background/warehouse/warehouse.usda` | `[0.245, 0.093, 0.0]` |
| popcorn | `background/popcorn_01/popcorn_01.usda` | `[0.055, -0.064, 0.0]` |
| table | `scenes/room/room_00.usda` | `[-0.765, -0.027, -0.01]` |

## Key Code Paths

| What | File | Key Method |
|------|------|------------|
| Benchmark runner | `benchmark/task_benchmark.py` | `TaskBenchmark.evaluate_policy()` |
| Task generation | `plugins/tgs/layout/task_generate.py` | `TaskGenerator.generate_tasks()` |
| Object spawning | `benchmark/envs/base_env.py:164` | `add_object()` |
| Scene loading | `app/controllers/api_core.py:713` | `_init_robot_cfg()` |
| Sub-task loading | `app/controllers/api_core.py:609` | `_reload_scenes()` |
| Robot reset | `benchmark/envs/dummy_env.py:76` | `reset()` |
| Physics/render loop | `app/controllers/api_core.py` | `run_on_render_loop()`, `run_on_physics_loop()` |

## Common Pitfalls

1. **Benchmark assets have no `.obj` files** — only `.usd`/`.usda`. `LayoutObject(use_sdf=True)` will crash. Use `sub_task` + `scene.usda` instead of `task_related_objects`.

2. **Container path vs host path** — Runtime assets are at `/geniesim/main/source/geniesim/assets`, not the host path. Scripts using `$PWD` must be run from the repo root on the host.

3. **`run_on_render_loop` is blocking** — Calls are queued and executed on the main thread. Long operations will block rendering.

4. **ROS reset mechanism** — Publish `std_msgs/Bool false` to `/sim/infer_start` to return to `env.reset()` loop (restores initial joint positions).

## Docker Mount Pattern

```yaml
volumes:
  - ./genie_sim:/geniesim/main          # genie_sim submodule
  - ./configs:/geniesim/project/configs  # your configs
  - ./src:/geniesim/project/src          # your code
```