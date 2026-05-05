---
name: screwsplat-articulation
description: Research-reference skill for ScrewSplat (seungyeon-k/ScrewSplat-public, MIT, late-2025), a GS-native method that jointly optimizes Gaussians and screw axes from multi-state RGB to recover revolute and prismatic joint axes. Use for offline cross-validation of the geometric estimator and algorithm mining; production path is multistate-diff-open3d (cat 24). Requires original multi-state RGB captures — cannot consume pre-trained PLYs directly.
version: 2.0.0
author: Orchestra Research
license: MIT
tags: [3DGS, GS, Screw Axis, Articulation, ScrewSplat, Research Reference, gsplat, Joint Recovery]
dependencies: [python==3.10, torch>=2.1, pytorch-cuda==12.1, gsplat>=0.1.0, open3d, plyfile, scipy, opencv-python, omegaconf, trimesh, pyglet==1.5.15, transformers==4.46.3, numba, pycuda, scikit-optimize]
---

# Articulation with ScrewSplat

**RESEARCH REFERENCE ONLY.** ScrewSplat (`seungyeon-k/ScrewSplat-public`, MIT) is the strongest late-2025 public Gaussian Splatting native articulation signal. It jointly optimizes Gaussians and screw axes from multi-state RGB, recovering revolute and prismatic joint axes with explicit screw parameterization.

**Production path**: `multistate-diff-open3d` (cat 24). ScrewSplat supplements it as an offline validator and algorithm-mining source — never as the runtime estimator.

Key facts:
- Repo: `https://github.com/seungyeon-k/ScrewSplat-public` — MIT, research-grade, no published releases, last activity ~2025-10-17
- Requires multi-state RGB + camera poses; cannot consume pre-trained splats
- Joint optimization cost is O(hours) on a single A100 — not synchronous-loop viable
- Paper compares against PARIS, PARIS*, DTA on single- and multi-joint joint-axis metrics

## Quick start

```bash
# Isolated Docker image — avoids collisions with LUDVIG (CUDA 11.8) and SAGA (CUDA 11.6)
docker build -f Dockerfile.screwsplat-cu121 -t screwsplat:cu121 .

docker run --gpus all --ipc=host --shm-size=32g \
  -v /data:/data -it screwsplat:cu121

# Inside the container:
git clone https://github.com/seungyeon-k/ScrewSplat-public.git
cd ScrewSplat-public
git checkout <pinned-SHA>    # pin to ~2025-10-17 commit, do NOT chase HEAD

# Minimal run (verify upstream README for exact CLI):
python train.py --config configs/lab_focus_knob.yaml \
  --data_dir /data/microscope_knob_multistate \
  --output_dir runs/microscope_focus_knob
```

Dockerfile essentials:
```dockerfile
FROM nvidia/cuda:12.1.1-devel-ubuntu22.04
# Install Miniforge3 with Python 3.10, then:
RUN pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
RUN pip install git+https://github.com/nerfstudio-project/gsplat.git@<pinned-SHA>
RUN pip install tensorboard tqdm open3d plyfile scipy opencv-python omegaconf \
    trimesh "pyglet==1.5.15" lxml imageio openexr numba scikit-image \
    pycuda scikit-optimize "transformers==4.46.3"
```

Verify: `python -c "import gsplat; import torch; print(torch.cuda.is_available())"` must print `True`.

## Common workflows

### Workflow 1: Load splat data and recover joint axes

Goal: re-optimize from preserved multi-state RGB and extract the recovered screw axis.

**Task Progress**:
- [ ] Confirm original multi-state RGB is available (trained PLYs alone are insufficient)
- [ ] Organize per-state image directories and shared camera intrinsics (COLMAP poses)
- [ ] Author `configs/lab_focus_knob.yaml` — reference upstream README for required keys
- [ ] Launch training: `python train.py --config configs/lab_focus_knob.yaml ...`
- [ ] Monitor convergence via TensorBoard (`tensorboard --logdir runs/`)
- [ ] After training, parse recovered joint: type (`revolute` / `prismatic`), axis direction (unit vector), axis point (world coordinates), optional pitch for screw joints
- [ ] Log result to `cross_validation/screwsplat_<scene>.json` with timestamp and commit SHA

Config YAML minimum structure (verify against upstream README):
```yaml
data:
  states:
    - images: /data/state0/images
      poses:  /data/state0/transforms.json
    - images: /data/state1/images
      poses:  /data/state1/transforms.json
train:
  iterations: 30000
  lambda_joint: 0.1
output:
  dir: runs/scene_name
```

---

### Workflow 2: Hungarian matching for multi-joint cross-validation

Goal: align ScrewSplat's per-joint output to the geometric spine's per-cluster output for a multi-joint scene (e.g., operator console with knob + slider).

