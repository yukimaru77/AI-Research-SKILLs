---
name: validating-sapien-articulations
description: Cross-simulator articulation sanity-check skill using SAPIEN 3.x (PhysX 5 GPU) to load PartNet-Mobility-style URDFs and verify joint axes, prismatic limits, door hinges, fixed cable harnesses, and collision groups. Use as a validation target against MuJoCo; SAPIEN is the second opinion, not the calibrated dynamics backend. Default cat-27 tool is MuJoCo; route here when PhysX 5 GPU semantics or PartNet-Mobility articulation cross-validation is required.
version: 2.0.0
author: Orchestra Research
license: MIT
tags: [Physics Simulation, SAPIEN, PartNet-Mobility, PhysX, Articulation, Validation, GPU, URDF]
dependencies: [sapien>=3.0.3]
---

# validating-sapien-articulations

SAPIEN 3.0.3 (released 2026-03-10) wraps NVIDIA PhysX 5 and is the native ecosystem for PartNet-Mobility articulated assets. It is best used as an articulation cross-validator alongside MuJoCo — not as the calibrated dynamics backend.

**License note**: GitHub repo LICENSE file (haosulab/SAPIEN) says Apache 2.0, copyright Hillbot Inc. 2025 / UCSD SU Lab 2020-2024. PyPI wheel metadata still shows MIT. Treat Apache 2.0 as the safer bound for redistribution; confirm with maintainers if wheel metadata matters for your use case. Bundled PhysX 5 GPU binaries: NVIDIA BSD-3 terms.

**Release timeline**: 3.0.0 (2025-07-25), 3.0.1 (2025-08-13), 3.0.2 (2025-12-18), 3.0.3 (2026-03-10). No 4.x announced as of 2026-05-05 — plan against 3.0.x. Not renamed, not forked/replaced; SAPIEN 3.0 was a major ECS/component-model overhaul relative to 2.x.

**Stack baseline**: sapien 3.0.3, Python 3.10–3.14 (cp310–cp314 wheels on PyPI; 3.10–3.12 safest), Ubuntu 22.04/24.04, NVIDIA GPU SM 6.0 / Pascal or newer, CUDA 12.x (no CUDA-specific wheel flavor; validate driver + Vulkan ICD per issues below).

## Quick start

```bash
python3.11 -m venv .venv-sapien && source .venv-sapien/bin/activate
python -m pip install --upgrade pip wheel setuptools
python -m pip install "sapien==3.0.3"
# Headless EGL: install libegl1 libxext6 in host/container
python -m sapien.example.offscreen   # smoke test
python -c "import sapien; print(sapien.__version__)"
```

**Docker (A100 / headless)**:

```dockerfile
FROM nvidia/cuda:12.4.1-runtime-ubuntu22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip libegl1 libxext6 \
 && rm -rf /var/lib/apt/lists/*

ENV NVIDIA_DRIVER_CAPABILITIES=graphics,utility,compute

RUN python3 -m pip install -U pip && python3 -m pip install sapien==3.0.3

CMD ["python3", "-m", "sapien.example.offscreen"]
```

```bash
docker run --gpus all -e NVIDIA_DRIVER_CAPABILITIES=graphics,utility,compute your-image
```

Modern entry point is `sapien.Scene()` — `sapien.Engine()` still exists as a deprecated compatibility shim; do not use it in new code.

```python
import sapien
scene = sapien.Scene()   # CPU PhysX + render system (default)
```

For GPU simulation construct the scene with `PhysxGpuSystem` before adding any actors:

```python
import sapien
physx = sapien.physx.PhysxGpuSystem()
scene = sapien.Scene([physx, sapien.render.RenderSystem()])
# add actors / articulations here
physx.gpu_init()
```

## Common workflows

### 1. Load URDF, enumerate joints, compare against canonical dict

