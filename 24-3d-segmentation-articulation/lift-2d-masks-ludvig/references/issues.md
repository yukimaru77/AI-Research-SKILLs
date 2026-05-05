# LUDVIG known issues and fixes

Curated from the upstream `naver/ludvig` issue tracker as of 2026-05-04 plus integration gotchas observed in the source code. Issue links are real; integration gotchas are flagged as such.

## Issue #2 - OOM in open-vocabulary object detection

**Symptom.** A100 40 GB OOM during graph diffusion with 600k Gaussians and 200 neighbors. Trace points to `features[:, None] - features[self.knn_neighbor_indices]` materialization in `GraphDiffusion.precompute_similarities()`.

**Maintainer fix.** Reduce `num_neighbors` in `configs/lerf_eval_sam.yaml` from 200 to 180 or 160.

**Agent-side fix.** Prune Gaussians to ~600k or below before uplifting (use `gsplat-scene-adapter` opacity / scale filters). Reduce feature dimension from 512 to 100 or 50. Disable graph diffusion entirely for debugging by switching to a non-diffusion config.

URL: https://github.com/naver/ludvig/issues/2

## Issue #4 - custom scene object segmentation / extracting Gaussians

**Symptom.** User asks how to segment/extract a query object in a custom scene.

**Maintainer guidance** (this is the canonical agent-side recipe):
- Existing 2D masks: `ludvig_uplift.py` with a `BaseDataset`-style config.
- Visual prompts/scribbles: `predictors.sam.SAMDataset`.
- Text prompts: uplift CLIP and DINOv2, then threshold 3D scores with Otsu/Li.
- Pruning helpers: `prune_points_noopt` / `recover_points`.
- Later comment: 3D scores live in `evaluation/removal/clip_diffusion.py`; pruning in `evaluation/removal/base.py`.

URL: https://github.com/naver/ludvig/issues/4

## Issue #5 - feature map resolution mismatch

**Symptom.** User asks if 1920x1080 training images can use 960x540 feature maps.

**Maintainer fix.** Yes; pass the corresponding `--height` and `--width`. LUDVIG rescales COLMAP intrinsics through `CamScene(self.colmap_dir, h=..., w=...)`.

URL: https://github.com/naver/ludvig/issues/5

## Issue #7 - inaccurate removal / wrong object removed

**Symptom.** Text prompt removes background or wrong object.

**Maintainer suggests.** Automatic thresholding such as Otsu/Li, adjusting diffusion bandwidth parameters, and recognizing that CLIP can confuse similar objects.

```yaml
thresholding:
  name: skimage.filters.threshold_otsu
  to_numpy: True
```

URL: https://github.com/naver/ludvig/issues/7

## Issue #9 - CUDA error during demo removal graph diffusion

**Symptom.** Error after CLIP query, while constructing graph pairwise similarities on 886,577 Gaussians with 160 neighbors.

**Maintainer says.** CLIP query happens first; failure occurs in the expensive graph construction / pairwise similarity computation. Reduce Euclidean neighbors to fit resources.

URL: https://github.com/naver/ludvig/issues/9

## Issue #10 - ScanNet data access / degraded renderings

**Symptom.** OpenGaussian link unavailable; user reports blurred or degraded ScanNet renderings.

**Maintainer says.** LUDVIG cannot redistribute ScanNet/OpenGaussian files; use the appropriate OpenGaussian source. For lab work: do not assume LUDVIG can repair a broken GS reconstruction.

URL: https://github.com/naver/ludvig/issues/10

## Issue #11 - ScanNet NaN/Inf camera poses

**Symptom.** Certain frames contain invalid transforms.

**Maintainer says.** They also encountered invalid poses and filter them during loading, e.g. `if np.any(np.isnan(R)): continue`. They also note OpenGaussian's fixed-position setup can yield blurry renderings; uplifting provided 2D semantic maps is the intended check.

URL: https://github.com/naver/ludvig/issues/11

## Issue #13 - custom dataset, 1,172,683 Gaussians, no removal

**Symptom.** Large custom scene; object not segmented; no maintainer comments yet at fetch time.

**Best mitigation (no official fix).** Validate image/camera naming and GraphDECO scene format, inspect CLIP/DINO PCA projections, prune Gaussians before diffusion, lower `num_neighbors`, try Otsu/Li thresholding, and first test with an already-computed 2D mask uplift to isolate whether the problem is in the data path or the diffusion path.

URL: https://github.com/naver/ludvig/issues/13

## Issue #8 - Broken Google Drive link for dataset

**Symptom.** `lego_real_night_radial` dataset Google Drive link returns 404 or access denied.

**Status.** Closed. No maintainer re-upload as of 2026-05-04. Use LUDVIG's built-in demo scenes or substitute your own COLMAP scene.

URL: https://github.com/naver/ludvig/issues/8

## Issue #12 - NVOS room mask missing from provided mask data

**Symptom.** The provided NVOS mask data does not include the room scene mask.

**Status.** Closed. Maintainer acknowledged; no resolution in the repo. Use your own masks for room-scale scenes.

URL: https://github.com/naver/ludvig/issues/12

## Integration gotcha - GraphDECO PLY required

**Symptom.** A gsplat-trained or nerfstudio-trained PLY silently fails or loads wrong fields when passed to `--gs_source`.

**Mechanism.** `ludvig_base.py` calls `GaussianModel(sh_degree=0).load_ply(gs_source)` and expects GraphDECO property names/layout.

**Fix.** Convert through the `gsplat-scene-adapter` skill before calling LUDVIG. Do not just rename a file.

## Integration gotcha - SAM2 checkpoint/config mismatch

**Symptom.** `utils.sam.load_sam2()` hardcodes `model_cfg = "sam2_hiera_l.yaml"`, while current SAM2 1.x uses namespaced paths like `configs/sam2.1/sam2.1_hiera_l.yaml`. Current SAM2 also documents `torch>=2.5.1`, conflicting with LUDVIG's PyTorch 2.4.0 pin.

**Fix.** Either patch `utils/sam.py` to branch on `"sam2.1" in ckpt_path`, OR generate SAM2 masks externally and uplift via `BaseDataset`. The external-generation path is the recommended robust deployment.

## Integration gotcha - mask filename / extension mismatch

**Symptom.** `BaseDataset.image_from_path()` reads the extension of the first file in the directory and applies it uniformly across `cam_name + ext`. Mixed `.png` / `.jpg` is a silent failure.

**Fix.** Standardize the extension across the entire mask directory.

## Integration gotcha - supported feature dimensions

**Symptom.** Building features with channel counts outside `{1, 2, 3, 10, 20, 30, 40, 50, 100, 200, 256, 512}` fails at the rasterizer level.

**Fix.** Edit `gaussiansplatting/submodules/diff-gaussian-rasterization/cuda_rasterizer/apply_weights.cu` to add the channel count, then rebuild the CUDA extension.

## Integration gotcha - specular metals and grayscale SEM imagery

**Symptom.** DINO/CLIP features unstable on mirrors, glass, polished metal, SEM grayscale.

**Fix.** Prefer SAM2/LangSAM mask uplift over feature uplift. Validate by re-rendering the per-Gaussian mask into held-out views. The LUDVIG paper notes that final quality is bounded by the GS reconstruction quality itself.
