---
name: lab-equipment-twinning
description: Orchestrates the end-to-end build of a digital twin of laboratory equipment (SEM, optical microscope, optical bench) from handheld video capture to validated VR/simulator/agent-planning runtime. Routes an autonomous coding agent through capture planning, pose recovery, two-track visual+physics reconstruction, semantic segmentation lift, VLM-based affordance reasoning, articulation inference, URDF/MJCF/USD authoring, physics validation, ARA versioning, and VR deployment. Produces a canonical twin_package/ directory. Use when the deliverable is more than a render — when an interactive, inspectable, physics-validated twin is required for SOP rehearsal, onboarding VR walkthroughs, or LLM-agent experiment planning.
version: 2.0.0
author: Orchestra Research
license: MIT
tags: [Digital Twin, Lab Equipment, SEM, Microscope, Optical Bench, 3DGS, OpenUSD, URDF, MJCF, VR, SOP, Affordance, ARA, Orchestration]
---

# Lab Equipment Twinning

Thin orchestrator skill. An autonomous coding agent reads this first when asked to build a digital twin of laboratory equipment. This skill trains nothing, runs nothing, and authors no simulator files — it dispatches to executable sub-skills, gates each stage, and records provenance. Treat it as a router, a state machine, and a release-policy enforcer.

**You ROUTE — sub-skills EXECUTE.**

## Overview

This META skill coordinates a complete digital-twin build for laboratory equipment such as an SEM, optical microscope, or optical bench. The canonical architecture is a **two-track asset**: an *appearance track* (Gaussian splat or high-poly mesh for visual realism) and a *physics track* (explicitly authored links, joints, collision proxies, inertials for interaction and validation). Both tracks are registered into the same coordinate frame and packaged as OpenUSD with URDF/MJCF exports.

This split is fundamental. Gaussian splats are excellent visual representations but are not reliable collision or joint models. Physics and visual assets must remain independently authored, then composed. OpenUSD is the source of truth; URDF and MJCF are export targets.

The minimum viable shippable twin:

- Validated camera poses (≥85% registration, ≤2.0 px median reprojection error)
- Splat or mesh visual asset with measured scale (scale error ≤1%)
- Segmented parts with stable IDs and semantic mIoU ≥0.75
- Typed affordances bound to segments + image evidence (confidence ≥0.80)
- K-state articulation with joint axis error ≤3° for all task-critical joints
- URDF/MJCF/USD physics proxy with watertight collision geometry
- Machine-readable QA report, ARA evidence bundle, one runtime deployment target

Everything beyond that is polish.

## Pipeline Stages

End-to-end pipeline with dispatch boundaries. The orchestrator chooses sub-skills based on equipment class, K, reflective area, target runtime, and prior-stage gate results.

```
classify(user_goal, equipment_type, target_runtime, K)
        |
        v
0. CAPTURE PLANNING        -> 28/multi-state-capture-protocol
        |                     (K-state plan, scale refs, fiducials, safety state)
        v
1. VIDEO PREPROCESSING     -> 23/preprocessing-reconstruction-videos
        |                     (keyframe extraction, blur filter, undistortion, masking)
        v
2. POSE RECOVERY           -> 23/estimating-sfm-camera-poses
                              23/recovering-pose-free-geometry  (rescue: DUSt3R/VGGT/MASt3R init)
        |
        v
        +-- reflective area >10%? -> 23/training-reflection-aware-splats
        |
        v
3. VISUAL RECONSTRUCTION   -> 23/training-gaussian-splats
                              23/training-nerf-fallbacks  (if 3DGS fails metric gates)
        |
        v
4. SURFACE EXTRACTION      -> 23/extracting-gs-surfaces
                              27/conditioning-collision-meshes  (mesh repair, CoACD proxies)
        |
        v
5. SEGMENTATION + LIFT     -> 24/gsplat-scene-adapter
                              24/lift-2d-masks-ludvig
                              24/per-gaussian-saga
        |
        v
6. AFFORDANCE + JOINTS     -> 25/multiview-joint-cards-renderer
                              25/qwen3-vl-affordance-prompter
                              25/kinematic-json-constrained-decode
                              25/articulation-priors-retrieval
                              25/vlm-physics-validation-loop
                              24/articulation-ditto-prior
                              24/screwsplat-articulation
                              24/multistate-diff-open3d
        |
        v
7. PHYSICS AUTHORING       -> 27/authoring-urdf-mjcf-usd
                              27/conditioning-collision-meshes
        |
        v
8. VALIDATION              -> 28/validating-digital-twins
        |
        v
9. VERSIONING + ARA        -> 28/versioning-twins-with-ara
                              22/compiler, 22/research-manager, 22/rigor-reviewer
        |
        v
10. RUNTIME DEPLOYMENT     -> 28/simulating-experiment-runs-in-twins
                              26/compiling-splat-assets
                              26/publishing-supersplat-webxr
                              26/deploying-quest-spatial-splats
                              26/rendering-unity-splats
                              26/rendering-unreal-xscene-splats
                              27/simulating-mujoco-mjx
                              27/validating-isaac-sim-lab
                              27/prototyping-genesis-physics
                              27/validating-sapien-articulations
```

