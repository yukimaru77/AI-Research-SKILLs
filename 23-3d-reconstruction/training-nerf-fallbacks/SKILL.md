---
name: training-nerf-fallbacks
description: Provides NeRF-based fallback rendering using Nerfacto (nerfstudio 1.1.5, Apache-2.0) and Instant-NGP v2.0 when 3DGS variants fail — excessive floaters on optical columns, transparent/glass specimens, sub-millimeter SEM aperture detail, or fundamentally hard specular geometry where Gaussian primitives are too coarse. Covers Nerfacto training from COLMAP with pose refinement, hash-grid tuning for micro-scale geometry, transparency handling, and Poisson/TSDF mesh export. CRITICAL LICENSE WARNING — Nerfacto/nerfstudio is Apache-2.0 (commercial-safe); Instant-NGP is NVIDIA Source Code License-NC (non-commercial/research only — do NOT ship outputs commercially). Use on Linux Docker with A100 GPU.
version: 2.0.0
author: Orchestra Research
license: MIT
tags: [NeRF, Nerfacto, Instant-NGP, Hash Grid, Transparency, Apache-2.0, Non-Commercial, Volumetric Rendering, tiny-cuda-nn]
dependencies: [torch==2.1.2+cu118, nerfstudio==1.1.5, tinycudann==2.0, numpy<2]
---

# Training NeRF Fallbacks

Operational fallback when 3DGS is primary but fails. Use this skill for: very small parts (sub-mm), transparent specimens, pose stress scenes, or floaters on specular narrow geometry (e.g. optical columns). Targets a single A100 on Linux Docker.

## When to use vs 3DGS

| Scene property | Use 3DGS | Use Nerfacto (this skill) |
|---|---|---|
| Photoreal novel-view rendering | Splatfacto | Nerfacto (slower) |
| Real-time VR / 60+ FPS | Splatfacto | Not viable (5–10 FPS) |
| Sub-millimeter geometry | Reflection-aware 3DGS or NeRF | Nerfacto (better) |
| Transparent specimens | Splatfacto fails | Nerfacto |
| Floaters on optical column | Try 3DGS first; use Nerfacto+pose-opt if floaters persist | |
| Volumetric / scattering media | Splatfacto fails | Nerfacto |
| Fast iteration / preview | Splatfacto | Instant-NGP (research only) |
| Watertight collision mesh | `extracting-gs-surfaces` | `ns-export poisson` (Apache-2.0) |

Within this skill: prefer **Nerfacto** (Apache-2.0) for any commercial output. Use **Instant-NGP** only for research validation / iteration speed; reproduce final runs in Nerfacto. See [references/issues.md](references/issues.md) for real GitHub issues.

## Version pins (2026, Linux A100 Docker)

```
# Official nerfstudio-supported stack (safest)
Base image:        nvidia/cuda:11.8.0-devel-ubuntu22.04
Python:            3.10
PyTorch:           torch==2.1.2+cu118, torchvision==0.16.2+cu118
nerfstudio:        nerfstudio==1.1.5  (released Nov 11, 2024, Apache-2.0)
tiny-cuda-nn:      git tag v2.0       (released Jul 8, 2025, BSD-3-Clause standalone)
Instant-NGP:       git tag v2.0       (released Jul 8, 2025, NVIDIA Source Code License-NC)
NumPy:             numpy<2
TCNN arch A100:    TCNN_CUDA_ARCHITECTURES=80

# CUDA 12.1 alternative (custom; validate end-to-end before shipping)
Base image:        nvidia/cuda:12.1.1-devel-ubuntu22.04
PyTorch:           torch==2.3.1, torchvision==0.18.1, cu121 wheels
# Avoid PyTorch >=2.6 with nerfstudio 1.1.5: issue #3683 / PRs #3702 #3711
# report torch.load(weights_only) breakage in ns-viewer, resume, ns-export.

# Architecture map
A100:              TCNN_CUDA_ARCHITECTURES=80
H100/H200:         TCNN_CUDA_ARCHITECTURES=90    (tiny-cuda-nn issue #455, #475)
RTX 4090/Ada:      TCNN_CUDA_ARCHITECTURES=89
RTX 5090/Blackwell: TCNN_CUDA_ARCHITECTURES=120  (tiny-cuda-nn issue #527, nerfstudio #3732)
```

