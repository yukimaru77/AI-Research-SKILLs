---
name: estimating-sfm-camera-poses
description: 'Provides Structure-from-Motion camera pose estimation using COLMAP 4.0.4 (incremental or global_mapper), hloc with SuperPoint+LightGlue, and pycolmap for metric Sim3 alignment. Use to turn curated keyframes into a sparse COLMAP model at sparse/0/ for downstream 3DGS. Covers specular-metal feature tuning, exhaustive vs sequential vs retrieval matching, incremental vs global mapper selection, AprilTag/ChArUco metric alignment, and reprojection diagnostics. GLOMAP standalone archived March 2026 — use COLMAP 4.x global_mapper instead. DUSt3R/MASt3R/VGGT/MapAnything are research-grade fallbacks with non-commercial licenses, not canonical replacements for COLMAP in production 3DGS pipelines as of May 2026.'
version: 2.0.0
author: Orchestra Research
license: MIT
tags: [SfM, COLMAP, GLOMAP, hloc, SuperPoint, LightGlue, Camera Pose, 3D Reconstruction, Bundle Adjustment]
dependencies: [colmap>=4.0.4, pycolmap-cuda12>=4.0.4, torch>=2.3.0, hloc, lightglue, numpy, h5py]
---

# Estimating SfM Camera Poses

Operational guide for metric camera pose estimation from lab-equipment video. Targets 100–500
keyframes from close-range scenes with specular/texture-poor equipment. Produces a COLMAP sparse
model at `colmap/sparse/0/` for downstream 3DGS.

**Version baseline (May 2026):**
- COLMAP 4.0.4 (April 27, 2026) — includes GLOMAP as `global_mapper`; canonical default
- COLMAP 3.13.0 (November 7, 2025) — no `global_mapper`; conservative ABI-compat pin for hloc
- GLOMAP standalone 1.2.0 (October 31, 2025) — archived March 9, 2026; use `global_mapper` instead
- pycolmap-cuda12==4.0.4 — CUDA 12 wheel; import name is `pycolmap`
- hloc master (~v1.5) — no release tag; requires `pycolmap>=3.13.0`
- LightGlue v0.2 (June 2024) — latest pinned release
- VGGT (facebookresearch/vggt, Oxford+Meta, 2025) — feed-forward cameras/depth; non-commercial checkpoint
- MapAnything v1.1.1 (March 23, 2026) — unified reconstruction framework; model is CC-BY-NC 4.0
- DUSt3R / MASt3R — CC-BY-NC-SA 4.0; research/fallback only

## Quick start

Minimal end-to-end run. Smoke test before tuning.

```bash
DATA="$PWD"
mkdir -p "$DATA/colmap/sparse"
colmap feature_extractor \
  --database_path "$DATA/colmap/database.db" \
  --image_path "$DATA/images" \
  --ImageReader.single_camera 1 \
  --SiftExtraction.use_gpu 1
colmap exhaustive_matcher \
  --database_path "$DATA/colmap/database.db" \
  --SiftMatching.use_gpu 1
colmap mapper \
  --database_path "$DATA/colmap/database.db" \
  --image_path "$DATA/images" \
  --output_path "$DATA/colmap/sparse"
test -f "$DATA/colmap/sparse/0/images.bin" && echo OK
```

Diagnose in Python:

```python
import pycolmap, statistics
rec = pycolmap.Reconstruction("colmap/sparse/0")
rec.update_point_3d_errors()
errors = [p.error for p in rec.points3D.values() if p.has_error()]
track_lengths = [p.track.length() for p in rec.points3D.values()]
print(f"Registered: {len(rec.images)}  Points: {len(rec.points3D)}")
print(f"Median reproj error: {statistics.median(errors):.3f} px")
print(f"Median track length: {statistics.median(track_lengths):.1f}")
```

## Common workflows

### 1. Incremental COLMAP for 100–500 lab keyframes (specular metals)

**Task Progress:**
- [ ] Step 1: Extract frames at 2 fps, review for near-duplicates and blur
- [ ] Step 2: Run feature extraction with DSP-SIFT, masks, single-camera mode
- [ ] Step 3: Run sequential or exhaustive matching with guided matching enabled
- [ ] Step 4: Run incremental `colmap mapper` with relaxed BA tolerances
- [ ] Step 5: Verify registered image count, mean reprojection error, sub-model count

Incremental mapper is the most robust path for close-range handheld video of specular equipment.
Mask saturated highlights, screens, glass glare. Use cross-polarization or matte tape on mirror
finishes. COLMAP supports per-image masks via `--ImageReader.mask_path` (black pixels suppress
features).

