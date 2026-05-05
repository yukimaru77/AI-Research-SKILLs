---
name: gsplat-scene-adapter
version: 2.0.0
author: Orchestra Research
license: MIT
description: Wraps gsplat (Apache-2.0, v1.5.3) as the canonical PLY I/O, depth-render, and visibility-filter adapter layer that downstream cat-24 segmentation, multi-state differencing, and articulation skills consume; use instead of legacy GraphDECO forks whenever a digital-twin pipeline needs permissively licensed read/render/export of trained 3DGS scenes on PyTorch 2.4+ and CUDA 11.8/12.x.
tags: [3DGS, GS, PLY, I/O, Adapter, CUDA, Rasterization, Apache-2.0]
dependencies: [torch>=2.4.0, gsplat==1.5.3, numpy>=1.26, plyfile>=1.0.3, imageio>=2.34]
---

# gsplat scene adapter

Provides the canonical I/O, rendering, and point-extraction layer for the `24-3d-segmentation-articulation` skill category. This is **not** a training skill (cat 23 owns reconstruction). It loads trained 3DGS PLY files from nerfstudio splatfacto, GraphDECO, or gsplat itself; normalizes Gaussian parameters to a shared convention; renders depth maps and alpha from arbitrary cameras; and writes per-cluster or visibility-filtered PLY artifacts that downstream skills (SAGA, LUDVIG, ScrewSplat, Ditto) consume.

**Deep_thinker verified (2026-05-05):** gsplat has NOT been renamed, replaced, or superseded. Canonical repo remains `nerfstudio-project/gsplat`. The AMD ROCm port (`amd_gsplat`) is a separate platform fork. Latest release is v1.5.3 (2025-07-04). Apache-2.0 license confirmed.

The Apache-2.0 license is the primary reason this tool is the category spine. GraphDECO `diff-gaussian-rasterization` forks carry a non-commercial research-use restriction; gsplat is fully permissive and maintained with active PR activity into April 2026.

**Version pins for reproducible A100 production (late-2025 / May-2026):**

```
Python:    3.10
PyTorch:   2.4.0
CUDA:      12.4 preferred, 11.8 conservative fallback
gsplat:    1.5.3+pt24cu124  (or +pt24cu118)
plyfile:   >=1.0.3
imageio:   >=2.34
```

---

## Quick start

Load a trained splatfacto checkpoint with `ns-export`, then emit a canonical colored PLY and per-camera depth maps.

```bash
# 1. Export PLY from a trained nerfstudio splatfacto run
ns-export gaussian-splat \
  --load-config outputs/scene/splatfacto/2026-05-04_120000/config.yml \
  --output-dir exports/splat \
  --output-filename scene.ply \
  --ply-color-mode rgb

# 2. Install adapter dependencies (pre-built wheel, no ninja required)
pip install "gsplat==1.5.3+pt24cu124" \
    --index-url https://docs.gsplat.studio/whl/pt24cu124
pip install "plyfile>=1.0.3" "imageio>=2.34"
```

