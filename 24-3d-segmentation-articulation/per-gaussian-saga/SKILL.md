---
name: per-gaussian-saga
description: Uses SAGA / SegAnyGAussians (v2 branch, top-level Apache-2.0 with non-commercial vendored 3DGS components — R&D/evaluation only) to train a per-Gaussian contrastive affinity field from SAM masks and emit boolean per-Gaussian masks via DearPyGUI point prompts, batch cosine queries, or HDBSCAN auto-discovery; use for lab-equipment digital-twin R&D when a per-Gaussian binary mask is the only required output and LUDVIG is not installed; downstream skills consume bool[N] over the same Gaussian order as scene_point_cloud.ply.
version: 2.0.0
author: Orchestra Research
license: MIT
tags: [3DGS, GS, SAM, SAGA, SegAnyGAussians, HDBSCAN, DearPyGUI, Segmentation]
dependencies: [python==3.7.13, pytorch==1.12.1, torchvision==0.13.1, cudatoolkit==11.6, plyfile==0.8.1, hdbscan==0.8.33, dearpygui==1.10.1, joblib==1.1.0, open-clip-torch, mkl==2024.0]
---

# Per-Gaussian masks with SAGA

Implements the SAGA / SegAnyGAussians v2 pipeline as an R&D per-Gaussian segmentation tool for lab-equipment digital twins. SAGA trains a contrastive affinity feature field over Gaussians from SAM-extracted 2D masks, then exposes three extraction paths: interactive DearPyGUI point-prompt session, batch cosine-similarity query from seed XYZ/indices, and HDBSCAN auto-discovery. Output is `bool[N]` over the same Gaussian order as `scene_point_cloud.ply`.

**License reality (updated 2026-05)**: SAGA's top-level repo is Apache-2.0, but the runnable v2 tree vendors GraphDECO/Inria 3DGS-derived CUDA extensions (`diff-gaussian-rasterization`, `simple-knn`) and Python source files (`render.py`, `arguments/`) under explicit non-commercial research/evaluation terms. SAGA is **not** a clean commercial improvement over LUDVIG on the license axis. Both require legal review or component replacement before commercial deployment, SaaS, or binary redistribution. Use SAGA for R&D/evaluation only unless legal approves the full dependency chain or non-commercial components are replaced.

**Maintenance status (2026-05)**: Last v2 commit is 2025-03-25 (`4acdaa6`, "Update README.md"). No release tags. Many 2025–2026 issues remain open. Treat as research-code, not production-maintained.

## Quick start

SAGA v2 pins Python 3.7.13 / PyTorch 1.12.1 / CUDA 11.6. Keep it in its own Docker image or conda environment and exchange artifacts as `.npy` / `.pt` files with any modern stack.

```bash
# Clone v2 + rewrite SSH to HTTPS for submodules
git config --global url."https://github.com/".insteadOf git@github.com:
git clone -b v2 --recursive https://github.com/Jumpat/SegAnyGAussians.git
cd SegAnyGAussians
git submodule sync --recursive && git submodule update --init --recursive
```

## Common workflows

### Workflow 0 (install): Build the SAGA legacy environment

