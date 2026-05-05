---
name: training-gaussian-splats
description: 'Provides primary 3D Gaussian Splatting training for lab-equipment digital twins (SEM) on Linux Docker A100. Input: COLMAP-aligned images with AprilTag metric scale from the pose-estimation step. Output: .ply for VR (Quest 3, Vision Pro) and downstream part-segmentation / physics. Canonical commercial path: gsplat 1.5.3 (Apache-2.0) standalone or nerfstudio 1.1.5 splatfacto (Apache-2.0). Covers install stacks with CUDA pins, AprilTag metric-scale preservation, DefaultStrategy vs MCMCStrategy densification, per-cluster training and PLY merge, and .ply SH export. Original Inria 3DGS is non-commercial only; OpenSplat is AGPL-3.0; both are excluded from commercial pipelines.'
version: 2.0.0
author: Orchestra Research
license: MIT
tags: [3DGS, Gaussian Splatting, gsplat, Nerfstudio, Splatfacto, MCMC, COLMAP, PLY Export, Apache-2.0, VR, Digital Twin]
dependencies: [nerfstudio==1.1.5, gsplat==1.5.3, torch==2.4.1, torchvision==0.19.1, numpy<2]
---

# Training Gaussian Splats

Primary 3DGS training skill for lab-equipment digital twins on a Linux Docker A100. Input: COLMAP sparse model with AprilTag-anchored metric scale. Output: `.ply` for Unity/Unreal/Quest/Vision Pro and downstream mesh or part-segmentation.

**CRITICAL LICENSE WARNING**: Original Inria 3DGS (`graphdeco-inria/gaussian-splatting`) is **non-commercial research only** — do not use it in commercial pipelines without explicit MPII/Inria consent. OpenSplat is AGPL-3.0 — closed commercial use requires legal review. **Commercial canonical stack: gsplat 1.5.3 (Apache-2.0) and nerfstudio 1.1.5 splatfacto (Apache-2.0).**

Confirmed versions as of May 2026:
- nerfstudio 1.1.5 (released 2024-11-11) — pins gsplat==1.4.0 internally
- gsplat 1.5.3 (released 2025-07-04) — standalone Apache-2.0; use in a separate venv
- Brush v0.3.0 (released 2025-09-14) — Apache-2.0, WebGPU/Rust, no CUDA/Python API
- Taichi 3DGS — no stable releases, experimental; not production-canonical
- OpenSplat 1.1.4 (released 2024-08-22) — AGPL-3.0; C++ CLI, not license-clean for closed use

## Quick start

```bash
# Layout: data/colmap-scene/{images,sparse/0}
ns-train splatfacto \
  --data data/colmap-scene \
  --max-num-iterations 1000 \
  --vis viewer \
  colmap --colmap-path sparse/0
CFG="$(find outputs -name config.yml | sort | tail -1)"
ns-viewer --load-config "$CFG"
```

## Common workflows

### 1. Install: nerfstudio-pinned stack (primary commercial path)

Task Progress:
- [ ] Step 1: Pull CUDA 12.1 devel image
- [ ] Step 2: Install torch 2.4.1+cu121 from PyTorch index
- [ ] Step 3: Install gsplat==1.4.0 prebuilt wheel, then nerfstudio==1.1.5
- [ ] Step 4: Smoke-test imports

Nerfstudio 1.1.5 pins `gsplat==1.4.0`; do not upgrade gsplat inside this venv.

```bash
# FROM nvidia/cuda:12.1.1-cudnn8-devel-ubuntu22.04
python3.10 -m venv /opt/venvs/nerfstudio
source /opt/venvs/nerfstudio/bin/activate
pip install -U pip setuptools wheel

pip install torch==2.4.1+cu121 torchvision==0.19.1+cu121 \
  --index-url https://download.pytorch.org/whl/cu121

pip install ninja "numpy<2" jaxtyping rich

# Prebuilt gsplat wheel before nerfstudio (avoids JIT source build)
pip install gsplat==1.4.0 \
  --index-url https://docs.gsplat.studio/whl/pt24cu121

pip install nerfstudio==1.1.5 \
  --extra-index-url https://docs.gsplat.studio/whl/pt24cu121

# Smoke test
python -c "
import torch, gsplat, nerfstudio
print(torch.__version__, torch.version.cuda, gsplat.__version__)
assert torch.cuda.is_available()
print('GPU:', torch.cuda.get_device_name(0))
"
```