```python
#!/usr/bin/env python3
"""Minimal adapter: load splatfacto PLY -> canonical colored PLY + depth maps."""
from pathlib import Path
import numpy as np
import torch
import torch.nn.functional as F
import imageio.v3 as iio
from plyfile import PlyData, PlyElement
from gsplat.rendering import rasterization

SH_C0 = 0.28209479177387814

def load_gaussian_ply(path: Path) -> dict:
    """Load a Gaussian PLY. Returns raw (unconverted) arrays; caller activates."""
    ply = PlyData.read(str(path))
    v = ply["vertex"].data
    fields = set(v.dtype.names)
    means = np.stack([v["x"], v["y"], v["z"]], axis=-1).astype(np.float32)
    raw_scales = np.stack([v["scale_0"], v["scale_1"], v["scale_2"]], axis=-1).astype(np.float32)
    raw_quats = np.stack([v["rot_0"], v["rot_1"], v["rot_2"], v["rot_3"]], axis=-1).astype(np.float32)
    opacity_logits = np.asarray(v["opacity"], dtype=np.float32)
    if {"red", "green", "blue"}.issubset(fields):
        rgb = np.stack([v["red"], v["green"], v["blue"]], axis=-1).astype(np.float32) / 255.0
    elif {"f_dc_0", "f_dc_1", "f_dc_2"}.issubset(fields):
        fdc = np.stack([v["f_dc_0"], v["f_dc_1"], v["f_dc_2"]], axis=-1).astype(np.float32)
        rgb = np.clip(0.5 + SH_C0 * fdc, 0.0, 1.0)
    else:
        rgb = np.full_like(means, 0.7)
    return dict(means=means, raw_scales=raw_scales, raw_quats=raw_quats,
                opacity_logits=opacity_logits, rgb=rgb)


def render_scene(splat: dict, cameras: list, out_dir: Path, radius_clip=0.5) -> None:
    """Render RGB + expected-depth (ED) per camera. Saves .npy depth and .png images."""
    out_dir.mkdir(parents=True, exist_ok=True)
    dev = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    means   = torch.from_numpy(splat["means"]).to(dev)
    scales  = torch.exp(torch.from_numpy(splat["raw_scales"]).to(dev))
    quats   = F.normalize(torch.from_numpy(splat["raw_quats"]).to(dev), dim=-1)
    opacs   = torch.sigmoid(torch.from_numpy(splat["opacity_logits"]).to(dev))
    colors  = torch.from_numpy(splat["rgb"]).to(dev)
    for cam in cameras:
        H, W = int(cam["height"]), int(cam["width"])
        K  = torch.from_numpy(cam["K"]).to(dev)[None]    # [1,3,3]
        vm = torch.from_numpy(cam["w2c"]).to(dev)[None]  # [1,4,4]
        with torch.no_grad():
            renders, alphas, meta = rasterization(
                means, quats, scales, opacs, colors,
                vm, K, W, H,
                render_mode="RGB+ED",   # depth is last channel
                packed=True,
                radius_clip=radius_clip,
            )
        rgb_np   = renders[0, ..., :3].cpu().numpy()
        depth_np = renders[0, ...,  3].cpu().numpy()   # expected depth metres
        alpha_np = alphas[0, ...,  0].cpu().numpy()
        stem = Path(cam["name"]).stem
        np.save(out_dir / f"{stem}_depth_m.npy",
                np.where(alpha_np > 0.01, depth_np, np.nan).astype(np.float32))
        iio.imwrite(out_dir / f"{stem}_rgb.png",
                    np.clip(rgb_np * 255, 0, 255).astype(np.uint8))
        iio.imwrite(out_dir / f"{stem}_depth_mm.png",
                    np.clip(depth_np * 1000, 0, 65535).astype(np.uint16))
```

**Camera convention.** gsplat expects OpenCV world-to-camera viewmats. Nerfstudio `transform_matrix` is OpenGL camera-to-world; convert once:

```python
GL_TO_CV = np.diag([1., -1., -1., 1.]).astype(np.float32)
c2w_cv   = c2w_opengl @ GL_TO_CV
w2c      = np.linalg.inv(c2w_cv).astype(np.float32)
```

---

## Common workflows

### Workflow A — Canonical PLY I/O

Convert any producer's PLY (splatfacto, GraphDECO, gsplat `export_splats`) into the single layout all downstream cat-24 skills expect.

**Task Progress:**
- [ ] Inspect input PLY fields: `PlyData.read(path).elements[0].properties`
- [ ] Map variant field names (`features_dc_*` → `f_dc_*`, `features_rest_*` → `f_rest_*`)
- [ ] Verify opacity convention: values outside `[0,1]` are raw logits — do NOT sigmoid twice
- [ ] Verify quaternion order: gsplat, GraphDECO, and nerfstudio all use `(w,x,y,z)` as `rot_0..rot_3`
- [ ] Filter floaters: `opacity_logit < logit(0.05) ≈ -2.94` and `max(scale) > 5 × median(scale)`
- [ ] Write canonical PLY with `write_canonical_ply()` and record `metadata.json`
- [ ] Smoke-test: re-render one camera and compare against original training render

