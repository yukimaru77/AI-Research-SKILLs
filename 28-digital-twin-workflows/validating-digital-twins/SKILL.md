---
name: validating-digital-twins
description: META gate-keeper skill that runs strict, build-failing numerical QA across the full SEM/lab-equipment digital-twin pipeline (capture → pose → 3DGS → surface → segmentation → affordance → articulation → physics → VR). Emits qa_report.json (machine-readable, all metrics + pass/fail), qa_summary.md, per-stage metrics/, regression_snapshots/, and human_review_sheet.csv. Refuses to say "looks good" without numbers. Use after every pipeline stage and as the final pre-release CI step.
version: 2.0.0
author: Orchestra Research
license: MIT
tags: [Digital Twin, QA, Validation, Regression, PSNR, SSIM, LPIPS, Chamfer Distance, Hausdorff, Joint Axis Error, Kinematic RMSE, Contact Penetration, VR FPS, CI Gates, 3DGS, URDF, MJCF, USD, SEM]
---

# Validating Digital Twins

META validation skill for cat 28. Sits downstream of every executable sub-skill in cats 23–27. Consumes their outputs read-only, runs numerical gates, and either issues a `validated` stamp or routes failures back to the originating sub-skill. Never touches README, CLAUDE, ROADMAP, or other files.

**Key outputs** emitted under `twin_package/validation/`:

```
validation_plan.yaml           # which gates are active for this equipment_class
qa_report.json                 # all metrics + pass/fail (machine-readable)
qa_summary.md                  # human badges
metrics/
  pose_metrics.json
  rendering_metrics.json
  surface_metrics.json
  segmentation_metrics.json
  affordance_metrics.json
  articulation_metrics.json
  physics_metrics.json
  vr_metrics.json
regression_snapshots/
  heldout_renders/{S00,S01,...}/*.png
  mesh_slices/*.png
  joint_axes/*.json
failed_gates/<gate_name>.json  # one file per red gate, with reproduction info
human_review_sheet.csv
```

## Architecture

```
[ pipeline outputs from cats 23-27 ]
         |
         v
validating-digital-twins  (THIS SKILL — cat 28 META)
  load validation_plan.yaml
  for each gate family { capture, pose, render, surface,
                         semantics, articulation, physics, vr }:
      run metric → compare threshold → green / yellow / red
  write qa_report.json + qa_summary.md
  diff regression_snapshots vs prior release tag
  emit human_review_sheet.csv for safety-critical items
         |
    pass → versioning-twins-with-ara
    fail → route back to originating sub-skill
```

## Cross-references (cats 23–27)

**Cat 23 — 3D Reconstruction**
- [estimating-sfm-camera-poses](../../23-3d-reconstruction/estimating-sfm-camera-poses/SKILL.md) — pose gate inputs
- [training-gaussian-splats](../../23-3d-reconstruction/training-gaussian-splats/SKILL.md) — rendering gate inputs
- [training-reflection-aware-splats](../../23-3d-reconstruction/training-reflection-aware-splats/SKILL.md) — reflection fallback
- [extracting-gs-surfaces](../../23-3d-reconstruction/extracting-gs-surfaces/SKILL.md) — surface gate inputs
- [recovering-pose-free-geometry](../../23-3d-reconstruction/recovering-pose-free-geometry/SKILL.md) — pose-free fallback
- [preprocessing-reconstruction-videos](../../23-3d-reconstruction/preprocessing-reconstruction-videos/SKILL.md)
- [training-nerf-fallbacks](../../23-3d-reconstruction/training-nerf-fallbacks/SKILL.md)

**Cat 24 — 3D Segmentation & Articulation**
- [gsplat-scene-adapter](../../24-3d-segmentation-articulation/gsplat-scene-adapter/SKILL.md) — segmentation gate inputs
- [per-gaussian-saga](../../24-3d-segmentation-articulation/per-gaussian-saga/SKILL.md) — Gaussian segmentation
- [articulation-ditto-prior](../../24-3d-segmentation-articulation/articulation-ditto-prior/SKILL.md) — joint hypotheses
- [screwsplat-articulation](../../24-3d-segmentation-articulation/screwsplat-articulation/SKILL.md) — screw-motion joints
- [multistate-diff-open3d](../../24-3d-segmentation-articulation/multistate-diff-open3d/SKILL.md) — state correspondences
- [lift-2d-masks-ludvig](../../24-3d-segmentation-articulation/lift-2d-masks-ludvig/SKILL.md)