Alternative: CUDA 11.8 base (upstream nerfstudio Docker):

```bash
# FROM nvidia/cuda:11.8.0-devel-ubuntu22.04
pip install torch==2.1.2+cu118 torchvision==0.16.2+cu118 \
  --index-url https://download.pytorch.org/whl/cu118
pip install gsplat==1.4.0 \
  --index-url https://docs.gsplat.studio/whl/pt21cu118
pip install nerfstudio==1.1.5 \
  --extra-index-url https://docs.gsplat.studio/whl/pt21cu118
```

### 2. Splatfacto from COLMAP with AprilTag metric anchoring

Task Progress:
- [ ] Step 1: Verify `data/colmap-scene/{images,sparse/0}` layout
- [ ] Step 2: Disable auto-scaling/orientation — preserve AprilTag metric frame
- [ ] Step 3: Turn off camera optimizer for known-good poses
- [ ] Step 4: Train 30k iterations with antialiased rasterization
- [ ] Step 5: Export `.ply` with SH coefficients

Nerfstudio COLMAP dataparser defaults `auto_scale_poses=True`, `orientation_method="up"`, `center_method="poses"`. Disable all three for AprilTag-anchored metric scenes.

```bash
SCENE=data/colmap-scene

ns-train splatfacto \
  --data "$SCENE" \
  --vis viewer+tensorboard \
  --max-num-iterations 30000 \
  --pipeline.model.sh-degree 3 \
  --pipeline.model.sh-degree-interval 1000 \
  --pipeline.model.rasterize-mode antialiased \
  --pipeline.model.background-color random \
  --pipeline.model.cull-alpha-thresh 0.03 \
  --pipeline.model.cull-scale-thresh 0.35 \
  --pipeline.model.densify-grad-thresh 0.0008 \
  --pipeline.model.camera-optimizer.mode off \
  colmap \
    --colmap-path sparse/0 \
    --images-path images \
    --downscale-factor 1 \
    --auto-scale-poses False \
    --orientation-method none \
    --center-method none \
    --assume-colmap-world-coordinate-convention False
```

Notes:
- `--assume-colmap-world-coordinate-convention False` prevents extra coordinate rotation when `orientation-method=none`.
- Lower `cull-alpha-thresh` to 0.005 only after a clean default run; too-low thresholds preserve specular floaters on polished metal.
- `splatfacto-big`: higher quality, ~12 GB VRAM vs ~6 GB — use for final captures.
- Docker remote: add `--viewer.websocket-host 0.0.0.0 --viewer.websocket-port 7007`.

Export to PLY:

```bash
CFG=$(find outputs -name config.yml | sort | tail -1)
ns-export gaussian-splat \
  --load-config "$CFG" \
  --output-dir exports/splat \
  --output-filename lab_equipment.ply \
  --ply-color-mode sh_coeffs
```

PLY field convention: `x,y,z` means, `f_dc_*`/`f_rest_*` SH coefficients (transposed to Inria order), `opacity` raw logit, `scale_0..2` log-space, `rot_0..3` wxyz quaternion.

### 3. Standalone gsplat 1.5.3 trainer (specular-metal scenes / custom pipelines)

Task Progress:
- [ ] Step 1: Install gsplat==1.5.3 in a **separate** venv (do not mix with nerfstudio)
- [ ] Step 2: Initialize Gaussians from COLMAP seed points
- [ ] Step 3: Choose DefaultStrategy or MCMCStrategy; wire up strategy lifecycle
- [ ] Step 4: Render with `rasterize_mode="antialiased"`, `packed=True`, `absgrad=True`

