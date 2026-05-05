---
name: articulation-priors-retrieval
description: Retrieves articulation and kinematic priors from PartNet-Mobility, GAPartNet, AKB-48, and related databases given a VLM-proposed object class, to regularize joint-type and axis predictions for lab-equipment digital twins in a video-to-URDF pipeline. Use when a Qwen3.6-27B VLM affordance pass needs grounding, confidence is below threshold, or category-specific defaults must be applied before URDF/physics export.
version: 2.0.0
author: Orchestra Research
license: MIT
tags: [Articulation Priors, PartNet-Mobility, SAPIEN, GAPartNet, AKB-48, ScrewSplat, Affordance, URDF, Lab Equipment, HVAC, SEM, Digital Twin]
dependencies: [sapien>=3, partnet-mobility-utils>=0.1, numpy>=1.26, trimesh>=4.12, scikit-learn>=1.3, faiss-cpu>=1.7]
---

# Articulation Priors Retrieval

## Quick start

This skill is a retrieval/regularization layer, not a kinematic predictor. SEM chambers and lab
instruments are long-tail objects, but their mechanisms—knobs, rotary valves, hinged doors,
sliding stages, drawers, latches—have strong priors in articulated-object datasets. The skill
loads those priors to (a) bias Qwen3.6-27B VLM prompts with canonical examples, (b) score VLM
predictions, and (c) supply category defaults when VLM confidence is low.

```python
from articulation_priors import PriorPack, retrieve

priors = retrieve(
    semantic_candidates=["rotary_valve", "knob", "hinged_cover"],
    geometry_features={
        "has_cylinder_axis": True,
        "has_hinge_knuckles": False,
        "obb_extents": [0.04, 0.04, 0.06],
    },
    sources=["partnet_mobility", "gapartnet", "akb48"],
)
print(priors.default_joint_type)      # "revolute"
print(priors.default_axis_strategy)   # "shaft_centerline_via_cylinder_pca"
print(priors.range_policy)            # "unknown unless detents/stops visible"
```

## Prior source matrix (May 2026)

| Source | Repo / access | License | Sample count | Status / canonicality |
|---|---|---|---|---|
| PartNet-Mobility / SAPIEN | https://github.com/haosulab/SAPIEN ; download via `download_partnet_mobility()` or `https://sapien.ucsd.edu/api/download/compressed/{id}.zip?token={tok}` | Research-gated (SAPIEN code Apache-2.0; assets require registration token) | 2,346 models, 46 categories, 14,068 movable parts, URDF per object | **Canonical kinematic base.** Not renamed, not replaced as of May 2026. Best HVAC/lab-instrument starting point; not domain-complete. |
| GAPartNet | https://github.com/PKU-EPIC/GAPartNet ; dataset via project form | CC BY-NC 4.0 | 1,166 objects, 27 categories, 8,489 part instances, 9 GAPart classes | **Canonical actionable-part overlay** for handles, lids, doors, buttons, drawers. Complements PartNet-Mobility; does not replace it. |
| AKB-48 | https://liuliu66.github.io/articulationobjects/ ; Google Drive links on project page | No explicit standalone license visible; treat as terms-restricted | 2,037 models, 48 categories, ArtiKG (appearance + structure + semantics + physics) | Useful real-world physics supplement when categories overlap; not canonical for HVAC. Verify Drive-package terms before use. |
| ScrewSplat | https://github.com/OllieBoyne/ScrewSplat | MIT (code); dataset terms from Drive download | ~13 PartNet-Mobility evaluation objects (CoRL 2025 eval corpus) | **Method/eval corpus only.** Gaussian-splat + screw-primitive reconstruction (RGB, 2025). Not a prior database; does not replace PartNet-Mobility. |
| Ditto | https://github.com/UT-Austin-RPL/Ditto | MIT (code); data inherits cited sources | Two benchmarks, 4 categories each, plus real-world examples | **Reconstruction method, not a database.** Known issue: pretrained checkpoint mispredicts prismatic joints as revolute on custom data (issue #18, Apr 2025). |
| ManipulaTHOR / APND | https://github.com/allenai/manipulathor (archived Dec 2025) | MIT (code) | 30 kitchen scenes, 69 interactable categories | **Archived/abandoned** as of Dec 5, 2025. Do not use for new work. |
| OPDMulti / OPDFormer | https://github.com/3dlg-hcvc/OPDMulti | MIT | Single-view openable-part predictions | Legacy stack (Python 3.7 / PyTorch 1.10.1 / CUDA 11.1.1); still functional as a single-view evaluator in a separate env. |