**Canonical activation rules** (wrong order causes silent bugs):

```python
scales    = torch.exp(raw_scales)           # log-scale → world-space scale
opacities = torch.sigmoid(opacity_logits)  # logit → [0,1], do NOT apply twice
quats     = F.normalize(raw_quats, dim=-1) # wxyz; normalize before rendering
```

---

### Workflow B — Depth diff render (multi-state differencing for lab equipment)

Use case: SEM column door open vs closed, autoclave lid ajar, centrifuge hatch removed.

**Task Progress:**
- [ ] Export both states to canonical PLY via Workflow A
- [ ] Load a shared camera list (fixed rig or COLMAP sparse/images.bin)
- [ ] Render `(rgb, alpha, depth)` for both states with `render_mode="RGB+ED"`
- [ ] Compute `delta = |depth_B - depth_A|`; mask pixels where either `alpha < 0.1`
- [ ] Backproject high-delta pixels (`> 2 × voxel_size`) to 3D candidate points
- [ ] Voxel-aggregate across cameras → `diff_candidates.npy`; hand to `multistate-diff-open3d`

```python
from gsplat.rendering import rasterization

def depth_diff(splat_a, splat_b, cam, device, radius_clip=0.5):
    def _render(sp):
        means  = torch.from_numpy(sp["means"]).to(device)
        scales = torch.exp(torch.from_numpy(sp["raw_scales"]).to(device))
        quats  = F.normalize(torch.from_numpy(sp["raw_quats"]).to(device), dim=-1)
        opacs  = torch.sigmoid(torch.from_numpy(sp["opacity_logits"]).to(device))
        colors = torch.from_numpy(sp["rgb"]).to(device)
        H, W   = int(cam["height"]), int(cam["width"])
        K  = torch.from_numpy(cam["K"]).to(device)[None]
        vm = torch.from_numpy(cam["w2c"]).to(device)[None]
        with torch.no_grad():
            r, a, _ = rasterization(means, quats, scales, opacs, colors,
                                     vm, K, W, H, render_mode="RGB+ED",
                                     packed=True, radius_clip=radius_clip)
        return r[0, ..., 3].cpu().numpy(), a[0, ..., 0].cpu().numpy()
    d_a, al_a = _render(splat_a)
    d_b, al_b = _render(splat_b)
    valid = (al_a > 0.1) & (al_b > 0.1) & np.isfinite(d_a) & np.isfinite(d_b)
    return np.where(valid, np.abs(d_b - d_a), np.nan), valid
```

Use `ED` (expected depth), not `D`. ED normalizes by accumulated opacity weight and is less sensitive to differences between two independently trained Gaussian reconstructions.

---

### Workflow C — Per-cluster export for articulation fitting

Given a boolean mask `[N]` from SAGA or LUDVIG, extract the masked Gaussian subset as an independent PLY for ScrewSplat or Ditto.

**Task Progress:**
- [ ] Load canonical PLY and per-Gaussian mask (`assert len(mask) == len(means)`)
- [ ] Note: LUDVIG prunes Gaussians; its `features.npy` may be shorter than the original PLY. Re-export from LUDVIG's own `gaussians.ply` and re-canonicalize
- [ ] Subset all arrays; filter floaters within the subset
- [ ] Write masked subset as `cluster_<id>.ply` in canonical format
- [ ] Render two QA thumbnail views with `rasterize_mode="antialiased"` for visual check

```python
from gsplat import export_splats

def export_cluster(splat: dict, mask: np.ndarray, out_path: Path) -> None:
    assert len(mask) == len(splat["means"]), "mask length mismatch"
    sub = {k: v[mask] for k, v in splat.items()}
    n   = int(mask.sum())
    sh0 = np.zeros((n, 1, 3), dtype=np.float32)
    shN = np.zeros((n, 0, 3), dtype=np.float32)
    export_splats(
        sub["means"], sub["raw_scales"], sub["raw_quats"],
        sub["opacity_logits"], sh0, shN,
        format="ply", save_to=str(out_path),
    )
```

