# Renderer Issues — multiview-joint-cards-renderer v2.0.0

Tracks real GitHub issues, verified workarounds, and pitfall tables for the gsplat-based multi-view card pipeline. Updated 2026-05-05.

## Real GitHub Issues (verified)

### gsplat: rasterization_2dgs assert on sh_degree=None
**Project:** nerfstudio-project/gsplat  
**Issue:** #765 (opened 2025-07-17)  
**Symptom:** `rasterization_2dgs()` asserts when `sh_degree=None` is passed; affects 2DGS variant, not 3DGS.  
**Workaround:** Add a SH dimension to `colors` and pass `sh_degree=0` explicitly.  
**Relevance:** If you attempt 2DGS-based normal/depth cards in a batched render loop, this assert fires. Use 3DGS `rasterization()` for production card generation; reserve 2DGS for depth accuracy experiments.

```python
# Broken (sh_degree=None with 2DGS)
renders, alphas, meta = rasterization_2dgs(means, quats, scales, opacities,
    colors=colors, viewmats=vmats, Ks=Ks, width=W, height=H)

# Fixed: add SH dim and set sh_degree=0
colors_sh = colors.unsqueeze(1)  # [N,1,3]
renders, alphas, meta = rasterization_2dgs(means, quats, scales, opacities,
    colors=colors_sh, viewmats=vmats, Ks=Ks, width=W, height=H, sh_degree=0)
```

### Brush: no CLI/HTTP camera-card-to-file export
**Project:** ArthurBrussee/brush  
**Issue:** #189 (opened 2025-06-05)  
**Symptom:** User requests a CLI/TCP/HTTP way to set camera attitude/position and render to file programmatically; feature request, not yet shipped in v0.3.0.  
**Relevance:** Brush trains and views well but is not a drop-in for deterministic headless card export. Use gsplat directly for this pipeline; do not assume Brush supports `--render-camera-cards` style CLI.

### Nerfstudio: ns-render output diverges from viewer
**Project:** nerfstudio-project/nerfstudio  
**Issue:** #3568  
**Symptom:** Custom outputs visible in the interactive viewer are not available to `ns-render dataset`; headless render outputs can diverge from what the viewer shows.  
**Relevance:** When using nerfstudio/splatfacto for camera-path export, validate that the output type you need (e.g., `rgb`, `depth`, `accumulation`) is exposed to `ns-render` and not viewer-only.

## gsplat v1.x API Notes

### Deprecated: project_gaussians + rasterize_gaussians
gsplat v1.0 (released 2024) removed the old two-step API:

```python
# DEPRECATED — do not use
from gsplat import project_gaussians, rasterize_gaussians
xys, depths, radii, conics, num_tiles_hit, cov3d = project_gaussians(...)
out_img, out_alpha = rasterize_gaussians(...)
```

### Current: rasterization()
```python
from gsplat import rasterization

renders, alphas, meta = rasterization(
    means=means,       # [N,3] float32 CUDA
    quats=quats,       # [N,4] float32 CUDA (wxyz)
    scales=scales,     # [N,3] float32 CUDA (log-scale)
    opacities=opacs,   # [N]   float32 CUDA (pre-sigmoid or raw)
    colors=colors,     # [N,3] or [N,K,3] SH colors
    viewmats=vmats,    # [V,4,4] world-to-camera transforms
    Ks=Ks,            # [V,3,3] intrinsics
    width=W, height=H,
    near_plane=0.01, far_plane=100.0,
)
# renders: [V,H,W,3] float32, alphas: [V,H,W,1] float32
```

Batch over V views in one call — no loop needed. All canonical 9 views can be rendered simultaneously on A100.

## CUDA / Docker Setup

### Verified working (A100, 2026-05)
- CUDA 12.4 + PyTorch 2.4.0 + gsplat 1.5.3
- gsplat precompiled wheels are per Python/Torch/CUDA combo — mismatch causes import errors or silent wrong output
- Always install torch before gsplat; check compatibility matrix at https://docs.gsplat.studio/

```bash
# Install order matters
pip install torch==2.4.0+cu124 --index-url https://download.pytorch.org/whl/cu124
pip install gsplat==1.5.3
python -c "from gsplat import rasterization; print('ok')"
```

### EGL in Docker
```bash
docker run --rm --gpus all \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics \
  -e EGL_PLATFORM=surfaceless \
  myimage python3 render_cards.py
```

Missing `graphics` in `NVIDIA_DRIVER_CAPABILITIES` causes EGL_BAD_MATCH even if CUDA works. Both must be present.

## VLM Image Budget Reference

| VLM | Grid size | Tokens approx | Notes |
|-----|-----------|---------------|-------|
| Qwen2.5-VL | 1536×1536 | ~3072 visual tokens | 28x spatial compression; dynamic resolution; pin min_pixels=256*28*28, max_pixels=1280*28*28. Qwen3-VL not verified as of 2026-05. |
| Claude Sonnet/Haiku | 1536×1536 | ~3145 | tokens ≈ W×H/750; long-edge ≤ 1568 for non-Opus |
| Claude Opus 4.7 | up to 2576×2576 | ~8849 | supports higher resolution |
| GPT-4o detail=high | 1536×1536 | 1105 tiles | internally slices to 512-px tiles |
| GPT-4o detail=low | any | 85 | loses fine detail; not recommended for joint detection |

Send one composite grid image, not 9 separate images. IG-VLM research (arXiv:2406.04334) shows grid composite outperforms frame-by-frame on 9/10 zero-shot video-QA benchmarks.

## Pitfall Table

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| gsplat v0 API | AttributeError: `project_gaussians` | Use `rasterization()` — v1 removed old API |
| gsplat wheel mismatch | ImportError or wrong CUDA device | Match torch/CUDA exactly; install torch first |
| Object not centered | Black borders or partial object in cards | Normalize means to unit sphere; set camera distance accordingly |
| Inconsistent object frame | Axis labels meaningless | Freeze `T_object_world` in manifest before rendering |
| JPEG format used | Thin joint edges destroyed | PNG only for all card output |
| 9 separate images to VLM | Lost cross-view spatial context | Composite into single grid first |
| View names not burned in | VLM cannot reference card positions | Draw view label inside each tile before compositing |
| Qwen3-VL processor used | AttributeError or processor not found | Use Qwen2.5-VL; Qwen3-VL not a verified public release as of 2026-05 |
| Brush used for headless cards | No deterministic camera-card output | Use gsplat; Brush #189 is still open feature request |
| sh_degree=None with 2DGS | Assert in rasterization_2dgs | Set sh_degree=0; see gsplat #765 |

## Validation Smoke Test

```python
from PIL import Image
from pathlib import Path
import json

def validate_output(out_dir: str):
    root = Path(out_dir)
    # Check grid exists
    grid = root / "vlm_grid.png"
    assert grid.exists(), "vlm_grid.png missing"
    im = Image.open(grid)
    assert im.format == "PNG", "grid must be PNG"
    assert im.size == (1536, 1536), f"expected 1536x1536, got {im.size}"

    # Check manifest
    mf_path = root / "manifest.json"
    assert mf_path.exists(), "manifest.json missing"
    mf = json.loads(mf_path.read_text())
    assert mf["schema_version"] == "2.0"
    assert mf["units"] in {"meters", "millimeters"}
    assert mf["renderer"].startswith("gsplat")
    assert "object_frame" in mf
    layout = mf["grid_layout"]
    assert len(layout) == 3 and all(len(r) == 3 for r in layout)
    print("validation ok:", out_dir)
```
