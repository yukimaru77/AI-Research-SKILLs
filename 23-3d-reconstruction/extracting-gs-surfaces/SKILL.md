---
name: extracting-gs-surfaces
description: "Provides surface and mesh extraction from 3D Gaussian Splatting using 2DGS, GOF (Gaussian Opacity Fields), PGSR, and SuGaR for physics-grade collision meshes. Use this skill when downstream physics simulation (MuJoCo/Genesis/Isaac) needs collision meshes from a Gaussian Splatting reconstruction, or when geometry quality matters more than novel-view rendering. Covers method-specific training, TSDF fusion vs Marching Tetrahedra extraction, watertight mesh post-processing, scale validation against AprilTag/caliper, convex decomposition, and license-aware routing. CRITICAL LICENSE WARNING: ALL FOUR tools are non-commercial research only. 2DGS, GOF, and SuGaR inherit the Gaussian-Splatting non-commercial license; PGSR has a custom non-commercial educational license. None are safe for commercial digital twins without explicit authorization."
version: 2.0.0
author: Orchestra Research
license: MIT
tags: [Mesh Extraction, 2DGS, GOF, PGSR, SuGaR, TSDF, Marching Tetrahedra, Surface Reconstruction, Non-Commercial, Physics Mesh, MuJoCo, Digital Twin]
dependencies: [torch, pytorch3d>=0.7.4, open3d>=0.17.0, trimesh, plyfile, numpy]
---

# Extracting Gaussian Splat Surfaces

Operational guide for converting trained Gaussian Splatting models into watertight, metric-scale, physics-ready meshes. Targets a single A100 80GB Docker with COLMAP-style input. All four tools carry non-commercial research licenses — read the license table before shipping any output. Updated against late-2025/2026 upstream sources.

**NON-COMMERCIAL WARNING**: 2DGS, GOF, SuGaR — Gaussian-Splatting non-commercial license (Inria). PGSR — custom ZJU educational/non-profit license. Commercial use requires explicit prior consent from respective rights holders.

## Environments (separate conda envs required per tool)

Use separate envs — do NOT share one env across tools.

```bash
# Base image guidance
nvidia/cuda:11.8.0-devel-ubuntu22.04   # 2DGS / PGSR / SuGaR
nvidia/cuda:11.3.1-devel-ubuntu20.04   # GOF (official cu113 stack)

# Universal A100 submodule build exports
export CUDA_HOME="${CONDA_PREFIX}"
export PATH="${CUDA_HOME}/bin:${PATH}"
export TORCH_CUDA_ARCH_LIST="8.0"
export CPATH="${CONDA_PREFIX}/targets/x86_64-linux/include:${CPATH}"
```

### 2DGS — Python 3.8.18 / torch 2.0.0 / cu118 / Open3D 0.18.0

```bash
git clone https://github.com/hbb1/2d-gaussian-splatting.git --recursive
cd 2d-gaussian-splatting
conda env create --file environment.yml   # pins py3.8.18, torch2.0.0, open3d==0.18.0
conda activate surfel_splatting
export CUDA_HOME="${CONDA_PREFIX}" TORCH_CUDA_ARCH_LIST="8.0"
pip install -e submodules/diff-surfel-rasterization   # NOT diff-gaussian-rasterization
pip install -e submodules/simple-knn
```

### GOF — Python 3.8 / torch 1.12.1+cu113 / cudatoolkit-dev=11.3

```bash
git clone https://github.com/autonomousvision/gaussian-opacity-fields.git --recursive
cd gaussian-opacity-fields
conda create -y -n gof python=3.8
conda activate gof
pip install torch==1.12.1+cu113 torchvision==0.13.1+cu113 \
  --extra-index-url https://download.pytorch.org/whl/cu113
conda install -y -c conda-forge cudatoolkit-dev=11.3 cmake gmp cgal
pip install -r requirements.txt
export CUDA_HOME="${CONDA_PREFIX}" TORCH_CUDA_ARCH_LIST="8.0"
export CPATH="${CONDA_PREFIX}/targets/x86_64-linux/include:${CPATH}"
pip install -e submodules/diff-gaussian-rasterization
pip install -e submodules/simple-knn
cd submodules/tetra-triangulation && cmake . && make -j"$(nproc)" && pip install -e . && cd ../..
```

