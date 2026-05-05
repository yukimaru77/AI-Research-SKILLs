---
name: lift-2d-masks-ludvig
description: Uses Naver LUDVIG (learning-free 2D-to-3D feature/mask uplifting for Gaussian Splatting, DINOv2+SAM+SAM2+CLIP, GraphDECO scene format) to lift per-view masks and dense features into per-Gaussian features.npy and a pruned gaussians.ply. CRITICAL — LUDVIG ships a custom NON-COMMERCIAL license; it is NOT safe for commercial deployment regardless of any dependency licenses. Use for internal R&D and lab-equipment digital-twin validation only; switch to a commercially-licensed alternative before any shipment.
version: 2.0.0
author: Orchestra Research
license: MIT
tags: [3DGS, GS, SAM, SAM2, DINOv2, CLIP, Mask Uplift, LUDVIG, Non-Commercial]
dependencies: [torch==2.5.1, torchvision==0.20.1, xformers==0.0.28.post3, open-clip-torch==2.26.1, plyfile>=1.0, opencv-python, scipy, scikit-image]
---

# Lift 2D masks with LUDVIG

Implements the Naver LUDVIG (`naver/ludvig`, ICCV 2025) learning-free uplifting pipeline that turns 2D DINOv2 features, SAM/SAM2 binary masks, or LangSAM text-prompted masks into per-Gaussian feature vectors and pruned PLYs. The canonical public repo is `https://github.com/naver/ludvig` — no repo named `virgilebarthet/LUDVIG` exists publicly. Contact for the project is Juliette Marrie (see paper/README). Latest public commit: `4461fc5` ("Update README.md", 2025-08-27). No commits since. No releases or tags. 4 known forks (including jk4011/ludvig, Nov 2025).

**NON-COMMERCIAL LICENSE — hard blocker for any shipped product.** LUDVIG's top-level `LICENSE.txt` (copyright Inria and NAVER, updated 2025-08-27, commit `16d5410`) grants use only for non-commercial purposes and prohibits commercial use and commercial derivatives. This applies to the LUDVIG code regardless of the Apache-2.0/MIT/CC licenses of its dependencies. Do not ship this skill in any product without explicit written permission from Naver Labs Europe.

