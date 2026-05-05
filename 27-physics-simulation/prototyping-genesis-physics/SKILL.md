---
name: prototyping-genesis-physics
description: Research sandbox skill using Genesis (genesis-world) for fast Pythonic GPU physics experiments, multiphysics prototyping (MPM, granular, fluid, deformable), and differentiable physics exploration. Differentiable MPM and Tool Solver paths are stable; differentiable rigid/articulated body simulation is partially shipped but not production-stable. Use when GPU-first experimentation, multiphysics breadth, or Pythonic single-file scripting matters more than rigid-body simulation accuracy. Default rigid-body truth in category 27 remains MuJoCo.
version: 2.0.0
author: Orchestra Research
license: MIT
tags: [Physics Simulation, Genesis, GPU, Differentiable Physics, MPM, FEM, Multiphysics, Sandbox]
dependencies: [genesis-world>=0.4.6, torch>=2.8]
---

# prototyping-genesis-physics

Genesis (genesis-world, Apache-2.0) is a GPU-first, Pythonic physics simulator covering rigid bodies, articulation, MPM, SPH, FEM, and the Tool Solver. As of 2026-05-05 the latest release is **0.4.6** (2026-04-11). The default rigid-body and articulated-body simulator for category 27 remains MuJoCo / MJX; use Genesis as an exploratory sandbox and for multiphysics paths that MuJoCo cannot cover.

## Quick start

```bash
python3.11 -m venv .venv-genesis
source .venv-genesis/bin/activate
pip install --upgrade pip wheel setuptools

# PyTorch must be installed first with a CUDA wheel; Genesis does NOT pull it automatically.
# Genesis 0.4.x requires torch>=2.8. CUDA 12.6 wheel shown below; match to host driver.
pip install torch --index-url https://download.pytorch.org/whl/cu126
pip install genesis-world==0.4.6

python - <<'EOF'
import torch, genesis as gs
assert torch.cuda.is_available(), "CUDA torch required"
gs.init(backend=gs.gpu, precision="32")
print("Genesis", gs.__version__, "ready")
EOF
```

For source/main:
```bash
pip install git+https://github.com/Genesis-Embodied-AI/Genesis.git
```

Python requirement: `>=3.10,<3.14`. JAX is **not** a Genesis core dependency.

## Common workflows

### 1. Headless hello-world: MJCF / URDF import + GPU rollout

```
Task Progress
- [ ] gs.init(backend=gs.gpu) once at module top; assert torch.cuda.is_available() first
- [ ] Construct gs.Scene with show_viewer=False and a Rasterizer renderer
- [ ] Add plane and robot entity via gs.morphs.MJCF or gs.morphs.URDF(fixed=True)
- [ ] Add headless camera with GUI=False
- [ ] scene.build() — first call compiles JIT kernels (5-15 s normal)
- [ ] Run scene.step() loop (first step triggers additional JIT; exclude from timing)
- [ ] Extract state via entity.get_dofs_position(); save render to PNG
```

```python
import numpy as np
from PIL import Image
import genesis as gs

gs.init(backend=gs.gpu, precision="32")

scene = gs.Scene(
    sim_options=gs.options.SimOptions(dt=1e-3),
    show_viewer=False,
    renderer=gs.renderers.Rasterizer(),
)

plane  = scene.add_entity(gs.morphs.Plane())
robot  = scene.add_entity(
    gs.morphs.MJCF(file="xml/franka_emika_panda/panda.xml")
    # or: gs.morphs.URDF(file="urdf/panda.urdf", fixed=True)
)
cam = scene.add_camera(res=(640, 480), pos=(3.5, 0.0, 2.5),
                       lookat=(0.0, 0.0, 0.5), fov=30, GUI=False)

scene.build()

for _ in range(120):
    scene.step()

out = cam.render(rgb=True)
rgb = out[0] if isinstance(out, tuple) else out
if rgb.dtype.kind == "f":
    rgb = np.clip(rgb * 255, 0, 255).astype(np.uint8)
Image.fromarray(rgb).save("genesis_hello.png")
print("qpos:", robot.get_dofs_position().cpu().numpy())
```

### 2. MPM granular prototype (differentiable path)

```
Task Progress
- [ ] Use small dt (1e-4 to 5e-4) for MPM stability; NaN detection is enabled by default
- [ ] Add rigid stage as fixed entity from MJCF/URDF
- [ ] Add MPM Sand material entity above stage
- [ ] Run scene.step() forward pass; observe particle settling
- [ ] Compute scalar loss on sand.get_particles_pos() (MPM tensor is requires_grad-capable)
- [ ] Call loss.backward() — MPM differentiable path is stable
- [ ] Log centroid trajectory; compare with physical expectation
```