**Cat 25 — Affordance VLM**
- [qwen3-vl-affordance-prompter](../../25-affordance-vlm/qwen3-vl-affordance-prompter/SKILL.md) — affordance gate inputs
- [vlm-physics-validation-loop](../../25-affordance-vlm/vlm-physics-validation-loop/SKILL.md) — VLM cross-check
- [kinematic-json-constrained-decode](../../25-affordance-vlm/kinematic-json-constrained-decode/SKILL.md) — structured outputs
- [articulation-priors-retrieval](../../25-affordance-vlm/articulation-priors-retrieval/SKILL.md)
- [multiview-joint-cards-renderer](../../25-affordance-vlm/multiview-joint-cards-renderer/SKILL.md)

**Cat 26 — 3D Rendering & VR**
- [deploying-quest-spatial-splats](../../26-3d-rendering-vr/deploying-quest-spatial-splats/SKILL.md) — VR FPS gate
- [rendering-unity-splats](../../26-3d-rendering-vr/rendering-unity-splats/SKILL.md) — Unity VR gate
- [publishing-supersplat-webxr](../../26-3d-rendering-vr/publishing-supersplat-webxr/SKILL.md)
- [compiling-splat-assets](../../26-3d-rendering-vr/compiling-splat-assets/SKILL.md)
- [editing-supersplat-scenes](../../26-3d-rendering-vr/editing-supersplat-scenes/SKILL.md)
- [rendering-unreal-xscene-splats](../../26-3d-rendering-vr/rendering-unreal-xscene-splats/SKILL.md)

**Cat 27 — Physics Simulation**
- [authoring-urdf-mjcf-usd](../../27-physics-simulation/authoring-urdf-mjcf-usd/SKILL.md) — physics gate inputs
- [simulating-mujoco-mjx](../../27-physics-simulation/simulating-mujoco-mjx/SKILL.md) — MuJoCo contact metrics
- [validating-isaac-sim-lab](../../27-physics-simulation/validating-isaac-sim-lab/SKILL.md) — Isaac Lab contact/solver
- [validating-sapien-articulations](../../27-physics-simulation/validating-sapien-articulations/SKILL.md) — SAPIEN contact
- [conditioning-collision-meshes](../../27-physics-simulation/conditioning-collision-meshes/SKILL.md) — watertight meshes
- [calibrating-sysid-rl-hooks](../../27-physics-simulation/calibrating-sysid-rl-hooks/SKILL.md)
- [prototyping-genesis-physics](../../27-physics-simulation/prototyping-genesis-physics/SKILL.md)

**Cat 28 — Digital Twin Workflows**
- [lab-equipment-twinning](../lab-equipment-twinning/SKILL.md) — orchestrator, calls this skill at every stage
- [multi-state-capture-protocol](../multi-state-capture-protocol/SKILL.md) — capture gate inputs
- [versioning-twins-with-ara](../versioning-twins-with-ara/SKILL.md) — consumes qa_report.json for release lineage
- [simulating-experiment-runs-in-twins](../simulating-experiment-runs-in-twins/SKILL.md) — VR FPS gates feed here

## Common workflows

### Workflow 1 — Full CI validation (post-pipeline)

Run after every pipeline stage. Build fails on the first red required gate.

