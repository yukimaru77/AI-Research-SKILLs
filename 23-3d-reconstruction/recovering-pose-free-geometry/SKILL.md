---
name: recovering-pose-free-geometry
description: 'Recovers dense geometry and camera poses from unposed handheld video without COLMAP/SfM, targeting 3DGS pipelines for lab-equipment digital twins (SEM, optical benches). Canonical commercial path: VGGT-1B-Commercial (Meta custom AUP, excludes military) or MapAnything Apache-2.0. Research fallback: DUSt3R/MASt3R (CC-BY-NC-SA-4.0, non-commercial). Use when COLMAP registration < 50%, scene is specular metal/glass/low-texture, or enclosed geometry causes track fragmentation. CRITICAL LICENSE: DUSt3R, MASt3R, Spann3R, Fast3R are non-commercial only. NoPoSplat license files have unresolved conflicts — treat as research-only. Only facebook/map-anything-apache (Apache-2.0) and facebook/VGGT-1B-Commercial (custom AUP, commercial-permitted with restrictions) are cleared for commercial digital-twin pipelines.'
version: 2.0.0
author: Orchestra Research
license: MIT
tags: [Pose-Free Geometry, MapAnything, VGGT, DUSt3R, MASt3R, Fast3R, Spann3R, NoPoSplat, Pointmap, COLMAP Export, Apache-2.0, Non-Commercial, 3D Reconstruction, Digital Twin]
dependencies: [torch>=2.3.1, torchvision>=0.18.1, mapanything, vggt, dust3r, mast3r, numpy>=1.26.1, pupil-apriltags]
---

# Recovering Pose-Free Geometry

Operational fallback when COLMAP/hloc fails on lab-equipment scenes: specular metal, glass, low texture, or narrow camera motion. Produces dense pointmaps and approximate poses; exports COLMAP sparse models for gsplat or initializes a COLMAP+BA pass.

**Canonical method (May 2026):** VGGT-1B-Commercial for direct pose/depth/pointmap output with `demo_colmap.py --use_ba`; MapAnything Apache-2.0 as the license-clean alternative with metric output and COLMAP export. Both have documented gsplat handoff paths.

## Quick start

Commercial-safe default: MapAnything Apache-2.0 on A100.

```python
import torch
from mapanything.models import MapAnything
from mapanything.utils.image import load_images

device = "cuda"
views = load_images("path/to/images/", resolution_set=518, norm_type="dinov2")
views = [{k: (v.to(device) if hasattr(v, "to") else v) for k, v in x.items()} for x in views]
model = MapAnything.from_pretrained("facebook/map-anything-apache").to(device).eval()
with torch.no_grad():
    pred = model.infer(
        views, memory_efficient_inference=True, minibatch_size=1,
        use_amp=True, amp_dtype="bf16", apply_mask=True, mask_edges=True,
    )
pointmaps = [p["pts3d"].detach().cpu() for p in pred]
poses_c2w = [p["camera_poses"].detach().cpu() for p in pred]
```

Set `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True` to avoid fragmentation OOM.

## Environment pins (2026)

```
OS:          Ubuntu 22.04 in Docker
GPU:         A100 40 GB (min) / 80 GB (preferred)
CUDA:        12.1
Python:      3.12 (MapAnything); 3.11 (DUSt3R / MASt3R / Fast3R); 3.9 (Spann3R)
PyTorch:     2.3.1+cu121 (MapAnything/VGGT official pins)
MapAnything: github.com/facebookresearch/map-anything v1.1.1 (Mar 23 2026)
VGGT:        github.com/facebookresearch/vggt (no release tags; pin SHA)
DUSt3R:      github.com/naver/dust3r (no release tags; CVPR 2024; pin SHA)
MASt3R:      github.com/naver/mast3r (no release tags; MASt3R-SfM at 3DV 2025)
Fast3R:      github.com/facebookresearch/fast3r (no release tags; CVPR 2025)
Spann3R:     github.com/HengyiWang/spann3r checkpoint v1.01 (Feb 25 2025)
NoPoSplat:   github.com/cvg/NoPoSplat (ICLR 2025 research code; no releases)
gsplat:      >=1.3.0
numpy:       1.26.1 (VGGT hard requirement)
```