```python
import torch, genesis as gs

gs.init(backend=gs.gpu)

scene = gs.Scene(sim_options=gs.options.SimOptions(dt=2e-4), show_viewer=False)
stage = scene.add_entity(gs.morphs.MJCF(file="stage.xml"))
sand  = scene.add_entity(
    gs.morphs.Box(pos=(0, 0, 0.05), size=(0.04, 0.04, 0.04)),
    material=gs.materials.MPM.Sand(),
)
scene.build()

for _ in range(3000):
    scene.step()

particles = sand.get_particles_pos()          # torch tensor, differentiable
loss = particles.mean(dim=0).pow(2).sum()
loss.backward()                               # MPM grad path — stable in 0.4.x
print("grad norm:", sand.get_particles_pos().grad.norm().item() if particles.requires_grad else "detached")
```

If `NaN detected in MPM states` is raised, halve `dt` or reduce particle density. See `references/issues.md` for issue #1949 / #2239.

### 3. A100 Docker headless parameter sweep

```
Task Progress
- [ ] Build and launch container with --gpus '"device=0"', --ipc=host, --shm-size=16g
- [ ] Set NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics (needed even for headless Rasterizer)
- [ ] Confirm PyTorch 2.8+ CUDA wheel inside container; genesis-world 0.4.6
- [ ] gs.init(backend=gs.gpu); assert torch.cuda.is_available()
- [ ] Build a single batched scene rather than N separate processes
- [ ] Vary friction/mass/pose across batch dimensions; time post-warmup steps/sec
- [ ] Exit cleanly (Ctrl+C or sys.exit) to preserve kernel JIT cache
- [ ] Validate physics results against MuJoCo MJX baseline before promoting
```

```bash
docker run --rm -it \
  --gpus '"device=0"' \
  --ipc=host \
  --shm-size=16g \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics \
  -v "$PWD":/workspace \
  genesis:latest \
  python /workspace/sweep.py
```

A100-specific caveats: issue #2133 reports an nvJitLink crash on A100 80GB PCIe during batch rendering; issue #414 shows FPS collapse under concurrent recording. Prefer pure-physics paths without live rendering in Docker on A100.

## When to use vs alternatives

| Concern | Genesis | MuJoCo + MJX |
|---|---|---|
| Source of truth, rigid/articulated lab equipment | **NO** | Yes |
| MPM / granular / fluid prototypes | Yes | No |
| Differentiable MPM or Tool Solver | Yes | No |
| Differentiable rigid contact | **NOT STABLE** (partial, see below) | Use MJX + finite-diff sysid |
| Large-scale rigid parameter sweeps | Maybe | Yes (preferred) |
| Pythonic single-file GPU experiment | Yes | Yes |
| RTX / USD camera fidelity | No | No (use Isaac) |
| Headless server batch jobs | Yes | Yes |