```
Task Progress:
- [ ] Create sapien.Scene() (CPU PhysX default is fine for enumeration)
- [ ] loader = scene.create_urdf_loader(); loader.fix_root_link = True
- [ ] robot = loader.load(urdf_path, package_dir=urdf_dir)
- [ ] Verify type(robot) is sapien.physx.PhysxArticulation; fail loudly otherwise
- [ ] Iterate robot.get_joints() — record name, type, axis, limits
- [ ] Iterate robot.get_active_joints() — verify DOF ordering for control
- [ ] robot.get_qlimits() → float32 array shape (dof, 2)
- [ ] Diff joint types and axes against canonical dict; write sapien_articulation_report.json
```

```python
import json, numpy as np, sapien

scene = sapien.Scene()
loader = scene.create_urdf_loader()
loader.fix_root_link = True
robot = loader.load(
    "/datasets/partnet_mobility/12345/mobility.urdf",
    package_dir="/datasets/partnet_mobility/12345",
)

assert isinstance(robot, sapien.physx.PhysxArticulation), \
    "URDF loaded as actor, not articulation — check mesh paths / zero-link pitfall"

joints  = robot.get_joints()
qlimits = robot.get_qlimits()      # shape (dof, 2), dtype float32
qpos    = np.zeros(robot.dof, dtype=np.float32)
robot.set_qpos(qpos)

canonical = {"stage_x": "prismatic", "stage_y": "prismatic",
             "magnification_knob": "revolute"}
seen  = {j.get_name(): str(j.type).lower() for j in joints}
diffs = [{"joint": k, "expected": v, "got": seen.get(k, "MISSING")}
         for k, v in canonical.items() if v not in seen.get(k, "")]

report = {
    "sapien_version": sapien.__version__,
    "n_dof": robot.dof,
    "joints": [{"name": j.get_name(), "type": str(j.type),
                "limits": j.get_limits().tolist() if j.get_dof() > 0 else None}
               for j in joints],
    "diffs": diffs,
}
with open("sapien_articulation_report.json", "w") as f:
    json.dump(report, f, indent=2)
```

Note: SAPIEN maps URDF `continuous` joints to `revolute` internally. Treat `revolute` with `[-inf, inf]` limits as equivalent to `continuous` in diff logic.

### 2. Drive each DOF and cross-validate vs MuJoCo

```
Task Progress:
- [ ] For each DOF d: set qpos to lower limit, step 50 frames, record actual qpos[d]
- [ ] For each DOF d: set qpos to upper limit, step 50 frames, record actual qpos[d]
- [ ] Compute overshoot = max(0, |actual| - max(|lo|, |hi|)) per DOF
- [ ] Run identical-control 1-second rollout in MuJoCo (simulating-mujoco-mjx skill)
- [ ] Diff per-joint qpos SAPIEN vs MuJoCo; tolerable RMS < 5e-3
- [ ] Persistent RMS > 5e-3 → file bug in authoring-urdf-mjcf-usd, not a SAPIEN fix
```

```python
qlimits = robot.get_qlimits()   # (dof, 2), float32
results = []
for d in range(robot.dof):
    for lo_hi, label in [(qlimits[d, 0], "lower"), (qlimits[d, 1], "upper")]:
        qpos = np.zeros(robot.dof, dtype=np.float32)
        qpos[d] = lo_hi
        robot.set_qpos(qpos)
        for _ in range(50):
            scene.step()
        actual    = robot.get_qpos()[d]
        limit_mag = max(abs(qlimits[d, 0]), abs(qlimits[d, 1]))
        overshoot = max(0.0, abs(actual) - limit_mag)
        results.append({"dof": d, "label": label,
                        "target": float(lo_hi), "actual": float(actual),
                        "overshoot": float(overshoot)})
```

SAPIEN is the second opinion. Corrections must flow back into `authoring-urdf-mjcf-usd` so the asset is consistent across all simulators.

### 3. GPU collision-group verification (cable harness stays fixed)

```
Task Progress:
- [ ] Construct scene with PhysxGpuSystem (before any actor/loader creation)
- [ ] Call physx.gpu_init() after all actors are loaded
- [ ] Load articulation; cable_harness link must use fixed joint in URDF
- [ ] Add a free-floating sample actor onto the stage
- [ ] Step N frames; assert cable_harness pose displacement < 1e-5 m
- [ ] scene.get_contacts() returns list[PhysxContact]; enumerate active pairs each step
- [ ] Flag any contact between sample and cable_harness as unexpected
- [ ] Write collision_group_report.json
```