**Hard rule.** This skill must not implement any of the steps above. It calls them. If you find yourself writing a COLMAP command or a 3DGS config inline, stop and dispatch.

### Sibling sub-skills in this category

| Stage | Sub-skill | Responsibility |
|---|---|---|
| Capture | [multi-state-capture-protocol](../multi-state-capture-protocol/SKILL.md) | K-state physical capture protocol, calibration manifest, fiducials, lighting, safety state |
| Validation | [validating-digital-twins](../validating-digital-twins/SKILL.md) | Numerical QA gates, regression tests, build-failing CI |
| Versioning | [versioning-twins-with-ara](../versioning-twins-with-ara/SKILL.md) | OpenUSD packaging, ARA evidence bundle, lineage |
| Runtime | [simulating-experiment-runs-in-twins](../simulating-experiment-runs-in-twins/SKILL.md) | VR walkthrough, SOP rehearsal, agent planning environment |

### Canonical twin_package/ tree

```
twin_package/
  twin_manifest.yaml             # single entrypoint for agents
  twin.lock.json                 # frozen hashes, versions, gate results
  metadata/
    equipment_profile.yaml
    safety_state.yaml
    coordinate_frames.yaml
    units_and_scale.yaml
    target_use_case.yaml
    dispatch_trace.jsonl
  capture/                       # produced by multi-state-capture-protocol
    capture_plan.yaml
    k_state_plan.yaml
    calibration/
    raw/
    logs/
  reconstruction/                # produced by 23 + 27 sub-skills
    poses/{colmap,glomap,hloc,selected_pose_graph.json}
    splats/{baseline_3dgs,reflective_branch,selected}
    surfaces/{meshes_raw,meshes_repaired,watertight,collision}
    scale_alignment/
  semantics/                     # produced by 24 + 25 sub-skills
    2d_masks/
    3d_masks/
    gaussian_groups/
    affordances.json
    labels/{controls,hazards,consumables,access_panels,optics,stages}.yaml
  articulation/                  # produced by 24 + 25 sub-skills
    state_correspondences/
    joint_hypotheses.json
    urdf/equipment.urdf
    mjcf/equipment.xml
    usd/equipment_articulated.usda
  simulation/                    # produced by simulating-experiment-runs-in-twins
    usd/root.usda
    mujoco/equipment.xml
    isaac_lab/scene.py
    genesis/scene.py
    sapien/scene.py
    unity/Assets/
    webxr/index.html
    agent_env/{gymnasium_wrapper.py,action_schema.json,safety_constraints.yaml}
  validation/                    # produced by validating-digital-twins
    validation_plan.yaml
    gate_results.json
    metrics_summary.md
    regression_snapshots/
    failed_gates/
  ara/                           # produced by versioning-twins-with-ara
    evidence_bundle.json
    provenance.ttl
    claims.yaml
    reproducibility/{environment.yml,containers.lock,command_log.sh,data_hashes.json}
  release/
    twin_package_vMAJOR.MINOR.PATCH.tar.zst
    root.usdz
    root.usdc
    thumbnail.png
    changelog.md
    known_limitations.md
```

OpenUSD (v26.x as of 2026) is the source of truth; USDZ is for sealed delivery to visionOS only. URDF and MJCF are export targets. Gaussian splats are stored as visual payloads or USD light-field layers, not the sole authoritative asset.

## Common Workflows

Three end-to-end runs. Each step references a concrete sub-skill — never inline a tool command.

### Workflow A — Onboarding VR walkthrough of an optical microscope

Goal: visual-and-semantic twin for new-student onboarding, one day on a single A100. Target runtime: Quest 3 or WebXR. Default K=1 static; K=3 if turret/stage controls must animate.