Task Progress:
- [ ] V1. Load `validation/validation_plan.yaml` (defaults filled per equipment_class)
- [ ] V2. **Capture gates**: safety_state present, calibration manifest present, scale-bar evidence, K-state quotas → fail → [multi-state-capture-protocol](../multi-state-capture-protocol/SKILL.md)
- [ ] V3. **Pose gates**: registered-image ratio, mean/median reprojection error, track length, scale drift vs caliper/AprilTag → fail → [estimating-sfm-camera-poses](../../23-3d-reconstruction/estimating-sfm-camera-poses/SKILL.md)
- [ ] V4. **Rendering gates**: held-out PSNR/SSIM/LPIPS stratified by state+view, control-label ROI PSNR, train/val gap → fail → [training-gaussian-splats](../../23-3d-reconstruction/training-gaussian-splats/SKILL.md) or reflection-aware variant
- [ ] V5. **Surface gates**: median + P95 Chamfer vs CAD/scan, normal error, watertight collision meshes → fail → [extracting-gs-surfaces](../../23-3d-reconstruction/extracting-gs-surfaces/SKILL.md) + [conditioning-collision-meshes](../../27-physics-simulation/conditioning-collision-meshes/SKILL.md)
- [ ] V6. **Segmentation gates**: foreground assignment ≥0.95, mIoU ≥0.75, interactive-part coverage 100% → fail → [per-gaussian-saga](../../24-3d-segmentation-articulation/per-gaussian-saga/SKILL.md)
- [ ] V7. **Affordance VLM gates**: schema conformity, segment binding, image+state evidence, safety-critical human review → fail → [vlm-physics-validation-loop](../../25-affordance-vlm/vlm-physics-validation-loop/SKILL.md)
- [ ] V8. **Articulation gates**: joint-type, axis angular error, origin error, joint-limit error, held-out keypoint RMS → fail → [articulation-ditto-prior](../../24-3d-segmentation-articulation/articulation-ditto-prior/SKILL.md) / [screwsplat-articulation](../../24-3d-segmentation-articulation/screwsplat-articulation/SKILL.md)
- [ ] V9. **Physics gates**: URDF/MJCF/USD load, interpenetration <1 mm, resting drift, energy drift, cross-engine endpoint ≤5 mm → fail → [authoring-urdf-mjcf-usd](../../27-physics-simulation/authoring-urdf-mjcf-usd/SKILL.md)
- [ ] V10. **VR rendering gates**: Quest 3 ≥72 FPS, Vision Pro ≥90 FPS, motion-to-photon latency → fail → [deploying-quest-spatial-splats](../../26-3d-rendering-vr/deploying-quest-spatial-splats/SKILL.md)
- [ ] V11. Diff regression_snapshots vs prior release tag (PSNR delta, joint-axis delta)
- [ ] V12. Emit `qa_report.json` + `qa_summary.md` + `human_review_sheet.csv`
- [ ] V13. Red required gate → write `failed_gates/<gate>.json`, set `status: failed_validation`

### Workflow 2 — Validate pose recovery

Goal: confirm SfM/pose-free reconstruction matches physical reality before 3DGS training.

Task Progress:
- [ ] 1. Export `selected_pose_graph.json` from [estimating-sfm-camera-poses](../../23-3d-reconstruction/estimating-sfm-camera-poses/SKILL.md)
- [ ] 2. Compute registered-image ratio; require ≥85%
- [ ] 3. Compute mean/median reprojection error after BA; require ≤0.8 px (calibrated) / ≤1.2 px (phone)
- [ ] 4. Check scale drift vs known ruler/AprilTag/caliper; require <1%
- [ ] 5. Verify anchor frames (safety + articulated states) each ≥80% registered
- [ ] 6. Verify track length ≥3.5 views mean
- [ ] 7. If any gate yellow/red: re-run hloc rescue in [estimating-sfm-camera-poses](../../23-3d-reconstruction/estimating-sfm-camera-poses/SKILL.md); else proceed to 3DGS

### Workflow 3 — Validate VLM-proposed kinematics

Goal: ensure VLM affordance predictions translate to physically valid articulation before URDF authoring.

