---
name: training-reflection-aware-splats
description: Provides reflection-aware and specular-aware 3D Gaussian Splatting training for highly specular, metallic, and glossy surfaces such as polished steel, anodized aluminum, SEM exteriors, optical benches, and glass covers. Covers Spec-Gaussian (MIT), Ref-Gaussian (MIT with audit required), GaussianShader (non-commercial Inria-style — research only), 3DGS-DR (non-commercial rasterizer license — research only), and Ref-GS (MIT, CVPR 2025). Use when vanilla 3DGS produces floaters, view-dependent artifacts, or fails to model environment reflections on specular lab equipment.
version: 2.0.0
author: Orchestra Research
license: MIT
tags: [3DGS, GS, Specular, Reflection, PBR, Spec-Gaussian, Ref-Gaussian, MIT, Non-Commercial, CVPR 2025]
dependencies: [torch>=1.12, diff-gaussian-rasterization, simple-knn, plyfile, numpy]
---

# Training Reflection-Aware Splats

Teaches an autonomous agent to train, render, compare, and debug reflection-aware 3DGS variants for lab-equipment digital twins (SEM exteriors, optical benches, brushed-aluminum knobs, mirror mounts). Vanilla 3DGS allocates floater Gaussians to fit moving highlights; these methods parameterize view-dependent shading explicitly.

**Commercial use**: Spec-Gaussian and Ref-GS are MIT-safe. Ref-Gaussian requires a dual-license audit (MIT root + bundled Inria non-commercial LICENSE.md). GaussianShader and 3DGS-DR are non-commercial research only.

## Quick start

Spec-Gaussian is the MIT default for polished metal and anodized aluminum. End-to-end copy-paste sequence for a real indoor scene on a single GPU:

```bash
# 1. Clone and enter repo
git clone --recursive https://github.com/ingra14m/Specular-Gaussians.git
cd Specular-Gaussians

# 2. Create isolated Python 3.7 / CUDA 11.6 environment
conda create -n spec_gs python=3.7 -y && conda activate spec_gs
pip install torch==1.13.1+cu116 torchvision==0.14.1+cu116 \
  --extra-index-url https://download.pytorch.org/whl/cu116
pip install torch-scatter -f https://data.pyg.org/whl/torch-1.13.0+cu116.html

# 3. Install local submodules BEFORE requirements.txt (order matters)
pip install submodules/depth-diff-gaussian-rasterization submodules/simple-knn
pip install -r requirements.txt

# 4. Train (real indoor scene; -r 2 = half resolution to avoid OOM)
python train.py -s /data/colmap_scene -m output/spec_default \
  --eval --is_real --is_indoor --asg_degree 12 -r 2

# 5. Render held-out views and compute metrics
python render.py -m output/spec_default --skip_train --mode render
python metrics.py -m output/spec_default
```

