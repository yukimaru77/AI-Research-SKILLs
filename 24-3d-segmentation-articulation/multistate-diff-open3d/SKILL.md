---
name: multistate-diff-open3d
description: Compares two reconstructed point clouds or Gaussian splat exports of the SAME lab equipment captured in DIFFERENT mechanical states (e.g., SEM door open vs closed, knob at 0 vs 90 deg, button pressed vs unpressed) to extract moving regions, fit per-part SE(3) transforms, and classify revolute/prismatic/screw joints; use as the SPINE of the lab-equipment digital-twin pipeline because Gaussian identities are not stable across independently trained splats — this skill compares world-space occupancy and nearest-neighbor distances after RANSAC+ICP scene alignment, not row indices. MIT (Open3D) + BSD-3-Clause (pytransform3d), both safe for commercial digital-twin use.
version: 2.0.0
author: Orchestra Research
license: MIT
tags: [3DGS, Open3D, ICP, RANSAC, HDBSCAN, SE(3), Screw Axis, Revolute, Prismatic, Articulation, CloudCompare, Change Detection]
dependencies: [open3d==0.19.0, pytransform3d>=3.1.0, numpy>=2.0.0,<3, scipy>=1.14.0, scikit-learn>=1.5.0, trimesh>=4.0.0]
---

# Multi-state differencing with Open3D

Compares two independently trained 3DGS scenes (or any aligned point-cloud pair) of the same lab equipment in different mechanical states. Recovers per-part SE(3) transforms, screw axes, and joint type classifications. The pipeline is purely geometric and does not depend on Gaussian IDs (not stable across independent training runs).

Pipeline: PLY Gaussian centers → voxel downsample → static-ROI alignment (FPFH/RANSAC then ICP) → stable-region refinement → bidirectional C2C distance map → HDBSCAN moved-cluster extraction → rigid SE(3) fit per cluster → SE(3) screw decomposition (pytransform3d) → prismatic/revolute/screw/ambiguous classification → JSON joint record.

## Quick start

```bash
# Install (Python 3.10 or 3.11 recommended for broadest tool compatibility; 3.12 OK for Open3D-only)
python -m pip install -U pip
pip install "open3d==0.19.0" "pytransform3d>=3.1.0" \
  "numpy>=2.0.0,<3" "scipy>=1.14.0" "scikit-learn>=1.5.0" "trimesh>=4.0.0"

python hello_joint_diff.py state0.ply state1.ply \
  --unit-scale 0.001 --voxel 0.0005 --diff-eps 0.0015
# Emits JSON: joint_type, axis_direction, axis_point, theta_deg,
# translation_magnitude, pitch, residuals, confidence, diagnostics.
```

Open3D 0.19.0 (released Jan 8, 2025) is the current stable release on PyPI. It adds Python 3.12 + NumPy 2 support, Chamfer/Hausdorff/F-score metrics, and CUDA 12 support. Do NOT use Python 3.13+ with stable Open3D 0.19.0 — no stable wheel exists as of May 2026; dev wheels or source builds only.

On Linux: `open3d-cpu` (leaner, CPU-only) and `open3d` (GPU-enabled) are separate packages. Do NOT install both in the same environment.

## Common workflows

### Workflow 0 (install): Docker container for the multi-state-diff pipeline

```dockerfile
FROM python:3.11-slim-bookworm
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 \
    OMP_NUM_THREADS=4 OPENBLAS_NUM_THREADS=4 MKL_NUM_THREADS=4
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 libglib2.0-0 libgomp1 libxext6 libxrender1 ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN pip install --upgrade "pip>=24.3.1" setuptools wheel
RUN pip install \
    "open3d==0.19.0" "pytransform3d>=3.1.0" \
    "numpy>=2.0.0,<3" "scipy>=1.14.0" \
    "scikit-learn>=1.5.0" "trimesh>=4.0.0"
```

Use `open3d-cpu` instead of `open3d` on the slim Linux container if GPU rendering is not needed; it is smaller. Do NOT install both.

### Workflow A: SEM chamber door, closed vs open (revolute, large displacement)

Large displacement; occupancy mode preferred over NN distances because C2C saturates when the door swings far from its closed position. Stable-region voting prevents the large moved door from corrupting scene-level ICP.