Install MapAnything:
```bash
git clone https://github.com/facebookresearch/map-anything.git && cd map-anything
conda create -n mapanything python=3.12 -y && conda activate mapanything
pip install -e ".[colmap]"   # includes COLMAP export deps
```

Install VGGT:
```bash
git clone https://github.com/facebookresearch/vggt && cd vggt
pip install -r requirements.txt && pip install -r requirements_demo.txt
```

Install DUSt3R / MASt3R (research container only):
```bash
git clone --recursive https://github.com/naver/dust3r.git && cd dust3r
conda create -n dust3r python=3.11 cmake=3.14.0 -y && conda activate dust3r
conda install pytorch torchvision pytorch-cuda=12.1 -c pytorch -c nvidia
pip install -r requirements.txt
# MASt3R — shares dust3r environment
git clone --recursive https://github.com/naver/mast3r.git && cd mast3r
pip install -r requirements.txt
```

## Common workflows

### 1. Primary commercial path: VGGT-1B-Commercial → COLMAP → gsplat

Task Progress:
- [ ] Accept VGGT AUP on HuggingFace (gated; custom vggt-aup-license; excludes military/warfare/ITAR)
- [ ] Curate 16–100 frames (A100 40 GB) or 32–200 (A100 80 GB); mask reflective surfaces
- [ ] Run COLMAP export with bundle-adjustment; verify image count and point density
- [ ] Sim(3)-align to AprilTag corners or measured caliper baseline
- [ ] Train gsplat/splatfacto on COLMAP-style output

```python
import torch
from vggt.models.vggt import VGGT
from vggt.utils.load_fn import load_and_preprocess_images
from vggt.utils.pose_enc import pose_encoding_to_extri_intri
from vggt.utils.geometry import unproject_depth_map_to_point_map

device, dtype = "cuda", torch.bfloat16
model = VGGT.from_pretrained("facebook/VGGT-1B-Commercial").to(device).eval()
images = load_and_preprocess_images(["000.png", "001.png", "002.png"]).to(device)
with torch.no_grad(), torch.cuda.amp.autocast(dtype=dtype):
    pred = model(images)
extrinsic, intrinsic = pose_encoding_to_extri_intri(pred["pose_enc"], images.shape[-2:])
pts = unproject_depth_map_to_point_map(pred["depth"], extrinsic, intrinsic)
```

```bash
cd /opt/vggt
python demo_colmap.py --scene_dir=/data/scene --use_ba \
  --max_query_pts=2048 --query_frame_num=5
# handoff to gsplat
pip install gsplat>=1.3.0
python examples/simple_trainer.py default \
  --data_factor 1 --data_dir /data/scene/colmap_output
```

Individual VGGT heads (for selective inference):
```python
aggregated_tokens_list, ps_idx = model.aggregator(images)
pose_enc = model.camera_head(aggregated_tokens_list)[-1]
depth_map, depth_conf = model.depth_head(aggregated_tokens_list, images, ps_idx)
point_map, point_conf = model.point_head(aggregated_tokens_list, images, ps_idx)
```

Artifact metadata to log:
```yaml
skill: recovering-pose-free-geometry
model_route: vggt-commercial
model_checkpoint: facebook/VGGT-1B-Commercial
license_basis: vggt-aup-license (commercial-permitted, excludes military)
commercial_safe: conditional
```

### 2. License-clean fallback: MapAnything Apache → COLMAP → gsplat

Task Progress:
- [ ] Curate 16–96 frames (A100 40 GB) or 32–256 (A100 80 GB); mask specular highlights
- [ ] Run MapAnything with confidence masking; reject low-confidence patches
- [ ] Export COLMAP sparse model; Sim(3)-align to AprilTag/caliper baseline
- [ ] Train gsplat or splatfacto

```bash
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
cd /opt/map-anything
python scripts/demo_colmap.py \
  --images_dir=/data/scene/images \
  --output_dir=/data/scene/mapanything_colmap \
  --apache --voxel_fraction=0.002 --save_glb
```