> **HVAC / lab-instrument canonical stack (May 2026):** PartNet-Mobility (URDF kinematic base) +
> GAPartNet (actionable-part labels) + optional AKB-48 physics supplement. Map domain parts
> (rotary valves, dampers, fume-hood sashes, centrifuge lids, pipette plungers) onto these
> primitives; no single dataset covers the domain natively.

## Core data structures

```python
from dataclasses import dataclass, field

@dataclass
class PriorPack:
    semantic_candidates: list[str]
    default_joint_type: str                 # "revolute" | "prismatic" | "fixed"
    default_axis_strategy: str              # "shaft_centerline_via_cylinder_pca" | "hinge_barrel_pca" | "rail_direction"
    default_anchor_strategy: str            # "shaft_center" | "hinge_pin_midpoint" | "carriage_centroid_on_rail"
    range_policy: str                       # "unknown unless stops visible" | "[0, pi/2] if cover" | "rail_length_minus_carriage"
    canonical_examples: list[dict] = field(default_factory=list)
    semantic_aliases: list[str] = field(default_factory=list)
    interaction_verbs: list[str] = field(default_factory=list)
    source_weights: dict[str, float] = field(default_factory=lambda: {
        "partnet_mobility": 1.0, "gapartnet": 0.7, "akb48": 0.5
    })
```

## Common workflows

### Workflow 1: Build a category prior pack for a SEM rotary valve

```
- [ ] Collect Qwen3.6-27B VLM semantic candidates (rotary_valve_handle, knob, handwheel)
- [ ] Download PartNet-Mobility URDFs for "Faucet", "Window", "Bottle" categories via SAPIEN token API
- [ ] Extract joint axes, types, and limits using PMObject + PMTree
- [ ] Query GAPartNet for round_fixed_handle / lever taxonomy
- [ ] Filter by OBB aspect ratio similarity to observed geometry
- [ ] Aggregate axis-strategy prior: shaft_centerline or normal-to-circular-face
- [ ] Aggregate range prior: full rotation if >90% PM examples are; stop-limited otherwise
- [ ] Emit PriorPack → feed to VLM prompt and scoring validator
```

```python
import os
from sapien.asset import download_partnet_mobility
from partnet_mobility_utils.data import PMObject, PMTree, Semantics

TOKEN = os.environ["SAPIEN_ACCESS_TOKEN"]

def load_pm_priors(model_ids: list[str], cache_dir: str) -> list[dict]:
    records = []
    for mid in model_ids:
        path = download_partnet_mobility(mid, token=TOKEN, directory=cache_dir)
        obj = PMObject(path)
        sem = Semantics.from_file(obj.semantics_fn)
        tree = PMTree.parse_urdf(obj.urdf_fn)
        for j in tree.joints:
            if j.type in {"revolute", "prismatic"}:
                records.append({
                    "model_id": mid, "category": obj.category,
                    "joint_type": j.type, "limits": j.limits,
                    "part_label": sem.get_label(j.child),
                })
    return records
```

**SEM/lab equipment defaults:**

- **Knob / rotary valve / handwheel**: `revolute`; axis along shaft or normal to circular face; `[-π, π]` only when continuous rotation is plausible; use stop-limited ranges when valve markings or detents are visible.
- **Linear stage / specimen drawer**: `prismatic`; axis along rails or screw shaft; range = `rail_length − carriage_length` (never VLM-guessed).
- **Hinged cover / load-lock door / chamber hatch**: `revolute`; axis through hinge barrel line; range opens from 0; validator clips by collision.
- **Ports / flanges / screws / detector housings / fixed brackets**: `fixed` unless clear motion evidence. A visible fastener is not itself an affordance.

### Workflow 2: Score a Qwen3.6-27B VLM prediction against priors

```
- [ ] Receive JointSpec from Qwen3.6-27B (joint_type, axis, range, anchor, semantic_label)
- [ ] Find top-k similar priors by semantic + OBB feature similarity (FAISS or sklearn)
- [ ] Compute disagreement: joint_type_match, axis_strategy_match, range_in_distribution
- [ ] Penalize: prismatic predicted when revolute prior dominant; range outside [p5, p95]
- [ ] Emit prior_score in [0, 1]; concatenate with geometry validator score
```