Task Progress:
- [ ] 1. Receive `semantics/affordances.json` from [qwen3-vl-affordance-prompter](../../25-affordance-vlm/qwen3-vl-affordance-prompter/SKILL.md)
- [ ] 2. Verify schema conformity ≥95% first-pass, 100% after retry
- [ ] 3. Each affordance must reference a 3D segment, a state image, and a confidence score
- [ ] 4. Cross-check joint type/axis predictions against [articulation-ditto-prior](../../24-3d-segmentation-articulation/articulation-ditto-prior/SKILL.md) output; flag disagreements
- [ ] 5. Run [vlm-physics-validation-loop](../../25-affordance-vlm/vlm-physics-validation-loop/SKILL.md) to simulate proposed motion in MuJoCo; check penetration and limit violations
- [ ] 6. Safety-critical affordances: require 100% human sign-off in `human_review_sheet.csv`
- [ ] 7. Kinematic RMSE check: load proposed URDF in [yourdfpy](https://pypi.org/project/yourdfpy/); compute per-joint angle RMSE over K held-out states; require ≤3° revolute, ≤2 mm prismatic
- [ ] 8. Cross-model disagreement on safety label → fail until resolved
- [ ] 9. Pass → hand to [authoring-urdf-mjcf-usd](../../27-physics-simulation/authoring-urdf-mjcf-usd/SKILL.md)

### Workflow 4 — Pre-release final certification

Goal: certify `validated` status before [versioning-twins-with-ara](../versioning-twins-with-ara/SKILL.md).

Task Progress:
- [ ] 1. All required gates green
- [ ] 2. `human_review_sheet.csv` signed for every safety-critical affordance
- [ ] 3. Regression snapshots committed and diffed against prior tagged release
- [ ] 4. Cross-engine endpoint agreement: MuJoCo vs Isaac Lab vs SAPIEN ≤5 mm
- [ ] 5. Held-out state evaluation: one state withheld from articulation fitting reproduces within RMS threshold
- [ ] 6. Generate `qa_summary.md` with badges; emit final `status: validated` stamp
- [ ] 7. Hand `qa_report.json` to [versioning-twins-with-ara](../versioning-twins-with-ara/SKILL.md)

## Validation gates & quality thresholds

### Pose recovery

| Metric | Green | Yellow | Red |
|---|---|---|---|
| Registered-image ratio | ≥85% | 70–85% | <70% |
| Mean reprojection error — calibrated | ≤0.8 px | 0.8–2.0 px | >2.0 px |
| Mean reprojection error — phone | ≤1.2 px | 1.2–2.0 px | >2.0 px |
| Median reprojection error | ≤0.7 px | 0.7–1.5 px | >1.5 px |
| Mean track length | ≥3.5 views | 2.5–3.5 | <2.5 |
| Scale drift vs ruler/AprilTag | <1% | 1–3% | >3% |

COLMAP's 4 px reprojection filter is a cleanup threshold, not an acceptance threshold.

### 3DGS photometric (held-out frames, stratified by state and view)

Metrics: PSNR (dB), SSIM, LPIPS (lpips/AlexNet), optionally DISTS. Published articulated-3DGS benchmarks (ArticulatedGS CVPR 2025, Part2GS arXiv 2026) report PSNR 29–43 dB, SSIM 0.944–0.996, LPIPS 0.007–0.087 depending on object and state. Set project-specific gates from calibration runs.

| Metric | MVP | Good | Excellent |
|---|---|---|---|
| PSNR — reflective/metal | ≥24 dB | ≥28 dB | ≥30 dB |
| PSNR — matte | ≥26 dB | ≥28 dB | ≥30 dB |
| SSIM | ≥0.85 | ≥0.90 | ≥0.93 |
| LPIPS (AlexNet) | ≤0.20 | ≤0.12 | ≤0.08 |
| Control-label ROI PSNR | ≥28 dB | ≥30 dB | ≥32 dB |
| Held-out split size | 10–15% stratified | same | same |

Switch to [training-reflection-aware-splats](../../23-3d-reconstruction/training-reflection-aware-splats/SKILL.md) when: specular mask area >10% of pixels, LPIPS >0.18 despite PSNR ≥28, view-dependent ghosting >3 px, or same-point color CoV >0.25 across views.

### Surface geometry (Chamfer, Hausdorff vs CAD/scan, 10K sampled points)

Published values from DigitalTwinArt (CVPR 2024): CD-s 0.08, CD-m 0.00, CD-w low. Part2GS reports CD-static 0.56–1.18, CD-movable 0.07–1.95 across objects. Set equipment-specific tolerances from CAD manufacturing tolerances and collision-clearance margins.

| Metric | Small benchtop | Full SEM | Optical bench |
|---|---|---|---|
| Median Chamfer vs CAD/scan | ≤0.5 mm | ≤2 mm | ≤2 mm |
| P95 Chamfer | ≤2 mm | ≤8–10 mm | ≤5 mm |
| Relative mean Chamfer | ≤0.2% bbox diag | ≤0.2% | ≤0.2% |
| Hausdorff 95th percentile | ≤3 mm | ≤12 mm | ≤8 mm |
| Planar normal error | ≤3° | ≤5° | ≤2° |
| Mean normal consistency | ≥0.90 good; ≥0.85 MVP | same | same |
| Collision mesh | watertight, 0 non-manifold edges | same | same |

Use separate assets: visual mesh (pretty), collision mesh (watertight, simple), semantic mesh (segmented), measurement mesh (validated vs calipers/CAD).

### Articulation / kinematic

Reference: Articulate-Anything (ICLR 2025) uses 50 mm position threshold and 0.25 rad (~14°) axis threshold; URDF-Anything (NeurIPS 2025) reports 29% average joint-error reduction vs baselines. These are benchmarks, not universal gates. Use tighter tolerances for SEM.

| Metric | Green | Yellow | Red |
|---|---|---|---|
| Joint type classification | 100% | ≥95% research | any safety-critical ambiguity |
| Revolute axis angular error | ≤3° | 3–5° | >5° |
| Prismatic axis angular error | ≤2° | 2–4° | >4° |
| Revolute origin/axis offset — knobs/turrets | ≤2 mm | 2–8 mm | >8 mm |
| Revolute origin/axis offset — doors | ≤5 mm | 5–8 mm | >8 mm |
| Joint limit error | ≤2° or ≤5% range | ≤5° or ≤10% | worse |
| Held-out state keypoint RMS — small | ≤2 mm | 2–10 mm | >10 mm |
| Held-out state keypoint RMS — SEM door | ≤5 mm | 5–10 mm | >10 mm |
| Minimum states for final joint | K≥4 | K=3 | K≤2 (coarse only) |

K=2 states: enough to hypothesize, not to ship. Require K≥4 or strong CAD/manual evidence for release.

### VLM affordance

| Gate | Threshold |
|---|---|
| JSON schema conformity after retry | 100% |
| First-pass schema conformity | ≥95% |
| Affordance references 3D segment + state image | 100% |
| Safety-critical human review sign-off | 100% |
| Cross-model disagreement on safety label | fail until resolved |

Use structured outputs via [kinematic-json-constrained-decode](../../25-affordance-vlm/kinematic-json-constrained-decode/SKILL.md). Never accept prose.

### Physics / contact

MuJoCo exposes `mjData.contact[i].dist` (negative = penetration) and `mj_geomDistance` (v3.1.6+). Genesis exposes `KinematicContactProbe` with penetration + force. SAPIEN exposes `scene.get_contacts()` with `separation` distance. Isaac Lab exposes contact-force sensors and solver residuals.

| Gate | MuJoCo | Isaac Lab | Genesis | SAPIEN |
|---|---|---|---|---|
| Import warnings | 0 critical | 0 critical | 0 critical | 0 critical |
| Initial interpenetration | <1 mm | <2 mm | <2 mm | <2 mm |
| Resting drift / 10 s | <1 mm, <1° | <2 mm, <2° | <2 mm, <2° | <2 mm, <2° |
| Passive joint energy drift / 10 s | <0.5% | <1% | <1% | <1% |
| Cross-engine endpoint disagreement | ≤5 mm | compare | compare | compare |
| NaNs / exploding velocities | 0 | 0 | 0 | 0 |

Known issue: `isaac-sim/IsaacSim#599` (Apr 2026) — URDF importer creates independent links instead of a chained articulation tree; Body0 points to root prim instead of prior link. Validate imported articulation structure explicitly before running physics gates. `isaac-sim/IsaacLab#2358` (Apr 2025) — PhysX silently adjusts joint frames when joint axis is not body-aligned with X/Y/Z; compare joint frames before and after import.

### VR rendering

| Platform | Minimum | Target |
|---|---|---|
| Quest 3 | 72 FPS | 90 FPS |
| Apple Vision Pro | 90 FPS | 90–100 FPS |
| Desktop tethered VR | 90 FPS | 120 FPS |
| Motion-to-photon latency | <25 ms standalone | <20 ms tethered |
| Quest visible triangles | <1.5M | lower with LOD |

## Metric APIs

| Tool | Install | Key call | Measures | License |
|---|---|---|---|---|
| lpips | `pip install lpips` | `lpips.LPIPS(net="alex")(img0, img1)` | Learned perceptual distance (AlexNet/VGG) | BSD-2-Clause |
| piqa | `pip install piqa` | `piqa.PSNR()`, `piqa.SSIM()`, `piqa.LPIPS()` | PSNR, SSIM, MS-SSIM, LPIPS, FID | MIT |
| DISTS | `pip install dists-pytorch` | `DISTS()(X, Y)` | Perceptual distance tolerating texture/mild geometry variation | MIT |
| pyfvvdp | `pip install pyfvvdp` | `pyfvvdp.fvvdp(...).predict(test, ref, dim_order="HWC")` | Full-reference perceptual image/video quality with display model | CC BY-NC 4.0 |
| skimage | `pip install scikit-image` | `peak_signal_noise_ratio`, `structural_similarity`, `hausdorff_distance` | PSNR, SSIM, image Hausdorff | BSD-3-Clause |
| torch-fidelity | `pip install torch-fidelity` | `calculate_metrics(input1=..., input2=..., fid=True, kid=True)` | FID, KID, ISC, precision/recall | Apache-2.0 |
| open3d | `pip install open3d` | `pcd1.compute_metrics(pcd2, [Metric.ChamferDistance, Metric.HausdorffDistance, Metric.FScore], params)` | Point-cloud Chamfer, Hausdorff, F-score | MIT |
| pytorch3d | source/version install | `chamfer_distance(pts_a, pts_b)` | Chamfer loss over point sets or sampled meshes | BSD |
| yourdfpy | `pip install yourdfpy` | `yourdfpy.URDF.load("robot.urdf")` | URDF load, validate, visualize | MIT |
| pinocchio | `conda install pinocchio -c conda-forge` | `pin.buildModelFromUrdf(...)`, `pin.forwardKinematics(...)` | Kinematics, dynamics, contacts | BSD-2-Clause |
| evo | `pip install evo` | `evo_ape`, `evo_rpe`, `evo_traj` | ATE/RPE for camera or end-effector trajectories | GPLv3 |

## qa_report.json schema

```json
{
  "twin_id": "sem_017",
  "build_version": "0.3.1",
  "validation_plan": "validation/validation_plan.yaml",
  "status": "validated | failed_validation | research_preview",
  "gates": {
    "capture": { "safety_state_present": "pass", "calibration_manifest": "pass" },
    "pose": { "registered_ratio": 0.91, "median_reproj_px": 0.62, "scale_drift_pct": 0.4, "status": "pass" },
    "rendering": { "psnr_db": 28.4, "ssim": 0.91, "lpips": 0.11, "status": "pass" },
    "surface": { "median_chamfer_mm": 0.42, "p95_chamfer_mm": 1.8, "watertight": true, "status": "pass" },
    "segmentation": { "foreground_assignment": 0.97, "miou": 0.78, "status": "pass" },
    "affordance": { "schema_conformity": 1.0, "safety_review": 1.0, "status": "pass" },
    "articulation": { "axis_error_deg": 1.7, "k_states_used": 5, "rms_mm": 1.4, "status": "pass" },
    "physics": { "interpenetration_mm": 0.3, "energy_drift_pct_10s": 0.4, "status": "pass" },
    "vr": { "quest3_fps": 75, "vision_pro_fps": 91, "status": "pass" }
  },
  "regression": { "vs_prev_tag": "v0.3.0", "psnr_delta_db": "+0.4", "axis_drift_deg": 0.1 },
  "human_review_sheet": "validation/human_review_sheet.csv",
  "generated_at": "2026-05-05T00:00:00Z"
}
```

## Common issues

| Symptom | Likely cause | Route to |
|---|---|---|
| Registered ratio 78% | Repetitive panels, low texture | hloc rescue in [estimating-sfm-camera-poses](../../23-3d-reconstruction/estimating-sfm-camera-poses/SKILL.md); else recapture |
| PSNR high, LPIPS bad | View-dependent reflections | [training-reflection-aware-splats](../../23-3d-reconstruction/training-reflection-aware-splats/SKILL.md) |
| Mesh has holes | Surface extraction weak on glossy | [extracting-gs-surfaces](../../23-3d-reconstruction/extracting-gs-surfaces/SKILL.md) (PGSR/2DGS) + [conditioning-collision-meshes](../../27-physics-simulation/conditioning-collision-meshes/SKILL.md) |
| mIoU 0.62 | Segmentation lift weak | [per-gaussian-saga](../../24-3d-segmentation-articulation/per-gaussian-saga/SKILL.md) |
| Affordance safety disagreement | VLM ambiguity | [vlm-physics-validation-loop](../../25-affordance-vlm/vlm-physics-validation-loop/SKILL.md); require human review |
| Joint axis 6° off | K too low or bad correspondences | [multistate-diff-open3d](../../24-3d-segmentation-articulation/multistate-diff-open3d/SKILL.md); recapture K≥5 |
| Isaac imports but links are independent | IsaacSim#599 URDF importer chain bug | Validate articulation tree post-import; check Body0 references |
| Joint frames shifted in Isaac | IsaacLab#2358 PhysX frame adjustment | Compare joint frames pre/post import; realign axis in URDF |
| URDF loads but jittery | Bad inertia / non-watertight collision | [conditioning-collision-meshes](../../27-physics-simulation/conditioning-collision-meshes/SKILL.md) |
| Cross-engine endpoint mismatch >5 mm | Joint frame mismatch URDF↔MJCF | [authoring-urdf-mjcf-usd](../../27-physics-simulation/authoring-urdf-mjcf-usd/SKILL.md) |
| Quest 3 FPS 55 | Too many Gaussians | [deploying-quest-spatial-splats](../../26-3d-rendering-vr/deploying-quest-spatial-splats/SKILL.md) — prune, LOD, bake |
| Regression snapshot joint-axis drift | Refit changed without justification | Inspect ARA log via [versioning-twins-with-ara](../versioning-twins-with-ara/SKILL.md) |

## References

### Published validation studies (2024–2026)

- Weng et al. "Neural Implicit Representation for Building Digital Twins of Unknown Articulated Objects" (DigitalTwinArt), CVPR 2024. Reports CD-w/CD-s/CD-m (mm, 10K points), axis angular error, axis position error, part-motion error.
- Guo et al. "ArticulatedGS: Building Controllable Articulated 3D Gaussians from Visual Data", CVPR 2025. PSNR 35–43 dB, SSIM 0.975–0.996, LPIPS 0.007–0.087 on PARIS dataset.
- Le et al. "Articulate-Anything: Automatic Modeling of Articulated Objects via a Vision-Language Foundation Model", ICLR 2025. Joint type/axis/origin/limits; success 75% at 50 mm / 0.25 rad thresholds on PartNet-Mobility (1.9K revolute + 7.6K prismatic joints).
- Li et al. "URDF-Anything: Zero-Shot Photorealistic Digital Twin Generation for Articulated Objects", NeurIPS 2025 spotlight. mIoU, joint errors, physical executability; 29% average joint-error reduction vs baselines.
- Yu et al. "Part2GS: Dynamic 3D Gaussian Splatting from Multi-Part Dynamics", arXiv Apr 2026. CD-static 0.56–1.18, CD-movable 0.07–1.95; PSNR 29.9–34.2, SSIM 0.944–0.979, LPIPS 0.033–0.064.

### Known real GitHub issues

- `isaac-sim/IsaacSim#599` (Apr 28, 2026): URDF importer creates independent links, not a chained tree; Body0 points to root prim.
- `isaac-sim/IsaacLab#2358` (Apr 23, 2025): PhysX silently adjusts joint frames when axis is not body-aligned with X/Y/Z.

### Deep reference files

- [references/validation-checklist.md](references/validation-checklist.md) — full checklist with reproduction commands
- [references/regression-strategy.md](references/regression-strategy.md) — snapshot diffing strategy across builds