```bash
ffmpeg -i input.mp4 -vf fps=2 images/%06d.jpg
mkdir -p colmap/sparse

colmap feature_extractor \
  --database_path colmap/database.db \
  --image_path images \
  --ImageReader.single_camera 1 \
  --ImageReader.camera_model OPENCV \
  --ImageReader.mask_path masks \
  --SiftExtraction.use_gpu 1 \
  --SiftExtraction.gpu_index 0 \
  --SiftExtraction.max_num_features 8192 \
  --SiftExtraction.estimate_affine_shape 1 \
  --SiftExtraction.domain_size_pooling 1

colmap sequential_matcher \
  --database_path colmap/database.db \
  --SiftMatching.use_gpu 1 \
  --SequentialMatching.overlap 12 \
  --SiftMatching.guided_matching 1

# For unordered keyframe sets use exhaustive_matcher instead:
# colmap exhaustive_matcher --database_path colmap/database.db --SiftMatching.use_gpu 1

colmap mapper \
  --database_path colmap/database.db \
  --image_path images \
  --output_path colmap/sparse \
  --Mapper.ba_global_function_tolerance 1e-5 \
  --Mapper.ba_local_function_tolerance 1e-6 \
  --Mapper.ba_global_max_num_iterations 50
```

Switch to `global_mapper` only after validating intrinsic priors and match-graph quality (see
workflow 3 and `references/global-mapper.md`). Confirmed risk: GLOMAP/global_mapper on shaky
handheld video produces catastrophic outlier poses that hurt 3DGS PSNR ([GLOMAP #145]).

### 2. hloc SuperPoint + LightGlue for specular / low-texture scenes

**Task Progress:**
- [ ] Step 1: Install pycolmap-cuda12 before hloc to prevent CPU-pycolmap resolution
- [ ] Step 2: Configure SuperPoint extraction (4096 keypoints, resize 1600)
- [ ] Step 3: Generate retrieval or exhaustive pair list
- [ ] Step 4: Match with LightGlue (lower filter_threshold=0.05 for difficult scenes)
- [ ] Step 5: Run `reconstruction.main` with fixed intrinsics if calibrated

Use when SIFT registers fewer than 60% of frames or matches are sparse on polished metal or glass.
Install order is critical — install CUDA wheel first:

```bash
pip install "pycolmap-cuda12==4.0.4"
pip install "git+https://github.com/cvg/LightGlue.git@v0.2"
pip install -e /path/to/Hierarchical-Localization --no-deps
```

```python
from pathlib import Path
import pycolmap
from hloc import extract_features, match_features, pairs_from_exhaustive, reconstruction

images = Path("images")
outputs = Path("outputs")
sfm_dir = Path("colmap/sparse/0")
outputs.mkdir(parents=True, exist_ok=True)
sfm_dir.mkdir(parents=True, exist_ok=True)
pairs = outputs / "pairs-sfm.txt"

feature_conf = extract_features.confs["superpoint_max"].copy()
matcher_conf = match_features.confs["superpoint+lightglue"].copy()
# For specular/low-texture: lower threshold, disable adaptive pruning
matcher_conf["model"] = dict(matcher_conf.get("model", {}))
matcher_conf["model"]["filter_threshold"] = 0.05
matcher_conf["model"]["depth_confidence"] = -1
matcher_conf["model"]["width_confidence"] = -1

features = extract_features.main(feature_conf, images, outputs, as_half=True, overwrite=True)

# ≤500 frames: exhaustive; 500+ frames: use pairs_from_retrieval below
pairs_from_exhaustive.main(pairs, features=features)

matches = match_features.main(matcher_conf, pairs, features, outputs, overwrite=True)

model = reconstruction.main(
    sfm_dir, images, pairs, features, matches,
    camera_mode=pycolmap.CameraMode.AUTO,
    image_options={"camera_model": "OPENCV"},
    mapper_options={
        "ba_global_function_tolerance": 1e-5,
        "ba_global_max_num_iterations": 50,
        "ba_refine_focal_length": False,
        "ba_refine_extra_params": False,
    },
)
model.write(sfm_dir)
```

For 500+ frames, replace `pairs_from_exhaustive` with retrieval:

```python
from hloc import pairs_from_retrieval
retrieval_conf = extract_features.confs["netvlad"]
retrieval_path = extract_features.main(retrieval_conf, images, outputs)
pairs_from_retrieval.main(retrieval_path, pairs, num_matched=20)
```

### 3. Metric Sim3 alignment from AprilTag / ChArUco anchors

**Task Progress:**
- [ ] Step 1: Detect fiducial corners; note corner ordering (AprilTag: bottom-right; ArUco: upper-left)
- [ ] Step 2: Triangulate corner 3D positions in the SfM model
- [ ] Step 3: Build Nx3 arrays of SfM coords and measured metric coords (meters)
- [ ] Step 4: Run `pycolmap.estimate_sim3d_robust` or `colmap model_aligner`
- [ ] Step 5: Verify metric distances against measured baselines; check per-tag residuals

Option A — pycolmap robust Sim3 from fiducial corner correspondences (preferred):

```python
import numpy as np, pycolmap

rec = pycolmap.Reconstruction("colmap/sparse/0")
src = np.loadtxt("tag_corners_sfm_xyz.txt")   # SfM frame [N, 3]
tgt = np.loadtxt("tag_corners_metric_xyz.txt") # lab-measured meters [N, 3]

opts = pycolmap.RANSACOptions(max_error=0.005, min_inlier_ratio=0.7)
sim3 = pycolmap.estimate_sim3d_robust(src, tgt, opts)
if sim3 is None:
    raise RuntimeError("Sim3 failed; check tag IDs, corner order, units, non-coplanarity")
rec.transform(sim3)
rec.write("colmap/sparse_metric/0")
```

Option B — `colmap model_aligner` from known camera center positions:

```bash
mkdir -p colmap/sparse_metric/0
colmap model_aligner \
  --input_path colmap/sparse/0 \
  --output_path colmap/sparse_metric/0 \
  --ref_images_path geo.txt \
  --ref_is_gps 0 \
  --alignment_type custom \
  --alignment_max_error 0.02 \
  --min_common_images 3
```

`geo.txt` format: `image_name X Y Z` (one line per image, ≥3 images). `--robust_alignment` does
not exist in 4.0.4 — use `--alignment_max_error` as the RANSAC threshold.

**Corner order warning:** AprilTag corners start bottom-right (clockwise); ArUco upper-left
(clockwise). Normalize indexing before building correspondences or risk a flipped Sim3. Use
multiple non-coplanar fiducial planes for non-degenerate scale estimation.

## When to use vs alternatives

| Scenario | Recommended path |
|---|---|
| Default handheld lab video, 100–500 frames | COLMAP 4.0.4 incremental mapper |
| hloc or downstream breaks on COLMAP 4.x API | Pin COLMAP/pycolmap 3.13.0 |
| SIFT < 60% registration, specular/low-texture | hloc + SuperPoint+LightGlue |
| Large unordered dataset, clean intrinsics, strong loops | COLMAP 4.x `global_mapper` |
| COLMAP cannot initialize at all | VGGT or MapAnything to diagnose/seed; validate with COLMAP-format reprojection before using poses for 3DGS |
| GLOMAP standalone | Archived March 2026; do not use for new work |

**License constraints:**
- COLMAP/pycolmap: BSD (commercial OK)
- hloc: Apache-2.0 (commercial OK)
- LightGlue: Apache-2.0 (commercial OK)
- VGGT default checkpoint: non-commercial; commercial checkpoint exists but has restrictions
- MapAnything default model (`facebook/map-anything`): CC-BY-NC 4.0 (non-commercial); use
  `facebook/map-anything-apache` for commercial work
- DUSt3R / MASt3R: CC-BY-NC-SA 4.0 (non-commercial)

Note: "VGGT by NVIDIA" is a misnomer — VGGT is from Oxford Visual Geometry Group + Meta AI
(`facebookresearch/vggt`). There is no "hloc2" project; citations to hloc^2 refer to the same
`cvg/Hierarchical-Localization` repo.

## Common issues

1. **Textureless / reflective objects fail** ([COLMAP #2514](https://github.com/colmap/colmap/issues/2514)) —
   Improve acquisition: oblique views, cross-polarization, matte tape, AprilTags. Mask saturated
   highlights. Increase SIFT recall: `--SiftExtraction.estimate_affine_shape 1
   --SiftExtraction.domain_size_pooling 1 --SiftMatching.guided_matching 1`. Switch to hloc +
   SuperPoint+LightGlue.

2. **`global_mapper` NaN in rotation averaging on COLMAP 4.0.3** ([COLMAP #4362](https://github.com/colmap/colmap/issues/4362), April 25, 2026) —
   Fixed in 4.0.4. Use COLMAP 4.0.4 (not 4.0.3). Verify: `colmap -h | grep global_mapper`.
   `global_mapper` requires COLMAP 4.0.0+; it does not exist in 3.13.0.

3. **CUDA BA falls back to CPU solvers** ([COLMAP #3100](https://github.com/colmap/colmap/issues/3100), January 4, 2025) —
   Ceres must be built with CUDA/cuDSS support, not just linked against CUDA. Rebuild Ceres with
   `-DCUDA=ON` or use the conda-forge CUDA build: `mamba install -c conda-forge ceres-solver
   cuda-compiler==12.6.2`.

4. **hloc pulls CPU pycolmap over CUDA wheel** —
   hloc's `requirements.txt` declares `pycolmap>=3.13.0`; pip may resolve to the CPU package.
   Fix: install `pycolmap-cuda12==4.0.4` first, then `pip install -e hloc --no-deps`.

5. **hloc pycolmap API mismatch** ([hloc #438](https://github.com/cvg/Hierarchical-Localization/issues/438), November 26, 2024; [hloc #491](https://github.com/cvg/Hierarchical-Localization/issues/491), January 14, 2026) —
   `Rigid3d`/essential-matrix API changed in pycolmap 3.13→4.x; MPS/OpenMP crash on non-Linux.
   Fix: keep hloc on master and use pycolmap-cuda12==4.0.4; test on Linux+CUDA only.

6. **LightGlue fewer matches than expected** ([LightGlue #181](https://github.com/cvg/LightGlue/issues/181)) —
   Adaptive pruning (`depth_confidence`, `width_confidence`) and default `filter_threshold=0.1`
   reduce match count. For specular scenes: `depth_confidence=-1`, `width_confidence=-1`,
   `filter_threshold=0.01`, `max_num_keypoints=None`. Re-enable filtering once pose initialization
   is stable.

7. **GLOMAP global_mapper worse than incremental for handheld video** ([GLOMAP #145](https://github.com/colmap/glomap/issues/145), December 3, 2024) —
   Self-collected handheld video + ALIKED/LightGlue produced catastrophic outlier poses and lower
   Splatfacto PSNR than incremental COLMAP. Use incremental mapper as default; reserve global_mapper
   for large clean datasets with known intrinsics and verified match graphs.

8. **Sub-models from weak connectivity** —
   COLMAP may produce `sparse/0`, `sparse/1`, etc. Use the largest coherent model. See
   `references/submodel-merging.md` for `colmap model_merger` + `colmap bundle_adjuster` recovery.

## Advanced topics

- `references/build-from-source.md` — Dockerfile for COLMAP 4.0.4 with `CMAKE_CUDA_ARCHITECTURES=80`
  (A100), ONNX runtime for LightGlue/ALIKED, conda-forge Ceres with CUDA.
- `references/global-mapper.md` — `colmap view_graph_calibrator` + `colmap global_mapper` option
  reference (GlobalMapper.* namespace, rotation averaging, skip stages). Use only after validating
  intrinsic priors.
- `references/submodel-merging.md` — `colmap model_merger` + `bundle_adjuster` recovery and
  pycolmap reconstruction merging.
- `references/fallback-geometry.md` — VGGT/MapAnything/DUSt3R/MASt3R as COLMAP initializers with
  license warnings and scale-verification steps. Note: VGGT → COLMAP export works but shows
  10–20 cm / 5–40° pose errors on complex scenes ([VGGT #254]).
- `references/issues.md` — full table of GitHub issues and fixes (2024–2026).

## Resources

- COLMAP CLI reference: https://colmap.github.io/cli.html
- COLMAP FAQ (DSP-SIFT, masks, BA tuning): https://colmap.github.io/faq.html
- COLMAP 4.0.4 release notes: https://github.com/colmap/colmap/releases/tag/4.0.4
- COLMAP 3.13.0 release notes: https://github.com/colmap/colmap/releases/tag/3.13.0
- pycolmap Python docs: https://colmap.github.io/pycolmap/
- pycolmap-cuda12 on PyPI: https://pypi.org/project/pycolmap-cuda12/
- hloc: https://github.com/cvg/Hierarchical-Localization
- LightGlue: https://github.com/cvg/LightGlue
- GLOMAP standalone (archived March 2026): https://github.com/colmap/glomap
- VGGT (Oxford + Meta AI): https://github.com/facebookresearch/vggt
- MapAnything v1.1.1: https://github.com/facebookresearch/map-anything
- DUSt3R: https://github.com/naver/dust3r
- MASt3R: https://github.com/naver/mast3r
- COLMAP issues: #2514, #3100, #4362
- GLOMAP issues: #145, #179
- hloc issues: #438, #471, #491
- LightGlue issues: #181
- VGGT issues: #188, #254
- MapAnything issues: #93, #141