- [ ] A1. Create `twin_package/metadata/equipment_profile.yaml` (`equipment_type: optical_microscope`)
- [ ] A2. Run [multi-state-capture-protocol](../multi-state-capture-protocol/SKILL.md) → `capture_plan.yaml` approved with scale references (calibration target or known objective diameter)
- [ ] A3. Record safe state in `metadata/safety_state.yaml`
- [ ] A4. Use K=1 unless turret/condenser/camera-port/stage controls must animate
- [ ] A5. Run [preprocessing-reconstruction-videos](../../23-3d-reconstruction/preprocessing-reconstruction-videos/SKILL.md) → sharp calibrated keyframes, masks for hands/backgrounds
- [ ] A6. Run [estimating-sfm-camera-poses](../../23-3d-reconstruction/estimating-sfm-camera-poses/SKILL.md) → registration ≥85%, reprojection ≤2.0 px; scale aligned via AprilTag/calibration target
- [ ] A7. If glossy metal/glass area >10%, branch to [training-reflection-aware-splats](../../23-3d-reconstruction/training-reflection-aware-splats/SKILL.md)
- [ ] A8. Run [training-gaussian-splats](../../23-3d-reconstruction/training-gaussian-splats/SKILL.md) → held-out PSNR ≥26 dB, SSIM ≥0.80
- [ ] A9. If VR collision/labels need mesh, run [extracting-gs-surfaces](../../23-3d-reconstruction/extracting-gs-surfaces/SKILL.md) → per-class Chamfer gates pass
- [ ] A10. Run [lift-2d-masks-ludvig](../../24-3d-segmentation-articulation/lift-2d-masks-ludvig/SKILL.md) for text-queryable labels
- [ ] A11. Run [gsplat-scene-adapter](../../24-3d-segmentation-articulation/gsplat-scene-adapter/SKILL.md) for eyepiece/objective/stage/knob separation → semantic mIoU ≥0.75
- [ ] A12. Run [qwen3-vl-affordance-prompter](../../25-affordance-vlm/qwen3-vl-affordance-prompter/SKILL.md) → `affordances.json` with `look_through`, `adjust_focus`, `move_stage`, `do_not_touch_lens`
- [ ] A13. Skip articulation priors unless K≥2 and animation requested
- [ ] A14. Author simplified physics proxy via [authoring-urdf-mjcf-usd](../../27-physics-simulation/authoring-urdf-mjcf-usd/SKILL.md) (static body + any animated joints)
- [ ] A15. Run [validating-digital-twins](../validating-digital-twins/SKILL.md) → all Workflow A gates pass
- [ ] A16. Run [compiling-splat-assets](../../26-3d-rendering-vr/compiling-splat-assets/SKILL.md) then [publishing-supersplat-webxr](../../26-3d-rendering-vr/publishing-supersplat-webxr/SKILL.md) or [deploying-quest-spatial-splats](../../26-3d-rendering-vr/deploying-quest-spatial-splats/SKILL.md)
- [ ] A17. Quest 3 FPS ≥72 (route FPS failures back to splat optimization / LOD)
- [ ] A18. Run [versioning-twins-with-ara](../versioning-twins-with-ara/SKILL.md) → ARA bundle complete
- [ ] A19. Export `release/root.usdz`, `release/root.usdc`, `release/thumbnail.png`
- [ ] A20. Write `release/known_limitations.md` (especially lens/glass limitations)

Workflow A minimum release gates:

| Gate | Threshold |
|---|---|
| Pose registration | ≥85% |
| Held-out PSNR | ≥26 dB |
| Microscope body Chamfer | ≤2.0 mm |
| Objective/turret Chamfer | ≤1.0 mm |
| Fine focus knob Chamfer | ≤1.0 mm |
| Affordance confidence | ≥0.80 |
| Quest 3 FPS | ≥72 |
| Vision Pro FPS | ≥90 |

### Workflow B — SOP rehearsal twin of an SEM

Goal: 2–3 day full pipeline producing an SEM SOP rehearsal environment. Target runtime: Unity or Vision Pro for walkthrough; MuJoCo or Isaac Lab for procedural rehearsal. K=5 minimum for chamber door + sample stage.

Critical stance: never release an SEM SOP twin without safety state, hazard affordances, validation report, and ARA evidence. The SEM interior (vacuum column, electron optics, HV) cannot be inferred from handheld RGB — treat as metadata or separate CAD-authored asset.