If `forward() got unexpected keyword 'means2D_densify'` (issue #15): reinstall `submodules/depth-diff-gaussian-rasterization` inside a fresh conda env; the rasterizer API is incompatible with vanilla diff-gaussian-rasterization.

If `use_filter` is not recognised (issue #9): add `use_filter=True` in `arguments/__init__.py` defaults or pass it via the config dict; current render path applies filtering automatically for `is_real` scenes.

## Common workflows

### 1. Train Spec-Gaussian on an SEM exterior — polished steel without floaters

Task Progress:
- [ ] Step 1: Clone Specular-Gaussians (URL: https://github.com/ingra14m/Specular-Gaussians) into a fresh Python 3.7 / CUDA 11.6 conda env
- [ ] Step 2: Install torch==1.13.1+cu116, torch-scatter, and both local submodules explicitly before requirements.txt
- [ ] Step 3: Run baseline real-indoor training; inspect normal maps and render at checkpoint 7k
- [ ] Step 4: If floaters appear around chrome handles or glass panels, escalate to anchor training
- [ ] Step 5: Run metrics.py; compare PSNR/SSIM/LPIPS against vanilla 3DGS on the same test split

```bash
DATA=/data/sem_exterior
OUT=output/sem_specgs

# Default real-indoor run
python train.py -s "$DATA" -m "$OUT" \
  --eval --is_real --is_indoor --asg_degree 12 -r 2

# Escalation: anchor training reduces floaters on complex real scenes
python train_anchor.py -s "$DATA" -m "${OUT}_anchor" \
  --eval --is_real --is_indoor --asg_degree 12 -r 2 \
  --voxel_size 0.001 --update_init_factor 16 --iterations 30000

python render.py -m "$OUT" --skip_train --mode render
python metrics.py -m "$OUT"
```

Note: Maintainer explicitly recommends non-anchor training for quality (issue #13); use anchor only if VRAM or floaters force it.

### 2. Ref-Gaussian for a mirrored optical breadboard (PBR-grade)

Task Progress:
- [ ] Step 1: Clone fudan-zvg/ref-gaussian into a dedicated Python 3.8 / CUDA 11.7 conda env
- [ ] Step 2: Install submodules in order: cubemapencoder, diff-surfel-rasterization, simple-knn, raytracing
- [ ] Step 3: Pin scipy==1.10.1 to avoid the requirements.txt scipy==1.15.1 / Python 3.8 conflict
- [ ] Step 4: Train with env-scope flags to suppress background leakage; inspect env1.png/env2.png checkpoints
- [ ] Step 5: Run eval.py --save_images; verify normal maps are stable; check PSNR/SSIM/LPIPS/FPS in metric.txt
- [ ] Step 6: Confirm dual-license status before any commercial use

```bash
git clone --recursive https://github.com/fudan-zvg/ref-gaussian.git
cd ref-gaussian
conda create -n ref_gaussian python=3.8 -y && conda activate ref_gaussian
pip install torch==2.0.0 torchvision==0.15.0 torchaudio==2.0.0
pip install submodules/cubemapencoder submodules/diff-surfel-rasterization \
  submodules/simple-knn submodules/raytracing
pip install "scipy==1.10.1"   # override requirements.txt scipy==1.15.1
pip install -r requirements.txt

DATA=/data/optical_breadboard
OUT=output/breadboard_refgaussian

python train.py -s "$DATA" -m "$OUT" \
  --eval --iterations 20000 \
  --indirect_from_iter 10000 \
  --volume_render_until_iter 0 \
  --initial 1 --init_until_iter 3000 \
  --lambda_normal_smooth 0.45 \
  --use_env_scope \
  --env_scope_center 0.0 0.0 0.0 \
  --env_scope_radius 1.0 \
  -r 4

python eval.py --model_path "$OUT" --save_images
```

### 3. Ref-GS on real lab equipment (MIT, CVPR 2025) — single-GPU patch required

Task Progress:
- [ ] Step 1: Clone YoujiaZhang/Ref-GS into a Python 3.10+ / CUDA 12.x conda env
- [ ] Step 2: **Patch hardcoded GPU** — `train.py` and `train-real.py` both set `CUDA_VISIBLE_DEVICES=2`; change to `0` on single-GPU workstations (issue #4, closed but unfixed in repo)
- [ ] Step 3: Install submodules: diff-surfel-rasterization, simple-knn, nvdiffrast
- [ ] Step 4: Provide `images_4` or `images_8` directories; follow 3DGS-DR Ref-Real resolution protocol (issue #7)
- [ ] Step 5: Run `train-real.py` (no separate render.py); evaluate via `notebook/test.ipynb`
- [ ] Step 6: Confirm MIT root license; verify any third-party CUDA submodule licenses before redistribution

```bash
git clone --recursive https://github.com/YoujiaZhang/Ref-GS.git
cd Ref-GS

# Patch hardcoded GPU (issue #4 — still present in repo as of May 2025)
sed -i 's/os.environ\["CUDA_VISIBLE_DEVICES"\] = "2"/os.environ["CUDA_VISIBLE_DEVICES"] = "0"/' train.py train-real.py

conda create -n ref_gs python=3.10 -y && conda activate ref_gs
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121
pip install submodules/diff-surfel-rasterization submodules/simple-knn
pip install nvdiffrast
pip install -r requirements.txt

DATA=/data/sem_exterior          # must contain images_4/ or images_8/
OUT=output/sem_refgs

python train-real.py -s "$DATA" -m "$OUT" \
  --eval --iterations 30000 \
  --lambda_normal_smooth 0.1 \
  --use_env_scope \
  --env_scope_center 0.0 0.0 0.0 \
  --env_scope_radius 1.5

# Evaluate via notebook (no root render.py or eval.py in this repo):
# jupyter nbconvert --to notebook --execute notebook/test.ipynb \
#   --ExecutePreprocessor.kernel_name=python3
```

Note: `nero2blender.py` conversion script is not bundled — obtain from GaussianShader repo (issue #10).

### 4. Compare GaussianShader vs Spec-Gaussian on a brushed-aluminum knob

Task Progress:
- [ ] Step 1: Confirm GaussianShader use is research-only (non-commercial Inria license)
- [ ] Step 2: Create isolated Python 3.7.13 / CUDA 11.1 conda env from environment.yml
- [ ] Step 3: Train both methods on identical COLMAP split; record git SHA for both
- [ ] Step 4: Render identical held-out camera paths; compare PSNR and human inspection grid
- [ ] Step 5: Document license status in artifact metadata; do not include GaussianShader outputs in commercial deliverables

```bash
SCENE=/data/brushed_knob

# --- Spec-Gaussian (MIT) ---
conda activate spec_gs
python train.py -s "$SCENE" -m output/knob_specgs \
  --eval --is_real --is_indoor --asg_degree 24 -r 2
python render.py -m output/knob_specgs --skip_train --mode render
python metrics.py -m output/knob_specgs

# --- GaussianShader (non-commercial) --- separate env ---
git clone --recursive https://github.com/Asparagus15/GaussianShader.git
cd GaussianShader
conda env create --file environment.yml
conda activate gaussian_shader
python train.py -s "$SCENE" -m output/knob_gshader \
  --eval --brdf_dim 0 --sh_degree -1 \
  --lambda_predicted_normal 2e-1 --brdf_envmap_res 512
python render.py -m output/knob_gshader --skip_train \
  --brdf_dim 0 --sh_degree -1 --brdf_mode envmap --brdf_envmap_res 512
python metrics.py -m output/knob_gshader
```

Use `--asg_degree 12` first if VRAM is tight; 24 gives finer anisotropic lobes on brushed surfaces.

## When to use vs alternatives

| Tool | Best for | License | Activity |
|---|---|---|---|
| Spec-Gaussian | Brushed metal, anisotropic highlights, polished real objects | MIT | Last commit Nov 2024; dormant |
| Ref-Gaussian | PBR roughness/metalness, relighting, env-map outputs | MIT + Inria audit required | Last commit Mar 2025; dormant |
| Ref-GS | MIT-friendly real-scene directional factorization, 2DGS geometry | MIT | Last commit May 2025; most recent |
| GaussianShader | Research baseline: learned BRDF + env-map shading | Non-commercial Inria-style | Last commit Jan 2024; stale |
| 3DGS-DR | Research baseline: deferred reflection, env-scope leakage | Non-commercial (rasterizer) | Last commit Jul 2024; stale |

**Commercial path**: use Spec-Gaussian or Ref-GS. For PBR outputs, use Ref-Gaussian after legal audit of its bundled LICENSE.md.

**Non-commercial flags**: GaussianShader LICENSE.md is the Gaussian-Splatting research/evaluation-only license. 3DGS-DR has no top-level license file; its bundled submodules/diff-gaussian-rasterization_c7/LICENSE.md is also non-commercial. Treat both as non-commercial unless authors provide explicit clearance.

**Vanilla 3DGS fallback**: for commercially safe scenes where reflections are not the focus, `training-gaussian-splats` with mask-based highlight suppression is simpler.

**NeRF fallback**: transparent and refractive objects (glass slides, optical lenses) are better served by volumetric NeRF methods; splat-based methods do not model refraction.

**Geometry**: no reflection-aware splat method produces physics-grade normals. Use CAD, calipers, or structured light for collision geometry.

## Common issues

1. **OOM on real scenes** (Spec-Gaussian #2, #9; 3DGS-DR #7, #20): add `-r 4` or `-r 8` to downsample. For 3DGS-DR Ref-Real sedan, use 1/8 resolution; other Ref-Real scenes use 1/4. Anchor Gaussian or `--use_filter=True` helps Spec-Gaussian. If a 24 GB GPU still OOMs with 3DGS-DR, follow maintainer guidance: train on provided images_4/images_8 directories, not full resolution.

2. **c3/c7 gradient shape mismatch in 3DGS-DR** (issue #18, open): caused by namespace collision between c3 and c7 rasterizers when reusing an existing 3DGS env. Fix: use a completely fresh Docker container; do not install c3 and vanilla diff-gaussian-rasterization in the same env.

3. **raytracing submodule compile error in Ref-Gaussian** (issue #2, open): Eigen/CUDA half-operator ambiguity on Windows. Use Linux Docker with CUDA 11.7/11.8 and PyTorch 2.0.0. Try `apt-get install libeigen3-dev` or an alternate raytracing fork for higher CUDA versions.

4. **GaussianShader install failure** (issues #23, #34): Python 3.7 environment file has aged out of channels; some packages are no longer available. Try `conda env create --file environment.yml --no-default-packages`; skip Cutlass (issue #23 confirms it may run without it). Issue #34 remains open with no maintainer fix.

5. **Normal instability / noisy normals on smooth surfaces**: On polished steel and flat anodized panels, Gaussian shortest-axis normals are unreliable. Monitor normal maps at checkpoints (7k, 15k). Reduce `--normal_lr`, extend init stage (`--init_until_iter`), or increase `--lambda_normal_smooth` only on smooth regions. For Ref-GS, increase camera baseline and add grazing-angle views rather than tuning loss weights alone. Spec-Gaussian issue #21 (`center_normal` question on smooth surfaces) is open with no documented fix; treat smooth-surface normals from any of these tools as unreliable for collision geometry. See [references/issues.md](references/issues.md) for per-tool open issue details.

6. **GaussianShader flag name discrepancy**: README documents `--brdf_env 512` but current `arguments/__init__.py` exposes `--brdf_envmap_res`. Always use `--brdf_envmap_res 512` with the current codebase. Additionally, issue #19 (open) documents that `get_minimum_axis` normal-axis selection is wrong/ambiguous; PR #20 provides a patch but is unmerged — apply it manually on research baselines where normal quality matters.

7. **GaussianShader env-map save/load degrades quality** (issue #24, open): saving and reloading the HDR environment map changes output appearance. User workaround: save and load `EnvironmentLight.state_dict()` directly instead of going through the HDR file I/O path. No maintainer fix as of May 2026.

8. **Ref-Gaussian cannot reproduce paper metrics / floaters after 20k iters** (issue #9, open): no maintainer fix posted. Mitigations: cap training at 20k iterations; use `--env_scope_radius` tightly around the object; verify that `--indirect_from_iter 10000` and `--initial 1 --init_until_iter 3000` flags are set (omitting them changes the training regime). `depth_to_normal` illegal memory access (issue #5) was closed as completed with no fix comment — if it reappears, downgrade CUDA or revert to PyTorch 2.0.0 exactly.

9. **Environment-map energy leakage / ghost geometry baked into env-map**: occurs when the env-scope sphere is too large relative to the object. No public issues explicitly titled this. Mitigation: pass `--use_env_scope --env_scope_center <cx> <cy> <cz> --env_scope_radius <r>` with the smallest sphere enclosing the target object in COLMAP world coordinates. Inspect env-map renders at iterations 3000–5000; large diffuse blobs at that stage indicate leakage. Background masking (RGBA input or mask directory) further reduces leakage.

10. **FP16 / NaN in 3DGS-DR** (issue #20, open): user-reported NaN after applying unofficial FP16 modifications. FP16 training is not officially supported in any of these repos; revert to FP32. The sedan Ref-Real scene is expected to require low-resolution data (images_8) even on 24 GB GPUs — this is documented behaviour, not a bug.

## Advanced topics

- Detailed per-tool open GitHub issues with verbatim fix status: [references/issues.md](references/issues.md)

## Resources

- Spec-Gaussian / Specular-Gaussians (MIT): https://github.com/ingra14m/Specular-Gaussians
- Ref-Gaussian (MIT + audit): https://github.com/fudan-zvg/ref-gaussian
- GaussianShader (non-commercial): https://github.com/Asparagus15/GaussianShader
- 3DGS-DR (non-commercial rasterizer): https://github.com/gapszju/3DGS-DR
- Ref-GS (MIT, CVPR 2025): https://github.com/YoujiaZhang/Ref-GS
- Original Gaussian-Splatting license: https://github.com/graphdeco-inria/gaussian-splatting/blob/main/LICENSE.md
- nvdiffrast (required by Ref-GS): https://github.com/NVlabs/nvdiffrast
