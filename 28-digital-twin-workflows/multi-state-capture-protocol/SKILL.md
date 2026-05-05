---
name: multi-state-capture-protocol
description: 'META skill: produces an executable K-state photo/video capture protocol for articulated lab-equipment digital twins (SEM, optical bench, microscope). Given equipment_class, articulation states, safety constraints, and target tolerances, emits capture_plan.yaml, state_registry.yaml, calibration manifests, operator checklists, shot lists, and provenance sidecars. Invoked by the lab-equipment-twinning orchestrator before any reconstruction begins; does not run COLMAP, NeRF, or 3DGS — it produces the protocol that makes those downstream steps reliable.'
version: 2.0.0
author: Orchestra Research
license: MIT
tags: [Digital Twin, Capture Protocol, K-State, SEM, Microscope, Optical Bench, Calibration, AprilTag, ChArUco, Fiducials, Safety State, Provenance, RO-Crate]
---

# Multi-State Capture Protocol

META skill for cat 28. The orchestrator invokes this BEFORE any reconstruction. Output is a written, deterministic protocol that an operator or robot executes. It encodes the K-state articulation plan, per-state view counts, lighting/exposure rules, calibration manifests, fiducial layouts, provenance sidecar schema, and verified safety state.

You PLAN — skills in [23-3d-reconstruction](../../23-3d-reconstruction/) execute reconstruction afterward.

## Overview

Each articulation state (door open/closed, knob 0°/90°, button on/off) is treated as an independent static capture set. Mixing states inside one SfM run produces hallucinated or incorrectly-merged geometry. The outputs of this skill are consumed directly by [multistate-diff-open3d](../../24-3d-segmentation-articulation/multistate-diff-open3d/SKILL.md) in cat 24, which requires clean, per-state reconstruction inputs.

Artifact tree produced under `twin_package/capture/`:

```
capture/
  capture_plan.yaml
  state_registry.yaml
  calibration/
    cameras.yaml
    lens_intrinsics.json
    checkerboard_report.json
    color_chart_report.json
    scale_bars.json
    fiducial_map.yaml
  operator_checklist.md
  shot_list.csv
  fiducial_layout.pdf
  provenance/
    capture_sidecar.yaml      # project-local sidecar (ARA L2 input)
    ro-crate-metadata.json    # RO-Crate research-object package
    sha256_manifest.txt
    exiftool.json
  logs/
    capture_session.jsonl
    rejected_frames.csv
    lighting_notes.md
  safety_photos/              # one photo per state proving safe condition
```

## K-State Policy (2026)

| Equipment / articulation | Hypothesis K | Ship-ready K |
|---|---|---|
| Rigid object only | K=1 | K=1 + closeups |
| Binary latch (two hard stops) | K=2 | K=2 |
| Single revolute or prismatic joint | K=3 | K=5 (0/25/50/75/100% travel) |
| Knob with N detents | K=N | K=N |
| Microscope objective turret | one per objective | one per objective |
| Screw / helical joint | K=5 | K=7–9 |
| Coupled multi-joint (D DoF) | K=1+2D | K=1+5D + interaction + return-home |
| Optical stage travel (X, Y, Z) | K=3 per axis | K=5 per axis + return home |

**Hard rule**: K=2 is hypothesis only, not ship-ready, unless the mechanism is provably binary. Include intermediate angles for any joint used in robotic planning or simulation — ScrewSplat (2025) demonstrates that intermediate-angle rendering requires explicit capture at those angles.

**Minimum spacing**: revolute ≥30° between states; prismatic ≥20% travel or ≥10 mm.

## Capture Phases — Per-State Checklist

Run this checklist independently for **each** articulation state. Keep separate folders: `footage/closed/`, `footage/open_90/`, `footage/angle_45/`.

**Phase 0 — Safety lock-out**
- [ ] Write `safety_state.yaml`: all energy sources off or positively isolated; beam off/blanked (SEM); laser shutter closed + key removed (optical bench); stage at safe Z; no interlocks bypassed
- [ ] Photograph safety-state placard; store in `safety_photos/<state_id>.jpg`
- [ ] Block capture if `safety_state.status != "pass"`