- [ ] B1. Create `equipment_profile.yaml` (`equipment_type: SEM`)
- [ ] B2. Run [research-manager](../../22-agent-native-research-artifact/research-manager/SKILL.md) to scope SOP, equipment boundaries, evidence plan
- [ ] B3. Run [multi-state-capture-protocol](../multi-state-capture-protocol/SKILL.md); write `metadata/safety_state.yaml` before capture begins
- [ ] B4. Safety gate: confirm powered/standby state, chamber state, vacuum/HV exclusion zones documented
- [ ] B5. Place fiducials on non-critical exterior surfaces only; never inside vacuum or on safety-critical surfaces without facility approval
- [ ] B6. Capture K=5: closed, partially open, open, stage-access, operator-view/control-panel; capture HDR/polarized pairs for glossy panels, viewport glass, metal handles
- [ ] B7. Run [preprocessing-reconstruction-videos](../../23-3d-reconstruction/preprocessing-reconstruction-videos/SKILL.md) → calibrated keyframes, background/hand masks
- [ ] B8. Run [estimating-sfm-camera-poses](../../23-3d-reconstruction/estimating-sfm-camera-poses/SKILL.md); if low texture, route to hloc rescue inside that skill
- [ ] B9. If pose registration <85%, fall back to [recovering-pose-free-geometry](../../23-3d-reconstruction/recovering-pose-free-geometry/SKILL.md) (DUSt3R/VGGT/MASt3R initialization, then bundle-adjust)
- [ ] B10. If reflective area >10%, run [training-reflection-aware-splats](../../23-3d-reconstruction/training-reflection-aware-splats/SKILL.md)
- [ ] B11. Run [training-gaussian-splats](../../23-3d-reconstruction/training-gaussian-splats/SKILL.md) → held-out PSNR ≥26 dB
- [ ] B12. Run [extracting-gs-surfaces](../../23-3d-reconstruction/extracting-gs-surfaces/SKILL.md) for chamber/door/stage/console visual meshes → per-class Chamfer passes
- [ ] B13. Run [conditioning-collision-meshes](../../27-physics-simulation/conditioning-collision-meshes/SKILL.md) → watertight CoACD collision proxies for all physics links
- [ ] B14. Run [gsplat-scene-adapter](../../24-3d-segmentation-articulation/gsplat-scene-adapter/SKILL.md) for chamber/door/handle/stage/detector/console regions → mIoU ≥0.75
- [ ] B15. Run [lift-2d-masks-ludvig](../../24-3d-segmentation-articulation/lift-2d-masks-ludvig/SKILL.md) for natural-language queries → query QA ≥0.80
- [ ] B16. Run [multiview-joint-cards-renderer](../../25-affordance-vlm/multiview-joint-cards-renderer/SKILL.md) to build VLM joint-evidence cards
- [ ] B17. Run [qwen3-vl-affordance-prompter](../../25-affordance-vlm/qwen3-vl-affordance-prompter/SKILL.md) and [kinematic-json-constrained-decode](../../25-affordance-vlm/kinematic-json-constrained-decode/SKILL.md) → `affordances.json` including `open_chamber`, `insert_sample_stub`, `adjust_stage`, `do_not_touch_detector`, `forbidden_hv_region`
- [ ] B18. Run [articulation-priors-retrieval](../../25-affordance-vlm/articulation-priors-retrieval/SKILL.md) for SEM-class mechanical priors (chamber door = revolute, stage = prismatic XY+Z)
- [ ] B19. Run [articulation-ditto-prior](../../24-3d-segmentation-articulation/articulation-ditto-prior/SKILL.md) and/or [screwsplat-articulation](../../24-3d-segmentation-articulation/screwsplat-articulation/SKILL.md) for chamber door joint axis → axis error ≤3°; treat outputs as proposals, not final truth — manually verify mechanical constraints
- [ ] B20. Run [multistate-diff-open3d](../../24-3d-segmentation-articulation/multistate-diff-open3d/SKILL.md) for state-correspondence sanity
- [ ] B21. Run [vlm-physics-validation-loop](../../25-affordance-vlm/vlm-physics-validation-loop/SKILL.md) to reject hallucinated affordances; require hazard-label completeness = 100%
- [ ] B22. Export `articulation/urdf/equipment.urdf` and `articulation/mjcf/equipment.xml` via [authoring-urdf-mjcf-usd](../../27-physics-simulation/authoring-urdf-mjcf-usd/SKILL.md)
- [ ] B23. Run [simulating-mujoco-mjx](../../27-physics-simulation/simulating-mujoco-mjx/SKILL.md) for chamber-door + stage motion → physics sanity passes
- [ ] B24. Run [simulating-experiment-runs-in-twins](../simulating-experiment-runs-in-twins/SKILL.md) for SOP rehearsal build (Unity / Vision Pro)
- [ ] B25. Run [validating-digital-twins](../validating-digital-twins/SKILL.md) → all SEM gates pass
- [ ] B26. Run [rigor-reviewer](../../22-agent-native-research-artifact/rigor-reviewer/SKILL.md) for claims and limitations
- [ ] B27. Run [compiler](../../22-agent-native-research-artifact/compiler/SKILL.md) for ARA evidence bundle
- [ ] B28. Run [versioning-twins-with-ara](../versioning-twins-with-ara/SKILL.md) → release version created
- [ ] B29. Export `release/root.usdz`, `release/root.usdc`, `release/changelog.md`
- [ ] B30. Freeze `twin.lock.json` and write `known_limitations.md` (including: interior column/optics not reconstructed from video; glass/reflective geometry is visual-only)

