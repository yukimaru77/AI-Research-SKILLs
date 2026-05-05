# Genesis Upstream Issues Reference

Sourced from Genesis-Embodied-AI/Genesis GitHub and PyPI as of 2026-05-05 (genesis-world 0.4.6).

---

## Differentiable rigid / articulated body stability

| Issue / PR | Summary |
|---|---|
| PR #1808, #2063, #2068 | v0.3.8: Differentiable forward dynamics for rigid-body sim shipped (partial). |
| PR #1733 | Differentiable constraint solver added. |
| PR #1701 | Differentiable contact detection added (WIP at time of merge). |
| Issue #2059 | Kernel compilation failure with `requires_grad=True` and 2+ rigid bodies. Workaround: use single-body tests until upstream fixes the multi-body grad path. |
| Issue #2150 | Backward through Franka forward kinematics hangs or core-dumps (opened 2025-12-27). Status: open / unresolved as of 2026-05-05. Do not use rigid backward in production. |

**Guidance**: Treat rigid/articulated differentiability as experimental. Guard all `loss.backward()` calls through articulated solvers with `NotImplementedError` until upstream marks the path stable.

---

## MPM convergence and NaN handling

| Issue / PR | Summary |
|---|---|
| PR #1949 | Fixed silent process-killing when MPM produces NaN. Now raises: `NaN detected in MPM states. Try reducing the time step size or adjusting simulation parameters.` |
| Issue #2239 | Request to make NaN handling configurable (warn-only) for RL rollouts rather than hard-erroring the whole process. Open as of 2026-05-05. |

**Guidance**: When MPM raises NaN, first halve `dt`; then reduce particle density or domain size. For RL rollout wrappers, monitor issue #2239 for a configurable handler.

---

## Kernel compile cache

| Issue / PR | Summary |
|---|---|
| Issue #487 | Genesis prints "Compiling simulation kernels" even on cache hits; users confused. Cached run is faster despite the message — time the second run to verify. |
| Issue #1174 | Multiprocess compilation request; discusses Taichi offline cache limitations (pre-0.4.0). |
| PR #1868, #1873, #1875, #1880 | v0.3.5: Dynamic-array / fast-cache support added. |
| PR #1885 | GsTaichi fast cache enabled by default (superseded by Quadrants migration in v0.4.0). |
| PR #2399, #2409 | v0.4.0: Breaking migration from GsTaichi to Quadrants compiler backend. All Taichi cache env-var advice is stale. |

**Guidance**: Exit cleanly (Ctrl+C or `sys.exit`) to persist the kernel cache. Hard-kill (SIGKILL / OOM killer) discards it. The "Compiling" log line is not a reliable cache-miss indicator; measure wall-clock time on the second run.

---

## A100 vs H100 performance and rendering

| Issue / PR | Summary |
|---|---|
| Issue #1740 | CUDA/memory failure scaling from 10 K to 20 K parallel envs; maintainer comment notes the script worked with 40 K envs on H100, implying A100 hits memory limits earlier. |
| Issue #2133 | Batch rendering crash on A100 80GB PCIe with CUDA / nvJitLink error. Upgrade to 0.4.6 (CUDA crash fixes in release notes). |
| Issue #414 | A100 80GB PCIe FPS collapse during concurrent rendering + recording. Appears to be renderer / toolchain bottleneck rather than compute. Avoid live rendering paths inside Docker on A100; use headless physics-only and save frames programmatically. |

**Guidance**: No formal A100-vs-H100 Genesis benchmark exists publicly. A100 reports cluster around renderer/JIT bottlenecks, not raw physics throughput. For pure physics RL workloads, A100 performance is generally adequate; avoid concurrent batch rendering.

---

## Install / dependency pitfalls

| Area | Detail |
|---|---|
| `torch>=2.8` minimum | PR #2034: `genesis/__init__.py` warns if `torch.__version__ < 2.8.0`. Images based on PyTorch 2.6 (CUDA 12.4) are incompatible with Genesis 0.4.x. |
| libigl 2.6.0 | Issue #1156: `ValueError: too many values to unpack`. Pin `libigl==2.5.1` as workaround. |
| WSL2 CUDA discovery | Quadrants may not find `libcuda.so` even when PyTorch finds CUDA. Fix: `export LD_LIBRARY_PATH=/usr/lib/wsl/lib:$LD_LIBRARY_PATH`. |
| Docker EGL context | Issue #2673: EGL context release bug in long-running render jobs, fixed in v0.4.6. |

---

## Genesis-vs-MuJoCo divergence audit script

```python
"""
Minimal cross-simulator divergence audit.
Run identical control inputs through Genesis and MuJoCo; compute RMS qpos divergence.
Pass threshold: rigid-articulated <= 1e-3 m or rad RMS over 1 s.
"""
import numpy as np
import mujoco
import genesis as gs

# --- Genesis rollout ---
gs.init(backend=gs.gpu)
scene = gs.Scene(sim_options=gs.options.SimOptions(dt=1e-3), show_viewer=False)
ent = scene.add_entity(gs.morphs.URDF(file="robot.urdf", fixed=True))
scene.build()
gs_qpos = []
for _ in range(1000):
    scene.step()
    gs_qpos.append(ent.get_dofs_position().cpu().numpy())
gs_qpos = np.stack(gs_qpos)

# --- MuJoCo rollout ---
model = mujoco.MjModel.from_xml_path("robot.urdf")  # or .xml
data  = mujoco.MjData(model)
mj_qpos = []
for _ in range(1000):
    mujoco.mj_step(model, data)
    mj_qpos.append(data.qpos.copy())
mj_qpos = np.stack(mj_qpos)

# --- Compare ---
rms = np.sqrt(np.mean((gs_qpos - mj_qpos[:, :gs_qpos.shape[1]]) ** 2))
print(f"RMS divergence: {rms:.6f}  ({'PASS' if rms <= 1e-3 else 'FAIL - do not promote Genesis result'})")
```

Adapt `file=` paths and DOF slicing for your asset. For MPM, replace the comparison with centroid displacement over 1 s (threshold: 5% of domain size).