**Task Progress**:
- [ ] Capture multi-state RGB with each joint at 2+ positions; all joints must be visible across states
- [ ] Run ScrewSplat with multi-joint config; parse `N_joints` from output
- [ ] Run `multistate-diff-open3d` Workflow B independently; obtain `M_clusters` with axes and centroids
- [ ] Build cost matrix `C[i,j]` = centroid distance between ScrewSplat joint `i` and geometric cluster `j`
- [ ] Solve assignment: `row_ind, col_ind = scipy.optimize.linear_sum_assignment(C)`
- [ ] For each matched pair: compute axis-angle between recovered axes; log to cross-validation record
- [ ] Apply confidence promotion table (see cross-validation policy below)
- [ ] Flag unmatched joints (`geometric_only` or `screwsplat_only`) for operator review

```python
import numpy as np
from scipy.optimize import linear_sum_assignment
from scipy.spatial.distance import cdist

def match_joints(screwsplat_joints, geometric_clusters):
    """
    screwsplat_joints: list of dicts with 'centroid' (3,), 'axis' (3,), 'type'
    geometric_clusters: list of dicts with 'centroid' (3,), 'axis' (3,), 'type'
    Returns: matched pairs (ss_idx, geo_idx), unmatched_ss, unmatched_geo
    """
    ss_centroids  = np.array([j['centroid'] for j in screwsplat_joints])
    geo_centroids = np.array([c['centroid'] for c in geometric_clusters])
    C = cdist(ss_centroids, geo_centroids)           # shape (N, M)
    row_ind, col_ind = linear_sum_assignment(C)
    threshold_m = 0.10                               # 10 cm max match radius
    matched = [(r, c) for r, c in zip(row_ind, col_ind) if C[r, c] < threshold_m]
    matched_ss  = {r for r, _ in matched}
    matched_geo = {c for _, c in matched}
    unmatched_ss  = [i for i in range(len(screwsplat_joints))   if i not in matched_ss]
    unmatched_geo = [i for i in range(len(geometric_clusters))  if i not in matched_geo]
    return matched, unmatched_ss, unmatched_geo
```

---

### Workflow 3: Algorithm mining — screw parameterization and loss design

Goal: extract ScrewSplat's screw-axis parameterization, joint-axis loss, and confidence logic for potential integration into the geometric spine — without taking ScrewSplat as a runtime dependency.

**Task Progress**:
- [ ] Read loss construction code in the upstream repo; locate the screw parameterization (per-state Gaussian transforms parameterized by screw axes)
- [ ] Document: axis representation, how pitch is separated from rotation, per-Gaussian part-membership weighting
- [ ] Read the joint-axis loss terms; identify which terms correspond to point-consistency vs axis-consistency
- [ ] Write `references/algorithm-mining.md` summarizing findings (2-4 pages max)
- [ ] Identify any pieces directly portable to `aggregate_axis_observations()` in the geometric spine
- [ ] Add unit tests for any ported primitives against synthetic two-rigid-body scenes

## When to use vs alternatives

**RESEARCH REFERENCE — not a production runtime.**

| Scenario | Recommended path |
|---|---|
| Production joint-axis recovery | `multistate-diff-open3d` (cat 24) |
| Offline cross-validation (RGB preserved) | ScrewSplat (this skill) |
| Algorithm mining for loss / parameterization | ScrewSplat (this skill) |
| Furniture-class validation, fast turnaround | `articulation-ditto-prior` |
| No original RGB, only pre-trained PLYs | `multistate-diff-open3d` only |

Compared to other late-2025 GS-native articulation candidates:

- **ArticulatedGS** (MIT): legacy stack (Python 3.7, PyTorch 1.13.1, CUDA 11.6), "own dataset" TODOs — watchlist only, do not build on it
- **SplArt** (2025): Nerfstudio + SAM2 + gsplat + CUDA 12.4 — watchlist; ScrewSplat has stronger joint-axis/type recovery per Phase A
- **REArtGS**: watchlist only; track for future evaluation
- **PARIS / PARIS***: NeRF-era, conceptually clean but not GS-native; superseded for GS pipelines
- **DTA**: compared baseline in ScrewSplat paper; superseded

## Cross-validation policy

ScrewSplat agreement is additive evidence, not authoritative. Apply:

| geometric spine | ScrewSplat | action |
|---|---|---|
| revolute, conf > 0.7 | revolute, axis-angle < 5 deg, axis-line dist < 5 cm | promote to `confidence_strong` |
| revolute or prismatic | screw with non-trivial pitch | annotate `screw_evidence: screwsplat`; surface to operator |
| prismatic | revolute | downgrade; request additional state from operator |
| any | failed or unstable optimization | discard ScrewSplat output |

Note: ScrewSplat's RGB-driven loss is sensitive to specular highlights (chrome knobs, polished lenses). On such surfaces, weight toward the geometric estimate; the geometric spine works on Gaussian centers and avoids the RGB specularity issue.