---

## When to use vs alternatives

| Situation | Use |
|---|---|
| Apache-2.0 read/render/export for any 3DGS PLY on PyTorch 2.4+ | **this skill** |
| Training new Gaussian splat scenes | cat 23 (`train-gaussian-splats`) |
| Per-Gaussian semantic features (DINO/SAM/CLIP uplift) | `ludvig-feature-uplift` |
| Per-Gaussian segmentation masks | `per-gaussian-saga` |
| Articulation fitting from Gaussians | `screwsplat-articulation` (builds on gsplat HEAD) |
| Point cloud I/O only, no rendering needed | `open3d-pointcloud-io` |
| AMD ROCm / Instinct GPUs | `amd_gsplat` from AMD's PyPI (ROCm port, same API surface) |
| Non-commercial context requiring GraphDECO algorithm | keep behind its own Docker image; do not put on I/O critical path |

**Do not use** `graphdeco-inria/gaussian-splatting` or any `diff-gaussian-rasterization` fork as the category I/O layer. Those carry non-commercial research-use restrictions and require Python 3.7 / PyTorch 1.12 / CUDA 11.6 stacks that conflict with the rest of the category.

---

## Common issues

**Opacity double-sigmoid.** The most common interoperability bug. All standard 3DGS PLY variants store the raw logit. `gsplat.rasterization()` expects sigmoid opacity `[0,1]`. Apply `torch.sigmoid()` once at load time.

**Log-scale not exponentiated.** `rasterization()` expects world-space positive scales. Always call `torch.exp(raw_scales)` before rendering.

**Quaternion order mismatch.** gsplat expects `(w, x, y, z)` as `rot_0..rot_3`. GraphDECO and nerfstudio also use wxyz. Some minor forks use xyzw; detect by checking whether norms equal 1.0 before and after reorder.

**Nerfstudio camera convention.** `transform_matrix` in `transforms.json` is OpenGL camera-to-world (+Y up, -Z forward). gsplat viewmats are OpenCV world-to-camera (+Y down, +Z forward). Convert with `c2w_gl @ GL_TO_CV` then invert; skipping this silently flips depth maps.

**PLY field name drift.** Different exporters use `f_dc_*` vs `features_dc_*` vs `red green blue`. Always call `PlyData.read(path).elements[0].properties` first.

**CUDA OOM on large scenes (5M+ Gaussians).** Reported in public issues (OOM in `isect_tiles`, 9M-Gaussian / 20-camera failure). Mitigations: `packed=True`, `radius_clip >= 0.5`, `render_mode="ED"` for depth-only passes, small camera batch size (2–4 at a time), `torch.no_grad()`.

