---
name: looping-vlm-against-physics-validators
description: Closes the loop between a VLM joint hypothesis and a physics/geometry validator by sampling joint parameters across the proposed range, scoring with collision/contact/parent-child checks, and re-prompting the VLM with concrete failure evidence until the JointSpec passes or the budget is spent. Use after constrained decoding has produced a schema-valid JointSpec (cat 25) but before downstream URDF authoring (cat 27); pairs a local vision-language proposer with trimesh geometry checks or a SAPIEN full-physics validator and an actor-critic re-prompt strategy.
version: 2.0.0
author: Orchestra Research
license: MIT
tags: [VLM, Physics Validation, Iterative Refinement, Articulate-Anything, Self-Correction, Re-Prompting, Joint Sampling, Collision Check, SEM, Lab Equipment, URDF]
dependencies: [pydantic>=2.12,<2.13, numpy>=1.26, trimesh==4.12.2, python-fcl==0.7.0.11, scipy>=1.11]
---

# Looping VLM Against Physics Validators

Actor-critic loop: VLM proposes JointSpec → physics/geometry validator instantiates joint and samples motion → on failure, build concrete evidence and re-prompt → repeat until pass or budget exhausted.

Audit snapshot: trimesh 4.12.2 (May 1 2026, MIT), python-fcl 0.7.0.11 (Apr 8 2026, BSD), sapien 3.0.3 (Mar 10 2026, MIT). VLM names verified 2026-05-05: primary affordance proposer is **Qwen/Qwen3.6-27B** (unified image-text-to-text, Apache-2.0). "Qwen3-VL" (e.g. Qwen/Qwen3-VL-8B-Instruct) is the 2025 VL-specific family and remains valid as a legacy/baseline; it is NOT the 2026 primary name. The unified Qwen3.5 / Qwen3.6 families supersede it for new affordance-proposal work.

## Quick start

```bash
# Validator env (Python 3.10+)
pip install "trimesh==4.12.2" "python-fcl==0.7.0.11"
pip install "sapien==3.0.3"   # GPU + Vulkan/EGL required; skip on CPU-only nodes

# VLM env — keep separate from sapien env if using local inference
pip install "transformers>=4.47" "qwen-vl-utils" pillow torchvision
# or production serving:
pip install "vllm>=0.19.0"        # Qwen3.6 / InternVL3.5 compatible
# pip install "sglang[all]>=0.5.10"  # alternative serving
```

```python
from validation_loop import run_validation_loop

final_json = run_validation_loop(
    part=segmented_part,
    parent_part=parent,
    scene_geometry=scene_geom,
    propose_fn=propose_joint_candidates,   # cat 25 prompter using Qwen3.6-27B
    validator=physics_validator,            # trimesh or SAPIEN backend
    max_attempts=3,
)
```

**VLM model IDs for affordance proposal (2026):**

| Role | HuggingFace ID | License |
|------|---------------|---------|
| Primary (2026) | `Qwen/Qwen3.6-27B` | Apache-2.0 |
| Primary alt | `Qwen/Qwen3.6-35B-A3B` | Apache-2.0 |
| Verifier | `OpenGVLab/InternVL3_5-8B-HF` | Apache-2.0 |
| Verifier large | `OpenGVLab/InternVL3_5-38B-HF` | Apache-2.0 |
| Baseline | `lmms-lab/LLaVA-OneVision-1.5-8B-Instruct` | Apache-2.0 |
| Legacy Qwen VL | `Qwen/Qwen3-VL-8B-Instruct` | Apache-2.0 |

Trimesh sign convention (critical): `ProximityQuery.signed_distance` returns **positive** inside/near-surface, **negative** outside. This is the opposite of many SDF libraries. Confirmed in current docs and issue #1031.

## Common workflows

### Workflow 1: Sample a revolute joint and score it

Task Progress:
```
- [ ] Sample 16 angles across [range[0], range[1]]
- [ ] For each angle, rotate child mesh about axis/anchor
- [ ] Compute signed distance against parent surface (ProximityQuery)
- [ ] Score collision_free_motion = fraction of samples with signed_dist > -1mm
- [ ] Score parent_child_consistency = fraction with |signed_dist| < 5mm (near-contact)
- [ ] Score range_stop_consistency = endpoints align with detected mechanical stops
- [ ] If any score fails threshold, call build_reprompt_from_failures and re-propose
```