**Phase 1 — Intrinsics and lighting setup (once per session)**
- [ ] Camera intrinsics calibrated on OpenCV ChArUco board; save `calibration/cameras.yaml` + SHA-256
- [ ] Lock exposure (ISO, shutter, aperture), white balance (Kelvin value), focus, focal length; record all values in `capture_plan.yaml`
- [ ] Set artificial diffuse lighting (5600 K softboxes); tape or mark fixture positions on floor; disable auto-HDR, variable frame-rate, night mode
- [ ] For glass/mirror surfaces: add cross-polarized diffuser; log polarizer orientation
- [ ] Photograph gray card and color chart at start; log `color_chart_report.json`

**Phase 2 — Fiducial deployment**
- [ ] Place `tagStandard41h12` or `tag36h11` AprilTags on fixed, non-articulating surfaces at ≥120° spacing across ≥2 elevation bands
- [ ] Measure each tag with calibrated caliper at 4 points; record `printed_mm`, `measurement_convention: outside_edge_of_inner_black_border`, caliper ID, certificate; reject if deviation from nominal >0.5%
- [ ] Place ChArUco board on static bench surface for intrinsics cross-check
- [ ] Add ≥2 independent calibrated scale bars on static surfaces; log in `measurements.anchors[]`
- [ ] **Never** place fiducials on vacuum interior surfaces, in laser beam paths, on safety-critical surfaces without written facility approval, or on articulating parts

**Phase 3 — State setup and capture**
- [ ] Move equipment to target state; record actual joint values (angle, displacement) in `state_registry.yaml` — use protractor, encoder, ruler, or caliper, not just descriptive names
- [ ] Pre-capture check: fire one test orbit; verify ≤2% highlight clipping, ≥2 scale anchors visible at ≥8 px/module per tag, focus stable
- [ ] Capture full orbit: low ring (~60 images), mid ring (~100), high ring (~60), controls closeups (~40), fiducial anchor views (~30)
- [ ] For handheld or gimbal: lock camera speed; reject frames with edge smear >2 px; keep per-ring folders
- [ ] For turntable (removable components only): mask background; capture in discrete steps; separate set per state
- [ ] Log `capture_session.jsonl` entry per ring (state_id, ring, image_count, timestamp, hash)

**Phase 4 — QA and hold-out reservation**
- [ ] Run `ffprobe` / ExifTool on all footage; dump to `provenance/exiftool.json`; verify locked settings in EXIF
- [ ] Reserve 10–15% of views per ring stratified-random as hold-out; add one unseen validation state (e.g. door at 60°)
- [ ] Check COLMAP registration rate per state before handing off — rates below 10% trigger recapture (see Common Issues)
- [ ] Record `sha256_manifest.txt` for all raw files

**Phase 5 — Provenance package**
- [ ] Write `capture_sidecar.yaml` (see contract below); this is the input evidence for ARA Seal Level 2 review via [versioning-twins-with-ara](../versioning-twins-with-ara/SKILL.md)
- [ ] Write `ro-crate-metadata.json` using RO-Crate 1.1 JSON-LD; reference equipment, operator, capture files, and processing commands as contextual entities
- [ ] Freeze `capture_session.jsonl` + `safety_photos/`; hand off to downstream

## Common Workflows

### Workflow 1 — SEM chamber door (binary + intermediate states)

Goal: K=5 door states for SOP rehearsal and robotic simulation.

```
S00  door_deg=0     (closed, sealed)
S01  door_deg=22    (25% travel)
S02  door_deg=45    (50% travel)
S03  door_deg=67    (75% travel)
S04  door_deg=90    (fully open, safe stop)
S05  stage_home     (door closed, stage XY=0, Z=safe)
SV1  door_deg=55    (held-out validation state)
```

1. Complete safety lock-out: EHT off, beam blanked/off, chamber vented (if open), stage at safe Z, detectors retracted, no vacuum-incompatible materials — sign with operator ID + UTC timestamp
2. Lighting: cross-polarized diffuse softbox at 5600 K for exterior; bracketed HDR (−2/0/+2 EV) for chamber interior using a second locked exposure preset; avoid direct reflections on polished chamber walls
3. AprilTags at ~120° on fixed exterior panels at two elevations; ChArUco on bench; caliper-measure each tag; scale bar on chassis width feature (e.g. 412.80 mm measured 3×)
4. Capture S00–S04 as separate independent orbits; never open chamber during exterior orbit
5. For chamber interior: handheld with gimbal; keep ISO fixed; use `footage/interior_<state>/` subfolder
6. Set `qa_targets`: `min_registration_ratio: 0.85`, `max_reprojection_rmse_px: 1.2`, `scale_residual_percent_fail: 1.0`
7. Mark `interior_geometry_status: visual_only_reflective` if chamber walls are mirror-like; route to [training-reflection-aware-splats](../../23-3d-reconstruction/training-reflection-aware-splats/SKILL.md)