```python
def score_against_priors(spec, prior_pack: PriorPack) -> float:
    score = 0.0
    if spec.joint_type == prior_pack.default_joint_type:
        score += 0.5
    if any(v in prior_pack.interaction_verbs for v in spec.interaction_verbs):
        score += 0.2
    if prior_pack.default_joint_type == "revolute" and prior_pack.canonical_examples:
        spans = [ex["limits"][1] - ex["limits"][0]
                 for ex in prior_pack.canonical_examples if ex.get("limits")]
        if spans:
            s = sorted(spans)
            p5, p95 = s[max(0, len(s)//20)], s[min(len(s)-1, len(s)*19//20)]
            span = spec.range[1] - spec.range[0]
            if p5 <= span <= p95:
                score += 0.3
    return min(1.0, score)
```

### Workflow 3: VLM fallback with prior defaults

```
- [ ] Detect uncertainty: confidence < 0.65 or joint_type == "unknown"
- [ ] Retrieve PriorPack matching semantic_label + OBB extents
- [ ] If priors agree on joint_type, apply PriorPack.default_joint_type
- [ ] Snap axis via geometry routine (hinge barrel PCA, rail direction, cylinder PCA)
- [ ] Apply range_policy (often "unknown" until physical measurement)
- [ ] Mark prediction "prior_assisted" so downstream loop knows it is not VLM-pure
```

```python
def fallback_with_priors(vlm_pred, prior_pack: PriorPack, geometry):
    if vlm_pred.confidence >= 0.65 and vlm_pred.joint_type != "unknown":
        return vlm_pred
    pred = vlm_pred.model_copy()
    pred.joint_type = prior_pack.default_joint_type
    if prior_pack.default_axis_strategy == "hinge_barrel_pca" and geometry.has_hinge_knuckles:
        pred.axis, pred.anchor = geometry.hinge_axis, geometry.hinge_pin_midpoint
    elif prior_pack.default_axis_strategy == "rail_direction" and geometry.has_parallel_rails:
        pred.axis, pred.anchor = geometry.rail_axis, geometry.carriage_centroid_on_rail
    elif prior_pack.default_axis_strategy == "shaft_centerline_via_cylinder_pca" and geometry.has_cylinder_axis:
        pred.axis, pred.anchor = geometry.cylinder_axis, geometry.cylinder_center
    pred.failure_reasons.append(f"prior_assisted_via_{prior_pack.default_axis_strategy}")
    return pred
```

## SAPIEN environment setup

PartNet-Mobility URDFs are loaded via SAPIEN. Offscreen rendering requires Vulkan/EGL in Docker.

```bash
docker run --rm --gpus all \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics \
  -e VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json \
  -v "$PWD":/workspace -w /workspace \
  sapien:cu124 \
  python load_partnet_mobility.py
```

```python
import sapien

engine = sapien.Engine()
renderer = sapien.SapienRenderer(offscreen_only=True)
engine.set_renderer(renderer)
scene = engine.create_scene()
loader = scene.create_urdf_loader()
articulation = loader.load("path/to/partnet_mobility/<id>/mobility.urdf")

for joint in articulation.get_joints():
    if joint.type in {"revolute", "prismatic"}:
        print(joint.name, joint.type, joint.get_limits().tolist())
```

## GAPartNet actionable-part taxonomy

GAPartNet annotates 9 functional part classes across PartNet-Mobility and AKB-48. Use the
taxonomy as semantic_label vocabulary for Qwen3.6-27B prompts. CC BY-NC 4.0: do not bundle
into a commercial pipeline.

```python
GAPART_TO_LAB = {
    "round_fixed_handle": ["rotary_knob", "valve_handle", "micrometer_knob"],
    "lever":              ["chamber_door_handle", "rotary_valve_lever"],
    "drawer":             ["specimen_drawer", "tool_drawer"],
    "lid":                ["chamber_lid", "load_lock_lid", "centrifuge_lid"],
    "door":               ["chamber_door", "access_panel", "fume_hood_sash"],
    "button":             ["control_button", "emergency_stop"],
}
```

## Retrieval index

Build an offline FAISS index keyed by (semantic embedding, OBB aspect ratio, contact-feature flags).

