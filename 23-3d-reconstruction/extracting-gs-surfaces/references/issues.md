# GitHub Issues Reference — GS Surface Extraction Tools

Verified late-2024 through 2026 issues relevant to lab-equipment digital twin workflows (SEM sample stages, machined-metal/brushed surfaces, physics mesh extraction, A100 Docker).

---

## 2DGS — hbb1/2d-gaussian-splatting

### #178 — "About the degenerate solution" (open, Nov 2024)

**Symptoms**: Over-densification, center-dot artifacts, needle-like Gaussian splats on specular or low-texture surfaces. Produces floaters and degenerate geometry in the extracted TSDF mesh.

**Affected scenarios**: Machined-metal / brushed-metal SEM stages; any scene where highlights create view-inconsistent appearance.

**Mitigations**:
- Use bounded TSDF extraction; do NOT use `--unbounded` for small lab hardware
- Inspect Gaussian count and visual floaters *before* running TSDF fusion
- Crop reconstruction to known stage bounding box before or immediately after fusion
- Remove small connected components (area/volume threshold) in post-processing
- Do not reduce `--voxel_size` until floaters are controlled — smaller voxels amplify floater artifacts
- `--opacity_cull 0.05` (source default) prunes low-opacity Gaussians during training

**Status**: Open. No upstream fix confirmed.

---

### #178-adjacent — degenerate splat training flags

Source exposes `--opacity_cull` (default 0.05) and render-time controls. The README flag `--lambda_distortion` does NOT match the current source; use `--lambda_dist` in automation scripts.

---

### #208 — "Mesh rendering failure, memory is not enough" (closed)

**Symptoms**: Open3D TSDF fusion fails with memory allocation error when using many images or high resolution.

**Mitigations**:
- Reduce number of views fed into fusion (subsample images)
- Downsample training/render resolution with `-r 2` or `-r 4`
- Increase `--voxel_size` (e.g., 0.001 instead of 0.0005) to reduce TSDF grid memory
- Reduce `--depth_trunc` to the physical object volume (e.g., 0.20 m for a benchtop stage)
- Do not use `--unbounded --mesh_res 1024` for bounded lab hardware

**Status**: Closed.

---

### #250 — "issue with submodules, cuda mismatch and install on RTX5070" (open, Jan 2026)

**Symptoms**: Submodule build failures and CUDA architecture mismatch on RTX 50-series (CUDA 12.8). Not an A100-specific issue but warns about old extension code + new CUDA era.

**A100 mitigation**: Use `nvidia/cuda:11.8.0-devel-ubuntu22.04`, build from `environment.yml`, always set `TORCH_CUDA_ARCH_LIST="8.0"` before pip-installing submodules.

```bash
export CUDA_HOME="${CONDA_PREFIX}"
export TORCH_CUDA_ARCH_LIST="8.0"
pip install -e submodules/diff-surfel-rasterization
pip install -e submodules/simple-knn
```

**Status**: Open. RTX 50-series not yet resolved upstream.

---

## GOF — autonomousvision/gaussian-opacity-fields

### #9 — "For tetra-triangulation, make error" (closed)

**Symptoms**: CGAL template errors / build failures during `cmake . && make` in `submodules/tetra-triangulation`.

**Root cause**: Python version mismatch or missing CGAL/GMP conda packages.

**Fix**:
```bash
conda create -y -n gof python=3.8
conda activate gof
conda install -y -c conda-forge cmake gmp cgal
cd submodules/tetra-triangulation
rm -rf CMakeCache.txt CMakeFiles build
cmake .
make -j"$(nproc)"
pip install -e .
```

**Status**: Closed (Python 3.8 + conda-forge CGAL confirmed fix).

---

### #52 — "nvrtc: error: invalid value for --gpu-architecture (-arch)" (open)

**Symptoms**: NVRTC compile error when building diff-gaussian-rasterization or running training with GOF's official cu113 stack.

**Root cause**: CUDA compiler architecture mismatch between the NVRTC JIT and the installed driver/PyTorch.

**Fix path**:
1. First: Use official cu113 stack with `TORCH_CUDA_ARCH_LIST="8.0"` and `CUDA_HOME="${CONDA_PREFIX}"`
2. If #1 fails in your container: compatibility workaround uses cu116 or cu118 PyTorch, but this is not the upstream-supported environment and may affect reproducibility