```bash
# FROM nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04
python3.10 -m venv /opt/venvs/gsplat
source /opt/venvs/gsplat/bin/activate
pip install torch==2.4.1+cu124 torchvision==0.19.1+cu124 \
  --index-url https://download.pytorch.org/whl/cu124
pip install "numpy<2" ninja
pip install gsplat==1.5.3 \
  --index-url https://docs.gsplat.studio/whl/pt24cu124
```

```python
import torch, torch.nn.functional as F
from gsplat.rendering import rasterization
from gsplat.strategy import DefaultStrategy, MCMCStrategy

# DefaultStrategy: Inria-style adaptive densification
strategy = DefaultStrategy(
    prune_opa=0.005,
    grow_grad2d=0.0002,
    grow_scale3d=0.01,
    grow_scale2d=0.05,
    prune_scale3d=0.1,
    prune_scale2d=0.15,
    refine_start_iter=500,
    refine_stop_iter=15000,
    reset_every=3000,
    refine_every=100,
    absgrad=True,
    revised_opacity=False,
)
state = strategy.initialize_state(scene_scale=scene_extent_meters)
strategy.check_sanity(params, optimizers)

for step in range(30000):
    cam = sample_training_camera()
    sh_degree = min(step // 1000, 3)
    renders, alphas, meta = rasterization(
        means=params["means"],
        quats=params["quats"],
        scales=torch.exp(params["scales"]),
        opacities=torch.sigmoid(params["opacities"]).squeeze(-1),
        colors=params["colors"],
        viewmats=cam.viewmat[None],
        Ks=cam.K[None],
        width=cam.width, height=cam.height,
        render_mode="RGB", sh_degree=sh_degree,
        packed=True, absgrad=True,
        rasterize_mode="antialiased",
    )
    strategy.step_pre_backward(params, optimizers, state, step, meta)
    loss = F.l1_loss(renders[0], cam.image.cuda())
    loss.backward()
    for opt in optimizers.values():
        opt.step(); opt.zero_grad(set_to_none=True)
    strategy.step_post_backward(
        params=params, optimizers=optimizers, state=state,
        step=step, info=meta, packed=True,
    )
```

For VRAM-constrained scenes, use `MCMCStrategy`:

```python
strategy = MCMCStrategy(
    cap_max=600_000,
    refine_start_iter=500,
    refine_stop_iter=15000,
    noise_lr=5e-3,
    min_opacity=0.005,
)
```

### 4. Per-cluster training and PLY merge

Task Progress:
- [ ] Step 1: Compute one global metric frame (AprilTags) for the full scene
- [ ] Step 2: Partition images by cluster; each cluster trains with the same world frame
- [ ] Step 3: Export each cluster to PLY with identical SH mode and world transform
- [ ] Step 4: Merge PLYs; validate schema identity before merging

```bash
npm install -g @playcanvas/splat-transform

# Merge clusters sharing the same world frame
splat-transform \
  cluster_a.ply cluster_b.ply cluster_c.ply \
  merged.ply --filter-nan

# Apply a known rigid offset before merge
splat-transform \
  -t 1.2,0,0 cluster_b.ply \
  -r 0,0,90  cluster_c.ply \
  cluster_a.ply \
  merged.ply
```

Only concatenate PLY vertices when all files share identical schema and SH degree/order. Mixing nerfstudio vs raw gsplat exports without schema normalization causes silent rendering artifacts.

## When to use vs alternatives

| Need | Recommendation |
|---|---|
| Visual fidelity, VR novel-view (commercial) | This skill — splatfacto or gsplat (both Apache-2.0) |
| Physics collision meshes | `extracting-gs-surfaces` (2DGS, GOF, PGSR, SuGaR) |
| Dominant specular metals / DR | `training-reflection-aware-splats` (Spec-Gaussian, GaussianShader) |
| Tiny parts, transparent specimens | `training-nerf-fallbacks` (Nerfacto, Instant-NGP) |
| Cross-platform / WebGPU, no CUDA | Brush v0.3.0 (ArthurBrussee/brush, Apache-2.0, Rust) |
| Non-commercial research only | Original Inria 3DGS (graphdeco-inria) — non-commercial research license |
| AGPL-acceptable C++ portability | OpenSplat 1.1.4 — AGPL-3.0, check legal before commercial use |