## Common issues

**Not a "trained splat in, joints out" library.** ScrewSplat jointly optimizes Gaussians and axes from raw multi-state RGB. Pre-trained PLYs alone are insufficient — the original per-state image sequences plus COLMAP poses are required.

**Compute cost.** O(hours) per scene on a single A100. Schedule as an asynchronous background job; never block the agent loop on it.

**`pyglet==1.5.15` pin.** Newer pyglet breaks the mesh viewer. Keep this pin frozen — do not let dependency updates float it.

**`transformers==4.46.3` pin.** Newer transformers versions break LangSAM compatibility inside ScrewSplat. Keep frozen.

**`pycuda` requires CUDA devel image.** `pycuda` builds against `nvcc`; runtime CUDA images lack it. Use `nvidia/cuda:12.1.1-devel-ubuntu22.04` as the base — not the runtime variant.

**OpenEXR linker errors.** `openexr` Python bindings can fail to link on some Ubuntu versions. Pin `OpenEXR-Python==1.3.9` and `Imath==3.1.x`; verify `import OpenEXR` before training.

**LangSAM double-loading.** ScrewSplat's real-world data path uses LangSAM internally. If the agent already loaded LangSAM via `lift-2d-masks-ludvig`, patch ScrewSplat's data loader to consume pre-generated masks rather than running LangSAM a second time.

**Camera-pose precision.** If the pre-trained gsplat shows visible registration drift, re-run COLMAP refinement before ScrewSplat — unstable poses prevent joint optimization from converging.

**Multi-joint label assignment.** Match recovered joints to the geometric spine's clusters by Hungarian centroid distance, not by index — joint ordering from ScrewSplat is arbitrary.

**Frame conventions.** ScrewSplat follows gsplat (COLMAP) camera conventions. Ensure captured poses have been converted accordingly before training.

**State-count minimum.** Two states is the minimum; three or more improves axis recovery. Do not run ScrewSplat on single-state captures.

**Robot-control / text-guided code.** These code paths are present in the repo but are out of scope for this category. Do not invoke them; they belong to cat 25 (affordance/VLM) and cat 27 (physics sim).

## Advanced topics

**Screw parameterization** — ScrewSplat parameterizes joint motion as a screw transformation: a rotation about an axis combined with a translation along it (pitch). Pure revolute has pitch = 0; pure prismatic has infinite pitch. Extracting and adapting this parameterization for the geometric spine is the primary algorithm-mining target. See `references/algorithm-mining.md` (create after mining Workflow 3).

**Per-Gaussian membership weighting** — ScrewSplat assigns each Gaussian a soft part-membership weight, enabling gradient flow through both the geometry and the joint parameters jointly. This is architecturally different from the geometric spine's hard segmentation via cluster assignment.

**Confidence aggregation across states** — With N states, ScrewSplat can aggregate axis evidence across all N(N-1)/2 state pairs. The geometric spine currently aggregates via `aggregate_axis_observations()`. Review ScrewSplat's aggregation for robustness improvements (outlier downweighting, uncertainty propagation).

**gsplat HEAD pinning** — gsplat HEAD changes frequently. Record the exact commit SHA used to build the container and store it in the `references/install.md` pin table. Rebuilding with a different gsplat SHA may require ScrewSplat code changes.

**Multi-joint optimization** — ScrewSplat handles multiple joints in one pass. Per Phase A, the agent should validate multi-joint scenes (2+ interactive parts) using the Hungarian matching workflow (Workflow 2) to compare against independent per-cluster geometric estimates.

## Resources

- ScrewSplat repository: https://github.com/seungyeon-k/ScrewSplat-public
- ScrewSplat license (MIT): https://github.com/seungyeon-k/ScrewSplat-public/blob/main/LICENSE
- ScrewSplat open issues: https://github.com/seungyeon-k/ScrewSplat-public/issues
- gsplat (build dependency): https://github.com/nerfstudio-project/gsplat
- gsplat install docs: https://docs.gsplat.studio/main/installation.html
- Hungarian assignment (scipy): https://docs.scipy.org/doc/scipy/reference/generated/scipy.optimize.linear_sum_assignment.html
- COLMAP camera conventions: https://colmap.github.io/format.html
- PARIS (compared baseline): https://github.com/3dlg-hcvc/paris
- LangSAM / segment-geospatial: https://samgeo.gishub.org/text_sam/
- pyglet 1.5.x docs: https://pyglet.readthedocs.io/en/pyglet-1.5-maintenance/
- transformers 4.46.3: https://huggingface.co/docs/transformers/v4.46.3/index
- OpenEXR Python: https://pypi.org/project/OpenEXR/
- nvidia/cuda devel images: https://hub.docker.com/r/nvidia/cuda
- Open3D release notes: https://www.open3d.org/2025/01/30/open3d-0-19-release/