```bash
# Official first-attempt path for A100
export CUDA_HOME="${CONDA_PREFIX}"
export TORCH_CUDA_ARCH_LIST="8.0"
export CPATH="${CONDA_PREFIX}/targets/x86_64-linux/include:${CPATH}"
pip install torch==1.12.1+cu113 torchvision==0.13.1+cu113 \
  --extra-index-url https://download.pytorch.org/whl/cu113
conda install -y -c conda-forge cudatoolkit-dev=11.3
```

**Status**: Open.

---

### #102 — "Out of memory" (during extraction)

**Symptoms**: `extract_mesh.py` OOMs during tetra point generation or marching tetrahedra on GPU; reported on GPUs with 24GB VRAM.

**Note**: Even A100 80GB can OOM on dense reconstructions with loose `--far` bounds. The tetra cell graph can reach hundreds of millions of cells.

**Mitigations**:
- Always set tight `--near` and `--far` bounds
- Delete stale `cells.pt` cache: `rm -f "$OUT"/test/ours_30000/fusion/cells.pt`
- Reduce image count with `-r 4` during training
- Fall back to `extract_mesh_tsdf.py`

**Status**: Open.

---

### #114 — "extra_mesh out of Memory (200 images)" (open, Aug 2025)

**Symptoms**: `extract_mesh.py` fails with ~29 GiB allocation error on a 24GB GPU with 200 input images. Directly confirms that tetra extraction memory scales dangerously with image/Gaussian count.

**A100 relevance**: The same scaling issue applies at 80GB — very large image sets or loose `far` bounds can exceed A100 memory.

**Confirmed mitigations**:
```bash
# Bound far tightly for lab-scale objects
python extract_mesh.py \
  -m "$OUT" --iteration 30000 \
  --filter_mesh --texture_mesh \
  --near 0.01 --far 0.30

# Delete stale cell cache before re-running
rm -f "$OUT"/test/ours_30000/fusion/cells.pt

# TSDF fallback (limited knobs, but memory-safe)
python extract_mesh_tsdf.py -m "$OUT" --iteration 30000
```

**TSDF hard-coded values** (source-confirmed, not exposed as CLI):
- `voxel_size = 0.002`
- `block_count = 50000`
- `depth_min = 1.0`, `depth_max = 6.0`

For lab use, patch these in a local fork to accept CLI args.

**Status**: Open. No upstream fix.

---

## PGSR — zju3dv/PGSR

### #10 — "On indoor datasets, there will be holes in the walls." (open, Jul 2024)

**Symptoms**: Planar surfaces (walls, benches, instrument housings) develop holes in TSDF output mesh. Reported on auditorium, Tanks and Temples, and self-shot indoor scenes.

**Relevance to SEM stages**: SEM stage top plates, side panels, and rail surfaces are analogous to large flat indoor walls — susceptible to the same hole artifact.

**Mitigations** (README-confirmed):
```bash
# Training
python train.py -s "$SCENE" -m "$OUT" \
  --max_abs_split_points 0 \
  --opacity_cull_threshold 0.05

# Mesh extraction (note: use --skip_test not --skip_train)
python render.py -m "$OUT" --skip_test \
  --max_depth 0.20 --voxel_size 0.0005 --use_depth_filter
```

Inspect `tsdf_fusion_post.ply` (post-processed output), not just raw `tsdf_fusion.ply`.

**Status**: Open. No upstream fix committed.

---

### #105 — "Severe artifacts and bumps on planar regions with real-world indoor data." (open, Aug 2025)

**Symptoms**: Severe bumps and artifacts on planar walls even when using README weak-texture flags (`--max_abs_split_points 0`, `--opacity_cull_threshold 0.05`). Real-world indoor data; confirmed 2025.

**Relevance**: Confirms that upstream weak-texture mitigations do not fully solve planar artifact issues on real scenes. For SEM stages, expect residual bumps and validate with contact-plane flatness checks.

**Additional mitigations for brushed-metal SEM stages** (lab heuristics, not upstream presets):
```bash
python train.py -s "$SCENE" -m "$OUT" \
  --max_abs_split_points 0 \
  --opacity_cull_threshold 0.05 \
  --multi_view_num 12 \
  --multi_view_max_angle 20 \     # avoid large specular-shift view pairs
  --multi_view_min_dis 0.005 \
  --multi_view_max_dis 1.0 \
  --multi_view_ncc_weight 0.05 \  # default 0.15; lower for specular surfaces
  --multi_view_geo_weight 0.03
```