**Repo status (DT-validated 2026-05-05).** No commits after 2025-08-27. No GitHub releases or tags. 0 open PRs. 1 open issue (#13, large scene, no removal). Repo is not archived. Low-activity research code with no active release cadence.

## Quick start

The recommended 2026 stack upgrades PyTorch to 2.5.1 (required by current SAM2.1) and CUDA to 12.4. The original `environment.yml` pins `pytorch=2.4.0 / pytorch-cuda=11.8`, which conflicts with current SAM2's `torch>=2.5.1` requirement. Pin to commit `4461fc515439bb498a75d71738a1e73cf7a452ed`.

```bash
docker run --gpus all --ipc=host --shm-size=32g \
  -v /data:/data -v $PWD/logs:/opt/ludvig/logs \
  -it ludvig-sam2:2026 \
  python ludvig_uplift.py \
    --colmap_dir /data/sem_scene \
    --gs_source /data/sem_scene/gs/point_cloud/iteration_30000/point_cloud.ply \
    --config configs/lab_sam2_mask.yaml \
    --height 1080 --width 1920 \
    --tag sem/sam2_mask --save_visualizations
# writes logs/sem/sam2_mask/{config.yaml, gaussians.ply, features.npy}
```

The entry point is `ludvig_uplift.py`. Use `demo.py` for the bundled GraphDECO demo scene; use `demo_removal.py` for the object-removal demo.

## Common workflows

### Workflow 0 (install): Build the 2026 LUDVIG + SAM2.1 container

LUDVIG's `environment.yml` pins `python=3.11`, `pytorch=2.4.0`, `pytorch-cuda=11.8`. The following proposed Dockerfile uses PyTorch 2.5.1 (minimum for current SAM2.1) and patches the hardcoded SAM2 config path in `utils/sam.py`. If you only need externally-generated mask uplift and never call LUDVIG's built-in SAM2 loader, the patch is optional but still recommended. Use singular `script/` (not `scripts/`) for all shell helpers.

```dockerfile
FROM nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV CUDA_HOME=/usr/local/cuda
ENV PATH=/opt/venv/bin:$PATH

RUN apt-get update && apt-get install -y --no-install-recommends \
    git wget curl ca-certificates build-essential ninja-build \
    python3.11 python3.11-dev python3.11-venv python3-pip \
    libgl1 libglib2.0-0 \
 && rm -rf /var/lib/apt/lists/*

RUN python3.11 -m venv /opt/venv \
 && python -m pip install --upgrade pip setuptools wheel

# PyTorch 2.5.1 + CUDA 12.4: satisfies current SAM2 torch>=2.5.1 requirement.
RUN pip install --index-url https://download.pytorch.org/whl/cu124 \
    torch==2.5.1 torchvision==0.20.1

# xformers 0.0.28.post3 requires exactly torch==2.5.1; use --no-deps to prevent
# pip from replacing the CUDA-specific torch wheel.
RUN pip install --no-deps xformers==0.0.28.post3

RUN pip install \
    open-clip-torch==2.26.1 \
    imageio opencv-python plyfile tqdm scikit-learn scikit-image \
    matplotlib pyyaml scipy einops numpy hydra-core iopath

WORKDIR /workspace
RUN git clone https://github.com/naver/ludvig.git
WORKDIR /workspace/ludvig
RUN git checkout 4461fc515439bb498a75d71738a1e73cf7a452ed

# Build LUDVIG's vendored CUDA extensions. Do NOT replace with upstream clones:
# LUDVIG's diff-gaussian-rasterization includes apply_weights.cu for uplift.
RUN pip install -e gaussiansplatting/submodules/diff-gaussian-rasterization \
 && pip install -e gaussiansplatting/submodules/simple-knn

# SAM1 and SAM2 (SAM2.1 config names used here).
RUN pip install "git+https://github.com/facebookresearch/segment-anything.git" \
 && pip install "git+https://github.com/facebookresearch/sam2.git@2b90b9f"

# Patch LUDVIG's hardcoded old SAM2 config path (no PR merged as of 2026-05-05).
RUN python - <<'PY'
from pathlib import Path
p = Path("utils/sam.py")
s = p.read_text()
s = s.replace(
    'model_cfg = "sam2_hiera_l.yaml"',
    'model_cfg = "configs/sam2.1/sam2.1_hiera_l.yaml"',
)
p.write_text(s)
PY
```

Task Progress:
- [ ] Step 1: Build image: `docker build -t ludvig-sam2:2026 .`
- [ ] Step 2: Download `dinov2_vitg14_reg4_pretrain.pth` from `dl.fbaipublicfiles.com` into `checkpoints/`.
- [ ] Step 3: Download `sam_vit_h_4b8939.pth` (SAM ViT-H) into `checkpoints/`.
- [ ] Step 4: Download `sam2.1_hiera_large.pt` into `checkpoints/` if using LUDVIG's built-in SAM2 loader.
- [ ] Step 5: Verify GPU access: `docker run --gpus all --rm ludvig-sam2:2026 python -c "import torch; print(torch.cuda.is_available())"`.
- [ ] Step 6: Run bundled demo: `python demo.py` (requires demo data from `bash script/demo_download.sh`).

**CUDA 11.8 fallback.** PyTorch 2.5.1 ships cu118 wheels. If your driver does not support CUDA 12.4, replace `cu124` with `cu118` and use `nvidia/cuda:11.8.0-devel-ubuntu22.04` as the base.

### Workflow A: Uplift externally-generated SAM2 binary masks to per-Gaussian mask

The most reliable path for custom lab equipment. Generate per-view binary masks with SAM2 externally, save them with the same filenames as the COLMAP camera images, and uplift via `predictors.dino.BaseDataset`. This bypasses the SAM2 config-path mismatch entirely (issue #4 maintainer guidance).

Task Progress:
- [ ] Step 1: Generate one binary SAM2 mask image per training view and save to `sam2_masks/` with camera-image filenames (e.g. `00001.png`). All files must share the same extension.
- [ ] Step 2: Author `configs/lab_sam2_mask.yaml` (see below).
- [ ] Step 3: Run uplift: `python ludvig_uplift.py --config configs/lab_sam2_mask.yaml --colmap_dir /data/lab_scene --gs_source /data/.../point_cloud.ply --height 1080 --width 1920 --tag lab_equipment`.
- [ ] Step 4: Apply Otsu thresholding to `features.npy` to get `bool[N]` per-Gaussian mask (see snippet below).
- [ ] Step 5: Pass the mask to the multi-state-diff skill or digital-twin schema writer.

```yaml
# configs/lab_sam2_mask.yaml
tag: sam2_mask_uplift
dst_dir: logs
feature:
  name: predictors.dino.BaseDataset   # re-exports BaseDataset from predictors/base.py; matches demo_rgb.yaml
  directory: /data/lab_scene/sam2_masks
normalize: False
```

```python
import numpy as np
from skimage.filters import threshold_otsu

feat = np.load("logs/lab_equipment/sam2_mask_uplift/features.npy")
score = feat.mean(axis=1)           # masks loaded as RGB: three channels are near-identical
valid = np.isfinite(score)
thr = threshold_otsu(score[valid])
mask3d = score > thr
np.save("logs/lab_equipment/sam2_mask_uplift/mask3d.npy", mask3d)
print(f"threshold: {thr:.4f}  selected: {mask3d.sum()} / {len(mask3d)}")
```

### Workflow B: DINOv2 per-Gaussian features + cosine similarity query

Compute 40-D PCA-compressed DINOv2 features per Gaussian and query them with seed indices via cosine similarity.

Task Progress:
- [ ] Step 1: Uplift DINOv2 with `predictors.dino.DINOv2Dataset`, `n_components: 40`, `normalize: True`.
- [ ] Step 2: Select seed Gaussian indices from a known region or a prior mask.
- [ ] Step 3: Build unit-norm prototype: `proto = feats[seeds].mean(0); proto /= np.linalg.norm(proto)`.
- [ ] Step 4: Score all Gaussians: `scores = feats @ proto`.
- [ ] Step 5: Threshold by quantile (`scores > np.quantile(scores, 0.92)`) for a top-8% mask.
- [ ] Step 6: Save `*_scores.npy` and `*_mask.npy`.

```yaml
# configs/bench_dino40.yaml
tag: dinov2
dst_dir: logs/lab
feature:
  name: predictors.dino.DINOv2Dataset
  dino_ckpt: ./checkpoints/dinov2_vitg14_reg4_pretrain.pth
  dino_cfg:  ./dinov2/configs/vitg14_pretrain.yaml
  n_components: 40
normalize: True
```

### Workflow C: Real CLI calls verified from repo

```bash
# Download bundled demo data
bash script/demo_download.sh

# Run bundled GraphDECO demo
python demo.py

# RGB-feature mock (no DINOv2 checkpoint needed)
python demo.py --rgb

# Open-vocabulary object-removal demo (3 passes: DINOv2, CLIP, graph diffusion)
python demo_removal.py

# Segmentation pipeline (pass scene path + config)
bash script/seg.sh "$scene" "$cfg"

# LERF feature uplift
bash script/lerf_uplift.sh "$scene"

# LERF evaluation with graph diffusion
bash script/lerf_eval.sh "$scene" "$cfg"

# LERF evaluation without graph diffusion
bash script/lerf_eval.sh "$scene" "$cfg" --no_diffusion

# ScanNet semantic segmentation pipeline
bash script/scannet.sh "$scene"
```

Note: the shell helpers live in `script/` (singular), not `scripts/`. Verify the path in your checkout.

## When to use vs alternatives

Use LUDVIG when the project is non-commercial R&D, a trained 3DGS scene plus 2D masks or features are already available, and the highest-quality learning-free uplift is required. LUDVIG is the most feature-complete open-source learning-free uplift pipeline as of mid-2026 but carries a hard non-commercial restriction.

**No commercially safe alternative is fully validated as a drop-in uplift replacement as of 2026-05-05.** The following projects have Apache-2.0 or MIT top-level licenses and are the best candidates; all require independent audit of checkpoint and dependency licenses before commercial use:

| Project | License | Notes |
|---|---|---|
| Gaussian Grouping / GS-Grouping | MIT | ECCV 2024; lifts SAM masks into 3D Gaussian scenes for segmentation, grouping, and editing. More 3DGS-native than LUDVIG. Good first alternative. |
| Feature 3DGS | MIT | CVPR 2024; distills arbitrary 2D foundation-model features into 3DGS via distillation (not learning-free). Supports point/box/language prompting. |
| OpenGaussian | Apache-2.0 | NeurIPS 2024; open-vocabulary 3D Gaussian point-level understanding. LUDVIG's ScanNet eval intersects with OpenGaussian resources. |
| OpenSplat3D | Apache-2.0 | CVPRW 2025; open-vocabulary 3D instance segmentation using Gaussian Splatting. Direct instance-segmentation alternative. |
| SAGA (`Jumpat/SegAnyGAussians`) | Apache-2.0 (top-level) | Trains scale-gated affinity features; not learning-free. Binary 3D mask output. Needs separate checkpoint/dep audit. |
| ReferSplat | — | ICML 2025 oral; referring-expression segmentation in 3DGS. Use if main task is language-guided localization. |
| Unified-Lift | Apache-2.0 | CVPR 2025, 3DGS segmentation + lifting. Usage guide listed as under construction as of 2026-05-05. |
| PanoGS | Apache-2.0 | CVPR 2025, panoptic open-vocabulary 3DGS scene understanding. |
| Semantic Gaussians | MIT | TCSVT 2026; distills pretrained 2D semantics into 3D Gaussians. |
| Mosaic3D | Apache-2.0 | NVIDIA 2025; open-vocabulary 3D scene semantics. Not a drop-in mask-uplift equivalent. |

The maintainer-endorsed split is: existing 2D masks use `ludvig_uplift.py` with a `BaseDataset`-style config; visual prompts/scribbles use `predictors.sam.SAMDataset`; text prompts use lifted CLIP/DINOv2 features via `ludvig_clip.py`. Do not invent a fourth path.

## Common issues

**GraphDECO PLY required.** `ludvig_base.py` calls `GaussianModel(sh_degree=0).load_ply(gs_source)` and expects GraphDECO property names. A gsplat-trained or nerfstudio-trained PLY will silently fail or load wrong fields. Convert via the `gsplat-scene-adapter` skill before running LUDVIG.

**SAM2 config-path mismatch.** `utils.sam.load_sam2()` hardcodes `model_cfg = "sam2_hiera_l.yaml"`. Current SAM2.1 uses `configs/sam2.1/sam2.1_hiera_l.yaml` and checkpoint `sam2.1_hiera_large.pt`. No PR or fix has been merged (0 PRs total). Patch `utils/sam.py` (see Dockerfile above) or generate SAM2 masks externally and uplift via `BaseDataset`.

**PyTorch version conflict.** LUDVIG's `environment.yml` pins `pytorch=2.4.0`; current SAM2 requires `torch>=2.5.1`. Unresolved. Use PyTorch 2.5.1 + xformers 0.0.28.post3 for new installs (xformers 0.0.27.post2 requires exactly torch 2.4.0 and will break with 2.5.1).

**script/ vs scripts/ path.** All shell helpers live in `script/` (singular). External posts sometimes say `scripts/`. Verify the directory name in your checkout before writing automation.

**Mask filename / extension mismatch.** `BaseDataset.image_from_path()` reads the extension of the first file in the directory and applies it uniformly. Mixed `.png` / `.jpg` in one directory is a silent failure. Standardize the extension across the entire mask directory.

**Feature-map resolution.** If masks or features are at lower resolution than training images, pass that resolution via `--height` and `--width`; intrinsics are rescaled by `CamScene(..., h=..., w=...)` (issue #5). Default is `--height 1199 --width 1600`.

**Supported feature dimensions.** The CUDA rasterizer supports `{1, 2, 3, 10, 20, 30, 40, 50, 100, 200, 256, 512}`. Other channel counts require editing `gaussiansplatting/submodules/diff-gaussian-rasterization/cuda_rasterizer/apply_weights.cu` and rebuilding.

**OOM in graph diffusion (issues #2, #9).** A100 40 GB OOMs at ~600k Gaussians with `num_neighbors=200`. Reduce to 160 or 180, prune Gaussians beforehand, or disable graph diffusion for debugging. Issue #13 (1.17M Gaussians, no removal, open/no maintainer response) suggests the failure can be silent, not just OOM.

**NaN/Inf camera poses (issue #11, ScanNet).** Filter invalid frames before loading: `np.any(np.isnan(R))`. OpenGaussian's fixed-position Gaussian setup can yield blurry renderings; do not treat blurriness as a LUDVIG bug.

**ScanNet reproduction friction (issue #10, Dec 2025).** OpenGaussian's download link was unavailable; NAVER cannot share ScanNet-preprocessed files (belong to OpenGaussian authors). Obtain them directly from OpenGaussian or pre-process from the raw ScanNet dataset.

**open-clip-torch version.** PyPI shows 3.3.0 released 2026-02-27, but LUDVIG has not been tested against it. Pin to 2.26.1 for reproducibility.

**Specular metals and SEM grayscale.** DINO/CLIP features are unstable on mirrors, polished knobs, and SEM grayscale. Prefer SAM2/LangSAM mask uplift over feature uplift. Validate by re-rendering the per-Gaussian mask into held-out views.

**Coordinate frames.** LUDVIG does not solve frame conversion. Cameras and Gaussian coordinates must already agree. Convert once via `gsplat-scene-adapter` and verify by rendering RGB before uplifting.

**No top-level `.gitmodules` with commit SHAs.** The nested `gaussiansplatting/.gitmodules` names GraphDECO's `diff-gaussian-rasterization` and `simple-knn` but does not pin commit SHAs. Do NOT replace the vendored `diff-gaussian-rasterization` with a fresh upstream clone; LUDVIG's local extension includes `apply_weights.cu` for the uplifting path.

## Advanced topics

**API surface.** The autonomous agent surface is:
- `python ludvig_uplift.py --gs_source --colmap_dir --config --height --width [--tag] [--load_ply] [--save_visualizations]`
- `python demo.py [--rgb]` — bundled demo; `python demo_removal.py` — object-removal demo
- `bash script/seg.sh "$scene" "$cfg"` — segmentation pipeline
- `bash script/lerf_uplift.sh "$scene"` / `bash script/lerf_eval.sh "$scene" "$cfg" [--no_diffusion]` — LERF path
- `bash script/scannet.sh "$scene"` — ScanNet pipeline (filter NaN/Inf poses first)
- `LUDVIGUplift.uplift()` / `LUDVIGUplift.save()` — feature dataset init, `utils.solver.uplifting()`, write outputs
- `utils.solver.uplifting(loader, gaussian, resolution, prune_gaussians, min_gaussians=400000)` — returns `(features_3d, keep)`
- `predictors.dino.BaseDataset` — recommended path for externally-generated masks
- `predictors.dino.DINOv2Dataset` — DINOv2 feature maps, PCA-compressed to `n_components`
- `predictors.sam.SAMDataset` — visual-prompt / scribble path using SAM/SAM2
- `python ludvig_clip.py` — open-vocabulary CLIP/DINOv2 evaluation + graph diffusion
- `evaluation.removal.clip_diffusion.CLIPDiffusionRemoval` — text-prompt object-removal
- `evaluation.removal.base.Removal` — threshold 3D features, prune Gaussians, save `removal.ply`

**ScanNet semantic segmentation** (added 2025-08-27, commit `95724eb`). Use `script/scannet.sh`; filter NaN/Inf poses via `np.any(np.isnan(R))` as documented by maintainer in issue #11.

**Object removal demo** (added 2025-03-16). Runs three passes: DINOv2 uplift, CLIP uplift, then `evaluation.removal.clip_diffusion.CLIPDiffusionRemoval` with `num_neighbors: 160`, `num_iterations: 200`. Use Otsu/Li for robust thresholding (issue #7). "Stump" and similarly ambiguous CLIP prompts fail because CLIP features do not distinguish foreground from background.

**DINOv2 model.** LUDVIG imports `from dinov2.model import DINOv2` — not via PyTorch Hub. The ViT-G/14 with registers (`dinov2_vitg14_reg4_pretrain.pth`) is the correct checkpoint.

**LangSAM / segment-geospatial** (as of 2026-05-05). `segment-geospatial` is at 1.3.2 (released 2026-03-23, MIT). LangSAM still uses GroundingDINO. API: `LangSAM(model_type="sam2-hiera-large").predict(img, text_prompt, box_threshold, text_threshold, return_results=True)` returns `(masks, boxes, phrases, logits)`. Note: the nearby `SamGeo2` class uses `model_id=` rather than `model_type=`.

See `references/issues.md` for the full upstream issue table (#2, #4, #5, #7, #9, #10, #11, #13) with agent-side mitigations.

## Resources

- LUDVIG repository: https://github.com/naver/ludvig
- LUDVIG license (custom NON-COMMERCIAL, copyright Inria and NAVER): https://github.com/naver/ludvig/blob/main/LICENSE.txt
- Pinned commit: `4461fc515439bb498a75d71738a1e73cf7a452ed` (2025-08-27, "Update README.md")
- LUDVIG paper (ICCV 2025): https://arxiv.org/abs/2410.18791
- DINOv2 ViT-G with registers checkpoint: https://dl.fbaipublicfiles.com/dinov2/dinov2_vitg14/dinov2_vitg14_reg4_pretrain.pth
- SAM ViT-H checkpoint: https://dl.fbaipublicfiles.com/segment_anything/sam_vit_h_4b8939.pth
- SAM2.1 Hiera Large checkpoint: https://dl.fbaipublicfiles.com/segment_anything_2/092824/sam2.1_hiera_large.pt
- SAM2 repository (no releases/tags; use commit 2b90b9f): https://github.com/facebookresearch/sam2
- xformers 0.0.28.post3 (torch 2.5.1 pin): https://pypi.org/project/xformers/0.0.28.post3/
- open-clip-torch 2.26.1: https://pypi.org/project/open-clip-torch/2.26.1/
- segment-geospatial 1.3.2 (MIT, LangSAM front end): https://pypi.org/project/segment-geospatial/
- Gaussian Grouping / GS-Grouping (MIT, ECCV 2024): https://github.com/lkeab/gaussian-grouping
- Feature 3DGS (MIT, CVPR 2024): https://feature-3dgs.github.io/
- OpenGaussian (Apache-2.0, NeurIPS 2024): https://github.com/yanmin-wu/OpenGaussian
- OpenSplat3D (Apache-2.0, CVPRW 2025): https://github.com — search OpenSplat3D CVPRW2025
- SAGA (Apache-2.0 top-level, needs dep/checkpoint audit): https://github.com/Jumpat/SegAnyGAussians
- Unified-Lift (Apache-2.0, CVPR 2025): https://github.com — search Unified-Lift 3DGS CVPR2025
- PanoGS (Apache-2.0, CVPR 2025): https://github.com — search PanoGS CVPR2025
- Semantic Gaussians (MIT, TCSVT 2026): https://github.com — search Semantic-Gaussians TCSVT2026
- Mosaic3D (Apache-2.0, NVIDIA 2025): https://github.com — search Mosaic3D NVIDIA2025
- Issue #2 (graph-diffusion OOM, closed): https://github.com/naver/ludvig/issues/2
- Issue #4 (custom scene segmentation guidance, closed): https://github.com/naver/ludvig/issues/4
- Issue #5 (feature resolution, closed): https://github.com/naver/ludvig/issues/5
- Issue #7 (Otsu/Li thresholding for inaccurate removal, closed): https://github.com/naver/ludvig/issues/7
- Issue #9 (CUDA error during graph diffusion, closed): https://github.com/naver/ludvig/issues/9
- Issue #10 (ScanNet/OpenGaussian link, Dec 2025, closed): https://github.com/naver/ludvig/issues/10
- Issue #11 (NaN/Inf camera poses in ScanNet, closed): https://github.com/naver/ludvig/issues/11
- Issue #13 (large custom scene, no removal, open/no response): https://github.com/naver/ludvig/issues/13
- DINOv2 paper: https://arxiv.org/abs/2304.07193
- SAM2 paper: https://arxiv.org/abs/2408.00714
- skimage threshold_otsu / threshold_li: https://scikit-image.org/docs/stable/api/skimage.filters.html
- segment-anything (SAM, Apache-2.0): https://github.com/facebookresearch/segment-anything
- GroundingDINO (LangSAM dependency): https://github.com/IDEA-Research/GroundingDINO
- Naver Labs Europe: https://europe.naverlabs.com/