Workflow B minimum release gates:

| Gate | Threshold |
|---|---|
| Pose registration | ≥85% |
| Held-out PSNR | ≥26 dB |
| SEM outer panel Chamfer | ≤2.0 mm |
| Chamber door Chamfer | ≤1.5 mm |
| Sample stage Chamfer | ≤0.75 mm |
| Handle/control Chamfer | ≤1.0 mm |
| Joint axis error | ≤3° |
| Joint range coverage | ≥80% of SOP range |
| Hazard-label completeness | 100% |
| Quest 3 / Vision Pro FPS | ≥72 / ≥90 |

### Workflow C — Optical-bench planning environment for an LLM agent

Goal: validated, coordinate-aware environment where an LLM agent can plan optical-bench component placements and rehearse actions. Target runtime: USD scene plus MuJoCo/Isaac Lab/Genesis. K=1 static; K≥5 if rails/sliders/lens-mounts/shutters move. Coordinate-frame correctness matters more than photorealism — use known rail spacing for scale, not generic fiducials.

- [ ] C1. Create `equipment_profile.yaml` (`equipment_type: optical_bench`)
- [ ] C2. Define `coordinate_frames.yaml` (world, bench, optical_axis, rail, component frames); lock units in `units_and_scale.yaml`
- [ ] C3. Run [multi-state-capture-protocol](../multi-state-capture-protocol/SKILL.md) — capture scale bars, rail markings, posts, lens mounts, mirrors, screens, detectors
- [ ] C4. If mirrors/polished optics >10% visible area, capture HDR/polarized pairs
- [ ] C5. Run [preprocessing-reconstruction-videos](../../23-3d-reconstruction/preprocessing-reconstruction-videos/SKILL.md) → calibrated keyframes
- [ ] C6. Run [estimating-sfm-camera-poses](../../23-3d-reconstruction/estimating-sfm-camera-poses/SKILL.md) → registration ≥85%, scale aligned to known rail spacing (error ≤1%)
- [ ] C7. Run [training-gaussian-splats](../../23-3d-reconstruction/training-gaussian-splats/SKILL.md) → PSNR ≥26 dB; if mirrors dominate, run [training-reflection-aware-splats](../../23-3d-reconstruction/training-reflection-aware-splats/SKILL.md)
- [ ] C8. Run [extracting-gs-surfaces](../../23-3d-reconstruction/extracting-gs-surfaces/SKILL.md) for rails, mounts, posts, screens → Chamfer gates pass; replace thin posts with CAD cylinders if mesh extraction fails on small geometry
- [ ] C9. Run [gsplat-scene-adapter](../../24-3d-segmentation-articulation/gsplat-scene-adapter/SKILL.md) for separable rail components
- [ ] C10. Run [lift-2d-masks-ludvig](../../24-3d-segmentation-articulation/lift-2d-masks-ludvig/SKILL.md) for commands like "move lens after mirror M2"
- [ ] C11. Run [per-gaussian-saga](../../24-3d-segmentation-articulation/per-gaussian-saga/SKILL.md) for promptable component correction of small mounts
- [ ] C12. Run [qwen3-vl-affordance-prompter](../../25-affordance-vlm/qwen3-vl-affordance-prompter/SKILL.md) → `affordances.json` with movable mounts, forbidden beam paths, optics, clamps, rail slots
- [ ] C13. If rail sliders move, run [articulation-ditto-prior](../../24-3d-segmentation-articulation/articulation-ditto-prior/SKILL.md) or manual prismatic fitting → axis error ≤3°; model sliders as prismatic joints on rail axis
- [ ] C14. Run [authoring-urdf-mjcf-usd](../../27-physics-simulation/authoring-urdf-mjcf-usd/SKILL.md) to export prismatic rail joints; model optical paths as metadata, not geometry
- [ ] C15. Run [validating-isaac-sim-lab](../../27-physics-simulation/validating-isaac-sim-lab/SKILL.md) if robotics integration is required
- [ ] C16. Run [prototyping-genesis-physics](../../27-physics-simulation/prototyping-genesis-physics/SKILL.md) for fast planner experiments
- [ ] C17. Run [simulating-experiment-runs-in-twins](../simulating-experiment-runs-in-twins/SKILL.md) — build `simulation/agent_env/action_schema.json` and `safety_constraints.yaml` (beam, collision, forbidden-touch)
- [ ] C18. Run [validating-digital-twins](../validating-digital-twins/SKILL.md) → agent-env gates pass; planner regression tests pass
- [ ] C19. Run [versioning-twins-with-ara](../versioning-twins-with-ara/SKILL.md) → ARA bundle complete
- [ ] C20. Export `simulation/agent_env/gymnasium_wrapper.py` plus regression tests