Coordinate conversion note: MapAnything outputs OpenCV cam2world (+X right, +Y down, +Z forward). COLMAP `images.txt` expects world-to-camera. Apply `np.linalg.inv(c2w)`, then convert R to Hamilton qvec `[qw, qx, qy, qz]`.

```yaml
skill: recovering-pose-free-geometry
model_route: mapanything
model_checkpoint: facebook/map-anything-apache
license_basis: Apache-2.0
commercial_safe: true
```

### 3. Research rescue: DUSt3R / MASt3R (NON-COMMERCIAL — CC-BY-NC-SA-4.0)

Task Progress:
- [ ] Confirm research-only authorization; log checkpoint ID and CC-BY-NC-SA-4.0 notice
- [ ] Run pairwise inference with complete scene graph
- [ ] Global alignment: `init="mst"`, niter=500, schedule="cosine", lr=0.01
- [ ] Sim(3)-align to AprilTag/known baseline; validate against calipers

```python
from dust3r.model import AsymmetricCroCo3DStereo
from dust3r.utils.image import load_images
from dust3r.image_pairs import make_pairs
from dust3r.inference import inference
from dust3r.cloud_opt import global_aligner, GlobalAlignerMode

device = "cuda"
model = AsymmetricCroCo3DStereo.from_pretrained(
    "naver/DUSt3R_ViTLarge_BaseDecoder_512_dpt"
).to(device).eval()
images = load_images(["000.png", "001.png", "002.png", "003.png"], size=512)
pairs = make_pairs(images, scene_graph="complete", prefilter=None, symmetrize=True)
output = inference(pairs, model, device, batch_size=1)
scene = global_aligner(output, device=device, mode=GlobalAlignerMode.PointCloudOptimizer)
scene.compute_global_alignment(init="mst", niter=500, schedule="cosine", lr=0.01)
poses_c2w = scene.get_im_poses()
pts3d = scene.get_pts3d()
masks = scene.get_masks()
```

MASt3R dense descriptor matching for low-texture/specular pairs (CC-BY-NC-SA-4.0):
```python
from mast3r.model import AsymmetricMASt3R
from mast3r.fast_nn import fast_reciprocal_NNs
import mast3r.utils.path_to_dust3r  # noqa: adds dust3r to sys.path
from dust3r.utils.image import load_images
from dust3r.inference import inference

model = AsymmetricMASt3R.from_pretrained(
    "naver/MASt3R_ViTLarge_BaseDecoder_512_catmlpdpt_metric"
).to(device).eval()
images = load_images(["000.png", "001.png"], size=512)
output = inference([tuple(images)], model, device, batch_size=1, verbose=False)
desc1 = output["pred1"]["desc"].squeeze(0).detach()
desc2 = output["pred2"]["desc"].squeeze(0).detach()
matches_im0, matches_im1 = fast_reciprocal_NNs(
    desc1, desc2, subsample_or_initxy1=8, device=device, dist="dot", block_size=2**13
)
```

Frame budgets: DUSt3R 6–20 frames (complete graph); MASt3R 2–30 frames (pairwise) or up to 80 (sparse retrieval with ASMK).

## Scale validation: AprilTag Sim(3) alignment

```python
import cv2, numpy as np
from pupil_apriltags import Detector

def umeyama_sim3(src, dst):
    """Fit dst ~= s * R @ src + t. src, dst: (N, 3) float64."""
    src, dst = np.asarray(src, np.float64), np.asarray(dst, np.float64)
    mu_s, mu_d = src.mean(0), dst.mean(0)
    X, Y = src - mu_s, dst - mu_d
    C = (Y.T @ X) / len(src)
    U, D, Vt = np.linalg.svd(C)
    S = np.eye(3); S[-1, -1] = 1.0 if np.linalg.det(U @ Vt) >= 0 else -1.0
    R = U @ S @ Vt
    var = (X * X).sum() / len(src)
    scale = np.trace(np.diag(D) @ S) / var
    return scale, R, mu_d - scale * (R @ mu_s)

def fit_sim3_from_apriltags(image_bgr, pred_pts3d, board_corners_m):
    gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
    dets = Detector(families="tag36h11").detect(gray, estimate_tag_pose=False)
    src, dst = [], []
    for det in dets:
        if det.tag_id not in board_corners_m:
            continue
        for (px, py), mxyz in zip(det.corners, board_corners_m[det.tag_id]):
            xi, yi = int(round(px)), int(round(py))
            h, w = pred_pts3d.shape[:2]
            if 0 <= xi < w and 0 <= yi < h:
                p = pred_pts3d[yi, xi]
                if np.all(np.isfinite(p)):
                    src.append(p); dst.append(mxyz)
    if len(src) < 6:
        raise RuntimeError(f"Too few valid tag corners: {len(src)}")
    return umeyama_sim3(src, dst)
# s, R, t = fit_sim3_from_apriltags(img, pred_pts3d, board_corners_m)
# pts_metric = s * (pred_pts3d @ R.T) + t
```

