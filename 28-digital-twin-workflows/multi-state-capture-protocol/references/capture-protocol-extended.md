# Extended Capture Protocol Reference

This reference expands [SKILL.md](../SKILL.md) with operator-level scripts, fiducial layout algorithms, equipment-specific edge cases, scale-chain audit procedures, and 2025/2026 technique integration guidance. The skill file is the contract; this reference is the field manual.

---

## Detailed K-state mapping (2026)

### Articulation type → K and view-count rules

| Articulation | Hypothesis K | Ship-ready K | State spacing |
|---|---|---|---|
| Binary latch (two hard stops) | 2 | 2 | N/A |
| Single revolute door (SEM chamber) | 3 | 5 (0/25/50/75/100%) | ≥30° between states |
| Single prismatic stage axis | 3 | 5 (0/25/50/75/100%) | ≥20% travel or ≥10 mm |
| Screw / helical joint | 5 | 7–9 (include approach directions + return) | Distribute across full thread travel |
| Knob with N detents | N | N | One state per detent |
| Microscope objective turret (4 slots) | 4 | 4 | One state per objective |
| Filter wheel (6 slots) | 6 | 6 | One state per filter |
| Mirror pitch + yaw mount | 3 | 5 (neutral, ±yaw, ±pitch) | Separate pitch and yaw sweeps |
| Coupled focus knob driving Z | 5 | 8 (sample across full revolution + return) | Uniform angular spacing |
| Optical bench rail slider | 3 | 5 (0/25/50/75/100%) | Include full travel + closeups on rail marks |
| Detached sample holder on turntable | 1 (full orbit) | 1 (72 positions × 2 elevations) | 5° step interval |
| Multi-DoF object (D independent DoF) | 1+2D | 1+5D + coupled validation + return home | Capture each DoF independently first |

For coupled joints (e.g. concentric coarse + fine focus): capture the driver knob at densest sampling and let the driven DoF emerge from downstream joint inference. Do not try to manually enumerate the full coupled space.

### Multi-DoF state budget formula

```
K_total (scouting)    = 1 home + 2 × D + 1 return-home
K_total (minimum prod)= 1 home + 3 × D + 1 return-home
K_total (ship-ready)  = 1 home + 5 × D + interaction_states + 1 return-home
```

Example — optical microscope with X stage, Y stage, Z stage, focus:
- Ship-ready: 1 + 5×4 + 2 coupled validation + 1 return = 24 states minimum

---

## Fiducial placement rules (2026)

Use **AprilTag** (`tagStandard41h12` preferred; `tag36h11` for broad compatibility) or **ChArUco** boards.

| Surface | Allowed | Notes |
|---|---|---|
| Equipment exterior fixed panels | YES | Preferred world-frame anchors |
| Lab bench surface | YES | Use ChArUco board taped flat |
| Equipment door / handle / turret | NO — part_local only | Never use for global scale |
| Vacuum chamber interior (SEM) | NO | Outgassing risk; requires written facility approval |
| Mirror / lens surface | NO | Obscures optic and damages coating |
| Active beam path | NO | Safety hazard |
| Calibration card near chamber (removable) | YES | Mark `placement_frame: local_calibration`; exclude from global scale |

### Tag family selection

| Family | When to use |
|---|---|
| `tagStandard41h12` | Preferred default 2025/2026; AprilTag 3 recommended family; good at generous tag sizes |
| `tag36h11` | Best compatibility; widely supported; use when cross-tool interoperability matters |
| `DICT_5X5_100` or `DICT_6X6_250` | For ArUco-based boards when ID count and size allow |
| `DICT_4X4_50` | Avoid as sole scale anchor — small Hamming distance; only for close-range, low-ID-count boards |

### Pixel-size thresholds per detected tag

| Role | Hard reject | Warning | Target |
|---|---|---|---|
| ID-only detection | <4 px/module | 4–6 px/module | ≥6 px/module |
| Pose / registration anchor | <6 px/module | 6–8 px/module | ≥8–10 px/module |
| Scale anchor (metric) | <8 px/module | 8–10 px/module | ≥10 px/module |
| Tag side in image | <40 px | 40–80 px | ≥100 px |
| Black border ring | <4 px | 4–8 px | ≥8–12 px |

For lab-scale equipment, 80–120 mm tags work for orbital capture; for tabletop microscopes, 30–50 mm tags.

### Fiducial layout algorithm