```python
import numpy as np
import trimesh
from trimesh.proximity import ProximityQuery
from trimesh.transformations import rotation_matrix

def sample_revolute_motion(child_mesh, parent_mesh, axis, anchor, lo, hi, samples=16):
    angles = np.linspace(lo, hi, samples)
    prox = ProximityQuery(parent_mesh)   # ProximityQuery does NOT accept a transform; pre-transform points
    results = []
    for theta in angles:
        R = rotation_matrix(theta, axis, point=anchor)
        moved = child_mesh.copy().apply_transform(R)
        idx = np.random.choice(len(moved.vertices), min(500, len(moved.vertices)), replace=False)
        d = prox.signed_distance(moved.vertices[idx])
        # positive = inside/near-surface; negative = outside (trimesh convention, confirmed docs + issue #1031)
        results.append({
            "theta_rad": float(theta),
            "min_signed_distance_m": float(d.min()),
            "fraction_in_collision": float((d < -1e-3).mean()),   # outside AND deep
            "fraction_in_contact":   float((np.abs(d) < 5e-3).mean()),
        })
    return results
```

### Workflow 2: Build a trimesh collision check (static pose)

Task Progress:
```
- [ ] Install python-fcl alongside trimesh (CollisionManager depends on it)
- [ ] Load and validate both meshes with mesh.process(validate=True)
- [ ] Add fixed geometry to CollisionManager
- [ ] Call in_collision_single for boolean; min_distance_single for gap
- [ ] Transform query points into parent mesh frame before ProximityQuery (no per-call transform)
- [ ] Flag non-watertight meshes; use signed distance as heuristic only
```

```python
import numpy as np
import trimesh
from trimesh.collision import CollisionManager
from trimesh.proximity import ProximityQuery
from trimesh.transformations import translation_matrix

mesh_a = trimesh.load_mesh("fixed_part.stl", force="mesh")
mesh_b = trimesh.load_mesh("moving_part.stl", force="mesh")
mesh_a.process(validate=True)  # logs, does not silently repair in production code
mesh_b.process(validate=True)

T_a = np.eye(4)
T_b = translation_matrix([0.03, 0.0, 0.0])

cm = CollisionManager()
cm.add_object("fixed", mesh_a, transform=T_a)

# in_collision_single: boolean surface-interference test
hit, names = cm.in_collision_single(mesh_b, transform=T_b, return_names=True)
# min_distance_single: closest gap between mesh_b and objects in the manager
min_gap = cm.min_distance_single(mesh_b, transform=T_b)

# Signed distance: transform query points into mesh_a's frame first
verts_b_world = trimesh.transform_points(mesh_b.vertices, T_b)
verts_b_in_a  = trimesh.transform_points(verts_b_world, np.linalg.inv(T_a))
sdf = ProximityQuery(mesh_a).signed_distance(verts_b_in_a)
# positive = inside/near-surface; use as heuristic only if mesh_a is non-watertight
inside_depth = sdf[sdf > 0].max(initial=0.0)

print({"collides": bool(hit), "min_gap_m": float(min_gap), "max_penetration_m": float(inside_depth)})
```

### Workflow 3: SAPIEN full-physics joint validation (headless)

Task Progress:
```
- [ ] apt-get install libegl1 libxext6 on server; set NVIDIA_DRIVER_CAPABILITIES=graphics,utility,compute
- [ ] import sapien (package name is sapien, NOT sapien3)
- [ ] scene = sapien.Scene(); scene.set_timestep(1/240)
- [ ] loader = scene.create_urdf_loader(); loader.fix_root_link = True; robot = loader.load("robot.urdf")
- [ ] Sweep qpos with robot.set_qpos([theta]); scene.step(); contacts = scene.get_contacts()
- [ ] Score by contact count and contact separation/impulse at each step (not just contact existence)
- [ ] Minimal safe URDF: explicit <inertial> on every link, collision + visual geometry, joint limit, damping
```