### Workflow 2 — Optical bench (rail slider + mirror mount)

Goal: coordinate-frame-correct twin; each rail DoF captured independently before coupled states.

1. Safety lock-out: laser shutter closed + key removed + beam blocks in all paths; record laser class, wavelength, power; for Class 3B/4 confirm controlled-area posted, eyewear logged, interlocks active
2. Define `coordinate_frames.yaml`: world origin on table hole grid or rail marking; record all offsets
3. Lighting: diffuse + cross-polarized for mirrors; no laser-line capture — represent beams as simulated overlays
4. Fiducials: ChArUco boards on non-optical table surfaces; AprilTag pairs at known rail-hole spacing for long-axis scale; calibrated ruler along full rail length
5. K plan: K=5 per rail-slider DoF; K=5 per mirror pitch/yaw mount (neutral, ±yaw, ±pitch); K=N per filter/shutter positions; capture each DoF independently
6. Capture optics as pose-validated proxies — do not reconstruct lens glass or mirror coating truth; annotate optical elements in USD/MJCF separately

## Capture-Plan YAML Contract (minimum fields)

```yaml
schema_version: "capture-plan/v2.0"
session_id: "SEM-2026-05-05-001"
created_utc: "2026-05-05T08:00:00Z"
scale_tier: "production_metric"   # scouting | approximate | production_metric

operator:
  operator_id: "joperator"
  training: ["SEM_USER_2026"]

equipment:
  type: "sem"
  manufacturer: "ExampleCorp"
  model: "SEM-X"
  serial: "SN12345"

safety_state:
  status: "pass"               # BLOCK if not pass
  checked_by: "joperator"
  checked_utc: "2026-05-05T08:10:00Z"

capture_device:
  model: "Sony A7R V"
  lens: "50mm macro"
  intrinsics_file: "calibration/cam_a7r5_50mm.yaml"
  intrinsics_file_sha256: "..."
  exposure_locked: true
  white_balance_locked: true
  focus_locked: true
  manual_settings: {iso: 100, shutter_s: "1/125", aperture: "f/8", wb_k: 5600}

fiducials:
  - fiducial_id: "TAG_BASE_001"
    type: "AprilTag"
    family: "tagStandard41h12"
    role: [scale_anchor, pose_anchor]
    nominal_mm: 40.000
    printed_mm: 39.873
    measurement_convention: "outside_edge_of_inner_black_border"
    caliper_id: "CAL-001"
    min_px_per_module: 8

measurements:
  anchors:
    - anchor_id: "CHASSIS_WIDTH"
      length_mm: 412.80
      repeats_mm: [412.78, 412.81, 412.80]
      instrument_id: "CAL-001"
      temperature_c: 22.1

k_states:
  - state_id: "S00_HOME"
    joint_values: {chamber_door_deg: 0, stage_x_mm: 0.0}
    required_views: {orbit_low: 60, orbit_mid: 100, orbit_high: 60, controls_closeups: 40}

qa_targets:
  overlap_percent_min: 75
  blur_px_max: 2.0
  clipped_highlight_fraction_max: 0.02
  scale_residual_percent_fail: 1.0
  reprojection_rmse_px_fail: 1.5
  min_k_per_dof_ship_ready: 5
  min_registration_ratio: 0.85
```

## Validation Gates

Run AFTER capture, BEFORE handing off to reconstruction.

| Gate | Pass criterion | Fail action |
|---|---|---|
| `safety_state.yaml` signed, status=pass | required | Block — do not proceed |
| Intrinsics file SHA-256 matches | required | Recalibrate, recapture |
| Exposure/WB/focus locked (EXIF verified) | no drift across states | Reshoot affected states |
| Scale anchors per state | ≥2 visible, ≥8 px/module | Reposition tags or recapture |
| Scale residual (anchor disagreement) | ≤1.0% | Block metric release; audit printed_mm |
| COLMAP registration rate per state | ≥85% | Investigate blur/exposure; recapture |
| Per-state view count | meets shot_list.csv quotas | Recapture missing views |
| Blur (edge smear) | ≤2 px | Reshoot; use tripod + remote shutter |
| Highlight clipping | ≤2% important pixels | Adjust exposure, reshoot |
| Reflective area | <10% uncontrolled | Add cross-polarized capture; route to reflection-aware splats |
| K-state count per DoF | ≥5 ship-ready; ≥2 hypothesis | Add states or mark `ship_ready: false` |
| Return-home state | final home matches initial | Flag drift/backlash |
| Safety photo per state | present in `safety_photos/` | Recapture state |
| Hold-out reserved | 10–15% views OR one unseen state | Mark held-out subset |
| Provenance sidecar complete | `capture_sidecar.yaml` + `ro-crate-metadata.json` | Complete before ARA review |

