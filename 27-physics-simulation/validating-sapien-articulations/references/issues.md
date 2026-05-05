# SAPIEN 3.x — Issue Watchlist, GPU Determinism Notes, Diff Schema

Reference date: 2026-05-05. Source: haosulab/SAPIEN GitHub issues, PyPI 3.0.3.

## URDF loader edge-cases

| Symptom | Root cause | Fix |
|---|---|---|
| `load()` returns actor, not articulation | Root link has no child joints (zero-link articulation) | Use `load_multiple()` to diagnose; fix the URDF root |
| Mesh not found / silent zero geometry | `package://` prefix not stripped or `package_dir` wrong | Pass `package_dir=urdf_dir` to `load()`, not as `loader.package_dir` attribute |
| Mimic joints ignored (issue #236) | SAPIEN 3.0.x does not auto-enforce mimic constraints | Implement constraint in simulation loop; confirmed on Ubuntu 24.04 / Python 3.11 |
| `load()` throws on multiple articulations | URDF contains multiple root chains | Use `load_multiple()` → returns `(list[PhysxArticulation], list[Actor])` |
| `continuous` joint shows no limits | Expected — SAPIEN maps URDF `continuous` to `revolute` with `[-inf, inf]` | Treat as equivalent in diff logic; do not flag as mismatch |
| Mesh cache OOM over long runs (issue #275) | PhysX caches meshes by filename; unique names accumulate memory | Limit unique filenames; restart process between sweeps; no public cache-clear API in 3.0.3 |
| Migration errors from SAPIEN 2.x (issue #216) | `load_file_as_articulation_builder` missing in older 3.x betas | Use 3.0.3; API stabilized in current master |

## GPU simulation — known issues and determinism notes

### Issue index (haosulab/SAPIEN)

| Issue | Opened | Area | Summary | Confidence |
|---|---|---|---|---|
| #157 | 2024-05-10 | GPU enable ordering | `GPU PhysX can only be enabled once before any other PhysX code` | High |
| #171 | 2024-09-07 | Renderer OOM | `camera.take_picture()` stall; `ErrorOutOfHostMemory` in maintainer discussion | Medium |
| #216 | 2025-03-25 | 2.x→3.x migration | `load_file_as_articulation_builder` and scene/config API churn | Medium |
| #236 | 2025-05-13 | URDF mimic joints | Mimic joints not enforced on Ubuntu 24.04 / Python 3.11 / SAPIEN 3.0.0 | High |
| #250 | 2025-06-24 | H100 headless Vulkan | Vulkan device creation fails on H100 despite JSON ICD files; CUDA 12.8 / driver 570.148.08 | High |
| #256 | 2025-08-19 | EGL missing | Import failure from missing `/usr/share/glvnd/egl_vendor.d` in container | High |
| #261 | 2025-09-22 | GPU memory growth | Slow GPU memory accumulation with large parallel env count; later CUDA illegal memory access | Medium |
| #269 | 2025-11-04 | Vulkan ICD selection | SAPIEN picks wrong NVIDIA ICD in containers; workaround via `VK_ICD_FILENAMES` | High |
| #275 | 2025-12-01 | Mesh cache growth | PhysX mesh cache accumulates for changing filenames; request to clear/disable | High |
| #290 | 2026-04-20 | CUDA interop hang | `camera.get_picture_cuda("Color")` hangs on 3.0.2/3.0.3 + PyTorch cu121; H100; Singularity Vulkan/EGL bind-mount workaround | High |

### GPU simulation determinism caveats

- PhysX 5 GPU simulation is **not bit-exact** across runs or across CPU vs GPU mode. Use RMS divergence thresholds, not exact equality, when cross-validating.
- GPU mode requires all PhysX objects to be created **after** `PhysxGpuSystem` is instantiated. Creating loaders, actors, or other PhysX objects before constructing the system causes silent CPU fallback or the ordering error from #157.
- `sapien.physx.enable_gpu()` (legacy global toggle from older betas) must be called before any PhysX object if used; but prefer `PhysxGpuSystem` for 3.0.x stable code.
- CUDA 12.x interoperability with PyTorch (cu121) has a confirmed hang on H100 (#290). Workaround: bind-mount Vulkan/EGL vendor JSON files in the container runtime or use CPU rendering for validation pipelines.
- GPU memory does not monotonically decrease after releasing environments (#261, #275). For long sweeps, restart the Python process between batches.

## SAPIEN vs MuJoCo diff schema

Use this schema when running identical-control 1-second rollouts in SAPIEN and MuJoCo and comparing per-joint trajectories.

```json
{
  "asset": "out/sem/sem.urdf",
  "asset_hash": "sha256:...",
  "sapien_version": "3.0.3",
  "mujoco_version": "3.x.x",
  "physx_gpu": false,
  "sim_duration_s": 1.0,
  "timestep_s": 0.002,
  "n_steps": 500,
  "joints": [
    {
      "name": "stage_x",
      "type": "prismatic",
      "sapien_qpos_final": 0.0412,
      "mujoco_qpos_final": 0.0414,
      "rms_divergence": 0.0003,
      "passed": true
    },
    {
      "name": "magnification_knob",
      "type": "revolute",
      "sapien_qpos_final": 1.5708,
      "mujoco_qpos_final": 1.5721,
      "rms_divergence": 0.0013,
      "passed": true
    }
  ],
  "summary": {
    "max_rms": 0.0013,
    "threshold": 0.005,
    "passed": true
  }
}
```

**Threshold guidance**: tolerable RMS < 5e-3 rad/m per joint over a 1-second rollout. Persistent divergence above threshold indicates inertia round-trip issues in `authoring-urdf-mjcf-usd` or contact-pair tuning differences. SAPIEN is the second opinion — file bugs against the authoring skill, not as manual SAPIEN fixes.

**When SAPIEN flags an issue — where to fix it**

| SAPIEN diff | Likely root cause | Fix in skill |
|---|---|---|
| Joint type mismatch | URDF emitted wrong type | authoring-urdf-mjcf-usd |
| Axis mismatch > 1e-6 | Canonical axis not normalized | authoring-urdf-mjcf-usd |
| Limit overshoot in drive sweep | Actuator gain too high for PhysX 5 | calibrating-sysid-rl-hooks |
| Cable harness drifting | URDF emitted revolute instead of fixed | authoring-urdf-mjcf-usd |
| Zero-link articulation | Mesh path resolution failed | conditioning-collision-meshes |
| RMS > 5e-3 vs MuJoCo | Inertia/contact tuning mismatch | authoring-urdf-mjcf-usd |