1. Place one large world-frame ChArUco board on lab bench, perpendicular to dominant view direction.
2. Place 3+ AprilTags on equipment exterior fixed panels at ~120° azimuth spacing.
3. Place 2+ AprilTags at different elevations to disambiguate vertical scale drift.
4. Add a scale-bar AprilTag pair at known caliper-measured separation (rigid bar, not tape).
5. For detached subassemblies (turntable capture), add 2 small tags as a local frame.
6. Print fiducial layout PDF; photograph the layout at session start before first ring.

### Printed-mm recording procedure

Every printed marker must carry this YAML record:

```yaml
nominal_mm: 40.000
printed_mm: 39.873
measurement_convention: "outside_edge_of_inner_black_border"
measurement_repeats_mm: [39.87, 39.88, 39.87]
caliper_id: "MITUTOYO-500-196-30-SN12345"
calibration_certificate: "CERT-2026-0042"
uncertainty_mm: 0.02
measured_by: "operator_id"
measured_utc: "2026-05-05T03:10:00Z"
```

**Print-scale verification checklist:**
- [ ] Print with "actual size" / scaling disabled — no "fit to page," no driver shrink
- [ ] Let sheet stabilize ≥10 min after printing or lamination
- [ ] Measure each tag side at 4 points (top, bottom, left, right)
- [ ] Measure both diagonals for squareness
- [ ] Reject if: average size deviates from nominal >0.5%, or X/Y anisotropy >0.3%, or diagonal mismatch >0.5%, or lamination curl lifts tag >1 mm over its width
- [ ] Record `printed_mm` (actual measured value), NOT the nominal CAD size

---

## Lighting and exposure

| Equipment region | Lighting | Polarization | CCT |
|---|---|---|---|
| Matte equipment exterior | Diffuse softbox | Not required | 5600 K |
| Polished metal knobs | Diffuse softbox | Cross-polarized | 5600 K |
| Glass viewports / eyepieces | Cross-polarized | Required | 5600 K |
| Chamber interior (SEM) | LED panels at oblique angles, HDR brackets (-2/0/+2 EV) | Cross-polarized | 5000–5600 K |
| Optical bench mirrors | Cross-polarized + matte ND on overheads | Required | 5600 K |
| Laser-active bench | Lasers OFF or beam-blocked; no laser-line capture | N/A | 5600 K |

**Exposure locking rule**: After ring 1 dry-run, do not change ISO, shutter, aperture, WB, or focus for the rest of the session. If lighting must change between rings (necessary for chamber interior), document every change in `lighting_notes.md` and flag `lighting_changed_between_rings: true` in `capture_plan.yaml`.

**HDR brackets**: 3 exposures at -2 EV / 0 EV / +2 EV for high-dynamic-range chamber interiors; store all three; downstream skills choose.

---

## Scale provenance and metric chain

Every twin must have **at least two independent, non-collinear** scale anchors on the static base frame. One anchor is insufficient — always validate with a second.

| Anchor type | Production default |
|---|---|
| AprilTag pair at known separation | Rigid bar with caliper-measured center-to-center distance |
| Caliper-measured chassis feature | Door width, base footprint, eyepiece spacing |
| Long-axis calibrated ruler | Optical bench rails |
| Stage micrometer / known slide | Optical microscope scale |

**NIST traceability chain**: Documented measurement → calibrated instrument (with current certificate + uncertainty) → printed_mm record → image detections → reconstruction scale solve → residual report.

**Scale-chain audit procedure:**
1. Collect `printed_mm` and `uncertainty_mm` for every fiducial used as a scale anchor.
2. Collect caliper measurements with instrument ID and calibration certificate.
3. After SfM/reconstruction: extract the solved scale factor applied.
4. Compute residual for each anchor pair: `|solved_mm - measured_mm| / measured_mm × 100%`.
5. Pass: all residuals ≤1.0%. Warning: any residual 0.5–1.0%. Fail: any residual >1.0%.
6. If fail: audit units (mm vs m), printed-mm convention (inner vs outer border), moving-tag mis-classification, caliper calibration expiry, and thermal expansion.

**Common scale pitfalls:**
- EXIF focal length as scale source — never
- Nominal tag size instead of measured printed_mm — always measure
- Measuring wrong border (outer vs inner black border) — record convention explicitly
- Fiducials on moving parts contributing to global scale — reclassify as `part_local`
- Thermal expansion during long sessions — remeasure anchors at session start and end; record temperature

---

