---
name: simulating-mujoco-mjx
description: Default simulator skill for lab-equipment digital twins. Generates MJCF, compiles and validates it, runs deterministic CPU MuJoCo for authoring and debugging, then uses MJX (mujoco-mjx, JAX backend) for batched GPU rollouts and parameter sweeps. Use when articulated lab mechanisms — prismatic stages, hinges, knobs, chambers — need accurate rigid-body dynamics, offscreen rendering, contact diagnostics, or thousands of batched GPU rollouts on a single A100 for sweeps, RL, or robustness tests.
version: 2.0.0
author: Orchestra Research
license: MIT
tags: [Physics Simulation, MuJoCo, MJCF, Batched Rollouts, GPU, JAX]
dependencies:
  - mujoco==3.8.0
  - mujoco-mjx==3.8.0
  - jax[cuda12]==0.10.0
  - numpy==2.4.4
  - mediapy==1.2.6
---

# simulating-mujoco-mjx

Category 27 default simulator. Load MJCF, run CPU MuJoCo to author and debug, then port to MJX for batched GPU rollouts. MuJoCo 3.8.0 released 2026-04-24 (Apache-2.0, maintained by Google DeepMind); mujoco-mjx 3.8.0 same date; jax 0.10.0 released 2026-04-16, requires Python >=3.11. Use Python 3.12 for Docker production (3.14 newly supported but ecosystem less stable).