```python
physx = sapien.physx.PhysxGpuSystem()
scene = sapien.Scene([physx, sapien.render.RenderSystem()])

loader = scene.create_urdf_loader()
loader.fix_root_link = True
robot  = loader.load("/path/to/mobility.urdf", package_dir="/path/to/")
physx.gpu_init()

baseline_pose = robot.get_root_pose()
for _ in range(200):
    scene.step()
displacement = np.linalg.norm(
    np.array(robot.get_root_pose().p) - np.array(baseline_pose.p))
assert displacement < 1e-5, f"Cable harness drifted {displacement:.3e} m"

contacts = scene.get_contacts()   # list[PhysxContact] for CPU; use GPU tensor APIs for batched
```

## When to use vs alternatives

| Need | Use |
|---|---|
| Calibrated rigid-body dynamics on A100 | `simulating-mujoco-mjx` (cat-27 default) |
| PartNet-Mobility articulation cross-validation | **this skill** |
| PhysX 5 GPU as second opinion on joint axes / limits | **this skill** |
| RTX-rendered USD validation | `validating-isaac-sim-lab` |
| Multiphysics / MPM sandboxing | `prototyping-genesis-physics` |
| Physical parameter estimation | `calibrating-sysid-rl-hooks` |

SAPIEN does not replace MuJoCo as the calibrated dynamics backend. It does not handle USD/Isaac workflows and does not estimate physical parameters.

**MuJoCo** (Google DeepMind, Apache 2.0, `pip install mujoco`): stable, lightweight, best for control/dynamics. Use when you don't need PhysX or PartNet-Mobility assets.

**Isaac Sim 5.0.0** (NVIDIA, Aug 2025, Apache 2.0 + additional caveats): Omniverse/OpenUSD/RTX, ROS integration, multi-sensor synthetic data. Heavy; use for full digital-twin pipelines.

**Genesis v0.3.0** (Aug 2025, Apache 2.0, `pip install genesis-world`): universal physics + photorealistic renderer, Python >=3.10,<3.14. Research-oriented challenger; lighter than Isaac Sim.

## Common issues

**`sapien.Engine()` is deprecated** — use `sapien.Scene()` directly. Engine still works as a shim but emits deprecation warnings and `Engine.create_scene()` just returns a `Scene`.