## Equipment-specific edge cases

### SEM with mirrored chamber walls

If chamber walls are highly reflective (>60% specular at glancing angles): capture cross-polarized HDR brackets, mark `interior_geometry_status: visual_only_reflective` in `exclusions_and_blindspots.md`, and use a CAD or proxy mesh for collision in the final URDF/MJCF/USD. Route visual reconstruction to [training-reflection-aware-splats](../../23-3d-reconstruction/training-reflection-aware-splats/SKILL.md).

### SEM column open / closed states

Record `column_state: open` vs `column_state: closed` as distinct semantic states. The column apertures, pole piece, and detector positions are important affordances for SOP rehearsal. Capture closeups from available angles; do not attempt to reconstruct internal electron optics.

### Optical microscope with motorized stage

Power must be off (or stage in hold/disabled mode) during capture, or the stage will drift between rings. If power must remain on for safety reasons, capture all rings of one state in a single uninterrupted pass with no operator contact, and document in `lighting_notes.md`.

### Optical bench with active beam path

Lasers OFF at all times during photogrammetry. If the bench cannot be powered down (continuous experiment), use a beam blocker AND capture at low ambient lighting — never with any laser beam visible to the camera. Mark beam path as `simulated_overlay_only` in `capture_plan.yaml`; it will be rendered in runtime, not reconstructed geometrically.

### Rotating turntable parts

Detach rotating parts if possible (objective turret, sample holder). Capture detached on a separate turntable with local fiducials. Reattach in the digital twin via known mounting geometry rather than reconstructing from in-situ rotation, which introduces motion blur and misalignment.

### Reflective optical components (mirrors, beamsplitters, filters)

Capture optics as pose-validated proxies — measured position and orientation, not reconstructed glass truth. Use CAD-like primitives with material tags. Cross-polarized capture reduces glare but does not recover internal AR coatings. Document all such elements in `exclusions_and_blindspots.md` with status `proxy_geometry`.

---

## Safety state checklists — detailed

### SEM capture safety (per-session)

| Check | Required state |
|---|---|
| Operator training authorization | Approved for this SEM model |
| Beam / EHT | Off or blanked; EHT off or standby |
| Chamber | If open: vented and stable; if closed: sealed |
| Vacuum compatibility | No printed paper, adhesives, or unapproved materials inside vacuum |
| Stage position | Safe Z; no collision risk with pole piece, detectors, or chamber wall |
| Detectors | Retracted or safe if stage/chamber moves |
| Contamination | Samples/fiducials clean, dry, non-shedding |
| Interlocks / panels | No panels removed; no interlocks bypassed |
| Nitrogen ventilation | Room ventilation confirmed for any venting events |
| **Block condition** | Any unknown beam, vacuum, or interlock state → `safety_state: fail` |

### Optical microscope capture safety (per-session)

| Check | Required state |
|---|---|
| Illuminator | Off or shuttered |
| Hot lamps | Cooled before close capture; do not touch housing |
| Motorized stage | Disabled, hold mode, or jog-limited |
| Autofocus macros | Disabled |
| Objective/Z | Safe clearance between objective and stage/sample |
| Fluorescence / UV | Shutter closed; shield in place; no direct viewing path |
| **Block condition** | Any automated motion without operator clearance → `safety_state: fail` |

### Optical bench / laser capture safety (per-session)

| Check | Required state |
|---|---|
| Laser class recorded | class, wavelength, power, CW/pulsed |
| Class 3B | Controlled-area procedures; intrabeam hazardous |
| Class 4 (>500 mW) | Eye + skin + fire hazard; diffuse reflections also hazardous |
| Beam state | Shutter closed, key removed, beam off |
| Beam blocks | In place at end of every path and after high-risk optics |
| Interlocks | Active; no bypass — bypass is stop-work condition |
| Eyewear | OD matched to wavelength and power; model logged |
| Camera placement | Outside beam plane; no specular camera body/lens in beam path |
| Reflective objects | Phones, watches, tools, uncoated fiducials removed or covered |
| Area signage / access | Controlled area posted; access limited |
| **Block condition** | Unknown beam state, missing beam block, or interlock bypass → `safety_state: fail` |

### Robot / motorized capture rig safety (ISO 10218 concepts)

If a robot arm, cobot, automated optical stage, or motorized capture rig can move while a human is nearby, apply: risk assessment, safety-rated stops, speed/separation monitoring, power/force limiting, accessible emergency stop, and teach/jog mode for close work. Log rig mode in `safety_state.robot_or_motorized_capture`.