Task Progress:
- [ ] Step 1: Load closed-door gsplat export (`state0.ply`); filter low-opacity / huge-scale Gaussians at load time.
- [ ] Step 2: Load open-door gsplat export (`state1.ply`), same filter.
- [ ] Step 3: Register state1 to state0 using FPFH features + RANSAC global registration, then ICP on static structure only (base frame, rear panel, floor, rails — exclude door ROI).
- [ ] Step 4: Stable-region voting: mark points with small NN residual post-ICP as "static"; rerun ICP constrained to that subset.
- [ ] Step 5: Bidirectional C2C: `pcd_state0.compute_point_cloud_distance(pcd_state1)` + reverse direction; union above `diff_eps` threshold.
- [ ] Step 6: HDBSCAN-cluster the changed-point union; require both "old" cluster (state0) and "new" cluster (state1) — reject one-sided detections.
- [ ] Step 7: Fit rigid SE(3) from old cluster → new cluster using point-to-plane ICP on the isolated part.
- [ ] Step 8: Decompose with `pytransform3d` screw parameters.
- [ ] Step 9: Classify `revolute`; emit hinge axis_direction and axis_point.

```bash
python workflow_a_sem_door.py \
  --closed sem_door_closed.ply --open sem_door_open.ply \
  --unit-scale 0.001 --voxel 0.002 --diff-eps 0.006 \
  --diff-mode occupancy --min-cluster-size 250
```

Expected output: `joint_type="revolute"`, `theta_deg` near actual opening angle, `pitch ~ 0`, axis_direction and axis_point describing the hinge line in the state0/world frame.

### Workflow B: Microscope focus knob, 0 deg vs 90 deg (revolute, three-state validation)

Small-radius revolute; symmetric knob geometry creates rotational ambiguity at a single angle. Use a third state to verify axis consistency.

Task Progress:
- [ ] Step 1: Load knob states: 0 deg, 45 deg, 90 deg (or 0/30/60).
- [ ] Step 2: Register on fixed instrument faceplate/body; crop a knob ROI.
- [ ] Step 3: Compare state0 → stateA with `compare_two_states()`.
- [ ] Step 4: Compare state0 → stateB with the same pipeline.
- [ ] Step 5: Fit rigid SE(3) for the moved knob cluster in each comparison.
- [ ] Step 6: Decompose each transform with pytransform3d screw parameters.
- [ ] Step 7: Aggregate two screw-axis observations; score angular consistency (`theta_B / theta_A` should equal actual ratio ± tolerance).
- [ ] Step 8: Classify `revolute`; emit confidence-weighted axis.

```bash
python workflow_b_focus_knob.py \
  --state0 knob_000deg.ply \
  --stateA knob_045deg.ply \
  --stateB knob_090deg.ply \
  --unit-scale 0.001 --voxel 0.0008 --diff-eps 0.002 \
  --min-cluster-size 150
```

Expected output: `joint_type="revolute"`, screw pitch near zero, angle-ratio consistency score close to 1.0, axis through the knob shaft in the state0 frame.

### Workflow C: Push button, unpressed vs pressed (prismatic, small displacement)

Small axial displacement; button travel may be only 1–3 mm. Use tight voxel size and point-to-plane ICP on the panel face to suppress faceplate noise before local C2C on the button cap.

Task Progress:
- [ ] Step 1: Load unpressed and pressed states.
- [ ] Step 2: Segment the rigid front panel; run point-to-plane ICP on the panel only.
- [ ] Step 3: Crop a tight button ROI around the cap.
- [ ] Step 4: Compute bidirectional C2C within the ROI; threshold at 0.5–1 mm.
- [ ] Step 5: Fit SE(3) to the button cluster; confirm rotation < 3 deg and translation > noise floor.
- [ ] Step 6: Classify `prismatic`; emit axis_direction (typically panel-normal).

```bash
python workflow_c_push_button.py \
  --unpressed button_up.ply --pressed button_down.ply \
  --unit-scale 0.001 --voxel 0.0003 --diff-eps 0.0008 \
  --min-cluster-size 40 --roi-radius 0.015
```

Expected output: `joint_type="prismatic"`, `theta_deg < 2`, `translation_magnitude` in range 0.001–0.005 m, axis roughly parallel to the panel normal.

## Core Open3D API reference

| Function | Purpose |
|---|---|
| `o3d.io.read_point_cloud(path)` | Load PLY/PCD/XYZ into PointCloud |
| `pcd.voxel_down_sample(voxel_size)` | Uniform voxel preprocessing |
| `pcd.estimate_normals(search_param)` | Required for point-to-plane ICP |
| `o3d.pipelines.registration.compute_fpfh_feature(pcd, ...)` | FPFH features for global registration |
| `o3d.pipelines.registration.registration_ransac_based_on_feature_matching(...)` | RANSAC global alignment |
| `o3d.pipelines.registration.registration_icp(source, target, max_corr_dist, init, TransformationEstimationPointToPlane())` | ICP refinement |
| `o3d.pipelines.registration.evaluate_registration(source, target, threshold, T)` | Pre/post alignment diagnostics (fitness, inlier_rmse) |
| `pcd.compute_point_cloud_distance(target)` | Per-point nearest-neighbor C2C distance (returns numpy array) |
| `pcd.hidden_point_removal(camera, radius)` | Visibility filtering for open/closed occlusion artifacts |
| `o3d.t.geometry.PointCloud.compute_metrics(ref, [Metric.ChamferDistance, Metric.HausdorffDistance, Metric.FScore], ...)` | Global QA metrics (Open3D 0.19+) |