**NOT-rigid-body-truth boundary**: Genesis docs state differentiable rigid/articulated simulation is on the roadmap; v0.3.8 release notes added partial rigid forward dynamics (PRs #1808, #2063, #2068), but issue #2150 (Dec 2025) reports backward through Franka FK hanging or core-dumping, and issue #2059 reports kernel failure with `requires_grad=True` and 2+ rigid bodies. Do not use Genesis as the authoritative rigid simulator or for rigid-body sysid until upstream marks the backward path stable. Defer to `simulating-mujoco-mjx` for rigid-body truth, `validating-sapien-articulations` for PartNet-Mobility sanity checks, and `validating-isaac-sim-lab` for RTX cameras.

## Common issues

**CUDA / PyTorch wheel mismatch** — Genesis does not declare PyTorch as a pip dependency; you must install `torch>=2.8` with the correct CUDA wheel index before `genesis-world`. A CPU-only torch will silently give `gs.cpu` backend even with `backend=gs.gpu`. Always assert:
```python
import torch; assert torch.cuda.is_available(), "Need CUDA torch"
```

**Long JIT warmup** — `scene.build()` and the first `scene.step()` compile kernels (5-15 s on first run). Issue #487 shows the "Compiling simulation kernels" message appears even on cache hits; real indicator is whether it completes fast on the second run. Always exclude the first step from throughput measurements. Exit cleanly to preserve cache; hard-kill (SIGKILL) discards the cache.

**Breaking change: GsTaichi → Quadrants** — v0.4.0 (PRs #2399, #2409) replaced the Taichi/GsTaichi compiler backend with Quadrants. Older documentation, cache env-var advice, and offline cache notes referencing Taichi are stale.

**torch 2.8 minimum** — PR #2034 moved the minimum to `torch>=2.8`. Docker images based on PyTorch 2.6 CUDA 12.4 are incompatible with Genesis 0.4.x. When upgrading an image, switch to a `cu128` or `cu126` PyTorch wheel.

**libigl 2.6.0 breakage** — Issue #1156: `ValueError: too many values to unpack` after libigl 2.6.0 changed its API. Pin `libigl==2.5.1` if you hit this error.

**WSL2 CUDA discovery** — Taichi/Quadrants may not find `libcuda.so` even when `torch.cuda.is_available()` returns `True`. Fix: add `/usr/lib/wsl/lib` to `LD_LIBRARY_PATH`.

**MPM NaN** — Raised as `NaN detected in MPM states. Try reducing the time step size...` (introduced PR #1949). Halve `dt`; reduce particle density; or set the NaN handler to warn-only for RL rollouts (issue #2239 requests this configurability).

**URDF / MJCF import edge cases** — Genesis morph importers silently drop MJCF-only features (contact pairs, equality constraints, tendons). Run a side-by-side MuJoCo rollout on every new asset before trusting Genesis dynamics.

**Differentiable rigid backward** — Do not call `loss.backward()` through articulated rigid contact in production code. Guard with:
```python
if needs_rigid_grad:
    raise NotImplementedError("Rigid backward not yet stable in Genesis; use MJX finite-diff")
```

## Advanced topics

**Sandbox-only contract** — Genesis results are exploratory until cross-validated. Before promoting any result: (1) re-run in `simulating-mujoco-mjx` with matched `dt` and controls; (2) compute per-joint RMS divergence (rigid: 1e-3 m/rad; MPM: 5% centroid drift over 1 s); (3) record `gs.__version__`, GPU model, driver, seed alongside the divergence numbers.

**Multiphysics scenarios** — Genesis pays off for: powder dosing on a tilting stage (MPM Sand), optical immersion fluid splash on a mount (MPM fluid), deformable gasket on a vacuum door (MPM + rigid), cable harness strain limits (deformable). In each case Genesis output is a hypothesis; canonical threshold/alarm values belong to MuJoCo calibrated paths or physical lab measurements.

**Reproducibility** — Pin `genesis-world==0.4.6` and the matching CUDA torch wheel. Set both `torch.manual_seed(seed)` and `gs.set_random_seed(seed)` for reproducible MPM initial states. Prefer a single batched scene over N independent processes for GPU efficiency.

**When differentiable rigid stabilizes** — Once upstream announces a stable rigid/articulated backward pass, this skill should expand to gradient-based sysid for joint friction and contact parameters. Track the Genesis changelog before enabling; subtle gradient errors can pass smoke tests but produce biased calibrations. See also `calibrating-sysid-rl-hooks`.

**API quick reference**:
```python
import genesis as gs
gs.init(backend=gs.gpu)                         # one-time process init
scene = gs.Scene(sim_options=gs.options.SimOptions(dt=1e-3), show_viewer=False)
ent   = scene.add_entity(gs.morphs.URDF(file=..., fixed=True))
mjcf  = scene.add_entity(gs.morphs.MJCF(file=...))
sand  = scene.add_entity(gs.morphs.Box(...), material=gs.materials.MPM.Sand())
scene.build()                                   # JIT compile
scene.step()                                    # advance one dt
ent.set_dofs_position(qpos)
qpos  = ent.get_dofs_position()                 # rigid/articulated DOF state
parts = sand.get_particles_pos()                # MPM particle positions (torch tensor)
# SPH: entity.get_particles_pos() also documented for SPH entities
```

**Further reading**: See `references/issues.md` for annotated upstream GitHub issues and a Genesis-vs-MuJoCo divergence audit script.

## Resources

- GitHub: https://github.com/Genesis-Embodied-AI/Genesis
- Docs: https://genesis-world.readthedocs.io
- PyPI: https://pypi.org/project/genesis-world/
- Differentiable simulation: https://genesis-world.readthedocs.io/en/latest/user_guide/differentiable_simulation.html
- PyTorch CUDA 12.6 wheels: https://download.pytorch.org/whl/cu126
- Releases: v0.4.6 (2026-04-11), v0.4.5 (2026-04-05), v0.4.4 (2026-03-29); license Apache-2.0