Workflow C minimum release gates:

| Gate | Threshold |
|---|---|
| Pose registration | ≥85% |
| Scale error | ≤1% |
| Optical-rail/frame alignment | ≤1.0 mm or ≤0.25° |
| Rail / optic-mount Chamfer | ≤0.75 mm |
| Lens/mirror visual Chamfer | ≤0.5 mm if used for planning |
| Joint axis error | ≤3° |
| Action schema validation | 100% |
| Safety-constraint validation | 100% |
| Agent regression tests | 100% required tests pass |

## When to Use

```
IF user_goal is "pretty novel-view render only":
  bypass this meta-skill; call 23/training-gaussian-splats directly.

IF user_goal includes SOP rehearsal, VR walkthrough, robot planning,
   semantic controls, hazards, affordances, or articulation:
  use this meta-skill.

IF equipment_type is SEM:
  require safety_state.yaml before reconstruction.
  require K-state capture for chamber/door/stage if SOP includes chamber access.
  require forbidden-region affordances for beam column, vacuum, HV, sample stage.
  note: SEM interior column/optics cannot be inferred from handheld RGB —
        treat as metadata or separately authored CAD asset.

IF equipment_type is optical_microscope:
  prefer K=1 for onboarding walkthrough.
  require K>=2 only if knobs, condenser, stage, turret, or camera port animate.
  joint model: turret = revolute with discrete stops; stage = prismatic XY+Z;
  focus knob = revolute or screw-coupled to Z; condenser = prismatic/revolute.

IF equipment_type is optical_bench:
  require coordinate_frames.yaml.
  require known rail spacing or scale bars (error ≤1%).
  model sliders as prismatic joints on rail axis.
  require agent_env/action_schema.json if LLM-agent planning is requested.
  optical paths are metadata — not geometry.

IF target_runtime includes Quest3:
  require VR FPS >= 72; route FPS failures to 26/deploying-quest-spatial-splats.

IF target_runtime includes VisionPro:
  require VR FPS >= 90; route to 26/rendering-unity-splats or visionOS path.

IF reflective_surface_area > 10%:
  branch to 23/training-reflection-aware-splats; require polarized_pairs/ in capture.

IF transparent_or_glass_surface_area > 5%:
  mark geometry as visual-only; require manual QA masks; never claim glass collision
  accuracy unless mesh QA passes.

IF pose_registration < 85%:
  invoke pose-recovery rescue ladder inside 23/estimating-sfm-camera-poses.
  if still <85%, try DUSt3R/VGGT initialization in 23/recovering-pose-free-geometry.
  if still <85%, return to multi-state-capture-protocol.

IF moving_parts_count > 0 and K < 2:
  fail capture gate; recapture with at least two endpoint states per joint.

IF articulated joint has K=2 only:
  allow only if axis error <= 3 deg AND range coverage >= 80%; else recapture K>=5.

IF affordance_confidence < 0.80 OR hazard labels missing:
  re-run VLM affordance loop; do NOT release SOP environment.

IF articulation reconstruction auto-method produces axis error > 3°:
  treat output as proposal only; manually verify mechanical constraints;
  recapture endpoint + midpoint states with temporary markers.

IF any release gate fails:
  do NOT run versioning as a release; mark as "research_preview" or "failed_validation".
```

**Opinionated release policy.** Do not call a twin "validated" unless: (1) safety state captured; (2) pose registration ≥85%; (3) held-out PSNR ≥26 dB; (4) per-class Chamfer gates pass; (5) required affordances + hazards labeled; (6) joint axis error ≤3° for all task-critical joints; (7) target runtime FPS gate passes; (8) ARA evidence bundle exists; (9) known limitations explicit in `known_limitations.md`. Any gate fails → release status = `failed_validation` or `research_preview`.

## Common Issues