The official `environment.yml` is unsatisfiable (issue #84). Use the staged `mamba create` recipe. The critical extra step: pin MKL to 2024.0 to avoid the `libtorch_cpu.so: undefined symbol: iJIT_NotifyEvent` failure (issue #153) before building CUDA extensions.

Task Progress:
- [ ] Step 1: Clone v2 with SSH-to-HTTPS rewrite as shown in Quick Start.
- [ ] Step 2: `mamba create -n saga-v2 -y -c pytorch -c conda-forge python=3.7.13 pip=22.3.1 cudatoolkit=11.6 pytorch=1.12.1 torchvision=0.13.1 torchaudio=0.12.1 plyfile=0.8.1 tqdm matplotlib joblib==1.1.0 mkl=2024.0`.
- [ ] Step 3: `conda activate saga-v2`.
- [ ] Step 4: Verify torch BEFORE building any extension: `python -c "import torch; print(torch.__version__, torch.version.cuda, torch.cuda.is_available())"` — must succeed.
- [ ] Step 5: `pip install "setuptools<60" "wheel<0.40" "numpy<2" "opencv-python<4.9"`.
- [ ] Step 6: `pip install "dearpygui==1.10.1" "hdbscan==0.8.33" "open-clip-torch"`.
- [ ] Step 7: Install SAM: `pip install ./third_party/segment-anything`.
- [ ] Step 8: Install CUDA extensions in order: `pip install ./submodules/simple-knn`, then `./submodules/diff-gaussian-rasterization`, then `./submodules/diff-gaussian-rasterization-depth`, then `./submodules/diff-gaussian-rasterization_contrastive_f`. Each must succeed before the next.
- [ ] Step 9: Install PyTorch3D (required by `train_contrastive_feature.py` at import time). Build a PyTorch3D version compatible with Python 3.7 / PyTorch 1.12 / CUDA 11.6: `conda install -y -c iopath iopath && conda install -y -c bottler nvidiacub && pip install "git+https://github.com/facebookresearch/pytorch3d.git@stable"`. Use the devel CUDA image (`nvidia/cuda:11.6.2-cudnn8-devel-ubuntu20.04`), not runtime.
- [ ] Step 10: Download SAM ViT-H to `third_party/segment-anything/sam_ckpt/sam_vit_h_4b8939.pth`.
- [ ] Step 11: Smoke-test: `python train_contrastive_feature.py --help` — should print usage without ImportError.

```bash
# MKL pin (critical for issue #153)
mamba install "mkl=2024.0" -c defaults
python -c "import torch"  # must pass before any pip install of local extensions
```

### Workflow A: Microscope — label eyepiece + focus_knob + stage via DearPyGUI

Interactive path for human-curator labeling sessions. Produces one `bool[N]` `.pt` mask per named part via right-click point prompts in the DearPyGUI viewer. Requires X11 display.

Task Progress:
- [ ] Step 1: Train base 3DGS: `python train_scene.py -s "$SCENE" -m "$MODEL"`. Verify `$MODEL/point_cloud/iteration_30000/scene_point_cloud.ply` exists (symlink from `point_cloud.ply` if using vanilla GraphDECO output).
- [ ] Step 2: Extract SAM masks: `python extract_segment_everything_masks.py --image_root "$SCENE" --sam_checkpoint_path "$SAM" --sam_arch vit_h --downsample 4 --downsample_type image`. `--downsample` is critical for GPU memory; use 4 or 8 on large/high-res scenes.
- [ ] Step 3: Compute scales: `python get_scale.py --image_root "$SCENE" --model_path "$MODEL"`. Note: `get_scale.py` has no `--downsample` flag; if it OOMs, re-run step 2 with higher `--downsample`, then retry.
- [ ] Step 4: Train contrastive features: `python train_contrastive_feature.py -m "$MODEL" --iterations 10000 --num_sampled_rays 1000`. Expect slow: ~70 h on RTX 4090 under WSL2 (issues #131, #151). Smoke-test first with `--iterations 200 --num_sampled_rays 512`.
- [ ] Step 5: Launch GUI: `python saga_gui.py --model_path "$MODEL" --feature_iteration 10000 --scene_iteration 30000`. Needs display: `xhost +local:docker` if Docker.
- [ ] Step 6: In GUI — enable click mode, right-click the eyepiece, tune Scale and ScoreThres sliders, click `segment3D`, click `save`, enter name `eyepiece`. Repeat for `focus_knob` and `stage`. Output: `./segmentation_res/eyepiece.pt`, etc. — each is a `torch.Tensor` shape `[N]`, boolean, no metadata.
- [ ] Step 7: Render segmented output per part:

```bash
python render.py -m "$MODEL" \
  --precomputed_mask ./segmentation_res/eyepiece.pt \
  --target scene --segment

python render.py -m "$MODEL" \
  --precomputed_mask ./segmentation_res/eyepiece.pt \
  --target seg
```

- [ ] Step 8: Convert `.pt` masks to `.npy` for downstream skills: `python -c "import torch, numpy as np; np.save('masks/eyepiece.npy', torch.load('segmentation_res/eyepiece.pt', map_location='cpu').numpy())"`.

### Workflow B: SEM control panel — headless cosine-similarity segmentation from seed points

v2 provides no official headless seed-point CLI. Use a lab wrapper around SAGA's trained features: load `contrastive_feature_point_cloud.ply` (fields `f_0..f_31`), apply `scale_gate.pt` at chosen semantic scale, normalize features, score seed-point features by cosine similarity, threshold to `bool[N]`, save as `.pt`.

Task Progress:
- [ ] Step 1: Complete Workflow A steps 1–4 (train base model + contrastive features).
- [ ] Step 2: Produce `sem_knob_prompts.json` listing seed_xyz or seed_gaussian_indices per object.
- [ ] Step 3: Run lab wrapper `tools/saga_affinity_prompt_batch.py --feature_ply "$MODEL/point_cloud/iteration_10000/contrastive_feature_point_cloud.ply" --scale_gate "$MODEL/point_cloud/iteration_10000/scale_gate.pt" --prompts sem_knob_prompts.json --scale 0.55 --score_threshold 0.78 --out_dir ./segmentation_res/`.
- [ ] Step 4: QA each mask with `render.py --precomputed_mask ... --target scene --segment`.
- [ ] Step 5: Convert `.pt` → `.npy` for downstream skills.

```json
{ "objects": [
    {"name": "knob_01", "seed_xyz": [[0.124, -0.036, 0.811]]},
    {"name": "knob_02", "seed_xyz": [[0.182, -0.041, 0.804], [0.184, -0.038, 0.807]]},
    {"name": "knob_03", "seed_gaussian_indices": [102331, 102945]} ] }
```

Tune `--scale` (0.5–0.6) and `--score_threshold` (0.7–0.8) per scene. Both `seed_xyz` (nearest-neighbor lookup) and `seed_gaussian_indices` (direct index) can be mixed.

### Workflow C: HDBSCAN auto-discovery of semantic parts without prompts

GUI path (`cluster3d` button) samples ~2% of point features (`torch.rand(N) > 0.98`), runs CPU HDBSCAN with `min_cluster_size=10`, `cluster_selection_epsilon=0.01`, `allow_single_cluster=False` — all hardcoded, not GUI sliders. For headless use, replicate this in a lab wrapper.

Task Progress:
- [ ] Step 1: Complete Workflow A steps 1–4.
- [ ] Step 2: Load `contrastive_feature_point_cloud.ply`, apply scale gate, normalize features.
- [ ] Step 3: Sample 2% (or 100k–300k) features for CPU HDBSCAN. Do not run full HDBSCAN on > 5M Gaussians.
- [ ] Step 4: `HDBSCAN(min_cluster_size=10, cluster_selection_epsilon=0.01, allow_single_cluster=False)` on sampled features; compute cluster centers.
- [ ] Step 5: Assign all Gaussians to nearest cluster center by cosine similarity. Save one `bool[N]` `.pt` mask per cluster.
- [ ] Step 6: Render each cluster, map stable clusters to part names manually.

## API surface

| Script | Exists in v2? | Key flags |
|--------|--------------|-----------|
| `train_scene.py` | Yes | `-s` (source), `-m` (model), `--iterations`, `--eval` |
| `extract_segment_everything_masks.py` | Yes | `--image_root`, `--sam_checkpoint_path`, `--sam_arch`, `--downsample`, `--downsample_type` |
| `extract_features.py` | **No** (removed in v2, issue #77) | Legacy alias only; use `get_clip_features.py` instead |
| `get_scale.py` | Yes | `--image_root`, `--model_path`, `--iteration`, `--skip_train`, `--skip_test`; **no --downsample** |
| `get_clip_features.py` | Yes | `--image_root`; writes CLIP features for open-vocabulary notebook |
| `train_contrastive_feature.py` | Yes | `-m`, `--iterations`, `--num_sampled_rays` (set one; `--ray_sample_rate` is alternative), `--smooth_K` (default 16, K for feature smoothing) |
| `saga_gui.py` | Yes | `--model_path`/`-m`, `--feature_iteration`/`-f`, `--scene_iteration`/`-s` |
| `render.py` | Yes | `-m`, `--precomputed_mask`, `--target` {scene, seg, feature, coarse_seg_everything, contrastive_feature, xyz}, `--segment` |

Mask format: `./segmentation_res/<name>.pt` — `torch.Tensor`, shape `[N]`, boolean, no metadata. Pass `map_location='cpu'` when loading outside the CUDA environment. For downstream digital twin skills, store as `bool[N]` `.npy` matching `scene_point_cloud.ply` Gaussian order.

## When to use vs alternatives

Use SAGA when you need the interactive DearPyGUI point-prompt workflow for human-curator labeling sessions, HDBSCAN part auto-discovery, or when LUDVIG cannot be installed. Both SAGA and LUDVIG require R&D/legal review before commercial use.

| Tool | License | Promptable GUI | Per-Gaussian masks | 2025–2026 status |
|------|---------|---------------|-------------------|-----------------|
| SAGA v2 | Apache-2.0 top-level; non-commercial 3DGS components | Yes (DearPyGUI) | Yes | Low-maintenance, last commit Mar 2025 |
| LUDVIG | Non-commercial Inria/NAVER | No GUI | Yes (DINOv2/SAM lifting) | Research paper (ICCV 2025) |
| Gaussian Grouping | Apache-2.0 top-level; audit bundled 3DGS | Limited | Yes | Evaluate after dependency audit |
| OpenGaussian | Gaussian-Splatting License (non-commercial) | Click script | Yes | Not suitable as commercial base |
| OmniSeg3D-GS | MIT top-level; audit bundled 3DGS | Yes | Yes (PLY export) | Evaluate after dependency audit |

For multi-state articulation work, hand SAGA's `bool[N]` masks to the `multistate-diff-open3d` skill. The mask order matches the original `scene_point_cloud.ply` provided no pruning happened between training and mask emission.

## Common issues

**Missing `extract_features.py` (issue #77).** v2 removed this; use `extract_segment_everything_masks.py` for SAM masks and `get_clip_features.py` for CLIP features. Do not invent the legacy script.

**Conda environment unsatisfiable (issue #84).** Official `environment.yml` fails. Use staged `mamba create` with explicit pins (see Workflow 0), then pip-install extensions after `import torch` succeeds.

**`libtorch_cpu.so: undefined symbol: iJIT_NotifyEvent` (issue #153, Sep 2025).** Root cause: MKL 2024.1+ conflicts with PyTorch 1.12.1. Fix: `mamba install "mkl=2024.0" -c defaults` before any `pip install` of local extensions. Then re-verify `python -c "import torch"` before proceeding.

**`get_scale.py` killed / OOM (issue #75).** `get_scale.py` has no `--downsample` flag. Fix: re-run `extract_segment_everything_masks.py` with higher `--downsample` (4 or 8) to produce smaller SAM masks, then retry `get_scale.py`.

**`train_contrastive_feature.py` very slow (issues #131, #151, Jul 2025).** ~70 h for 10k iterations on RTX 4090D/WSL2. No upstream fix. Smoke-test: `--iterations 200 --num_sampled_rays 512`. Production: `10000 / 1000`. Use native Linux (not WSL2), fast NVMe storage, downsampled mask set.

**PyTorch3D required at import time.** `train_contrastive_feature.py` imports `pytorch3d.ops` at the top level. The pipeline fails immediately without it even if the code path is not reached. `saga_gui.py` does not require it. Build PyTorch3D after `import torch` passes.

**Float vs Bool dtype in render (issue #86).** Cast masks to bool before custom render calls. `render.py` handles `.pt`/`.npy` → bool conversion internally; use official flags exactly.

**GUI saves mask, not semantic PLY (issue #118).** `saga_gui.py` saves `./segmentation_res/<name>.pt`, a boolean mask tensor. No semantic PLY export in v2. Use `render.py` for visual output.

**DearPyGUI headless Docker.** GUI needs a display. Use Workflow B/C for headless/CI jobs. For interactive use: `xhost +local:docker` then mount X11 socket.

**DearPyGUI version for Python 3.7.** Current DearPyGUI 2.x requires Python >=3.8. Pin `dearpygui==1.10.1` (last 1.x with cp37 wheels) for the Python 3.7.13 environment. The API shape (dpg.create_context, dpg.add_slider_float, dpg.create_viewport) is compatible with the GUI code.

**SAM mask quality on specular lab surfaces.** Default thresholds (`pred_iou_thresh=0.88`, `stability_score_thresh=0.95`, `min_mask_region_area=100`) fail on glare. Control glare during capture (cross-polarization, diffuse lighting). Patch thresholds only after visual QA.

**HDBSCAN CPU-only, slow on large scenes.** GUI uses CPU HDBSCAN (`min_cluster_size=10`, `cluster_selection_epsilon=0.01`, `allow_single_cluster=False`) on ~2% random sample (hardcoded). For scenes > 5M Gaussians, always sample 100k–300k then assign by cosine center.

**Feature dimension is 32, hardcoded.** `FEATURE_DIM = 32` in the GUI; `feature_dim=32` in `ModelParams`; PLY loading asserts exactly 32 `f_*` fields. Do not change without patching the entire stack.

**Mixing SAGA stack with modern stack.** SAGA CUDA 11.6 / Python 3.7 / PyTorch 1.12 is incompatible with modern gsplat / PyTorch 2.x / CUDA 12.x / Python 3.10+. Keep SAGA in its own container; exchange masks as `.npy` / `.pt` artifacts.

**Symlink for vanilla GraphDECO output.** GUI expects `$MODEL/point_cloud/iteration_30000/scene_point_cloud.ply`. If the model only has `point_cloud.ply`, symlink first: `ln -s point_cloud.ply "$MODEL/point_cloud/iteration_30000/scene_point_cloud.ply"`.

## Advanced topics

- See `references/issues.md` for the full issue table (#75, #77, #84, #86, #118, #131, #151, #153) with confirmed workarounds and new 2025–2026 issues (#151, #152, #153, #159, #160, #162, #163).
- Open-vocabulary segmentation (CLIP-based) is only available via `prompt_segmenting.ipynb` in the v2 repo; not directly automatable from CLI.
- `--smooth_K` (default 16) controls K for traditional point-feature smoothing in the renderer; tune only if features look over-blurred on small parts.
- `--ray_sample_rate` is an alternative to `--num_sampled_rays`; set exactly one to a positive value.

## Downstream integration

SAGA's `bool[N]` masks integrate directly with:

- **`multistate-diff-open3d`** (articulation): pass the boolean mask as a moved-cluster candidate selector. Mask order must match the original `scene_point_cloud.ply` (no Gaussian pruning between SAGA training and mask emission).
- **`gsplat-scene-adapter`**: concatenate the canonical PLY with SAGA masks using the shared Gaussian index order.
- **State diff workflows**: store one `bool[N]` `.npy` file per moving part per scene configuration; downstream diff compares masks across states to detect articulation.

Converting `.pt` mask to `.npy` for cross-stack use:

```python
import torch, numpy as np
mask = torch.load("segmentation_res/focus_knob.pt", map_location="cpu")
np.save("masks/focus_knob.npy", mask.numpy())   # bool[N], same order as scene_point_cloud.ply
```

## Resources

- SAGA repo (v2 branch): https://github.com/Jumpat/SegAnyGAussians/tree/v2
- License: https://github.com/Jumpat/SegAnyGAussians/blob/v2/LICENSE
- SAGA paper: https://arxiv.org/abs/2312.00860
- Last v2 commit: 4acdaa6 (2025-03-25, "Update README.md")
- Issue #77: https://github.com/Jumpat/SegAnyGAussians/issues/77
- Issue #84: https://github.com/Jumpat/SegAnyGAussians/issues/84
- Issue #131: https://github.com/Jumpat/SegAnyGAussians/issues/131
- Issue #153: https://github.com/Jumpat/SegAnyGAussians/issues/153
- SAM ViT-H weights: https://dl.fbaipublicfiles.com/segment_anything/sam_vit_h_4b8939.pth
- PyTorch 1.12.1 + CUDA 11.6 install: https://pytorch.org/get-started/previous-versions/
- DearPyGUI 1.10.1 (Python >=3.7): https://pypi.org/project/dearpygui/1.10.1/
- HDBSCAN docs: https://hdbscan.readthedocs.io/
- PyTorch3D install: https://github.com/facebookresearch/pytorch3d/blob/main/INSTALL.md
- SAM (Apache-2.0): https://github.com/facebookresearch/segment-anything
- nvidia/cuda devel image (required for CUDA extension build): https://hub.docker.com/r/nvidia/cuda