### PGSR — Python 3.8 / torch 2.0.1+cu118

```bash
git clone https://github.com/zju3dv/PGSR.git --recursive
cd PGSR
conda create -y -n pgsr python=3.8
conda activate pgsr
pip install torch==2.0.1+cu118 torchvision==0.15.2+cu118 torchaudio==2.0.2+cu118 \
  --index-url https://download.pytorch.org/whl/cu118
pip install -r requirements.txt
export CUDA_HOME="${CONDA_PREFIX}" TORCH_CUDA_ARCH_LIST="8.0"
pip install -e submodules/diff-plane-rasterization   # PGSR-specific rasterizer
pip install -e submodules/simple-knn
```

### SuGaR — Python 3.9 / torch 2.0.1+cu118 / PyTorch3D 0.7.4

```bash
git clone https://github.com/Anttwo/SuGaR.git --recursive
cd SuGaR
conda env create --file environment.yml   # py3.9.18, torch2.0.1, open3d==0.17.0
conda activate sugar
export CUDA_HOME="${CONDA_PREFIX}" TORCH_CUDA_ARCH_LIST="8.0"
pip install -e gaussian_splatting/submodules/diff-gaussian-rasterization
pip install -e gaussian_splatting/submodules/simple-knn
```

## Common Workflows

### 1. SEM Stage Collision Mesh → MuJoCo MJCF

Task Progress:
- [ ] Step 1: Capture calibrated images of SEM stage; run COLMAP with metric scale
- [ ] Step 2: Train 2DGS (first attempt) using bounded scene settings
- [ ] Step 3: Extract TSDF mesh with explicit `--voxel_size` and `--depth_trunc`
- [ ] Step 4: Validate scale against AprilTag / caliper (see Workflow 2)
- [ ] Step 5: Remove floaters, crop to stage bounding box, fill reconstruction holes only
- [ ] Step 6: Convex-decompose collision mesh (VHACD or CoACD)
- [ ] Step 7: Write MJCF with visual geom (contype=0) + convex hull geoms (contype=1)
- [ ] Step 8: Run MuJoCo contact test; iterate if penetration or gap > tolerance

```bash
# Train 2DGS (use --lambda_dist, not --lambda_distortion — README inconsistency)
python train.py -s "$SCENE" -m "$OUT" \
  --depth_ratio 0.0 --lambda_normal 0.05 --lambda_dist 0.0

# Extract bounded TSDF mesh (--skip_mesh NOT passed = mesh extraction enabled)
python render.py -s "$SCENE" -m "$OUT" \
  --skip_train --skip_test \
  --depth_ratio 0.0 \
  --voxel_size 0.0005 \
  --depth_trunc 0.20 \
  --sdf_trunc 0.002
# Output: $OUT/train/ours_<iteration>/fuse.ply
```

```xml
<!-- MJCF pattern: visual + convex-decomposed collision bodies -->
<mujoco model="sem_stage">
  <compiler meshdir="meshes" angle="radian"/>
  <option><flag multiccd="enable"/></option>
  <asset>
    <mesh name="stage_vis"    file="stage_visual.obj"/>
    <mesh name="stage_col_00" file="stage_hull_00.obj"/>
    <mesh name="stage_col_01" file="stage_hull_01.obj"/>
  </asset>
  <worldbody>
    <body name="sem_stage" pos="0 0 0">
      <geom name="vis" type="mesh" mesh="stage_vis"
            contype="0" conaffinity="0" rgba="0.55 0.55 0.55 1"/>
      <geom name="col_00" type="mesh" mesh="stage_col_00"
            contype="1" conaffinity="1" friction="0.8 0.02 0.001"/>
      <geom name="col_01" type="mesh" mesh="stage_col_01"
            contype="1" conaffinity="1" friction="0.8 0.02 0.001"/>
    </body>
  </worldbody>
</mujoco>
```