**Breaking changes in Open3D 0.19:**
- `orient_normals_consistent_tangent_plane()` parameter renamed `lambda` → `lambda_penalty`.
- `furthest_point_sampling` torch argument typo was fixed (check arg names if upgrading scripts).
- Failed image reads now clear old image data (prior silent failure).

## CloudCompare CLI (independent validation backend)

CloudCompare stable: 2.13.2 "Kharkiv" (Aug 7, 2024). Beta: 2.14.beta (May 1, 2026). License: GNU GPL — do not embed in proprietary distribution; use as a separate validation process.

```bash
# C2C distance map + save (stable 2.13.2)
CloudCompare -SILENT \
  -O closed.ply -SS SPATIAL 0.003 \
  -O open.ply   -SS SPATIAL 0.003 \
  -ICP -OVERLAP 80 -RANDOM_SAMPLING_LIMIT 100000 \
  -C2C_DIST -MAX_DIST 0.03 \
  -SAVE_CLOUDS

# M3C2 (requires parameter file)
CloudCompare -SILENT -O state0.ply -O state1.ply -M3C2 m3c2_params.txt
```

Install (Linux): `flatpak install flathub org.cloudcompare.CloudCompare`

Use CloudComPy for Python-batch M3C2 (see issue #220 below — validate output against CLI before trusting batch results).

## When to use vs alternatives

Use this skill as the primary articulation estimator. It is MIT-licensed (Open3D core), CPU-capable, deterministic, and works on any pair of gsplat PLY exports from any trainer.

| Tool | Use when |
|---|---|
| **This skill (Open3D)** | Primary pipeline: any lab equipment pair, no GPU required, permissive license |
| **CloudCompare CLI** | Independent validation run before production; GPL fine for internal tooling |
| **CloudComPy** | Python-batch M3C2/C2C when GPL is acceptable; validate vs CLI first (issue #220) |
| **PyTorch3D 0.7.9** | Differentiable Chamfer/Hausdorff losses in a learning pipeline; install via conda-forge not pip (PyPI wheel is stale at 0.7.4) |
| **screwsplat-articulation** | Research reference for GS-native joint axis recovery via re-optimization; requires original multi-state RGB, not usable as "PLY in, joints out" |
| **PARIS** | NeRF-centric; avoid for new code |
| **Watch-It-Move** | Video/foreground-mask oriented; not a static-scan diff tool |
| **articulation-ditto-prior** | Offline validator for furniture-class revolute/prismatic; out-of-distribution for SEM/microscope parts |

## Common issues

**Gaussian IDs are not stable.** Never diff by row index. Always use world-space C2C or occupancy after alignment.

**Coordinate frames differ between splats.** Two gsplats trained from different camera-pose initializations do not share a frame. Run FPFH/RANSAC first, then ICP, then stable-region ICP.

**Moved part corrupts scene-level ICP.** If the moved object is large (door, drawer), full-scene ICP "splits the difference." Fix: mask the moving ROI before alignment or use stable-region voting.

**C2C saturates on large displacement.** When a part travels far (door swung open), NN distances all become large and thresholding fails. Switch to `occupancy` mode (voxel hash).

**Button / small-displacement travel below noise floor.** Gsplat reconstruction noise can exceed small button or stage travel. Use the smallest voxel that still gives stable normals; require reciprocal old/new clusters; increase scan density or use structured-light depth if possible.

**Specular metal and glass cause Gaussian drift.** Filter low-opacity / huge-scale Gaussians at load time; increase `diff_eps`; require bidirectional cluster evidence.

**Single-displacement ambiguity (prismatic vs large-radius revolute).** One translation is ambiguous. Capture two or more states for knobs, compound stages, and small-rotation hinges.

**HDBSCAN on > 5M Gaussians.** Downsample first; do not run full HDBSCAN on the entire raw splat.

**Symmetric objects fit multiple transforms.** Knurled or circular knobs create rotational ambiguity. The multi-state workflow (Workflow B) reduces this by requiring axis consistency across angles.

**CloudComPy M3C2 shift bug.** CloudComPy issue #220 (opened Nov 27, 2025): Python M3C2 may return shifted distances vs CLI. Always cross-validate CloudComPy M3C2 output against the CloudCompare GUI or CLI before trusting batch masks.

**Signed C2M direction inconsistency.** CloudCompare issue #1976 (opened Mar 6, 2024): signed point-to-mesh distances can be inconsistent when splitting positive/negative distances. Verify normals, watertightness, sign convention, and thresholds rather than trusting sign direction alone.

**Open3D colored ICP segfault.** Open3D issue #6935 (Aug 27, 2024): colored point-cloud ICP can crash. Use geometry-only ICP (PointToPlane) as the default; treat color as auxiliary only.

**PyTorch3D pip wheel is stale.** PyPI shows 0.7.4 (May 2023). Current release is 0.7.9 (Nov 28, 2025). Install via `conda install conda-forge::pytorch3d` to get the current version; mixing with arbitrary Torch CUDA builds causes ABI symbol failures.

## Output JSON schema

Every detected moving part emits this shape. `axis_point` for prismatic is the moved cluster centroid. For revolute/screw, `axis_point` is the estimated point on the hinge/screw axis in the state0/world frame. `pitch` is `null` for prismatic and revolute; a finite float for screw/helical joints.

```json
{
  "part_id": "string",
  "joint_type": "prismatic | revolute | screw | ambiguous",
  "axis_direction": [0.0, 0.0, 1.0],
  "axis_point": [0.0, 0.0, 0.0],
  "transform_0_to_1": [[1,0,0,0],[0,1,0,0],[0,0,1,0.005],[0,0,0,1]],
  "theta_rad": 0.0,
  "theta_deg": 0.0,
  "translation_magnitude": 0.005,
  "pitch": null,
  "residuals": {
    "part_icp_fitness": 0.0,
    "part_icp_inlier_rmse": 0.0,
    "symmetric_nn_rmse": 0.0,
    "symmetric_nn_median": 0.0,
    "symmetric_nn_p90": 0.0
  },
  "confidence": 0.0,
  "diagnostics": {
    "scene_alignment": {},
    "differencing": {},
    "old_cluster": {},
    "new_cluster": {},
    "classification_thresholds": {}
  }
}
```

## Advanced topics

- **references/spine-module.md** — full `gsplat_joint_spine.py` API: `load_gaussian_centers_ply`, `align_scenes_with_stable_voting`, `extract_changed_candidates`, `largest_hdbscan_cluster`, `fit_part_transform`, `decompose_screw`, `classify_joint_transform`, `compare_two_states`, `aggregate_axis_observations`, `ransac_line_3d`.
- **references/joint-classification.md** — SE(3) log, screw axis, pitch math, threshold logic (`angle_small_deg=5.0`, `min_translation`, `pitch_eps`).
- **references/output-schema.md** — canonical JSON joint record field definitions and validation rules.
- **references/lab-tuning.md** — recommended `voxel_size` / `diff_eps` / `min_cluster_size` per equipment class (SEM stage, microscope knob, optical mount, cabinet door).
- **references/issues.md** — real GitHub issues and workarounds (CloudComPy #220, CloudCompare #1976, Open3D #6935).

## Resources

- Open3D repository: https://github.com/isl-org/Open3D
- Open3D 0.19.0 release notes (Jan 8, 2025): https://www.open3d.org/2025/01/30/open3d-0-19-release/
- Open3D registration ICP API: https://www.open3d.org/docs/release/python_api/open3d.pipelines.registration.registration_icp.html
- Open3D compute_point_cloud_distance: https://www.open3d.org/docs/release/python_api/open3d.geometry.PointCloud.html
- Open3D compute_metrics (0.19+): https://www.open3d.org/docs/release/python_api/open3d.t.geometry.PointCloud.html
- pytransform3d repository: https://github.com/dfki-ric/pytransform3d
- scikit-learn HDBSCAN: https://scikit-learn.org/stable/modules/generated/sklearn.cluster.HDBSCAN.html
- PyTorch3D 0.7.9 (Nov 28, 2025): https://github.com/facebookresearch/pytorch3d/releases
- CloudCompare 2.13.2 stable: https://www.danielgm.net/cc/release/
- CloudCompare CLI reference: https://www.cloudcompare.org/doc/wiki/index.php/Command_line_mode
- CloudComPy Python API: https://www.simulation.openfields.fr/index.php/cloudcompy-documentation
- CloudComPy issue #220 (M3C2 shift, Nov 2025): https://github.com/CloudCompare/CloudComPy/issues/220
- CloudCompare issue #1976 (signed C2M inconsistency, Mar 2024): https://github.com/CloudCompare/CloudCompare/issues/1976
- Open3D issue #6935 (colored ICP segfault, Aug 2024): https://github.com/isl-org/Open3D/issues/6935