## Docker build snippet (official stack)

```dockerfile
FROM nvidia/cuda:11.8.0-devel-ubuntu22.04

ARG DEBIAN_FRONTEND=noninteractive
ENV CUDA_HOME=/usr/local/cuda
ENV PATH=${CUDA_HOME}/bin:${PATH}
ENV LD_LIBRARY_PATH=${CUDA_HOME}/lib64:${LD_LIBRARY_PATH}
ENV TCNN_CUDA_ARCHITECTURES=80
ENV MAX_JOBS=8

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 python3.10-dev python3-pip git build-essential \
    ninja-build cmake ffmpeg libgl1 libglib2.0-0 \
 && rm -rf /var/lib/apt/lists/*

RUN python3.10 -m pip install --upgrade pip setuptools wheel ninja

RUN python3.10 -m pip install \
    torch==2.1.2+cu118 torchvision==0.16.2+cu118 \
    --index-url https://download.pytorch.org/whl/cu118

RUN python3.10 -m pip install "numpy<2"

# Pin tiny-cuda-nn to v2.0; build can take >1 h on H100/sm_90 (issue #475).
RUN python3.10 -m pip install \
    "git+https://github.com/NVlabs/tiny-cuda-nn.git@v2.0#subdirectory=bindings/torch"

RUN python3.10 -m pip install nerfstudio==1.1.5

# Verify CUDA and GPU
RUN python3.10 - <<'PY'
import torch
print(torch.__version__, torch.version.cuda, torch.cuda.get_device_name(0))
PY
```

## Quick start — ns-train nerfacto

```bash
# Minimal: nerfstudio-processed data (transforms.json in /data/scene_processed)
ns-train nerfacto \
  --data /data/scene_processed \
  --vis viewer \
  --viewer.websocket-port 7007

# Direct COLMAP folder (images/, sparse/0 layout)
ns-train nerfacto \
  --data /data/scene_colmap \
  --vis viewer \
  --max-num-iterations 30000 \
  colmap \
  --images-path images \
  --colmap-path sparse/0 \
  --orientation-method up \
  --center-method poses \
  --eval-mode interval

CFG="$(find outputs -name config.yml | sort | tail -1)"
ns-viewer --load-config "$CFG" --viewer.websocket-port 7007 --viewer.websocket-host 0.0.0.0
```

Note: COLMAP flags accept both hyphens (`--images-path`) and underscores (`--images_path`); prefer hyphens (GNU style, Tyro default). Flags must come **after** the `colmap` subcommand token.

Output structure:
```
outputs/<experiment>/nerfacto/<YYYY-MM-DD_HHMMSS>/
  config.yml
  nerfstudio_models/step-000029999.ckpt
  events.out.tfevents...
```

## Workflow 1 — Floater suppression on optical column (pose refinement)

When 3DGS produces excessive floaters on a narrow cylindrical specular scene (optical column), fall back to Nerfacto with camera pose refinement.

Task progress:
- [ ] Step 1: Confirm 3DGS floater failure; export COLMAP sparse/0 from the same capture
- [ ] Step 2: Train Nerfacto with SO3xR3 camera optimizer and raised distortion loss
- [ ] Step 3: Monitor `camera_opt_translation_*` / `camera_opt_rotation_*` in TensorBoard — reduce LR if diverging
- [ ] Step 4: Export Poisson mesh; validate against AprilTag scale reference

