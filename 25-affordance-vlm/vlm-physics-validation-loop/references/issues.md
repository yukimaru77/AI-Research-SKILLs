# Validation Loop — Issues, Patterns, and Advanced Reference

Audit snapshot: trimesh 4.12.2 (May 1 2026), python-fcl 0.7.0.11 (Apr 8 2026), sapien 3.0.3 (Mar 10 2026). Verified 2026-05-05.

---

## Verified trimesh 4.x GitHub issues

### Proximity / signed-distance / containment

**Issue #2534** — "mesh.contains regression in 4.12.x", opened Apr 29 2026.
Reporter showed `mesh.contains([[0,0,0]])` returning True for a point inside a subtracted cavity changed behavior between 4.11.5 and 4.12.1. Directly relevant: validation loops that rely on inside/outside tests are affected.

**PR #2535** — "Release: Mesh.contains fix", merged Apr 30 2026.
Fixed #2534 by restoring a scale-aware offset broken by an Embree 2→4 change. Ships in 4.12.2. Pin to `trimesh==4.12.2` minimum.

**Issue #1031** — "Signed Distance" (opened 2020, still canonical for non-watertight behavior).
Documents unexpected positive signed distances; explicitly connects the issue to non-watertight meshes. Trimesh sign convention confirmed: positive = inside/near-surface, negative = outside. This is the opposite of many SDF libraries.

### Collision / containment semantics

**Issue #2223** — "Collision Detection Inaccuracy", opened May 8 2024.
Example involves nested objects and confusion between collision and containment semantics. `CollisionManager` detects surface interference, NOT semantic containment. Relevant for digital-twin validation where "object inside cavity but not touching" must be handled separately.

**PR #2475** — `CollisionManager.min_distance_internal(name=...)`, merged Nov 7 2025.
Added optional `name` parameter to `min_distance_internal()` for clearance checks involving one managed object against the rest. Preserves existing behavior.

**PR #2479** — Collision name release and deprecation cleanup, merged Nov 24 2025.
Released #2475. Also applied a March 2024 deprecation by removing `Trimesh.remove_degenerate_faces` and `Trimesh.remove_duplicate_faces`. Prefer `mesh.process(validate=True)` plus explicit checks.

### Install / Docker

**Issue #2264** — `trimesh[easy]` Docker install failure, opened Aug 12 2024.
Wheels for `manifold3d` and `vhacdx` fail to build in some container images. Fix: pin explicit packages, not broad extras.

---

## Verified trimesh 4.x API surface (2026-05-05)

### ProximityQuery

```python
pq = trimesh.proximity.ProximityQuery(mesh)
signed = pq.signed_distance(points)   # (n,3) array → (n,) float
```

- Still present, not renamed.
- Does NOT accept a `transform` argument per call. Transform query points into the target mesh frame before calling.
- Sign: positive = inside / near surface; negative = outside.

### CollisionManager

```python
from trimesh.collision import CollisionManager
cm = CollisionManager()
cm.add_object("fixed", mesh_a, transform=T_a)
hit = cm.in_collision_single(mesh_b, transform=T_b)
distance = cm.min_distance_single(mesh_b, transform=T_b)
```