**GPU init ordering (issue #157)** — `GPU PhysX can only be enabled once before any other PhysX code`. Construct `PhysxGpuSystem` before any scene/actor/loader creation. There is no post-hoc `set_gpu_simulation_enabled()` toggle in 3.0.x stable; that was a beta/older API. Validate with `sapien.physx.is_gpu_enabled()`.

**EGL / headless Vulkan failures (issues #256, #250, #269, #280, #290)** — SAPIEN needs `libegl1` and `libxext6`. On H100 with CUDA 12.8 / driver 570 offscreen Vulkan device creation has failed even with JSON vendor files present; issue #280 (SAPIEN 3.0.1, RTX 3090, VNC/xvfb, CUDA 11.8) reports `vk::PhysicalDevice::getSurfacePresentModesKHR: ErrorUnknown`; issue #290 (SAPIEN 3.0.2/3.0.3, H100, PyTorch cu121) reports `get_picture_cuda("Color")` hangs. Check inside the container:

```bash
ls /usr/share/glvnd/egl_vendor.d
ls /usr/share/vulkan/icd.d
echo "$VK_ICD_FILENAMES"
vulkaninfo --summary   # install vulkan-tools if missing
python -m sapien.example.offscreen
```

Workaround for Singularity: bind-mount Vulkan/EGL vendor JSON files. For VNC/xvfb setups, try `VK_ICD_FILENAMES` to force the correct ICD.

**URDF mesh path resolution / zero-link articulation** — Pass `package_dir` to the `load()` call, not as `loader.package_dir`, because internal parsing overwrites the attribute from the function argument. SAPIEN strips `package://` then resolves against `package_dir`. If the root has no child joints, the loader emits an actor, not an articulation — use `load_multiple()` to diagnose:

```python
arts, actors = loader.load_multiple(urdf_path, package_dir=urdf_dir)
assert len(arts) > 0, "URDF parsed as actor(s) only — check mesh paths"
```

**Mimic joints not enforced (issue #236)** — Ubuntu 24.04 / Python 3.11 / SAPIEN 3.0.0. Mimic joint semantics are not automatically applied during simulation; implement constraint logic manually or upgrade to 3.0.3.

**GPU memory accumulation (issues #261, #275)** — With very large parallel env counts, GPU memory grows over long runs. PhysX mesh cache accumulates for changing filenames (#275); no public API to clear it in 3.0.3. Workaround: restart the process between long sweeps or limit unique mesh filenames.

**PhysX 5 actuator stiffness** — PhysX 5 can oscillate with servo-style `kp` values that MuJoCo handles without issue. Start at half the MuJoCo gain and validate with the drive-sweep workflow above.

## Advanced topics

**`get_active_joints()` vs `get_joints()`** — `get_joints()` returns all joints including fixed. `get_active_joints()` returns non-zero-DOF (actuated) joints and is the correct list for PID/drive setup. Generalized force ordering matches `get_joints()` order, not `get_active_joints()` order — do not assume they are interchangeable for force vectors.

```python
active_joints = robot.get_active_joints()
for joint in active_joints:
    joint.set_drive_property(stiffness=1000, damping=100)
robot.set_drive_target(target_qpos)   # float32 array, length = robot.dof
```

**`get_qlimits()` shape** — returns `np.float32` array of shape `(robot.dof, 2)`. Column 0 is lower limit, column 1 is upper limit.

**`set_qpos()` coercion** — pybind accepts Python lists but internally expects `float32`. Always coerce: `robot.set_qpos(np.array(q, dtype=np.float32))`.

**`scene.get_contacts()`** — returns `list[PhysxContact]` for CPU PhysX. Each `PhysxContact` has `bodies`, `shapes`, and `points`; each `PhysxContactPoint` has `impulse`, `normal`, `position`, `separation`. For GPU batched simulation use `PhysxGpuSystem` tensor-style contact APIs instead.

**ECS model (SAPIEN 3.x)** — SAPIEN 3.0 introduced an Entity/Component architecture. `sapien.Actor` from 2.x is now `sapien.Entity`; functionality moved into components. `ActorBuilder`/`ArticulationBuilder` are largely unchanged at the builder level but the resulting objects follow the ECS model. Do not carry SAPIEN 2.x `Actor` patterns into 3.x code.

**URDF 2.x → 3.x migration** — `load_file_as_articulation_builder` exists in 3.0.3 master but was missing in earlier betas (issue #216). Scene constructor and config API differ from 2.x; do not carry 2.x patterns forward.

**License clarification** — GitHub repo LICENSE (haosulab/SAPIEN): Apache License 2.0, copyright Hillbot Inc. 2025 and UCSD SU Lab 2020-2024. PyPI wheel metadata: MIT (stale). For redistribution, treat Apache 2.0 as the operative license and inspect bundled third-party notices. Bundled PhysX 5 GPU binaries: NVIDIA BSD-3 terms.

## Resources

- SAPIEN GitHub: https://github.com/haosulab/SAPIEN
- SAPIEN PyPI: https://pypi.org/project/sapien/
- SAPIEN docs: https://sapien-sim.github.io/docs/
- PartNet-Mobility: https://sapien.ucsd.edu/browse
- PhysX 5 SDK: https://github.com/NVIDIA-Omniverse/PhysX
- Real issues referenced: #157 (GPU enable ordering), #171 (camera OOM), #216 (2.x→3.x migration), #236 (mimic joints), #250 (H100 Vulkan), #256 (EGL missing), #261 (GPU memory growth), #269 (Vulkan ICD), #275 (mesh cache), #280 (Vulkan ErrorUnknown VNC/xvfb), #290 (CUDA interop hang H100)
