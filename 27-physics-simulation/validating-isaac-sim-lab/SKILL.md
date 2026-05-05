---
name: validating-isaac-sim-lab
description: Secondary validation and export skill that loads URDF/MJCF/USD-derived assets in NVIDIA Isaac Sim 5.1 + Isaac Lab 2.3.x, checks articulation semantics, inspects visuals, and supports physics validation for lab-equipment digital twins (SEM and similar). Use when the project needs USD/Omniverse workflows, RTX sensors (cameras, LiDAR), large synthetic-robotics environments, or tight NVIDIA ecosystem integration. Not the default A100 runtime because Isaac Sim explicitly does not support A100/H100 (no RT cores); requires RTX 4080+ for full rendering.
version: 2.0.0
author: Orchestra Research
license: BSD-3-Clause
tags: [Physics Simulation, Isaac Sim, Isaac Lab, USD, NVIDIA, RTX, Validation, Digital Twin]
dependencies: [isaacsim==5.1.0, isaaclab==2.3.2]
---

# validating-isaac-sim-lab

## Quick start

Stack baseline (May 2026, verified): Isaac Sim **5.1.0** (GA, Oct 2025) + Isaac Lab **2.3.2** (stable 2.x line). Omniverse Kit pin for 5.1.0 is **107.3.3**. Python is **3.11** (changed from 3.10 in 4.x). Omniverse Launcher is **deprecated as of Oct 1, 2025**; the primary install paths are pip and container. A100/H100 are explicitly unsupported (no RT cores). RTX 4080 / 16 GB VRAM is the current documented minimum; RTX 5080 is "Good", RTX PRO 6000 Blackwell is "Ideal".

Isaac Sim 6.0.0-dev2 + Isaac Lab 3.0.0-beta exist as pre-releases (Mar 2026) targeting Kit 110.0.0 and Python 3.12, but are **not stable GA** — treat as migration preview only.

```bash
# --- Option A: pip install (workstation) ---
pip install "isaacsim[all,extscache]==5.1.0" --extra-index-url https://pypi.nvidia.com
# First run triggers EULA acceptance interactively.
# For headless/CI set: export OMNI_KIT_ACCEPT_EULA=Y

# Isaac Lab from source on top of the same Python env:
git clone --branch v2.3.2 https://github.com/isaac-sim/IsaacLab.git
cd IsaacLab && ./isaaclab.sh -i

# --- Option B: container (headless / cloud) ---
docker pull nvcr.io/nvidia/isaac-sim:5.1.0
docker run --gpus all --runtime=nvidia -it --rm \
  -e ACCEPT_EULA=Y -e PRIVACY_CONSENT=Y \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics \
  -v "$PWD:/workspace" \
  nvcr.io/nvidia/isaac-sim:5.1.0 \
  /isaac-sim/python.sh /workspace/validate_asset.py
```

> Do NOT attempt to install Isaac Sim via Omniverse Launcher — it is deprecated and unavailable since Oct 1, 2025. Use pip or the NGC container.

## Common workflows

### 1. Headless USD/URDF asset validation (pip or container)

```
Task Progress:
- [ ] Step 1: Confirm RTX 4080+ GPU on host (A100/H100 are unsupported; RTX 30xx is below current official minimum)
- [ ] Step 2: Install Isaac Sim 5.1.0 via pip or pull nvcr.io/nvidia/isaac-sim:5.1.0
- [ ] Step 3: Set ACCEPT_EULA=Y / OMNI_KIT_ACCEPT_EULA=Y for non-interactive runs
- [ ] Step 4: Launch SimulationApp in headless mode; import URDF or open USD stage
- [ ] Step 5: Query articulation tree; verify joint names, axes, types, limits
- [ ] Step 6: Capture RTX render to PNG for visual smoke test
- [ ] Step 7: Emit isaac_validation_report.json with counts/limits/diffs
```