Validate with calipers: report median absolute error over 5–10 measured distances (screw heads, rack pitch, bracket widths).

## When to use vs alternatives

Use this skill when COLMAP/hloc fails: registered images < 50%, sparse cloud fragmented, or scene is dominated by specular/low-texture surfaces.

| Route | Commercial | License | Notes |
|---|---|---|---|
| `facebook/VGGT-1B-Commercial` | Conditional | Custom vggt-aup-license | Canonical 2026 baseline; gated HF; excludes military/ITAR; requires legal review |
| `facebook/map-anything-apache` | Yes | Apache-2.0 | License-clean commercial default; metric output; COLMAP export; v1.1.1 |
| `facebook/map-anything` (NC) | No | CC-BY-NC-4.0 | Research only |
| `facebook/VGGT-1B` | No | CC-BY-NC-4.0 | Research only |
| `naver/DUSt3R_*` | No | CC-BY-NC-SA-4.0 | Research only; share-alike; CVPR 2024 |
| `naver/MASt3R_*` | No | CC-BY-NC-SA-4.0 | Research only; share-alike; MASt3R-SfM 3DV 2025 |
| Fast3R (`jedyang97/Fast3R_ViT_Large_512`) | No | FAIR Noncommercial | Research only; CVPR 2025; fast multiview DUSt3R-style |
| Spann3R v1.01 | No | CC-BY-NC-SA-4.0 | Research only; online incremental; checkpoint Feb 2025 |
| NoPoSplat | Research-only | MIT (contested) | Directly outputs 3DGS — no COLMAP step; license files have unresolved conflicts; not production-ready |
| MASt3R-SLAM | No | CC-BY-NC-SA-4.0 | Online SLAM ~15 FPS; research only |

Log checkpoint ID in every reconstruction artifact. Fail closed when `commercial_safe` is unknown or false.

## Common issues

1. **MapAnything CUDA OOM** — Set `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True`. Use `memory_efficient_inference=True`, `minibatch_size=1`, `use_amp=True, amp_dtype="bf16"`. Issues #57 and community threads; no merged fix — use flags.