**Always validate** against caliper plane flatness checks. Contact-plane RMS > 0.2 mm is a failure for precision-placement tasks.

**Status**: Open. No upstream fix committed.

---

### PGSR — Critical mesh extraction trap

```bash
# WRONG — skips TSDF mesh fusion entirely
python render.py -m "$OUT" --skip_train

# CORRECT — runs train-camera TSDF fusion, skips test renders
python render.py -m "$OUT" --skip_test
```

The mesh fusion code is inside the `if not skip_train:` branch in `render.py`. `--skip_train` is a render-only shortcut, NOT a mesh-extraction shortcut. This is the most common PGSR operational mistake.

---

## SuGaR — Anttwo/SuGaR

### #104 — "Extracting mesh from an existing PLY file" (open, Jan 2024)

**Symptoms**: User wants to run SuGaR mesh extraction from a bare `.ply` Gaussian file without re-running the full pipeline.

**Current limitation**: `train_full_pipeline.py` expects a full 3DGS output directory via `--gs_output_dir`, not a raw `.ply` file. The full pipeline is designed around scene_path + 3DGS output directory.

**Workaround**: Reconstruct or recover the expected 3DGS output tree, then provide `--gs_output_dir`:
```bash
python train_full_pipeline.py \
  -s "$SCENE" \
  --gs_output_dir "$GS_OUT" \   # must be a valid 3DGS output dir, not bare PLY
  -r dn_consistency \
  --low_poly True \
  --refinement_time short \
  --export_obj True
```

For bare PLY-only input, use SuGaR's lower-level scripts with adapted checkpoint loading (requires source modifications).

**Status**: Open. No upstream workaround provided in issue thread.

---

### SuGaR — Poisson density / ellipsoidal bump issues

**Symptoms**: Extracted mesh has holes (incomplete coverage) or ellipsoidal bumps on flat surfaces.

**Fix for holes** — source edit in `sugar_extractors/coarse_mesh.py`:
```python
# Reduce quantile threshold to preserve low-density areas
vertices_density_quantile = 0.0   # default: 0.1
```

**Fix for ellipsoidal bumps** — source edit in same file:
```python
# Lower Poisson reconstruction depth
poisson_depth = 7   # default: 10; try 6 or 8 as needed
```

These are NOT exposed as CLI flags in `train_full_pipeline.py`. Source edits required.

**Reference**: SuGaR upstream README troubleshooting tips (confirmed, Sep 2024 update).

---

## Cross-Tool: A100 Docker Build Checklist

Before building any submodule extension on A100:

```bash
# Confirm CUDA alignment
python -c "import torch; print(torch.__version__, torch.version.cuda)"
nvcc --version

# Set architecture flags
export CUDA_HOME="${CONDA_PREFIX}"
export PATH="${CUDA_HOME}/bin:${PATH}"
export TORCH_CUDA_ARCH_LIST="8.0"   # A100 = SM 8.0
export CPATH="${CONDA_PREFIX}/targets/x86_64-linux/include:${CPATH}"

# Build
pip install -e submodules/<rasterizer>
pip install -e submodules/simple-knn
```

Common failure: `torch.utils.cpp_extension` picks `/usr/local/cuda` (system CUDA 12.x from Docker image) while PyTorch was installed for cu113/cu118. Fix: always set `CUDA_HOME="${CONDA_PREFIX}"` before building submodules.

---

## Flag Mismatch Reference

| Tool | README flag | Source (actual) flag | Note |
|---|---|---|---|
| 2DGS | `--lambda_distortion` | `--lambda_dist` | README inconsistency |
| GOF | `--voxel_size`, `--depth_trunc`, `--mesh_res` | NOT IN `extract_mesh.py` | Use `--near`, `--far` instead |
| PGSR | `--skip_train` for mesh | `--skip_test` for mesh | `--skip_train` bypasses mesh fusion |
| GOF env.yml | Python 3.7.13, cu116 | README: Python 3.8, cu113 | env.yml is stale; follow README |
| SuGaR env.yml | open3d==0.17.0 | README mentions 0.18.0 in some contexts | env.yml pin (0.17.0) is authoritative |