## Common Issues

| Symptom | Cause | Fix |
|---|---|---|
| COLMAP pose yield <10% | Phone video quality, exposure changes, excessive blur | Check EXIF lock; verify per nerfstudio #3435 pattern; recapture with tripod |
| Floating exposure across states | Auto-exposure re-engaged between states | Stop capture; compare EXIF; reshoot remaining states with manual lock |
| Missing static scale anchor in one state | Fiducial occluded or fell off | Add tag to different fixed surface; recapture that state |
| Glare on SEM chamber / polished mirrors | Uncontrolled specularities | Add cross-polarized softbox; lower light angle; route to [training-reflection-aware-splats](../../23-3d-reconstruction/training-reflection-aware-splats/SKILL.md) |
| Motion blur (handheld) | Camera shake | Switch to tripod + remote shutter; reject frames with edge smear >2 px |
| K too low shipped (K=2) | Insufficient joint-travel coverage | Mark `ship_ready: false`; add mid/quarter states + return-home |
| Scale anchors disagree >1% | Printed shrinkage, moving-tag error, wrong measurement convention | Audit `printed_mm` vs nominal; verify convention; remeasure 3× |
| Fiducials moved between states | Tags placed on articulating parts | Reclassify as `part_local`; add static base anchors |
| Thermal drift between states | Long session, warm equipment | Pause for stabilization; remeasure anchors; add return-home at start and end |
| Knobs fused into panel after segmentation | Insufficient closeup views | Add per-knob closeup ring; use [per-gaussian-saga](../../24-3d-segmentation-articulation/per-gaussian-saga/SKILL.md) |
| Joint axis wrong >10° | K too low or oblique views missing | Recapture K≥5; add oblique views around hinge |
| SEM mirror-like chamber walls | Reflective interior | Mark `interior_geometry_status: visual_only_reflective`; use CAD proxy in URDF/MJCF/USD |
| Optical-rail scale off | Missing long-axis scale bar | Add calibrated ruler along rail + two tag-pair anchors |
| 3DGS viewer splats missing/shimmering on Quest | Sorting bug on Vulkan (aras-p/UnityGaussianSplatting #112) | Pin Aras-P plugin version; verify Quest build targets against exact plugin release notes |

### Rescue Ladder

1. **Mask**: Remove hands, screens, glare, moving cables from remaining shots
2. **Split capture**: Reshoot per state, per subassembly, per elevation ring
3. **Lock from calibration**: Use locked intrinsics file; do not estimate per-image
4. **Neural prior rescue**: Seed poses with VGGT/MapAnything via [recovering-pose-free-geometry](../../23-3d-reconstruction/recovering-pose-free-geometry/SKILL.md) — never replace physical scale anchors with neural-predicted scale
5. **Manual control points**: Add on fiducials, table holes, calibration bars, or known CAD features
6. **Reshoot** if registration stays <70% or scale drift >1.0% — do not continue downstream

## Advanced Topics

Extended K-state mapping tables, fiducial layout algorithm, lighting/exposure recipes, operator checklist template, equipment-specific edge cases, scale-chain audit procedure, RGB-D/IMU fusion rules, RO-Crate metadata authoring: see [references/capture-protocol-extended.md](references/capture-protocol-extended.md)

## Cross-Reference

### Cat 28 — Digital-twin workflow siblings

- [lab-equipment-twinning](../lab-equipment-twinning/SKILL.md) — orchestrator that invokes this skill
- [validating-digital-twins](../validating-digital-twins/SKILL.md) — post-reconstruction gate runner
- [versioning-twins-with-ara](../versioning-twins-with-ara/SKILL.md) — ARA Seal Level 2 provenance + `level2_report.json`
- [simulating-experiment-runs-in-twins](../simulating-experiment-runs-in-twins/SKILL.md) — downstream simulation campaigns

### Cat 23 — 3D reconstruction consumers

- [preprocessing-reconstruction-videos](../../23-3d-reconstruction/preprocessing-reconstruction-videos/SKILL.md) — de-shake, mask, dedupe
- [estimating-sfm-camera-poses](../../23-3d-reconstruction/estimating-sfm-camera-poses/SKILL.md) — COLMAP/GLOMAP/hloc pose recovery
- [recovering-pose-free-geometry](../../23-3d-reconstruction/recovering-pose-free-geometry/SKILL.md) — VGGT/MapAnything fallback
- [training-gaussian-splats](../../23-3d-reconstruction/training-gaussian-splats/SKILL.md)
- [training-reflection-aware-splats](../../23-3d-reconstruction/training-reflection-aware-splats/SKILL.md)
- [extracting-gs-surfaces](../../23-3d-reconstruction/extracting-gs-surfaces/SKILL.md)
- [training-nerf-fallbacks](../../23-3d-reconstruction/training-nerf-fallbacks/SKILL.md)

### Cat 24 — Primary downstream articulation consumer

- [multistate-diff-open3d](../../24-3d-segmentation-articulation/multistate-diff-open3d/SKILL.md) — requires clean per-state reconstruction inputs from this protocol
- [per-gaussian-saga](../../24-3d-segmentation-articulation/per-gaussian-saga/SKILL.md) — Gaussian segmentation corrections
- [screwsplat-articulation](../../24-3d-segmentation-articulation/screwsplat-articulation/SKILL.md) — joint estimation; needs ≥2 separate static configurations
- [articulation-ditto-prior](../../24-3d-segmentation-articulation/articulation-ditto-prior/SKILL.md)
- [lift-2d-masks-ludvig](../../24-3d-segmentation-articulation/lift-2d-masks-ludvig/SKILL.md)
- [gsplat-scene-adapter](../../24-3d-segmentation-articulation/gsplat-scene-adapter/SKILL.md)

### Cats 25–27 — Further downstream

- [vlm-physics-validation-loop](../../25-affordance-vlm/vlm-physics-validation-loop/SKILL.md) — validates articulation hypotheses
- [authoring-urdf-mjcf-usd](../../27-physics-simulation/authoring-urdf-mjcf-usd/SKILL.md) — consumes joint values from state_registry.yaml

## Resources

### Capture-protocol CLI tools

| Tool | Use | License |
|---|---|---|
| `ffmpeg` / `ffprobe` | Extract frames, inspect streams | LGPL 2.1+ (GPL if built with GPL components) |
| `exiftool` | Dump EXIF/camera metadata to provenance sidecar | Free (same terms as Perl) |
| `oiiotool` (OpenImageIO) | Audit exposure stats, color, clipping per frame | Apache-2.0 |
| `colmap` | SfM/MVS per state; COLMAP 4.0 includes GLOMAP | New BSD |
| `ns-process-data` (Nerfstudio) | Convert frames to NeRF/3DGS-ready datasets | Apache-2.0 |
| `meshroom_batch` (AliceVision) | Alternative pipeline cross-check | MPL-2.0 |
| `openMVG` + `openMVS` | Independent SfM/MVS cross-check | OpenMVG: MPL-2.0; OpenMVS: AGPLv3 |
| `blender -b` | Scale checks, rig QA, mesh export | GPL |
| `c2patool` | Attach/inspect C2PA provenance manifests | MIT/Apache |
| `RealityCapture CLI` | Fast commercial alignment and QA comparison | Free for revenue <$1M; licensed otherwise |

### Literature (case studies)

- **ArticulatedGS** (CVPR 2025): Two distinct static multi-view sets per articulation configuration; validates that separate per-state capture is required for 3DGS-based articulated twins
- **ScrewSplat** (2025): Multiple joint configurations; evaluates rendering at unseen intermediate angles — confirms intermediate-angle capture is mandatory for interpolation
- **iTACO** (2025 / 3DV 2026): 784-video RGB-D dataset of interactable objects; separate transition videos used for joint estimation alongside static reconstruction sets

### Standards and references

- AprilTag 3 — `tagStandard41h12` (preferred 2025/2026); `tag36h11` for broad compatibility
- OpenCV ChArUco — intrinsics calibration; more accurate than isolated ArUco corners
- RO-Crate 1.1 — JSON-LD research-object packaging; `ro-crate-metadata.json` wraps all capture artifacts
- C2PA / c2patool — cryptographically verifiable content provenance; `.c2pa` sidecar per asset
- ANSI Z136.1-2022 — laser safety classes (3B, 4); controlled-area requirements
- ISO 10218-1/2:2025 — robot/cobot safety for motorized capture rigs
- NIST traceability — documented measurement chain with uncertainty for metric anchors