**Source build OOM (issue #500, Nov 2024).** Limit parallelism during Docker image builds: `export MAX_JOBS=2` before `pip install gsplat`.

**CUDA 13 not supported for v1.5.3 wheels.** Stick to CUDA 12.4 or 11.8 for released wheels.

**Docker: no CUDA device during build.** Set `TORCH_CUDA_ARCH_LIST="8.0+PTX"` explicitly when building without a visible GPU (issue #862, Jan 2026). A100 is compute capability 8.0.

**LUDVIG mask length mismatch.** LUDVIG prunes Gaussians during feature uplift. Re-export and re-canonicalize from LUDVIG's own `gaussians.ply`.

**Feature rendering not supported in v1.5.3 release.** Issue #529 (Jan 2025, closed) requested simultaneous color + N-D feature rendering. Workaround: render color and features in separate `rasterization()` calls and merge outputs.

---

## Advanced topics

**Visibility pre-culling without full rasterization.** `gsplat.fully_fused_projection()` returns projected Gaussian IDs, depths, and radii without compositing. Useful for articulation sampling and pre-filtering:

```python
from gsplat import fully_fused_projection

radii, means2d, depths, conics, compensations = fully_fused_projection(
    means=means, covars=None, quats=quats, scales=scales,
    viewmats=viewmat, Ks=K, width=W, height=H,
    packed=True,
    opacities=opacities,  # optional; tightens visible-radius bounds
    radius_clip=0.5,
)
# packed=True: meta includes gaussian_ids for visible Gaussian indices
```

**Lower-level tile pipeline.** For custom rendering passes: `isect_tiles()` maps projected Gaussians to intersecting tiles; `isect_offset_encode()` encodes sorted IDs into per-tile offsets; `rasterize_to_pixels()` composites pixels directly. Use these when `rasterization()` is too opaque for a specialized SEM-part rendering pipeline.

**All valid `render_mode` values.** `"RGB"`, `"D"`, `"ED"`, `"RGB+D"`, `"RGB+ED"`, `"d"`, `"Ed"`, `"RGB-d"`, `"RGB-Ed"`. Uppercase `D`/`ED` use projected z-depth; lowercase `d`/`Ed` use actual ray distances. For depth-diff pipelines use `"ED"` (z-depth, normalized by accumulated opacity).

**Batch rendering (v1.5.3+).** `rasterization()` accepts leading batch dimensions. Return shape is `[..., C, H, W, channels]`. Use ellipsis indexing, not hard-coded rank assumptions.

**Antialiased rendering.** Pass `rasterize_mode="antialiased"` for QA thumbnails. Do not use for depth-diff pipelines where depth values must be comparable between two renders.

**2DGS rasterizer.** `gsplat.rasterization_2dgs()` returns colors, alphas, normals, surface normals, distortion, and median depth. Useful for surface-quality QA on SEM specimen holders or flat mounting fixtures.

**F-Theta and fisheye camera models.** v1.5.3 adds F-Theta (`camera_model="ftheta"`, `ftheta_coeffs`) and fisheye support. Use for lab cameras with wide FOV optics.

**SH degree selection.** For adapter use (rendering only), degree 0 (DC term) is sufficient. Pass `colors` as `[N, 3]` RGB and set `sh_degree=None` in `rasterization()`.

**Nerfstudio OBB crop.** `ns-export` accepts `--obb-center`, `--obb-rotation`, `--obb-scale` to crop a single lab instrument from a larger scene before export. Reduces N for downstream skills:

```bash
ns-export gaussian-splat \
  --load-config outputs/lab/splatfacto/<run>/config.yml \
  --output-dir exports/centrifuge \
  --obb-center 0.15 -0.02 0.88 \
  --obb-rotation 0.0 0.0 15.0 \
  --obb-scale 0.35 0.35 0.40
```

**PPISP post-processing (main branch / Jan 2026).** Integrated as an alternative to bilateral-grid post-processing. Not in v1.5.3 release; relevant only when building from source for training workflows.

---

## Resources

- gsplat repository: https://github.com/nerfstudio-project/gsplat
- gsplat docs: https://docs.gsplat.studio
- Latest release v1.5.3 (2025-07-04): https://github.com/nerfstudio-project/gsplat/releases/tag/v1.5.3
- Pre-built CUDA wheels index: https://docs.gsplat.studio/whl/
- License (Apache-2.0): https://github.com/nerfstudio-project/gsplat/blob/main/LICENSE
- nerfstudio splatfacto: https://github.com/nerfstudio-project/nerfstudio
- nerfstudio data conventions: https://docs.nerf.studio/quickstart/data_conventions.html
- GraphDECO original 3DGS: https://github.com/graphdeco-inria/gaussian-splatting
- plyfile Python package: https://github.com/dranjan/python-plyfile
- ScrewSplat (builds on gsplat HEAD): https://github.com/lkstrikez/screwsplat
- SAGA per-Gaussian segmentation: https://github.com/Jumpat/SegAnyGAussians
- LUDVIG feature uplift: https://github.com/RenshengJi/LUDVIG
- gsplat issue tracker: https://github.com/nerfstudio-project/gsplat/issues
- Issue #529 (feature rendering, Jan 2025): https://github.com/nerfstudio-project/gsplat/issues/529
- Issue #862 (Docker/build, Jan 2026): https://github.com/nerfstudio-project/gsplat/issues/862
- See `references/issues.md` for per-issue summaries and workarounds