```bash
ns-train nerfacto \
  --data /data/optical_column_processed \
  --experiment-name optical_column_poseopt \
  --vis viewer+tensorboard \
  --max-num-iterations 60000 \
  --pipeline.model.camera-optimizer.mode SO3xR3 \
  --pipeline.model.camera-optimizer.trans-l2-penalty 0.05 \
  --pipeline.model.camera-optimizer.rot-l2-penalty 0.005 \
  --optimizers.camera-opt.optimizer.lr 3e-4 \
  --pipeline.model.use-average-appearance-embedding True \
  --pipeline.model.distortion-loss-mult 0.01 \
  --pipeline.model.background-color random
```

Camera optimizer key facts:
- Config class: `nerfstudio.cameras.camera_optimizers.CameraOptimizerConfig`
- Modes: `off`, `SO3xR3` (default in 1.1.5), `SE3`
- Flag location: `--pipeline.model.camera-optimizer.*` (NOT `--pipeline.datamanager.*` — that field is suppressed/deprecated in 1.1.5 via PR #2092)
- Avoid `--eval-mode all` with pose optimization; ColmapDataParser warns cameras may diverge
- Default L2 penalties: trans=0.01, rot=0.001; raise to 0.05/0.005 for noisy optical column poses

## Workflow 2 — Sub-millimeter SEM aperture via Instant-NGP (RESEARCH ONLY)

**NON-COMMERCIAL ONLY — NVIDIA Source Code License-NC.** Do not ship outputs commercially.

Task progress:
- [ ] Step 1: Confirm research-only authorization (NVIDIA Source Code License-NC)
- [ ] Step 2: Convert COLMAP to Instant-NGP transforms.json
- [ ] Step 3: Train with custom hash grid config for sub-millimeter detail
- [ ] Step 4: Document license restrictions in artifact metadata

```bash
# Build Instant-NGP v2.0 (Linux, A100)
git clone --recursive https://github.com/NVlabs/instant-ngp.git
cd instant-ngp && git checkout v2.0
export TCNN_CUDA_ARCHITECTURES=80
cmake . -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build --config RelWithDebInfo -j$(nproc)

# Convert COLMAP to transforms.json
python scripts/colmap2nerf.py \
  --colmap_db /data/sem/database.db \
  --images /data/sem/images \
  --out /data/sem/transforms.json

# Train and save snapshot
python scripts/run.py \
  --scene /data/sem/transforms.json \
  --network configs/nerf/base.json \
  --n_steps 50000 \
  --save_snapshot /data/sem/snapshots/sem_50k.ingp

# Load snapshot for inspection
python scripts/run.py \
  --scene /data/sem/transforms.json \
  --load_snapshot /data/sem/snapshots/sem_50k.ingp \
  --gui \
  --width 1920 --height 1080 \
  --sharpen 0.2 --exposure 0.0
```

CLI notes for v2.0:
- `--load_snapshot` and `--snapshot` are aliases (load); use `--save_snapshot` to write
- `--mode nerf` is accepted but prints: `Warning: the '--mode' argument is no longer in use. It has no effect.` — omit it
- OptiX is optional (faster SDF/mesh acceleration only); NeRF training does not require it

Hash grid config for sub-millimeter detail (`configs/nerf/base.json` override):
```json
{
  "encoding": {
    "otype": "HashGrid",
    "n_levels": 20,
    "n_features_per_level": 2,
    "log2_hashmap_size": 21,
    "base_resolution": 32,
    "per_level_scale": 1.34
  },
  "network": {
    "otype": "FullyFusedMLP",
    "activation": "ReLU",
    "output_activation": "None",
    "n_neurons": 64,
    "n_hidden_layers": 2
  }
}
```

`per_level_scale ≈ exp(log(finest_res / base_res) / (n_levels - 1))`: base_res=32, n_levels=20, scale≈1.34 → finest grid ≈ 8192 voxels. Test `log2_hashmap_size` 21–22 on A100.

tiny-cuda-nn v2.0 JIT fusion note: enabled via `model.jit_fusion = tcnn.supports_jit_fusion()`. Disable with `model.jit_fusion = False` if slow (>20M params or MLP width >128). No global CLI flag; set in code or leave default off.

## Workflow 3 — Transparent specimen holder (smooth density field)

Task progress:
- [ ] Step 1: Prepare masked images (textured background behind holder aids disambiguation)
- [ ] Step 2: Train Nerfacto with randomized background, lowered hash resolution, raised distortion loss
- [ ] Step 3: Export Poisson or TSDF mesh
- [ ] Step 4: Post-process in Open3D for watertightness

```bash
ns-train nerfacto \
  --data /data/transparent_holder_processed \
  --experiment-name holder_smooth \
  --vis viewer+tensorboard \
  --max-num-iterations 80000 \
  --pipeline.model.background-color random \
  --pipeline.model.use-average-appearance-embedding True \
  --pipeline.model.appearance-embed-dim 16 \
  --pipeline.model.distortion-loss-mult 0.01 \
  --pipeline.model.max-res 1024 \
  --pipeline.model.log2-hashmap-size 18 \
  --pipeline.model.camera-optimizer.mode SO3xR3

CONFIG=outputs/transparent_holder_processed/nerfacto/<timestamp>/config.yml

# Watertight mesh via Poisson
ns-export poisson \
  --load-config "$CONFIG" \
  --output-dir exports/holder_poisson \
  --num-points 2000000 \
  --remove-outliers True \
  --estimate-normals False \
  --normal-method open3d

# Volumetric fusion alternative
ns-export tsdf \
  --load-config "$CONFIG" \
  --output-dir exports/holder_tsdf \
  --resolution 512 \
  --use-bounding-box True
```

Why these settings:
- `background-color random`: reduces background baking at transparent boundaries
- `distortion-loss-mult 0.01` (5× default): suppresses floaters from refraction artifacts
- Lower `max-res` and `log2-hashmap-size`: prevent hash grid from fitting view-dependent glints as density
- `appearance-embed-dim 16`: captures per-frame lighting variation without overfitting

Post-export validation:
```python
import open3d as o3d
mesh = o3d.io.read_triangle_mesh("exports/holder_poisson/poisson_mesh.ply")
print("vertices:", len(mesh.vertices), "triangles:", len(mesh.triangles))
print("watertight:", mesh.is_watertight())
# If not watertight:
mesh = mesh.remove_non_manifold_edges()
mesh_cluster, _, _ = mesh.cluster_connected_triangles()
# keep largest component
```

## ns-export subcommands (all present in 1.1.5)

```bash
ns-export pointcloud   --load-config <cfg> --output-dir <out> --num-points 1000000
ns-export poisson      --load-config <cfg> --output-dir <out>
ns-export tsdf         --load-config <cfg> --output-dir <out> --resolution 512
ns-export marching-cubes --load-config <cfg> --output-dir <out>
ns-export cameras      --load-config <cfg> --output-dir <out>
ns-export gaussian-splat --load-config <cfg> --output-dir <out>
```

`ns-render` subcommands: `camera-path`, `interpolate`, `spiral`, `dataset` (FFmpeg required).

```bash
ns-render camera-path \
  --load-config outputs/.../config.yml \
  --camera-path-filename data/scene/camera_paths/path.json \
  --output-path renders/scene.mp4
```

## Common issues

**1. Floaters at bounding box edges** — Lower `--pipeline.model.distortion-loss-mult` (default 0.002; raise for more suppression). For small enclosed lab scenes, add `--pipeline.model.disable-scene-contraction True` and use metric COLMAP coordinates.

**2. Camera pose optimizer divergence** — Reduce `--optimizers.camera-opt.optimizer.lr` to 1e-4. Do not use `--eval-mode all` with camera optimization (ColmapDataParser warns of divergence; see also nerfstudio issue #1017). After convergence, consider re-running with `--pipeline.model.camera-optimizer.mode off` for a cleaner final bake.

**3. Transparency rendered as solid** — Default density activation (`trunc_exp`) rarely produces near-zero density. Use `--pipeline.model.background-color random`, lower `max-res`, and capture against a textured background. Mask the holder exterior if possible.

**4. Poisson mesh non-watertight** — Increase `--num-points` to 5M+, set `--remove-outliers True`, and post-process in Open3D (`remove_non_manifold_edges`, largest-component selection).

**5. PyTorch >=2.6 torch.load breakage** — nerfstudio 1.1.5 + PyTorch >=2.6 fails in ns-viewer, resume, and ns-export due to `weights_only` default change (issues #3683, PRs #3702 #3711). Workaround: stay on PyTorch <=2.5.1, or patch affected `torch.load(...)` calls with `weights_only=False` (trusted checkpoints only). Env workaround: `TORCH_FORCE_NO_WEIGHTS_ONLY_LOAD=1` (trust caveat applies).

**6. tiny-cuda-nn build timeout on H100** — Set `TCNN_CUDA_ARCHITECTURES=90` and `MAX_JOBS=8` before pip install. Build can exceed 1 h with sm_90 (issues #455, #475). Pin to v2.0 for reproducibility.

**7. Instant-NGP license contamination** — NVIDIA Source Code License-NC is non-commercial. Do NOT ship trained models, exported meshes, or renders from Instant-NGP in commercial products. Reproduce final runs in Nerfacto.

**8. COLMAP Docker permission error** — `ns-process-data` inside Docker may fail with unwritable `/.local` (issue #3456). Set `HOME=/workspace` or mount a writable `$XDG_DATA_HOME`.

## License summary

| Tool | License | Commercial use |
|---|---|---|
| nerfstudio / Nerfacto | Apache-2.0 | Yes — preserve copyright notice |
| tiny-cuda-nn (standalone) | BSD-3-Clause | Yes |
| Instant-NGP | NVIDIA Source Code License-NC | **No** — research/evaluation only; see issue discussion #933 for commercial licensing inquiry |
| Instant-NGP + tiny-cuda-nn (bundled) | NVIDIA Source Code License-NC governs | **No** |

For commercial digital twins, use nerfstudio + Nerfacto exclusively. Fall back to Instant-NGP only for internal research iteration; route final reproducible runs through Nerfacto.

## Key API flags (Nerfacto 1.1.5)

```bash
# Model
--pipeline.model.predict-normals True          # surface-aware regularization
--pipeline.model.disable-scene-contraction True # small enclosed scenes
--pipeline.model.distortion-loss-mult 0.002    # default; raise for floater suppression
--pipeline.model.background-color random       # or: black, white, last_sample
--pipeline.model.use-average-appearance-embedding True
--pipeline.model.appearance-embed-dim 32       # per-image lighting embedding size
--pipeline.model.hidden-dim 128                # default 64; raise for complex scenes
--pipeline.model.num-nerf-samples-per-ray 96   # default 48
--pipeline.model.max-res 2048                  # hash grid finest resolution
--pipeline.model.log2-hashmap-size 19          # default

# Camera optimizer (model-side, NOT datamanager — PR #2092)
--pipeline.model.camera-optimizer.mode SO3xR3
--pipeline.model.camera-optimizer.trans-l2-penalty 0.01
--pipeline.model.camera-optimizer.rot-l2-penalty 0.001
--optimizers.camera-opt.optimizer.lr 1e-4
```

## Resources

- Nerfstudio docs: https://docs.nerf.studio
- Nerfacto method: https://docs.nerf.studio/nerfology/methods/nerfacto.html
- ns-export geometry: https://docs.nerf.studio/quickstart/export_geometry.html
- Camera optimizer docs: https://docs.nerf.studio/developer_guides/cameras.html
- nerfstudio GitHub (1.1.5, Apache-2.0): https://github.com/nerfstudio-project/nerfstudio
- Instant-NGP GitHub (v2.0, NVIDIA Source Code License-NC): https://github.com/NVlabs/instant-ngp
- Instant-NGP license: https://github.com/NVlabs/instant-ngp/blob/master/LICENSE.txt
- tiny-cuda-nn (v2.0, BSD-3-Clause): https://github.com/NVlabs/tiny-cuda-nn
- Real issues: see [references/issues.md](references/issues.md)