| Agent observes | Likely cause | Route to | Fix |
|---|---|---|---|
| SEM side panel fails registration | Low texture, repetitive geometry | hloc rescue in [estimating-sfm-camera-poses](../../23-3d-reconstruction/estimating-sfm-camera-poses/SKILL.md) | Add fiducials, oblique views, retrieval+LightGlue/LoFTR |
| SEM glossy chamber looks warped | Specular reflections | [training-reflection-aware-splats](../../23-3d-reconstruction/training-reflection-aware-splats/SKILL.md) | Switch to reflective branch when area >10% |
| Microscope eyepiece glass floats | Transparent optics | [validating-digital-twins](../validating-digital-twins/SKILL.md) | Mark visual-only; never use for collision |
| Articulated chamber door K=2 unstable | Too few states | [multi-state-capture-protocol](../multi-state-capture-protocol/SKILL.md) | Recapture K≥5; add markers to moving parts |
| Joint axis error >3° | Bad state correspondence or auto-method unreliable | [articulation-ditto-prior](../../24-3d-segmentation-articulation/articulation-ditto-prior/SKILL.md) + [multistate-diff-open3d](../../24-3d-segmentation-articulation/multistate-diff-open3d/SKILL.md) | Refit; manually verify mechanical constraints; add midpoint state |
| Knobs fused into front panel | Segmentation lift weak | [per-gaussian-saga](../../24-3d-segmentation-articulation/per-gaussian-saga/SKILL.md) | Promptable correction; capture knob in isolation |
| Optical-rail scale off | Missing/weak scale references | [multi-state-capture-protocol](../multi-state-capture-protocol/SKILL.md) | Add rail markings + calibration target with known spacing |
| Surface mesh has holes | 3DGS-to-mesh extraction weak on thin/glossy parts | [extracting-gs-surfaces](../../23-3d-reconstruction/extracting-gs-surfaces/SKILL.md) + [conditioning-collision-meshes](../../27-physics-simulation/conditioning-collision-meshes/SKILL.md) | Try 2DGS/PGSR; replace thin posts with CAD primitives |
| Collision sim explodes | Non-watertight or thin mesh | [conditioning-collision-meshes](../../27-physics-simulation/conditioning-collision-meshes/SKILL.md) | Replace with CoACD convex proxies or simplified primitives |
| URDF parts rotate incorrectly | Joint frame mismatch | [authoring-urdf-mjcf-usd](../../27-physics-simulation/authoring-urdf-mjcf-usd/SKILL.md) | Reconcile coordinate frames and units |
| MJCF scale wrong | Units mismatch | [validating-digital-twins](../validating-digital-twins/SKILL.md) | Check `units_and_scale.yaml`; validate each joint in isolation |
| VR FPS too low after splat import | Too many Gaussians | [deploying-quest-spatial-splats](../../26-3d-rendering-vr/deploying-quest-spatial-splats/SKILL.md) | Prune splats; bake LODs; use invisible simplified colliders |
| Vision Pro stutters | Heavy scene / bad LOD | [rendering-unity-splats](../../26-3d-rendering-vr/rendering-unity-splats/SKILL.md) | Split USD payloads; foveated rendering |
| Affordance labels omit hazards | VLM under-specified | [vlm-physics-validation-loop](../../25-affordance-vlm/vlm-physics-validation-loop/SKILL.md) | Require hazard taxonomy review; never release SOP without 100% hazard labels |
| ARA bundle missing commands | Provenance not recorded | [versioning-twins-with-ara](../versioning-twins-with-ara/SKILL.md) | Rebuild command log + data hashes |
| User wants single .splat file | Scope too small for meta | [training-gaussian-splats](../../23-3d-reconstruction/training-gaussian-splats/SKILL.md) | Bypass this meta-skill |
| Auto-articulation method unreliable | Research-grade tool, not production-stable | manual rig + [authoring-urdf-mjcf-usd](../../27-physics-simulation/authoring-urdf-mjcf-usd/SKILL.md) | Use auto output as proposal; manually verify axes, limits, coupling |

## Advanced Topics

- **Dispatch state machine and trace events**: see [references/dispatch-trace.md](references/dispatch-trace.md)
- **Reconstruction routing (reflective, transparent, low-texture branches)**: see [references/reconstruction-routing.md](references/reconstruction-routing.md)
- **Use-case deliverables (VR onboarding, SOP rehearsal, agent planning)**: see [references/use-case-deliverables.md](references/use-case-deliverables.md)

## Resources

### Sub-skills in 28-digital-twin-workflows

- [multi-state-capture-protocol](../multi-state-capture-protocol/SKILL.md)
- [validating-digital-twins](../validating-digital-twins/SKILL.md)
- [versioning-twins-with-ara](../versioning-twins-with-ara/SKILL.md)
- [simulating-experiment-runs-in-twins](../simulating-experiment-runs-in-twins/SKILL.md)

### Cross-category routes