### 2. Scale Validation Against AprilTag / Caliper

Task Progress:
- [ ] Step 1: Identify AprilTag corners in reconstruction coordinates
- [ ] Step 2: Compute similarity transform from reconstructed to metric coordinates
- [ ] Step 3: Apply scale to mesh
- [ ] Step 4: Extract named feature distances (rail spacing, screw centers, plate width)
- [ ] Step 5: Compare against caliper measurements; fail if error > 0.5 mm or 0.5%
- [ ] Step 6: Fit contact planes (RANSAC); report RMS and normal error
- [ ] Step 7: Write `scale_report.json`; gate downstream pipeline on report pass

```python
import json, trimesh, numpy as np
from sklearn.linear_model import RANSACRegressor

def validate_mesh_scale(mesh_path, caliper_checks, april_scale_m):
    mesh = trimesh.load(mesh_path)
    results = {"mesh": mesh_path, "caliper_checks": []}
    for name, gt_m, pt_a, pt_b in caliper_checks:
        meas = np.linalg.norm(np.array(pt_b) - np.array(pt_a))
        err = abs(meas - gt_m)
        results["caliper_checks"].append({
            "name": name, "ground_truth_m": gt_m,
            "mesh_m": round(meas, 5),
            "error_m": round(err, 5),
            "error_percent": round(100 * err / gt_m, 3),
            "pass": err < 0.0005  # 0.5 mm threshold
        })
    return results
```

Acceptance thresholds (adjust per fixture tolerance):

| Check | Threshold |
|---|---|
| Scale error | < 0.5% |
| Feature distance error | < 0.5 mm |
| Contact plane RMS | < 0.2 mm |
| Floater components removed | all below area threshold |

### 3. 2DGS vs PGSR vs GOF on Machined-Metal / Brushed Surfaces

Task Progress:
- [ ] Step 1: Extract mesh with each candidate tool at identical voxel/depth settings
- [ ] Step 2: Run scale validation on each output
- [ ] Step 3: Fit contact planes; measure flatness RMS
- [ ] Step 4: Count floaters and connected components > threshold
- [ ] Step 5: Select winner by: (1) scale pass, (2) plane RMS, (3) floater count, (4) memory safety

Recommended ranking for SEM stages:

| Rank | Tool | Reason |
|---|---|---|
| 1 | 2DGS | Explicit TSDF knobs (`--voxel_size`, `--depth_trunc`, `--sdf_trunc`), surfel normals, bounded extraction path, active late-2025 upstream |
| 2 | PGSR | Planar regularization suits machined geometry; exposes weak-texture flags; but issues #10/#105 show residual holes/bumps on real scenes |
| 3 | GOF | Adaptive tetra extraction preserves fine detail but OOMs on large image sets; TSDF fallback available; older env (cu113) |
| 4 | SuGaR | Best for OBJ export and visual candidates; Poisson density/depth often needs source edits; not a first-choice collision extractor |

**Why brushed metal is hard**: Anisotropic highlights, low stable texture, repeated linear patterns, and view-dependent photometric changes break the assumption of consistent cross-view appearance. PGSR's NCC multi-view consistency is vulnerable to specular highlight shifts. 2DGS surfel orientation provides better normal estimation for flat machined surfaces.

## API Surface Reference

### 2DGS — `render.py` and `train.py`

```bash
# render.py flags (source-confirmed)
--skip_train --skip_test --skip_mesh
--depth_ratio    # via PipelineParams, default 0.0
--voxel_size --depth_trunc --sdf_trunc  # sdf_trunc defaults to 5*voxel_size
--num_cluster --unbounded --mesh_res
--iteration

# train.py surface-relevant flags
--lambda_normal --lambda_dist   # README says --lambda_distortion but source uses --lambda_dist
--opacity_cull  # default 0.05
```