```python
# validate_asset.py — works with pip-installed Isaac Sim 5.1 or container /isaac-sim/python.sh
# NOTE: use isaaclab.app.AppLauncher for Isaac Lab tasks; SimulationApp alone for bare Isaac Sim.
from isaacsim import SimulationApp
sim = SimulationApp({"headless": True, "renderer": "RayTracedLighting"})

import json
import omni.usd
from pxr import Usd, UsdPhysics

# URDF import (5.1 path — prefer isaacsim.* namespaces over legacy omni.isaac.*)
from isaacsim.asset.importer.urdf import _urdf as urdf_iface

urdf = urdf_iface.acquire_urdf_interface()
cfg = urdf_iface.ImportConfig()
cfg.fix_base = True           # lab equipment: fixed to world
cfg.merge_fixed_joints = False  # preserve named links for affordance lookup
result, prim_path = urdf.parse_and_import_urdf(
    "/workspace/out/sem/sem.urdf", cfg
)

stage = omni.usd.get_context().get_stage()
report = {"prim_path": prim_path, "joints": []}
for prim in stage.Traverse():
    if prim.IsA(UsdPhysics.RevoluteJoint) or prim.IsA(UsdPhysics.PrismaticJoint):
        j = prim.GetAttribute("physics:axis").Get()
        report["joints"].append({
            "name": prim.GetName(),
            "type": prim.GetTypeName(),
            "path": str(prim.GetPath()),
            "axis": str(j),
        })

with open("/workspace/isaac_validation_report.json", "w") as f:
    json.dump(report, f, indent=2)

sim.close()
```

> Key change from 4.x: import path is `isaacsim.asset.importer.urdf` not `omni.isaac.urdf`. Treat `omni.isaac.*` imports as deprecated in 5.x.

### 2. Isaac Lab manager-based environment for articulated lab equipment

```
Task Progress:
- [ ] Step 1: Clone IsaacLab v2.3.2; install via ./isaaclab.sh -i
- [ ] Step 2: Use AppLauncher (not bare SimulationApp) for Isaac Lab task bootstrap
- [ ] Step 3: Subclass ManagerBasedEnvCfg or DirectRLEnvCfg for the lab asset
- [ ] Step 4: Define ArticulationCfg pointing at the imported USD stage
- [ ] Step 5: Define ObservationCfg, ActionCfg, EventCfg matching affordance JSON
- [ ] Step 6: Run isaaclab.sh -p with low parallel-env count first to check RTX VRAM
- [ ] Step 7: Confirm articulation step rate; profile with --enable_camera if needed
```

```python
# Isaac Lab 2.3.x task bootstrap — always use AppLauncher, not bare SimulationApp
from isaaclab.app import AppLauncher
import argparse

parser = argparse.ArgumentParser()
AppLauncher.add_app_launcher_args(parser)
args = parser.parse_args()
app_launcher = AppLauncher(args)
simulation_app = app_launcher.app

# --- After app launch, import Isaac Lab / Isaac Sim APIs ---
import gymnasium as gym
from isaaclab_tasks.utils import parse_env_cfg
import isaaclab.sim as sim_utils

# Stage helpers (new in 2.3.x — prefer over raw omni.usd calls)
stage = sim_utils.get_current_stage()
sim_utils.create_prim("/World/SEM", "Xform")

# Gymnasium rollout
env_cfg = parse_env_cfg("Isaac-SEM-Validate-v0", num_envs=1)
env = gym.make("Isaac-SEM-Validate-v0", cfg=env_cfg, render_mode="rgb_array")
obs, _ = env.reset()
for _ in range(100):
    action = env.action_space.sample()
    obs, reward, terminated, truncated, info = env.step(action)
env.close()
simulation_app.close()
```

```python
# ArticulationCfg for a USD-authored SEM stage (Isaac Lab 2.3.x)
from isaaclab.assets import ArticulationCfg
from isaaclab.actuators import ImplicitActuatorCfg
import isaaclab.sim as sim_utils

SEM_CFG = ArticulationCfg(
    prim_path="{ENV_REGEX_NS}/SEM",
    spawn=sim_utils.UsdFileCfg(usd_path="/workspace/out/sem/sem.usda"),
    actuators={
        "stage_axes": ImplicitActuatorCfg(
            joint_names_expr=["stage_x", "stage_y", "stage_z"],
            stiffness=350.0,
            damping=20.0,
        ),
    },
)
```

### 3. RTX camera capture for visual validation