- 22 ARA: [compiler](../../22-agent-native-research-artifact/compiler/SKILL.md), [research-manager](../../22-agent-native-research-artifact/research-manager/SKILL.md), [rigor-reviewer](../../22-agent-native-research-artifact/rigor-reviewer/SKILL.md)
- 23 reconstruction: [preprocessing-reconstruction-videos](../../23-3d-reconstruction/preprocessing-reconstruction-videos/SKILL.md), [estimating-sfm-camera-poses](../../23-3d-reconstruction/estimating-sfm-camera-poses/SKILL.md), [recovering-pose-free-geometry](../../23-3d-reconstruction/recovering-pose-free-geometry/SKILL.md), [training-gaussian-splats](../../23-3d-reconstruction/training-gaussian-splats/SKILL.md), [training-reflection-aware-splats](../../23-3d-reconstruction/training-reflection-aware-splats/SKILL.md), [extracting-gs-surfaces](../../23-3d-reconstruction/extracting-gs-surfaces/SKILL.md), [training-nerf-fallbacks](../../23-3d-reconstruction/training-nerf-fallbacks/SKILL.md)
- 24 segmentation/articulation: [gsplat-scene-adapter](../../24-3d-segmentation-articulation/gsplat-scene-adapter/SKILL.md), [lift-2d-masks-ludvig](../../24-3d-segmentation-articulation/lift-2d-masks-ludvig/SKILL.md), [per-gaussian-saga](../../24-3d-segmentation-articulation/per-gaussian-saga/SKILL.md), [multistate-diff-open3d](../../24-3d-segmentation-articulation/multistate-diff-open3d/SKILL.md), [articulation-ditto-prior](../../24-3d-segmentation-articulation/articulation-ditto-prior/SKILL.md), [screwsplat-articulation](../../24-3d-segmentation-articulation/screwsplat-articulation/SKILL.md)
- 25 affordance VLM: [articulation-priors-retrieval](../../25-affordance-vlm/articulation-priors-retrieval/SKILL.md), [kinematic-json-constrained-decode](../../25-affordance-vlm/kinematic-json-constrained-decode/SKILL.md), [multiview-joint-cards-renderer](../../25-affordance-vlm/multiview-joint-cards-renderer/SKILL.md), [qwen3-vl-affordance-prompter](../../25-affordance-vlm/qwen3-vl-affordance-prompter/SKILL.md), [vlm-physics-validation-loop](../../25-affordance-vlm/vlm-physics-validation-loop/SKILL.md)
- 26 rendering/VR: [compiling-splat-assets](../../26-3d-rendering-vr/compiling-splat-assets/SKILL.md), [publishing-supersplat-webxr](../../26-3d-rendering-vr/publishing-supersplat-webxr/SKILL.md), [deploying-quest-spatial-splats](../../26-3d-rendering-vr/deploying-quest-spatial-splats/SKILL.md), [rendering-unity-splats](../../26-3d-rendering-vr/rendering-unity-splats/SKILL.md), [rendering-unreal-xscene-splats](../../26-3d-rendering-vr/rendering-unreal-xscene-splats/SKILL.md), [editing-supersplat-scenes](../../26-3d-rendering-vr/editing-supersplat-scenes/SKILL.md)
- 27 physics: [authoring-urdf-mjcf-usd](../../27-physics-simulation/authoring-urdf-mjcf-usd/SKILL.md), [conditioning-collision-meshes](../../27-physics-simulation/conditioning-collision-meshes/SKILL.md), [simulating-mujoco-mjx](../../27-physics-simulation/simulating-mujoco-mjx/SKILL.md), [validating-isaac-sim-lab](../../27-physics-simulation/validating-isaac-sim-lab/SKILL.md), [prototyping-genesis-physics](../../27-physics-simulation/prototyping-genesis-physics/SKILL.md), [validating-sapien-articulations](../../27-physics-simulation/validating-sapien-articulations/SKILL.md), [calibrating-sysid-rl-hooks](../../27-physics-simulation/calibrating-sysid-rl-hooks/SKILL.md)

### External anchors

- OpenUSD v26.x (Pixar / AOUSD) — canonical scene packaging, composition, variants, USDPhysics schemas
- ROS URDF, MuJoCo MJCF — robot/simulator export grammars
- 3D Gaussian Splatting (Kerbl et al., 2023) + gsplat library — visual reconstruction backbone
- SuGaR, 2DGS, PGSR — surface extraction from Gaussian splats
- Ref-Gaussian, SpecTRe-GS — reflection-aware splat variants
- SAM2, Grounded-SAM2 — 2D mask generation for segmentation lift
- LangSplat/LangSplatV2, Gaussian Grouping, SAGA — 3D semantic segmentation lifting
- PARIS, Ditto, ArtGS, REArtGS, ScrewSplat — articulated reconstruction (use as proposals; manually verify)
- CoACD — collision-aware approximate convex decomposition for physics proxies
- MuJoCo/MJX, Isaac Sim / USDPhysics — physics validation backends
- COLMAP, GLOMAP, hloc + LightGlue/LoFTR — pose recovery ladder
- DUSt3R, MASt3R, VGGT — feed-forward geometry priors for pose rescue
- Unity Gaussian Splatting (Aras-P forks), Unreal/Cesium 3D Tiles GS — VR deployment targets
- Apple Vision Pro, Meta Quest performance docs — VR FPS budgets