```python
import sapien  # package: sapien 3.0.3; import is `sapien`, not `sapien3`
import numpy as np

def validate_with_sapien(urdf_path, qpos_range, samples=16):
    scene = sapien.Scene()
    scene.set_timestep(1 / 240)

    loader = scene.create_urdf_loader()
    loader.fix_root_link = True
    robot = loader.load(urdf_path)   # returns PhysxArticulation
    robot.set_root_pose(sapien.Pose([0, 0, 0.5], [1, 0, 0, 0]))

    results = []
    for q in np.linspace(qpos_range[0], qpos_range[1], samples):
        robot.set_qpos([q])
        scene.step()
        contacts = scene.get_contacts()
        # inspect separation/impulse, not just contact count (SAPIEN 3 contact-offset behavior)
        penetrating = [c for c in contacts if any(p.separation < 0 for p in c.points)]
        results.append({"qpos": float(q), "n_contacts": len(contacts), "n_penetrating": len(penetrating)})
    return results
```

Headless note: SAPIEN 3 requires Vulkan/EGL and a GPU. There is no confirmed OSMesa-only path for SAPIEN 3 as of the audit date. For CPU-only servers, use trimesh as the default validator and defer SAPIEN to GPU nodes. SAPIEN issue #196 confirms the same URDF that failed in SAPIEN 2.2.2 works correctly in SAPIEN 3.0.0b1+, so do not port Articulate-Anything's SAPIEN-2-era code directly.

## When to use vs alternatives

Use this skill AFTER cat 25's prompter and constrained-decode skills have produced a schema-valid JointSpec, and BEFORE cat 27's URDF authoring. Required when the digital twin must support physical interaction (chamber door, linear stage) and silent kinematic errors would propagate to robot or simulation control.

**Validator engine selection:**

| Engine     | Use case                                    | Requirement             |
|------------|---------------------------------------------|-------------------------|
| trimesh    | Static signed-distance, OBB, collision bool | CPU-only; default       |
| SAPIEN 3   | Contact dynamics, gravity, sweep under load | GPU + Vulkan/EGL        |
| MuJoCo     | Reduced-coordinate joint dynamics           | Reserve for cat 27      |
| Genesis    | GPU-parallel multi-env physics              | Reserve for cat 27      |

**Articulate-Anything as architecture reference only**: The vlongle/articulate-anything repo (MIT, ICLR 2025) demonstrates the VLM actor-critic reprompt pattern but pins `sapien==2.2.2` and `python=3.9`. Issues #13 (PartNet-Mobility reproduction + model drift), #14 (joint attribute axis error), and #15 (mesh retrieval IndexError) show it is not production-ready for new SAPIEN 3 stacks. Port the proposer/critic/reprompt pattern; do NOT mix its dependency tree with sapien==3.0.3.

Skip this skill only when (a) predicted `joint_type` is `fixed` and geometry obviously supports it, or (b) ground-truth CAD provides validated joint metadata. Do NOT use this skill as a segmentation fixer (cat 24) or URDF authoring tool (cat 27).

## Common issues

### Validator marks all candidates as failing

Symptom: every candidate scores below threshold; loop exits with fallback fixed joint.
Fix: lower collision tolerance from `-1mm` to `-3mm` (scanned meshes are noisy); verify mesh units (meters vs mm); verify object frame consistency between proposal and validator; print parent-child contact map BEFORE running the loop.

### Re-prompt yields prose, not JSON

Symptom: VLM responds with natural language instead of JointSpec.
Fix: re-run the constrained decoder (`repair_until_valid`) on every VLM re-prompt response; never pass un-validated VLM output into `snap_to_geometry`; constrained decoding is the JSON gate, not a one-time step. Qwen3.6 and InternVL3.5 both require explicit JSON-mode prompting or schema injection; do not assume structured output without it.

### Loop oscillates between two failing candidates

Symptom: attempt 1 fails with collision, attempt 2 fails with out-of-bounds, attempt 3 returns to attempt 1's parameters.
Fix: track `(joint_type, axis_sign, range_round)` tuples across attempts; reject duplicate proposals; force re-classification of `joint_type` if axis/anchor space is exhausted. See `references/issues.md` for `LoopHistory`.

### Signed-distance wrong on lab-equipment scans

Symptom: non-watertight mesh returns unexpected positive signed distances.
Background: trimesh issue #1031 documents this; issue #2534 (4.12.x contains regression, fixed in PR #2535) shows `mesh.contains` also affected. Also: Embree 2→4 change introduced a scale-aware offset bug in 4.12.1, fixed in 4.12.2.
Fix: treat signed distance as a heuristic for open/non-watertight scans; combine with FCL collision boolean and unsigned nearest-surface distance; use watertight proxy if sign correctness is required.

### trimesh Docker install failure