---

## Operator-checklist template

```
1. PRE-SESSION
   [ ] Verify equipment safety state (beam, vacuum, lasers, interlocks)
   [ ] Photograph safety-state placard / interlock indicator
   [ ] Measure and record printed_mm for each fiducial (caliper + certificate)
   [ ] Lay out fiducials per fiducial_layout.pdf; photograph layout before first ring
   [ ] Verify camera intrinsics file matches lens; record SHA-256
   [ ] Lock exposure / WB / focus on first ring; verify histograms (≤2% clipping)
   [ ] Dry-run first ring: check fiducial detection (≥8 px/module for scale anchors)

2. CAPTURE (for each state in k_state_plan.yaml)
   [ ] Set equipment to planned state; record actual joint values
   [ ] Photograph safety-state placard for this state
   [ ] Capture orbit_low ring at 5° intervals
   [ ] Capture orbit_mid ring at 5° intervals
   [ ] Capture orbit_high ring at 10° intervals
   [ ] Capture closeups per shot_list.csv
   [ ] Verify ≥2 static scale-anchor tags detected per ring image
   [ ] Log capture_session.jsonl entry per ring (state_id, ring_id, image_count, timestamp)

3. POST-CAPTURE
   [ ] Return equipment to home state; photograph safety-state placard again
   [ ] Review capture_session.jsonl for missing rings; reshoot if needed
   [ ] Confirm ≥2 caliper measurements logged per equipment at temperature
   [ ] Confirm safety_photos/ has one photo per state
   [ ] Mark held-out image subset (10–15% stratified per ring)
   [ ] Compute SHA-256 hashes of raw image directories
   [ ] Run pre-reconstruction QA gates (see SKILL.md Validation table)
   [ ] Hand off to preprocessing-reconstruction-videos
```

---

## Neural prior and depth-sensor integration (2025/2026)

### Permitted uses of VGGT / MapAnything

```yaml
allowed:
  - neural_pose_seed           # seed SfM with predicted poses
  - missing_view_QA            # identify coverage gaps
  - coarse_depth_prior         # assist occlusion handling
  - cross_state_track_suggestions

not_allowed:
  - replacing physical scale anchors
  - overriding failed safety_state
  - silently filling unobserved joint states
  - claiming metric accuracy without physical measurement
```

### RGB-D / depth-sensor integration

RGB-D is useful for occluded equipment and casual dynamic capture (e.g., iTACO-style articulated reconstruction from handheld RGBD). However, reflective SEM chambers, mirrors, black anodized parts, glass, and polished optical mounts break many depth sensors.

```yaml
depth_fusion_role:
  use_as:
    - secondary_geometry
    - occlusion_support
    - pose_initialization
    - completeness_QA
  do_not_use_as:
    - sole_metric_scale          # use caliper-anchored scale instead
    - sole_geometry_source_for_reflective_surfaces
    - replacement_for_caliper_measurements
```

### IMU-assisted capture

Phone/camera IMU or visual-inertial odometry can estimate camera motion, detect shaky segments, and seed pose graphs. Log as auxiliary metadata:

```yaml
imu_assist:
  used: true
  source: "phone_vio"
  role: [pose_seed, blur_detection]
  used_for_metric_scale: false
```

---

## Agent decision gates (machine-readable summary)

| Gate | Pass condition | Fail action |
|---|---|---|
| Safety | `safety_state.status == pass` | Stop; do not proceed |
| Exposure | `exposure_locked == true` across all states | Reshoot affected states |
| Scale anchors | ≥2 independent static anchors; residual ≤1.0% | Block metric release |
| Fiducials | Required static anchors visible in every state | Recapture missing state |
| K-state | K_per_DoF ≥5 for production | Mark `ship_ready: false` or add states |
| Blur | ≤2 px edge smear | Recapture blurred views |
| Glare | No clipped specularities over tags, joints, or key edges | Adjust lighting; reshoot |
| Moving tags | Moving-part tags excluded from global scale | Add static anchors |
| Return-home | Final home state within scale residual target | Flag drift/backlash; investigate |
| Reconstruction plausibility | Visual appearance passes | Does NOT mean metric is valid — check scale chain |

The most important meta-rule: **a reconstruction can look visually plausible and still be metrically invalid.** Ship only when the scale chain, safety chain, K-state coverage, and failure logs all pass.