### GOF — `extract_mesh.py` and `extract_mesh_tsdf.py`

```bash
# extract_mesh.py (source-confirmed; NO --voxel_size / --depth_trunc / --mesh_res)
--iteration --quiet --filter_mesh --texture_mesh --near --far

# extract_mesh_tsdf.py (source-confirmed; voxel/depth are HARD-CODED)
--iteration --quiet
# Hard-coded: voxel_size=0.002, block_count=50000, depth_min=1.0, depth_max=6.0
```

### PGSR — `render.py` and `train.py`

```bash
# render.py flags (source-confirmed)
--iteration --skip_train --skip_test --quiet
--max_depth --voxel_size --num_cluster --use_depth_filter
# WARNING: --skip_train bypasses TSDF mesh fusion. Use --skip_test for mesh extraction.

# train.py weak-texture flags (README-confirmed)
--max_abs_split_points 0      # prevent weak-texture overfitting (default: 50000)
--opacity_cull_threshold 0.05  # aggressive floater pruning
# Multi-view photometric consistency flags (source-confirmed)
--multi_view_num --multi_view_max_angle --multi_view_min_dis --multi_view_max_dis
--multi_view_ncc_weight --multi_view_geo_weight
```

### SuGaR — `train_full_pipeline.py`

```bash
# Flags (source-confirmed)
-s/--scene_path --gs_output_dir
-r/--regularization_type   # dn_consistency recommended
--low_poly --high_poly
--refinement_time          # short=2000 iters, medium=7000, long=15000
--export_obj               # True/False
--bboxmin --bboxmax --center_bbox
--postprocess_mesh --postprocess_density_threshold
-v/--n_vertices_in_mesh
-g/--gaussians_per_triangle
```

## Common Issues

1. **2DGS `--skip_mesh` produces no mesh** — Remove `--skip_mesh`. Mesh extraction is the default; this flag explicitly disables it. See issue #178 for degenerate splat artifacts; use bounded extraction and crop to scene volume.

2. **GOF `--voxel_size`/`--mesh_res` not recognized** — These flags do NOT exist in `extract_mesh.py`. Use `--near`/`--far` to bound extraction. For TSDF fallback use `extract_mesh_tsdf.py` (voxel/depth are hard-coded; patch locally for control).

3. **GOF tetra extraction OOM on A100 80GB** — Tetra graph can exceed 80GB. Fix: set `--near 0.01 --far 0.30` for bounded lab scenes, delete cached `cells.pt`, reduce image count with `-r 4`, or fall back to `extract_mesh_tsdf.py`. See issue #114 and Section below.

4. **PGSR `--skip_train` skips mesh export** — TSDF mesh fusion runs only in the train-camera branch. Pass `--skip_test` (not `--skip_train`) for mesh extraction. See issue #10 (wall holes) and #105 (planar bumps) for artifact mitigations.

5. **SuGaR Poisson holes / ellipsoidal bumps** — Not CLI-fixable. Edit `sugar_extractors/coarse_mesh.py`: set `vertices_density_quantile = 0.0` for holes; set `poisson_depth = 7` (from 10) for ellipsoidal bumps. See issue #104 for PLY-only workflow limitations.

6. **Non-watertight mesh blocks physics import** — Post-process with Open3D (see Post-processing section). For MuJoCo, convex-decompose rather than using raw concave meshes.

7. **2DGS `--lambda_distortion` not found** — README inconsistency. Source uses `--lambda_dist`. Use `--lambda_dist` in automation.

## GOF Tetra Extraction OOM — Details

GOF `extract_mesh.py` builds a full tetra cell graph in GPU memory before marching tetrahedra. Memory scales with Gaussian count x camera count x `far` bound. The default `--far 1e6` is unsafe for any bounded scene.