Symptom: `trimesh[easy]` fails to build wheels for `manifold3d` or `vhacdx` (issue #2264, Aug 12 2024).
Fix: pin explicit packages (`trimesh==4.12.2 python-fcl==0.7.0.11`) instead of relying on `trimesh[easy]`; test in the target container before deploying.

### CollisionManager return_name / return_names inconsistency

Symptom: `return_name` vs `return_names` parameter name confusion in `in_collision_single` docs (noted in PR #2479).
Fix: test locally in your pinned environment before relying on the name-return optional; the boolean collision result is stable.

### Articulate-Anything Python 3.9 / SAPIEN 2 conflict

Symptom: import errors when mixed with a VLM CUDA 12.x stack, or SAPIEN version collisions.
Fix: keep articulate-anything in a SEPARATE conda env (`python=3.9`, `sapien==2.2.2`); port only the proposer/critic/reprompt pattern, not the dependency set. The production validator env uses `sapien==3.0.3` exclusively.

### SAPIEN headless fails on CPU-only server

Symptom: SAPIEN 3 crashes without GPU.
Fix: fall back to trimesh validator for static checks; schedule SAPIEN validation on GPU nodes only.

### SAPIEN contact scoring gives false positives

Symptom: contacts reported at every qpos step even when joint is far from collision.
Background: SAPIEN 3 can generate PhysxContact objects within "contact offset" (a pre-contact margin), not only at true penetration. Issue #218 (Mar 2025) discusses self-collision handling.
Fix: filter contacts by `separation < 0` and `impulse magnitude > threshold` to distinguish true penetration from contact-offset proximity.

### InternVL3.5 multi-image video inference errors

Symptom: LMDeploy inference errors with multi-image or video inputs (InternVL issue #1198).
Fix: use single-image input per SEM scan frame in the affordance proposal step; batch across frames manually rather than using video mode.

## Advanced topics

Full actor-critic re-prompt code, SEM-specific scoring weights, loop oscillation prevention (`LoopHistory`), multi-part cross-validation, loop budget tuning, and confidence calibration: see [references/issues.md](references/issues.md).

### Actor-critic loop skeleton

```python
from dataclasses import dataclass

@dataclass
class ValidatorScores:
    semantic_prior:               float = 0.0
    geometry_alignment:           float = 0.0
    contact_plausibility:         float = 0.0
    collision_free_motion:        float = 0.0
    range_stop_consistency:       float = 0.0
    parent_child_consistency:     float = 0.0
    unsupported_free_motion_penalty: float = 0.0

    @property
    def total(self) -> float:
        return (self.semantic_prior + self.geometry_alignment + self.contact_plausibility
                + self.collision_free_motion + self.range_stop_consistency
                + self.parent_child_consistency - self.unsupported_free_motion_penalty)

    @property
    def pass_threshold(self) -> bool:
        return self.total >= 3.0 and self.collision_free_motion >= 0.6


def run_validation_loop(*, part, parent_part, scene_geometry, propose_fn,
                         validator, schema, priors, max_attempts=3):
    cards = render_joint_cards(part, scene_geometry)
    candidates = propose_fn(cards, priors)
    valid_with_scores = []

    for cand in candidates:
        cand = emit_joint_json(cand, schema=schema)
        cand = snap_to_geometry(cand, part, parent_part)
        scores = validator.sample_and_score(
            part_id=part.id, joint_type=cand.joint_type,
            axis=cand.axis, anchor=cand.anchor, range=cand.range, samples=16,
        )
        if scores.pass_threshold:
            valid_with_scores.append((cand, scores))
            continue

        repair_prompt = build_reprompt_from_failures(cards, cand, scores)
        for rep in propose_fn(repair_prompt, priors):
            rep = emit_joint_json(rep, schema=schema)
            rep = snap_to_geometry(rep, part, parent_part)
            rep_scores = validator.sample_and_score(
                part_id=part.id, joint_type=rep.joint_type,
                axis=rep.axis, anchor=rep.anchor, range=rep.range, samples=16,
            )
            if rep_scores.pass_threshold:
                valid_with_scores.append((rep, rep_scores))

    if not valid_with_scores:
        return _fallback_fixed_joint(part, reason="all_candidates_failed_validation")

    return max(valid_with_scores, key=lambda cs: cs[1].total)[0]
```

### Re-prompt template

```python
def build_reprompt_from_failures(cards, candidate, scores, sample_results):
    failing = [s for s in sample_results
               if s.get("fraction_in_collision", 0) > 0.1 or not s.get("in_parent_bounds", True)]
    summary = "\n".join(
        f"- at {s.get('theta_rad', s.get('displacement_m')):.3f}: "
        f"collision={s['fraction_in_collision']:.2f}"
        for s in failing[:6]
    )
    return f"""Your JointSpec passed schema validation but FAILED physics validation.

Prediction: joint_type={candidate.joint_type}  axis={candidate.axis}
            anchor={candidate.anchor}  range={candidate.range}

Failing samples:
{summary}

Scores: geometry_alignment={scores.geometry_alignment:.2f}
        collision_free_motion={scores.collision_free_motion:.2f}
        parent_child_consistency={scores.parent_child_consistency:.2f}

Pick one fix:
1. Move anchor to lie ON the visible hinge barrel / rail centerline.
2. Flip axis sign (same physical hinge, may resolve sign ambiguity).
3. Tighten range (joint stops earlier than predicted).
4. Re-classify joint_type to fixed if no motion is plausible.

Return one corrected JointSpec JSON only."""
```

### Geometry snapping

Always snap before the expensive validator call. Catches easy errors (VLM axis 15-degrees off the true hinge) cheaply.

```python
def snap_to_geometry(candidate, part, parent_part):
    geom = compute_geometry_features(part, parent_part)
    if candidate.joint_type == "revolute" and geom.has_hinge_knuckles:
        if abs(np.dot(geom.hinge_axis, candidate.axis)) > 0.85:
            candidate.axis   = geom.hinge_axis.tolist()
            candidate.anchor = geom.hinge_pin_midpoint.tolist()
    elif candidate.joint_type == "prismatic" and geom.has_parallel_rails:
        if abs(np.dot(geom.rail_axis, candidate.axis)) > 0.85:
            candidate.axis   = geom.rail_axis.tolist()
            candidate.anchor = geom.carriage_centroid_on_rail.tolist()
            measured = max(0.0, geom.rail_length - geom.carriage_length)
            candidate.range  = [0.0, round(measured, 4)]
    return candidate
```

### Confidence calibration

```python
def calibrate_confidence(scores: ValidatorScores, vlm_confidence: float) -> float:
    physical_score = min(1.0, scores.total / 5.0)
    return 0.4 * vlm_confidence + 0.6 * physical_score
```

## Resources

- articulate-anything (pattern reference, NOT production dependency): https://github.com/vlongle/articulate-anything (MIT; Python 3.9; sapien==2.2.2; issues: #13 model drift, #14 axis attr error, #15 mesh retrieval IndexError)
- SAPIEN simulator: https://github.com/haosulab/SAPIEN (MIT); PyPI: `sapien==3.0.3`; issues: #196 (SAPIEN 2→3 URDF fix), #218 (self-collision handling)
- InternVL: https://github.com/OpenGVLab/InternVL (Apache-2.0); current family: InternVL3.5 (Aug 2025); issues: #1185 (InternVL3.5-4B repro), #1198 (LMDeploy multi-image errors)
- LLaVA-OneVision-1.5: https://github.com/LLaVA-VL/LLaVA-NeXT (Apache-2.0); supersedes LLaVA-NeXT naming
- Qwen3.6 model card: https://huggingface.co/Qwen/Qwen3.6-27B (Apache-2.0); serving: vllm>=0.19.0 or sglang>=0.5.10
- trimesh proximity API: https://trimesh.org/trimesh.proximity.html
- trimesh collision API: https://trimesh.org/trimesh.collision.html
- trimesh PyPI (pin advice, extras): https://pypi.org/project/trimesh/
- Real trimesh issues: #2534/#2535 (contains regression 4.12.x), #1031 (non-watertight SDF), #2223 (collision semantics), #2264 (Docker extras), #2479 (deprecation cleanup)
- Advanced patterns (SEM weights, loop oscillation, budget tuning): [references/issues.md](references/issues.md)

Operational rule: VLMs propose; geometry snaps; physics validates; the loop re-prompts only on concrete failures. Final JointSpec emitted to cat 27 MUST have passed both schema validation AND a multi-sample physics/geometry check. In 2026, use Qwen/Qwen3.6-27B as the primary affordance proposer; Qwen3-VL-* names are valid legacy baselines only.