```python
import faiss, numpy as np

def make_feature(entry: dict) -> np.ndarray:
    return np.concatenate([
        entry["semantic_onehot"],   # category one-hot
        entry["obb_aspect"],        # [l/w, l/h]
        entry["geometry_flags"],    # [has_hinge, has_rail, has_cylinder]
    ]).astype(np.float32)

features = np.stack([make_feature(e) for e in priors_db])
index = faiss.IndexFlatL2(features.shape[1])
index.add(features)

def retrieve_top_k(query: np.ndarray, k: int = 5):
    _, idx = index.search(query.reshape(1, -1), k)
    return [priors_db[i] for i in idx[0]]
```

## When to use vs alternatives

**Use this skill when:**
- Qwen3.6-27B VLM confidence < 0.65 or `joint_type == "unknown"`
- Need a calibration baseline for benchmarking URDF output
- Category-specific defaults must be applied (e.g., chamber doors are revolute, not free)
- Building prompt examples for structured VLM affordance queries

**Do NOT:**
- Use this as the sole source of joint parameters — lab equipment has long-tail mechanisms (rotary feedthroughs, magnetically coupled actuators) not covered by any dataset.
- Redistribute GAPartNet or AKB-48 assets commercially without verifying CC BY-NC 4.0 / Drive terms.
- Mix OPDMulti (Python 3.7 / PyTorch 1.10.1 / CUDA 11.1.1) into the main CUDA 12.x image.
- Rely on ManipulaTHOR for new work — repo archived Dec 2025.

## Common issues

### SAPIEN offscreen render fails: no Vulkan device

Symptom: `cannot create Vulkan instance`, `no Vulkan ICD found`.  
Fix: install NVIDIA Vulkan ICD inside container; set `VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json`; ensure Docker `--gpus all` with `graphics` capability.

### PartNet-Mobility URDF Y-up vs Z-up mismatch

Symptom: loaded articulation floats or faces wrong direction; child-parent transforms inconsistent.  
Fix: normalize object frames before scoring; many PartNet-Mobility entries assume Y-up while lab pipelines use Z-up. Record `T_object_world` before any downstream transform.

### GAPartNet dataset form-gating

Symptom: dataset not available for direct download; checkpoint links also form-gated.  
Fix: submit the official access form at the PKU-EPIC project page. Cache approved dataset locally; do not redistribute. See GAPartNet issue #23 (Jun 2025) regarding URDF structure and mesh-modification provenance.

### Ditto mispredicts prismatic joints on custom data

Symptom: pretrained `Ditto_s2m.ckpt` predicts almost all prismatic joints as revolute on real scenes.  
Root cause: documented in Ditto issue #18 (Apr 2025); model is biased toward revolute from training distribution.  
Fix: do not use Ditto as a general prior database or standalone predictor; use only as a reconstruction method evaluated on its own benchmark.

### ScrewSplat artifacts on Google Drive (not Hugging Face)

Symptom: artifacts not findable on Hugging Face; links appear broken.  
Fix: see ScrewSplat issue #3 (Aug 2025) — authors were asked to publish on Hugging Face but had not yet done so as of that filing. Download from the Google Drive link in the repo README; mirror internally.

### AKB-48 unstable download links

Symptom: GitHub repo is sparse; actual data is on the project homepage Google Drive.  
Fix: use the project page URL directly; mirror to a stable internal URL; record dataset version and Drive file ID.

## Resources

- PartNet-Mobility / SAPIEN: https://github.com/haosulab/SAPIEN (Apache-2.0 code; assets gated)
- PartNet-Mobility asset browser: https://sapien.ucsd.edu/browse
- partnet-mobility-utils: https://github.com/r-pad/partnet_mobility_utils
- GAPartNet: https://github.com/PKU-EPIC/GAPartNet (CC BY-NC 4.0)
- AKB-48: https://liuliu66.github.io/articulationobjects/ (terms-restricted; verify before use)
- ScrewSplat (CoRL 2025): https://github.com/OllieBoyne/ScrewSplat (MIT code)
- Ditto: https://github.com/UT-Austin-RPL/Ditto (MIT code; prismatic-bias caveat)
- ManipulaTHOR: https://github.com/allenai/manipulathor (ARCHIVED Dec 2025 — do not use)
- OPDMulti: https://github.com/3dlg-hcvc/OPDMulti (MIT; legacy Python 3.7 stack)

Operational rule: priors regularize Qwen3.6-27B hypotheses; geometry decides final parameters.
When VLM and priors disagree, prefer the source with stronger evidence; when both disagree with
geometry, defer to geometry.