```bash
# Step 1: Always delete stale cell cache before changing bounds
rm -f "$OUT"/test/ours_30000/fusion/cells.pt

# Step 2: Bounded extraction — use actual stage dimensions
python extract_mesh.py \
  -m "$OUT" --iteration 30000 \
  --filter_mesh --texture_mesh \
  --near 0.01 --far 0.30

# Step 3: TSDF fallback if tetra still OOMs
python extract_mesh_tsdf.py -m "$OUT" --iteration 30000
# Output: $OUT/test/ours_30000/fusion/tsdf.ply
```

For local fork: patch `extract_mesh_tsdf.py` to expose `--voxel_size`, `--depth_min`, `--depth_max`, `--block_count` as argparse args (hard-coded values: 0.002, 50000, 1.0, 6.0).

## Post-Processing for Physics

```python
import open3d as o3d, numpy as np

mesh = o3d.io.read_triangle_mesh("output/mesh.ply")
mesh.remove_degenerate_triangles()
mesh.remove_duplicated_triangles()
mesh.remove_duplicated_vertices()
mesh.remove_non_manifold_edges()

# Keep only largest connected component
tri_clusters, cluster_n_tri, _ = mesh.cluster_connected_triangles()
largest = int(np.argmax(cluster_n_tri))
keep = np.asarray(tri_clusters) == largest
mesh.remove_triangles_by_mask(~keep)
mesh.remove_unreferenced_vertices()

# Decimate for collision (target < 50k tris for physics)
mesh = mesh.simplify_quadric_decimation(target_number_of_triangles=50_000)

print("watertight:", mesh.is_watertight())
print("vertex_manifold:", mesh.is_vertex_manifold())
print("edge_manifold:", mesh.is_edge_manifold())
o3d.io.write_triangle_mesh("output/mesh_physics.ply", mesh)
```

## When to Use vs Alternatives

| Method | Best for | Extraction | License |
|---|---|---|---|
| 2DGS | Bounded lab objects, thin shells, default first attempt | TSDF fusion, explicit knobs | Gaussian-Splatting (non-commercial) |
| PGSR | Planar-rich machined geometry, weak-texture scenes | TSDF via `render.py` | ZJU custom (non-commercial) |
| GOF | High-detail adaptive surfaces when memory allows | Marching Tetrahedra (OOM risk) | Gaussian-Splatting (non-commercial) |
| SuGaR | OBJ visual candidates, alternative regularization | Poisson + refinement | Gaussian-Splatting (non-commercial) |

**Commercial alternatives** (when non-commercial licenses are a blocker):
- Use `training-gaussian-splats` (Apache-2.0 splatfacto/gsplat) + point-cloud collision proxies
- Use NeRF-based mesh via `training-nerf-fallbacks` (Nerfacto Apache-2.0) with `ns-export poisson`

## License Routing

| Tool | License | Commercial use |
|---|---|---|
| 2DGS | Gaussian-Splatting non-commercial (Inria) | Prohibited without prior consent |
| GOF | Gaussian-Splatting non-commercial (Inria) | Prohibited without prior consent |
| PGSR | ZJU educational/research/non-profit | Prohibited commercially; modifications must be open-source |
| SuGaR | Gaussian-Splatting non-commercial (Inria) | Prohibited without prior consent |

No license changes confirmed in any of the four repos in 2024–2025 (technical check only, not a legal audit).

## Resources

- 2DGS: https://github.com/hbb1/2d-gaussian-splatting (last activity: late 2025)
- GOF: https://github.com/autonomousvision/gaussian-opacity-fields (last activity: late 2024)
- PGSR: https://github.com/zju3dv/PGSR (last activity: 2024-2025)
- SuGaR: https://github.com/Anttwo/SuGaR (last update: 2024-09-18 for dn_consistency)
- Gaussian-Splatting license: https://github.com/graphdeco-inria/gaussian-splatting/blob/main/LICENSE.md
- GitHub issues deep-dive: See [references/issues.md](references/issues.md)
- Open3D mesh repair: https://www.open3d.org/docs/release/tutorial/geometry/mesh.html
- MuJoCo mesh collision: https://mujoco.readthedocs.io/en/stable/modeling.html#collision