- Both methods still present, not renamed.
- `in_collision_single(mesh, transform=None, return_names=False, return_data=False)` — note the docs use `return_names` in parameter text but `return_name` in signature text (PR #2479 area). Test locally before relying on name-return.
- `min_distance_single(mesh, transform=None, return_name=False, return_data=False)`.
- `CollisionManager` depends on `python-fcl`; pin `python-fcl==0.7.0.11`.

### Transform helpers

```python
from trimesh.transformations import rotation_matrix, translation_matrix
R = rotation_matrix(angle, direction, point=None)   # angle in radians; 4×4 homogeneous
T = translation_matrix(direction)                   # 4×4 translation matrix
```

No verified 2024–2026 breaking rename or signature change.

### Deprecated methods removed in 4.x

- `Trimesh.remove_degenerate_faces` — removed (PR #2479)
- `Trimesh.remove_duplicate_faces` — removed (PR #2479)
- Use `mesh.process(validate=True)` instead.

---

## SAPIEN 3 API surface (sapien 3.0.3, 2026-05-05)

Package name: `sapien` (not `sapien3`). PyPI: https://pypi.org/project/sapien/

```python
import sapien

scene = sapien.Scene()
scene.set_timestep(1 / 240)

loader = scene.create_urdf_loader()
loader.fix_root_link = True
robot = loader.load("robot.urdf")   # returns PhysxArticulation (sapien.physx.PhysxArticulation)

robot.set_root_pose(sapien.Pose([0, 0, 0.5], [1, 0, 0, 0]))
robot.set_qpos([0.3])
q = robot.get_qpos()
scene.step()
contacts = scene.get_contacts()
```

Headless install (Ubuntu-like):
```bash
apt-get install -y libegl1 libxext6
# For NVIDIA Docker:
# NVIDIA_DRIVER_CAPABILITIES=graphics,utility,compute
pip install "sapien==3.0.3"
```

SAPIEN 3 requires Vulkan/EGL and a GPU. No confirmed OSMesa-only path as of audit date. For CPU-only inference servers, use trimesh as default validator and run SAPIEN on GPU nodes.

Minimal safe URDF for SAPIEN: two links, one revolute joint, explicit `<inertial>` on EVERY link, collision geometry, visual geometry, joint axis, joint limit, and damping. Omitting inertials causes SAPIEN to silently use degenerate dynamics.

---

## articulate-anything reference

- Repo: https://github.com/vlongle/articulate-anything (MIT; Python 3.9; PartNet-Mobility)
- Pattern worth imitating: actor-critic harness — proposer suggests JointSpec, critic validates by simulation, failures fed back as natural-language guidance.
- Stack constraint: Python 3.9 conflicts with Qwen3-VL CUDA 12.8 environment. Keep in a SEPARATE env. Port the pattern only.
- PartNet-Mobility orientation gotcha: objects may arrive in Y-up vs Z-up. Normalize frames; record `T_partnet_to_object` in manifest before scoring.
- No verified 2024–2025 public repo with the same exact actor-critic pattern (VLM proposes → physics validates → critic re-prompts) outside of articulate-anything. Related 2025/2026 systems: Articulate AnyMesh, URDF-Anything, PhysX-Anything.

---

## SEM-specific scoring weights

```python
SEM_SCORING_WEIGHTS = {
    "semantic_prior":                0.5,
    "geometry_alignment":            1.0,
    "contact_plausibility":          0.8,
    "collision_free_motion":         1.5,   # most important for SEM safety
    "range_stop_consistency":        0.7,
    "parent_child_consistency":      1.0,
    "unsupported_free_motion_penalty": 2.0,  # penalize "free" without strong evidence
}

def weighted_total(scores, weights=SEM_SCORING_WEIGHTS):
    return (
        sum(getattr(scores, k) * w for k, w in weights.items() if not k.endswith("penalty"))
        - sum(getattr(scores, k) * w for k, w in weights.items() if k.endswith("penalty"))
    )
```

Strongest SEM checks: axis through actual shaft/hinge/rail; moving part remains connected to parent; no impossible chamber-wall collision in claimed range; no `free` joint unless part is genuinely detached.

---

## Loop oscillation prevention

```python
class LoopHistory:
    def __init__(self):
        self.tried = set()

    def signature(self, cand):
        sign = canonical_axis_sign(cand.axis)[0] >= 0
        return (cand.joint_type, sign, round(cand.range[0], 3), round(cand.range[1], 3))

    def is_duplicate(self, cand) -> bool:
        return self.signature(cand) in self.tried

    def add(self, cand):
        self.tried.add(self.signature(cand))
```

Reject duplicate proposals; force VLM to re-classify `joint_type` if axis/anchor space is exhausted.

---

## Loop budget defaults and tuning

```python
from dataclasses import dataclass

@dataclass
class LoopBudget:
    max_attempts: int = 3
    max_total_seconds: float = 60.0
    max_validator_calls: int = 32
```

Budget profiles:
- SEM batch annotation (offline, accuracy-first): `max_attempts=5`, `max_total_seconds=180`, `max_validator_calls=64`
- Interactive demo (latency-first): `max_attempts=2`, `max_total_seconds=15`, `max_validator_calls=16`

---

## Sample count by joint type

| Joint type | Recommended samples | Reason |
|------------|---------------------|--------|
| revolute   | 16                  | Sweep range; collision risk concentrated at endpoints |
| prismatic  | 8–16                | Linear rails; endpoints are usually the failure case |
| fixed      | 1                   | Single check at zero displacement |
| free       | n/a                 | Sentinel; do not simulate |

---

## Common failure modes

| Failure | Cause | Fix |
|---------|-------|-----|
| All candidates fail validation | Mesh in mm, axis/anchor in meters | Verify mesh units; print contact map before loop |
| Re-prompt yields prose, not JSON | Bypassed constrained decoder | Re-run `repair_until_valid` on every VLM response |
| Loop oscillates between two failures | No history tracking | Use `LoopHistory`; reject duplicate signatures |
| Validator too slow for 16 samples | Full mesh-mesh intersection | Cache parent BVH; subsample to ~500 vertices; use `ProximityQuery` |
| Articulate-Anything env conflict | Python 3.9 in main CUDA 12.8 image | Keep in separate env; port pattern only |
| PartNet-Mobility orientation drift | Y-up vs Z-up frame mix | Normalize frames; record `T_partnet_to_object` in manifest |
| Signed distance wrong on scan mesh | Non-watertight geometry | Treat as heuristic; combine with FCL boolean and unsigned distance |
| SAPIEN fails on CPU-only server | No GPU/Vulkan | Use trimesh for static checks; SAPIEN on GPU nodes only |

---

## Geometry snapping rules

- Revolute with hinge knuckles: `abs(np.dot(geom.hinge_axis, candidate.axis)) > 0.85` → snap axis and anchor.
- Prismatic with parallel rails: `abs(np.dot(geom.rail_axis, candidate.axis)) > 0.85` → snap axis, anchor, and range.
- Range snap for prismatic: `range = [0.0, rail_length - carriage_length]`.
- Range snap for revolute: only when stops/detents are detected; otherwise keep VLM range.

---

## Multi-part scenes

Validate each moving part INDEPENDENTLY against the static parent first. Cross-validation of co-actuation (door closed prevents stage withdrawal) is OPTIONAL; it inflates compute. Reserve for final integration tests, not per-part loops.

---

## Confidence calibration

```python
def calibrate_confidence(scores, vlm_confidence: float) -> float:
    physical_score = min(1.0, scores.total / 5.0)
    return 0.4 * vlm_confidence + 0.6 * physical_score
```

---

## Logging fields per attempt

- `attempt_idx`
- `candidate_json` (raw VLM output, post-schema-validation)
- `snapped_json` (after geometry snapping)
- `sample_results` (per-sample collision/contact metrics)
- `scores_breakdown` (semantic / geometry / contact / collision / range / parent-child / penalty)
- `latency_ms`
- `prior_pack_id`
- `schema_hash`

Keep raw VLM responses (failed AND final). Failed responses are the most valuable for debugging prompt regressions.

---

## OPDMulti cross-check

OPDMulti predictions can cross-check VLM JointSpec by mapping `motion_type` → `joint_type` and computing axis agreement with `abs(np.dot(...))`. Use as a single-view evaluator; do NOT replace the geometric validator.
Repo: https://github.com/3dlg-hcvc/OPDMulti (MIT; legacy stack)