Within this skill: use splatfacto for fast iteration; splatfacto-big for final captures; MCMCStrategy when splat count must be capped for a VRAM or delivery budget.

## Common issues

1. **gsplat/nerfstudio version mismatch** ([nerfstudio #3196](https://github.com/nerfstudio-project/nerfstudio/issues/3196)) — gsplat 1.0+ broke splatfacto imports (`ModuleNotFoundError: gsplat._torch_impl`). Fix: nerfstudio 1.1.5 pins `gsplat==1.4.0`. Never upgrade gsplat inside the nerfstudio venv; use a separate venv for gsplat 1.5.x standalone work.

2. **Splatfacto fails to reconstruct scene that Nerfacto handles** ([nerfstudio #3674](https://github.com/nerfstudio-project/nerfstudio/issues/3674)) — Seen with Ubuntu 22.04, RTX 3090, PyTorch 2.1.2+cu118. Splats require adequate point-cloud initialization from COLMAP; if COLMAP reconstruction is sparse, splatfacto converges poorly. Fix: improve COLMAP coverage, increase `--max-num-iterations`, or fall back to `training-nerf-fallbacks`.

3. **Output quality worse than original 3DGS** ([gsplat #777](https://github.com/nerfstudio-project/gsplat/issues/777)) — Reported with both simple_trainer.py and splatfacto. Often caused by incorrect scene scale, aggressive culling, or mismatched densification thresholds. Fix: verify `scene_scale` in MCMCStrategy init, lower `cull_alpha_thresh`, and confirm SH degree ramp-up is working.

4. **PyPI/venv install trouble with gsplat** ([gsplat #539](https://github.com/nerfstudio-project/gsplat/issues/539)) — gsplat 1.4.0 pip install failures with Python 3.11 and certain Torch/CUDA variants. Fix: use the prebuilt wheel index (`https://docs.gsplat.studio/whl/pt<XX>cu<YY>`) matching your exact torch+CUDA combination; use a `devel` Docker image, not `runtime`.

5. **CUDA OOM during MCMC growth** — MCMC growth toward high splat counts hits large tile-sorting allocations. Fix: lower `cap_max` (300k–800k for small enclosed scenes) or switch to DefaultStrategy. A100 80 GB can handle MCMC to 1M with controlled image count and resolution.

6. **Metric scale silently normalized** — Nerfstudio COLMAP dataparser auto-scales by default. For VR/physics, always set `--auto-scale-poses False --orientation-method none --center-method none --assume-colmap-world-coordinate-convention False` after AprilTag alignment.

7. **Empty PLY from save_ply** ([gsplat #590](https://github.com/nerfstudio-project/gsplat/issues/590)) — `gsplat.utils.save_ply` wrote empty PLY when opacities contained NaN (fixed in gsplat 1.5.2). If training diverges, all Gaussians may be filtered by `np.isfinite`; check for NaN in loss before export.

## Advanced topics

- **Compression before VR delivery**: `gsplat.compression.PngCompression` reduces a 1M-Gaussian PLY from ~236 MB to ~16.5 MB; PlayCanvas SplatTransform supports SH band stripping, opacity filtering, and SPZ format; KHR_gaussian_splatting glTF extension is a Release Candidate as of Feb 2026.
- **VR splat-count budgets**: Quest 3 real-time target is 200k–500k with an optimized renderer; Apple Vision Pro (MetalSplatter) supports 750k–2M with stereo amplification. Profile on target hardware.
- **DefaultStrategy vs MCMCStrategy**: DefaultStrategy duplicates high-gradient small Gaussians, splits large ones, prunes low-opacity Gaussians, and periodically resets opacity. MCMCStrategy caps total count and uses stochastic relocation — better for memory budgets, slower convergence. See gsplat strategy docs: https://docs.gsplat.studio/main/apis/strategy.html.
- **Standalone gsplat examples CLI**: `cd examples && python simple_trainer.py default --data_dir data/360_v2/garden/ --data_factor 4 --result_dir ./results/garden`

## Version pins and wheel index

```
# PATH A — nerfstudio + splatfacto (primary commercial)
Docker base:   nvidia/cuda:12.1.1-cudnn8-devel-ubuntu22.04
               nvidia/cuda:11.8.0-devel-ubuntu22.04  (upstream alt)
GPU:           NVIDIA A100 (arch sm_80)
Python:        3.10
PyTorch:       torch==2.4.1+cu121  OR  torch==2.1.2+cu118
Torchvision:   torchvision==0.19.1+cu121  OR  0.16.2+cu118
gsplat:        gsplat==1.4.0  (wheel: pt24cu121 or pt21cu118)
nerfstudio:    nerfstudio==1.1.5
NumPy:         numpy<2

# PATH B — standalone gsplat trainer (specular / custom)
Docker base:   nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04
PyTorch:       torch==2.4.1+cu124
Torchvision:   torchvision==0.19.1+cu124
gsplat:        gsplat==1.5.3  (wheel: pt24cu124)
NumPy:         numpy<2

Wheel index:   https://docs.gsplat.studio/whl
```

## API surface

`ns-train splatfacto` key model flags:

```bash
--max-num-iterations 30000
--pipeline.model.sh-degree 3
--pipeline.model.sh-degree-interval 1000
--pipeline.model.rasterize-mode antialiased      # classic|antialiased
--pipeline.model.background-color random
--pipeline.model.cull-alpha-thresh 0.03
--pipeline.model.cull-scale-thresh 0.35
--pipeline.model.densify-grad-thresh 0.0008
--pipeline.model.use-absgrad False
--pipeline.model.camera-optimizer.mode off
--vis viewer+tensorboard
--viewer.websocket-host 0.0.0.0                  # Docker remote
--viewer.websocket-port 7007
```

`colmap` dataparser flags:

```bash
--colmap-path sparse/0
--images-path images
--downscale-factor 1
--auto-scale-poses False
--orientation-method none
--center-method none
--assume-colmap-world-coordinate-convention False
```

`ns-export gaussian-splat`:

```bash
--load-config outputs/.../config.yml
--output-dir exports/splat
--output-filename lab_equipment.ply
--ply-color-mode sh_coeffs          # or rgb
--obb-center 0 0 0
--obb-rotation 0 0 0
--obb-scale 1 1 1
```

## Resources

- gsplat: https://github.com/nerfstudio-project/gsplat (1.5.3, 2025-07-04, Apache-2.0)
- gsplat wheel index: https://docs.gsplat.studio/whl
- gsplat rasterization API: https://docs.gsplat.studio/main/apis/rasterization.html
- gsplat strategies: https://docs.gsplat.studio/main/apis/strategy.html
- gsplat compression: https://docs.gsplat.studio/main/apis/compression.html
- nerfstudio: https://github.com/nerfstudio-project/nerfstudio (1.1.5, 2024-11-11, Apache-2.0)
- Splatfacto docs: https://docs.nerf.studio/nerfology/methods/splat.html
- ns-export docs: https://docs.nerf.studio/quickstart/export_geometry.html
- Brush: https://github.com/ArthurBrussee/brush (v0.3.0, 2025-09-14, Apache-2.0, WebGPU/Rust)
- OpenSplat: https://github.com/pierotofy/OpenSplat (1.1.4, 2024-08-22, AGPL-3.0)
- SplatTransform: https://github.com/playcanvas/splat-transform
- SuperSplat: https://github.com/playcanvas/supersplat
- KHR_gaussian_splatting RC: https://www.khronos.org/blog/khronos-release-candidate-khr-gaussian-splatting
- Issues: see references/issues.md