```
Task Progress:
- [ ] Step 1: Open USD stage in Isaac Sim with RayTracedLighting renderer
- [ ] Step 2: Define Camera prims at chamber-interior poses (NOT TiledCamera — see issue #4951)
- [ ] Step 3: Trigger physics step + render at target Hz for N frames
- [ ] Step 4: Save PNG/EXR per camera; record intrinsics/extrinsics JSON
- [ ] Step 5: Run affordance VLM on captures; compare to ground-truth
- [ ] Step 6: Adjust lighting/material params until VLM agrees on affordances
- [ ] Step 7: Export validated USD + camera_set.json for downstream pipeline
```

> Use `Camera` not `TiledCamera` when running on RTX 5090 / Blackwell — TiledCamera has a confirmed hang on that GPU class (IsaacLab #4951). Also: instanceable mesh prims can break RGB annotator pipelines under Isaac Sim 5.1 (IsaacLab #4565); flatten instanceable meshes before dataset capture.

## When to use vs alternatives

Use this skill when: (a) the host has an RTX 4080+ GPU (NOT A100/H100), (b) the project needs USD/Omniverse-native workflows, (c) RTX sensors must be photorealistic, (d) large parallel synthetic environments are required, or (e) the deliverable must integrate with the NVIDIA ecosystem.

**Do not** use as the primary A100 simulator — defer to `simulating-mujoco-mjx` for A100 hosts. Do not replace mesh repair (`conditioning-collision-meshes`) or sysid (`calibrating-sysid-rl-hooks`). Do not use for VR/web rendering.

**Isaac Sim 6.0.0-dev2 / Isaac Lab 3.0.0-beta**: these pre-releases (Mar 2026) require Kit 110.0.0, Python 3.12, PyTorch 2.10, URDF/MJCF Importer 3.0, and have breaking API changes. Do not adopt until they reach GA unless explicitly prototyping the migration path.

**Licensing**: Isaac Lab framework is BSD-3-Clause; `isaaclab_mimic` component is Apache 2.0. Isaac Sim runtime requires accepting the NVIDIA/Omniverse EULA. Review before redistribution.

## Common issues

- **Omniverse Launcher / Nucleus Workstation not found**: deprecated Oct 1, 2025. Switch to pip (`isaacsim[all,extscache]==5.1.0 --extra-index-url https://pypi.nvidia.com`) or NGC container. Any docs referencing Launcher are stale.

- **A100/H100 launch failures**: Isaac Sim 5.x does not support these GPUs. Detect at startup:
  ```python
  import subprocess
  out = subprocess.check_output(["nvidia-smi", "-L"]).decode()
  if "A100" in out or "H100" in out:
      raise RuntimeError("Isaac Sim 5.x does not support A100/H100 (no RT cores). "
                         "Use an RTX 4080+ host or defer to simulating-mujoco-mjx.")
  ```

- **RTX 30xx viability**: RTX 30xx is below the documented official minimum (RTX 4080 / 16 GB VRAM) for Isaac Sim 5.1. May run lightweight/headless scenes but is not supported. Use RTX 4080+ or above.

- **EULA / PRIVACY_CONSENT hang**: container or pip first-run will block without consent. Set `ACCEPT_EULA=Y` and `PRIVACY_CONSENT=Y` in container runs; set `OMNI_KIT_ACCEPT_EULA=Y` for pip-based headless runs.

- **`omni.isaac.*` import errors in 5.x**: Isaac Sim 5.x migrated APIs to `isaacsim.*` namespaces. Replace `from omni.isaac.urdf import ...` with `from isaacsim.asset.importer.urdf import ...`, and `from omni.isaac.lab.*` with `from isaaclab.*`. Old names may still work via compatibility shims but should be treated as deprecated.

- **Python 3.11 mismatch**: Isaac Sim 5.x ships Python 3.11 (not 3.10 as in 4.x). Do not mix 3.10 venv packages into the 5.x environment. Keep MuJoCo 3.x work in a separate process.

- **TiledCamera hang on RTX 5090 / Blackwell** (IsaacLab #4951, 2026): `TiledCamera` hangs with NVRTC issues on Blackwell-class GPUs. Workaround: use `Camera` instead of `TiledCamera` for validation pipelines.

- **RGB annotator fails on instanceable mesh prims** (IsaacLab #4565, 2026): RGB render product annotation fails when the USD stage contains instanceable mesh assets under Isaac Sim 5.1. Flatten instanceable prims before running synthetic data or visual capture pipelines.

- **`fix_base` / `merge_fixed_joints` on URDF import**: for lab equipment bolted to world, set `fix_base=True` and `merge_fixed_joints=False`. Merging fixed joints drops named links that affordance JSON depends on.

- **USD vs URDF frame divergence**: always compare `UsdPhysics.RevoluteJoint` / `PrismaticJoint` axis attributes against the URDF source and the canonical joint dictionary; flag any axis mismatch >1e-6 magnitude. Correct at source in `authoring-urdf-mjcf-usd`.

## Cross-simulator divergence audit

Run a deterministic 1-second rollout in both Isaac Sim and MuJoCo (`simulating-mujoco-mjx`) with identical control inputs and zero noise; record `qpos` traces and compute per-joint RMS divergence. Tolerable RMS for a well-conditioned articulated lab asset is under 1e-3 SI units. Larger divergence usually indicates (a) inertia round-trip loss, (b) joint frame mismatch, or (c) contact tuning differences — correct at source in the authoring skill.

## Containerized execution recipe

```bash
#!/usr/bin/env bash
set -euo pipefail
docker run --gpus all --runtime=nvidia --rm \
  -e ACCEPT_EULA=Y -e PRIVACY_CONSENT=Y \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics \
  -v "$PWD/out:/workspace/out" \
  -v "$PWD/scripts:/workspace/scripts" \
  -w /workspace \
  nvcr.io/nvidia/isaac-sim:5.1.0 \
  /isaac-sim/python.sh /workspace/scripts/validate_asset.py \
  --urdf /workspace/out/sem/sem.urdf \
  --report /workspace/out/sem/isaac_validation_report.json
```

Mount only needed directories. Isaac Sim first launch compiles shaders (30–90 seconds). NVIDIA driver >= 535.129.03 required; mismatched drivers surface as cryptic Kit shutdown messages.

## Isaac Lab v2.3.2 task scaffolding

When the project moves to RTX-rendered RL or domain randomization, scaffold with `ManagerBasedRLEnv` (not `DirectRLEnv`) for declarative, diffable observation/action/event configs:

1. `ArticulationCfg` with `sim_utils.UsdFileCfg(usd_path=...)` pointing at the asset from `authoring-urdf-mjcf-usd`.
2. `ObservationsCfg` matching the affordance JSON; expose joint positions, velocities, contact forces.
3. `ActionsCfg` mapping policy outputs to the same joint names used in MuJoCo for cross-simulator transfer.
4. `EventsCfg` for domain randomization reusing calibrated parameters from `calibrating-sysid-rl-hooks`.
5. Leave reward configuration empty in this skill's scope; reward shaping belongs to the consuming RL skill.

## Advanced topics

See `references/issues.md` for Isaac Sim 5.1.0 release notes, Isaac Lab 2.3.2 migration notes, the IsaacLab #4951 / #4565 issue details, and the canonical Isaac-vs-MuJoCo rollout-divergence audit script.

## Resources

- Isaac Sim releases: https://github.com/isaac-sim/IsaacSim/releases
- Isaac Lab releases: https://github.com/isaac-sim/IsaacLab/releases
- Isaac Sim 5.1 docs: https://docs.isaacsim.omniverse.nvidia.com/5.1.0/
- Isaac Sim pip install: https://docs.isaacsim.omniverse.nvidia.com/5.1.0/installation/install_pip.html
- Isaac Sim hardware requirements: https://docs.isaacsim.omniverse.nvidia.com/5.1.0/installation/requirements.html
- Isaac Sim NGC container: https://catalog.ngc.nvidia.com/orgs/nvidia/containers/isaac-sim
- Isaac Lab v2.3.2 release: https://github.com/isaac-sim/IsaacLab/releases/tag/v2.3.2
- IsaacLab issue #4951 (TiledCamera / Blackwell): https://github.com/isaac-sim/IsaacLab/issues/4951
- IsaacLab issue #4565 (RGB annotator / instanceable prims): https://github.com/isaac-sim/IsaacLab/issues/4565
- OpenUSD UsdPhysics schema: https://openusd.org/release/api/usd_physics_page_front.html