**Package note**: install `mujoco-mjx`, import as `from mujoco import mjx`. The install package is separate but shares the `mujoco` namespace; do not confuse with a fork or split (see Issue #2119).

**Breaking change in 3.8.0**: `multiccd` is enabled by default; disable explicitly for golden-regression comparisons against earlier versions.

**Warp backend** (3.5.0+, stable): `pip install "mujoco-mjx[warp]==3.8.0"` installs `warp-lang==1.12.1`. Broader feature coverage on NVIDIA hardware, no autodiff. Not a drop-in replacement for JAX MJX.

## Quick start

### Install (single A100 80 GB, CUDA 12, headless EGL)

```bash
python -m pip install \
  "mujoco==3.8.0" \
  "mujoco-mjx==3.8.0" \
  "jax[cuda12]==0.10.0" \
  "numpy==2.4.4" \
  "mediapy==1.2.6"
```

Full explicit pin (production requirements.txt):

```
mujoco==3.8.0
mujoco-mjx==3.8.0
jax==0.10.0
jaxlib==0.10.0
jax-cuda12-pjrt==0.10.0
jax-cuda12-plugin[with-cuda]==0.10.0
numpy==2.4.4
mediapy==1.2.6
```

Note: `mujoco-mjx` does not hard-pin JAX/JAXLIB; pin them yourself in the lockfile to prevent silent drift.

### Dockerfile (EGL headless)

```dockerfile
FROM python:3.12-slim-bookworm

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    libegl1 libgl1 libglvnd0 libglx0 libgles2 libopengl0 \
    libglew2.2 libosmesa6 \
    ffmpeg git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Set BEFORE importing mujoco / PyOpenGL / dm_control
ENV MUJOCO_GL=egl
ENV PYOPENGL_PLATFORM=egl
ENV MUJOCO_EGL_DEVICE_ID=0
# Prevent LD_LIBRARY_PATH from overriding pip-managed CUDA libs
ENV LD_LIBRARY_PATH=

RUN python -m pip install --upgrade pip
RUN python -m pip install \
    "mujoco==3.8.0" \
    "mujoco-mjx==3.8.0" \
    "jax[cuda12]==0.10.0" \
    "numpy==2.4.4" \
    "mediapy==1.2.6"

CMD ["python", "-c", "import mujoco, jax; print(mujoco.mj_versionString()); print(jax.devices())"]
```

Note: MuJoCo 3.3.5 moved Linux wheels to `manylinux_2_28`; use Debian Bookworm or Ubuntu 22.04+ base images.

```bash
docker run --rm --gpus '"device=0"' \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics \
  -e CUDA_VISIBLE_DEVICES=0 \
  -e MUJOCO_GL=egl \
  -e PYOPENGL_PLATFORM=egl \
  -e MUJOCO_EGL_DEVICE_ID=0 \
  your-image:tag
```

### Load MJCF, step physics, render headless

```python
import os
# Must be set before importing mujoco or any OpenGL-backed code
os.environ.setdefault("MUJOCO_GL", "egl")
os.environ.setdefault("PYOPENGL_PLATFORM", "egl")
os.environ.setdefault("MUJOCO_EGL_DEVICE_ID", "0")

import csv
import mujoco
import numpy as np
import mediapy as media

JOINTS = ["x_slide", "y_slide", "z_slide", "focus_knob"]

model = mujoco.MjModel.from_xml_path("sem_stage.xml")
data  = mujoco.MjData(model)
print("MuJoCo version:", mujoco.mj_versionString())
print("nq, nv, nu:", model.nq, model.nv, model.nu)

act_ids = {
    name: mujoco.mj_name2id(model, mujoco.mjtObj.mjOBJ_ACTUATOR, name)
    for name in ["x_pos", "y_pos", "z_pos", "focus_pos"]
}

qpos_log, frames = [], []
with mujoco.Renderer(model, height=480, width=640) as renderer:
    for step in range(300):
        t = step * model.opt.timestep
        data.ctrl[act_ids["x_pos"]]    = 0.010 * np.sin(2.0 * np.pi * 0.5 * t)
        data.ctrl[act_ids["y_pos"]]    = 0.008 * np.cos(2.0 * np.pi * 0.5 * t)
        data.ctrl[act_ids["z_pos"]]    = 0.010
        data.ctrl[act_ids["focus_pos"]]= 0.3   * np.sin(2.0 * np.pi * 0.25 * t)
        mujoco.mj_step(model, data)
        qpos_log.append({
            "time": float(data.time),
            **{j: float(data.joint(j).qpos[0]) for j in JOINTS},
            "ncon": int(data.ncon),
        })
        if step % 10 == 0:
            renderer.update_scene(data, camera="overview")
            frames.append(renderer.render())

with open("qpos_log.csv", "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=qpos_log[0].keys())
    writer.writeheader(); writer.writerows(qpos_log)

media.write_video("sem_stage_hello.mp4", frames, fps=30)
# Note: struct fields are raw memory views — copy values when logging
for j in JOINTS:
    print(j, data.joint(j).qpos.copy())
```

## Common workflows

### 1. SEM stage prismatic motion (XYZ servo control + contact logging)

```
Task Progress:
- [ ] Step 1: Load sem_stage.xml; confirm nq=4, nv=4, nu=4
- [ ] Step 2: Set integrator="implicitfast" and timestep=0.001 in <option>
- [ ] Step 3: Drive x/y/z with position actuators; verify qpos tracks ctrlrange
- [ ] Step 4: Render under MUJOCO_GL=egl with mujoco.Renderer
- [ ] Step 5: Log qpos + ncon to CSV each step; check ncon==0 at nominal pose
- [ ] Step 6: Assert final qpos error < 1 mm on nominal trajectory
- [ ] Step 7: If unstable, lower timestep to 0.0005 and raise armature
```

Minimal MJCF for prismatic stage (radians, SI units):

```xml
<mujoco model="sem_stage_hello">
  <compiler angle="radian" autolimits="true"/>
  <option timestep="0.001" integrator="implicitfast" solver="Newton"
          iterations="50" tolerance="1e-10"/>
  <default>
    <joint damping="1e-3" armature="1e-5" limited="true"/>
    <geom contype="1" conaffinity="1" condim="3" friction="0.8 0.1 0.01"/>
  </default>
  <worldbody>
    <light pos="0 0 0.4"/>
    <camera name="overview" pos="0.12 -0.16 0.12" xyaxes="1 0 0 0 0.6 1"/>
    <geom name="wall_xp" type="box" pos="0.055 0 0.025" size="0.002 0.055 0.03"/>
    <geom name="wall_xn" type="box" pos="-0.055 0 0.025" size="0.002 0.055 0.03"/>
    <geom name="wall_yp" type="box" pos="0 0.055 0.025" size="0.055 0.002 0.03"/>
    <geom name="wall_yn" type="box" pos="0 -0.055 0.025" size="0.055 0.002 0.03"/>
    <body name="stage" pos="0 0 0.015">
      <joint name="x_slide" type="slide" axis="1 0 0" range="-0.04 0.04"
             damping="0.05" armature="1e-4"/>
      <joint name="y_slide" type="slide" axis="0 1 0" range="-0.04 0.04"
             damping="0.05" armature="1e-4"/>
      <joint name="z_slide" type="slide" axis="0 0 1" range="-0.005 0.025"
             damping="0.10" armature="1e-4"/>
      <geom name="sample_stage" type="box" size="0.018 0.018 0.004"
            mass="0.1" rgba="0.2 0.6 0.9 1"/>
    </body>
  </worldbody>
  <actuator>
    <position name="x_pos" joint="x_slide" kp="2000" kv="80"
              ctrlrange="-0.04 0.04" ctrllimited="true"
              forcerange="-50 50" forcelimited="true"/>
    <position name="y_pos" joint="y_slide" kp="2000" kv="80"
              ctrlrange="-0.04 0.04" ctrllimited="true"
              forcerange="-50 50" forcelimited="true"/>
    <position name="z_pos" joint="z_slide" kp="3000" kv="120"
              ctrlrange="-0.005 0.025" ctrllimited="true"
              forcerange="-80 80" forcelimited="true"/>
  </actuator>
</mujoco>
```

Key rules: `slide` = prismatic joint; `hinge` = revolute; use `implicitfast` or `implicit` when `kv > 0` (avoids numerical stiffness from high damping gains); add nonzero `armature` to improve stability. For collision-envelope checks only, set `data.qpos[...]` directly and call `mujoco.mj_forward(model, data)` instead of stepping.

### 2. Revolute focus knob with limited range and friction

```
Task Progress:
- [ ] Step 1: Add hinge joint with range in radians; confirm compiler angle="radian"
- [ ] Step 2: Set frictionloss > 0 for detent / dry-friction feel
- [ ] Step 3: Use position actuator with kp/kv tuned for knob inertia
- [ ] Step 4: Verify joint stays within [-pi/2, pi/2] under max commanded torque
- [ ] Step 5: Cross-check frictionloss value against physical torque-to-rotate spec
```

```xml
<joint name="focus_knob" type="hinge" axis="0 1 0"
       range="-1.5708 1.5708" limited="true"
       damping="0.02" armature="1e-5" frictionloss="0.001"/>

<position name="focus_pos" joint="focus_knob"
          kp="0.4" kv="0.04"
          ctrlrange="-1.5708 1.5708" ctrllimited="true"
          forcerange="-0.05 0.05" forcelimited="true"/>
```

`range` is in degrees or radians depending on `compiler angle`; `frictionloss` enables dry friction; `armature` models reflected inertia.

### 3. Batched MJX rollouts on A100 (1024 environments, parameter sweep)

```
Task Progress:
- [ ] Step 1: Compile XML in full MuJoCo; validate nq/nv/nu
- [ ] Step 2: Call mjx.put_model once outside the rollout loop
- [ ] Step 3: Build control batch with jnp.linspace / jnp.meshgrid
- [ ] Step 4: Allocate per-env data with jax.vmap over mjx.make_data
- [ ] Step 5: Write rollout body using jax.lax.fori_loop; wrap with jax.vmap + jax.jit
- [ ] Step 6: Call jax.block_until_ready on warmup run before timing
- [ ] Step 7: Re-validate top candidates in full MuJoCo for mesh-heavy contacts
```

```python
import os
os.environ.setdefault("XLA_PYTHON_CLIENT_PREALLOCATE", "false")

import jax
import jax.numpy as jnp
import mujoco
from mujoco import mjx

host_model = mujoco.MjModel.from_xml_path("sem_stage.xml")
mjx_model  = mjx.put_model(host_model)   # call once; cache for control-only sweeps
print("JAX devices:", jax.devices())

# Single-env step
data0 = mjx.make_data(mjx_model)
data0 = data0.replace(ctrl=jnp.zeros(host_model.nu))
data1 = jax.jit(mjx.step)(mjx_model, data0)
print("single qpos:", data1.qpos)

# Batched rollout: 1024 envs, varied x/y/z/focus commands
batch = 1024
ctrl_batch = jnp.stack([
    jnp.linspace(-0.02,  0.02, batch),   # x
    jnp.linspace( 0.02, -0.02, batch),   # y
    jnp.full((batch,), 0.010),            # z
    jnp.linspace(-0.5,   0.5, batch),    # focus
], axis=1)

@jax.vmap
def init_and_rollout(ctrl):
    d = mjx.make_data(mjx_model)
    d = d.replace(ctrl=ctrl)
    def body(_, d):
        return mjx.step(mjx_model, d)
    d = jax.lax.fori_loop(0, 200, body, d)
    return d.qpos

qpos_batch = jax.jit(init_and_rollout)(ctrl_batch)
jax.block_until_ready(qpos_batch)        # warmup
print("batched qpos shape:", qpos_batch.shape)   # (1024, nq)
```

MJX functions are not auto-JIT-compiled; always wrap with `jax.jit`. Use `jax.lax.scan` for time loops, `jax.vmap` for batch, static sizes throughout.

**`nconmax` deprecation**: deprecated since 3.3.7; use `naconmax`, `naccdmax`, and `njmax` for Warp contact allocation in `mjx.make_data`.

**`tree_replace` API**: `mjx.Model.tree_replace({"field": value})` builds batched model pytrees for parameter sweeps. Call it on the MJX model to create a per-env model batch, then set `in_axes` appropriately for `jax.vmap`.

**Collision check (contact report)**:

```python
import numpy as np

def contact_report(model, data,
                   geom_names=("sample_stage", "wall_xp", "wall_xn", "wall_yp", "wall_yn")):
    geom_ids = {
        mujoco.mj_name2id(model, mujoco.mjtObj.mjOBJ_GEOM, n)
        for n in geom_names
    }
    reports = []
    force6  = np.zeros(6)
    for i in range(data.ncon):          # only first data.ncon entries are active
        c = data.contact[i]
        if c.geom1 in geom_ids or c.geom2 in geom_ids:
            mujoco.mj_contactForce(model, data, i, force6)
            reports.append({
                "contact_id": i,
                "geom1": mujoco.mj_id2name(model, mujoco.mjtObj.mjOBJ_GEOM, c.geom1),
                "geom2": mujoco.mj_id2name(model, mujoco.mjtObj.mjOBJ_GEOM, c.geom2),
                "dist":  float(c.dist),         # negative = penetration
                "pos":   c.pos.copy(),
                "force_contact_frame": force6.copy(),
            })
    return reports
```

For geometric pre-checks before stepping, use `mujoco.mj_geomDistance(model, data, geom1_id, geom2_id, distmax, fromto)`. `mj_maxContact` (new in 3.8.0) returns the maximum possible contacts when colliding two geom types.

## When to use vs alternatives

**Use MuJoCo + MJX (this skill, Category 27 DEFAULT)** when:
- Lab mechanisms are articulated rigid bodies (prismatic stages, hinges, knobs, vacuum chambers)
- Accurate generalized-coordinate dynamics + offscreen rendering + contact diagnostics are needed in the same loop
- Thousands of batched GPU rollouts on one A100 are required (sweeps, RL, robustness)
- Mesh contact can be approximated by primitive proxies for MJX-JAX

**Use PyBullet** only for legacy robotics baselines where modern JAX/GPU batching is not required.

**Use Brax / Brax-MJX hybrid** when the priority is RL policy training and full MuJoCo rendering in the inner loop is unnecessary.

**Use Drake** when the task is controls/optimization-heavy or requires formal multibody systems analysis rather than stochastic simulation throughput.

**Use Isaac Sim / Isaac Lab** (see `validating-isaac-sim-lab`) when NVIDIA RTX sensors — cameras, LiDAR — or large synthetic robotics environments are required.

**Avoid Gazebo** for ML-scale parameter sweeps or 4096-way GPU rollouts (Gazebo is best for ROS/system integration).

## Common issues

**EGL context failures in Docker (MuJoCo #1629)**
Set `MUJOCO_GL=egl` and `PYOPENGL_PLATFORM=egl` before any mujoco/OpenGL import. Install `libegl1 libglvnd0 libgles2 libgl1`. Run with `--gpus all` and `NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics`. Use `mujoco.Renderer`, not `viewer`, in headless CI.

**`ImportError: cannot import name 'mjx' from 'mujoco'` (MuJoCo #2119)**
Caused by namespace-package collision: `mujoco-mjx` shares the `mujoco` namespace. Ensure both `mujoco` and `mujoco-mjx` are installed in the same environment and at matching versions. Under Bazel or unusual Python path setups, verify that `mujoco-mjx` is not shadowed by a bare `mujoco` install.

**Wrong GPU selected in multi-GPU Docker (MuJoCo #3245, PR #3246 open)**
EGL can land on the wrong physical GPU when combined with `CUDA_VISIBLE_DEVICES`. Set both `CUDA_VISIBLE_DEVICES=0` and `MUJOCO_EGL_DEVICE_ID=0`; verify with `nvidia-smi`. PR #3246 (maps EGL devices to CUDA IDs) was open as of April 2026 — check if it has merged before trusting multi-GPU EGL selection.

**MJX mesh-mesh contact gap (MuJoCo #2759, open)**
Mesh-primitive collisions work; mesh-mesh collisions can silently penetrate in MJX-JAX. Use primitive (box/cylinder/capsule) or convex-hull collision layers for MJX-JAX. Validate finalists in full MuJoCo. MJX-Warp improves mesh coverage but is not a differentiable drop-in.

**MJX-Warp undefined symbol on second jit call (MuJoCo #2865)**
`wp_cuda_graph_launch` errors appear with older MJX-Warp/JAX combinations (reproduced with mujoco 3.3.6 + jax[cuda12]==0.7.2). Pin `mujoco`, `mujoco-mjx`, `jax`, `jaxlib`, `jax-cuda12-plugin`, and `warp-lang` together; do not mix globally installed `warp-lang`. Rebuild container after version changes. Current safe pin: `mujoco-mjx[warp]==3.8.0` pulls `warp-lang==1.12.1`.

**JAX CUDA 12 plugin failures — avoid JAX 0.6.1 (JAX #28929, #29042)**
JAX 0.6.1 had cuSPARSE/cuSolver failures with CUDA 12. Do not pin 0.6.1. Use 0.10.0.

**`LD_LIBRARY_PATH` overrides pip CUDA wheels**
JAX docs explicitly warn that `LD_LIBRARY_PATH` can load the wrong CUDA libraries when using pip-managed wheels. Clear or unset it in Dockerfile (`ENV LD_LIBRARY_PATH=`).

**JAX GPU not detected ("falling back to cpu")**
Install `jax[cuda12]==0.10.0` in the final image layer. Assert `any(d.platform == "gpu" for d in jax.devices())` at startup. Do not `pip install` bare `jax` after CUDA-enabled jax.

## Advanced topics

- **Warp backend**: Install `mujoco-mjx[warp]==3.8.0` (pins `warp-lang==1.12.1`). Improves mesh contact coverage on NVIDIA hardware; officially stable since 3.5.0. Not differentiable. Multi-device graph-mode issues reported (MuJoCo #3191, H100 + Warp 1.11.1 + JAX 0.8.2).
- **Removed MJX helpers**: `mjx.get_params`, `mjx.ncon`, `mjx.count_constraints` were removed in the 3.2 era. Use fields on `mjx.Data` directly.
- **Removed: Madrona MJX** (3.4.0+): Madrona-based batch renderer was removed; migrate to MJX-Warp batch renderer.
- **`device` parameter on `mjx.make_data`**: Added in 3.2.3 for parity with `mjx.put_model` and `mjx.put_data`. Specify to pin to a particular device in multi-device setups.
- **`mjx.put_data` vs `mjx.make_data`**: `make_data` allocates and initializes fresh device data; use for resets and batched initial states. `put_data(m, d)` copies an existing host `MjData` to device; use when you prepared state via keyframe load, `qpos` assignment, or `mj_forward` warm-start.
- **Tuning rules**: start lab contacts at `timestep=0.0005`; raise to `0.001` after contact and actuator validation. Increase solver `iterations` (8-20 for lab contacts) before assuming geometry is wrong. Add armature `0.001-0.02` to prismatic/hinge joints; raise if high-gain servos chatter. MuJoCo default geom density is 1000 kg/m³ — specify `mass` explicitly for moving parts.
- **Full API surface (verified 3.8.0)**:

| API | Notes |
|-----|-------|
| `mujoco.MjModel.from_xml_path(path)` | Load model from XML |
| `mujoco.MjData(model)` | Allocate simulation state |
| `mujoco.mj_step(model, data)` | Step and integrate |
| `mujoco.mj_forward(model, data)` | Forward dynamics, no integration |
| `mujoco.Renderer(model, ...)` | Headless renderer |
| `from mujoco import mjx` | MJX import (package: mujoco-mjx) |
| `mjx.put_model(model, impl=...)` | Device placement; impl='jax' or 'warp' |
| `mjx.make_data(model_or_mjx_model)` | Allocate MJX data on device |
| `mjx.put_data(model, data)` | Host-to-device data transfer |
| `mjx.step(mjx_model, mjx_data)` | MJX step |
| `mjx.forward(mjx_model, mjx_data)` | MJX forward dynamics, no integration |
| `mjx.get_state / mjx.set_state` | State extraction/injection (parity with mj_getState/mj_setState) |

- See `references/issues.md` for full MuJoCo issue tracker watchlist with reproductions.

## Resources

- MuJoCo GitHub: https://github.com/google-deepmind/mujoco
- MuJoCo 3.8.0 release: https://github.com/google-deepmind/mujoco/releases/tag/3.8.0
- MuJoCo docs: https://mujoco.readthedocs.io
- MJX getting started: https://mujoco.readthedocs.io/en/stable/mjx.html
- MJX feature parity: https://mujoco.readthedocs.io/en/stable/mjx.html#feature-parity
- JAX install (CUDA 12): https://jax.readthedocs.io/en/latest/installation.html
- MuJoCo XML reference: https://mujoco.readthedocs.io/en/stable/XMLreference.html
- mujoco-mjx PyPI: https://pypi.org/project/mujoco-mjx/

### MuJoCo 3.x release timeline

| Version | Date | Notable |
|---------|------|---------|
| 3.8.0 | Apr 24, 2026 | Python 3.14, mj_maxContact, multiccd default |
| 3.7.0 | Apr 14, 2026 | dcmotor actuator, reflected damping/armature |
| 3.6.0 | Mar 10, 2026 | Sparse tendon Jacobian, flex SDF collisions |
| 3.5.0 | Feb 12, 2026 | MuJoCo Warp officially stable |
| 3.4.0 | Dec 5, 2025 | Sleeping islands, mj_extractState/mj_copyState; Madrona MJX removed |
| 3.3.7 | Oct 13, 2025 | naconmax introduced; nconmax/njmax defaults changed |
| 3.3.6 | Sep 15, 2025 | Constraint islanding default, mj_forward idempotency |
| 3.3.5 | Aug 8, 2025 | MJX Warp backend (beta); Linux wheels -> manylinux_2_28 |
| 3.3.4 | Jul 8, 2025 | Model-editing breaking changes |
| 3.3.3 | Jun 10, 2025 | Island refactor, mj_makeM |
| 3.3.2 | Apr 28, 2025 | MJX inverse dynamics |
| 3.3.1 | Apr 9, 2025 | mjs_attach API consolidation |
| 3.3.0 | Feb 26, 2025 | Fast deformable flex, native convex collision default |