2. **MapAnything DINOv2 download on first load** (issue #149) — Pre-cache in Docker: `python -c "import torch; torch.hub.load('facebookresearch/dinov2', 'dinov2_vitg14')"`.

3. **MapAnything external predictions broken** (issue #141, Feb 2026) — `init_model_from_config("vggt")` / `model_factory` may fail on certain VGGT checkpoint paths; pin MapAnything v1.1.1 SHA and VGGT SHA together.

4. **VGGT OOM + double resize** (issue #470 / issues #188, #239) — `demo_colmap.py` may apply a second square resize after `load_and_preprocess_images`, doubling compute and causing OOM. Remove the extra resize; use `load_and_preprocess_images` output directly. Start at 16–30 frames on A100 40 GB. Issue #239 also raises undistortion question — verify COLMAP output is undistorted before feeding to gsplat.

5. **DUSt3R global alignment NaN/OOM** (issues #201, #28) — Issue #201: RoPE2D CUDA extension missing causes silent performance regression; recompile curope. Run without pose priors first. Use `init="mst"`, `schedule="cosine"`, `niter=300–1000`, `lr=0.01–0.003`. Split enclosed scenes into overlapping sub-graphs for > 20 images.

6. **MASt3R resolution / match quality tradeoff** (issue #35) — Running 256×256 inputs with 512-weight checkpoints causes large drop in match quality. Prefer 512 weights + `size=512`. Issue #131 (Jun 2025): MASt3R-SfM fails when registration is not 100% — work around by reducing scene complexity or switching to DUSt3R global aligner. For ASMK retrieval, install from `jenicek/asmk` (broken upstream link, issue #53).

7. **Mirrored / wrongly-scaled splat output** — MapAnything outputs OpenCV cam2world. COLMAP `images.txt` requires world-to-camera. Apply `np.linalg.inv(c2w)`, then convert R to Hamilton qvec `[qw, qx, qy, qz]`. Always Sim(3)-align before VR/physics export.

8. **Fast3R import paths** — Fast3R uses `fast3r.dust3r.*` internal modules, not `naver/dust3r` directly. Do not mix Fast3R and naver/dust3r environments.

## API surface summary

MapAnything key calls:
```python
MapAnything.from_pretrained("facebook/map-anything-apache")
model.infer(views, memory_efficient_inference, minibatch_size, use_amp, amp_dtype,
            apply_mask, mask_edges, apply_confidence_mask, confidence_percentile,
            ignore_calibration_inputs, ignore_depth_inputs, ignore_pose_inputs)
init_model_from_config("vggt", device="cuda")
get_available_models()
load_images("path/to/images/")
preprocess_inputs(views)
```

VGGT key calls:
```python
VGGT.from_pretrained("facebook/VGGT-1B-Commercial")
load_and_preprocess_images(path_list, mode="crop")
pose_encoding_to_extri_intri(pose_enc, image_size_hw)
unproject_depth_map_to_point_map(depth_map, extrinsics, intrinsics)
model.aggregator(images)
model.camera_head(aggregated_tokens_list)
model.depth_head(aggregated_tokens_list, images, ps_idx)
model.point_head(aggregated_tokens_list, images, ps_idx)
```

DUSt3R / MASt3R key calls:
```python
AsymmetricCroCo3DStereo.from_pretrained("naver/DUSt3R_ViTLarge_BaseDecoder_512_dpt")
AsymmetricMASt3R.from_pretrained("naver/MASt3R_ViTLarge_BaseDecoder_512_catmlpdpt_metric")
load_images(paths, size=512, square_ok=False)
make_pairs(imgs, scene_graph="complete", prefilter=None, symmetrize=True)
inference(pairs, model, device, batch_size=1)
global_aligner(output, device, mode=GlobalAlignerMode.PointCloudOptimizer)
scene.compute_global_alignment(init="mst", niter=500, schedule="cosine", lr=0.01)
scene.get_pts3d(); scene.get_im_poses(); scene.get_intrinsics(); scene.clean_pointcloud()
fast_reciprocal_NNs(d1, d2, subsample_or_initxy1=8, device="cuda", dist="dot", block_size=2**13)
```

## Resources

- MapAnything: https://github.com/facebookresearch/map-anything (v1.1.1, Mar 23 2026)
- MapAnything Apache HF: https://huggingface.co/facebook/map-anything-apache (Apache-2.0)
- VGGT: https://github.com/facebookresearch/vggt (pin SHA; VGGT License v1 updated Jul 29 2025)
- VGGT-1B-Commercial HF: https://huggingface.co/facebook/VGGT-1B-Commercial (gated, custom AUP)
- DUSt3R: https://github.com/naver/dust3r (CC-BY-NC-SA-4.0)
- MASt3R: https://github.com/naver/mast3r (CC-BY-NC-SA-4.0; MASt3R-SfM 3DV 2025)
- Fast3R: https://github.com/facebookresearch/fast3r (FAIR Noncommercial; CVPR 2025)
- Spann3R: https://github.com/HengyiWang/spann3r (CC-BY-NC-SA-4.0; v1.01 Feb 2025)
- NoPoSplat: https://github.com/cvg/NoPoSplat (MIT contested; research-only)
- MASt3R-SLAM: https://github.com/rmurai0610/MASt3R-SLAM (CC-BY-NC-SA-4.0)
- COLMAP text format: https://colmap.github.io/format.html
- gsplat: https://github.com/nerfstudio-project/gsplat (>=1.3.0)
- pupil-apriltags: https://github.com/pupil-labs/apriltags
- Issues reference: see references/issues.md
