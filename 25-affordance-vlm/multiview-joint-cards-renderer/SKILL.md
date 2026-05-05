---
name: multiview-joint-cards-renderer
description: Renders canonical multi-view "card" images of a 3D Gaussian Splatting scene (front/back/left/right/top/bottom + isometrics) using gsplat, then composites them into a single grid image for a VLM affordance/label/joint-detection pass. Use when a 3DGS scene of lab equipment (SEM chamber, optical bench, liquid handler) has been reconstructed and the next pipeline step needs reproducible visual evidence packets for a downstream VLM. Not for 3DGS training, mesh reconstruction, VR rendering, or physics simulation.
version: 2.0.0
author: Orchestra Research
license: MIT
tags: [3D Gaussian Splatting, Multi-View Rendering, Affordance, VLM, gsplat, Pillow, OpenCV, Joint Cards, SEM, Lab Equipment, Headless Rendering, Docker, A100]
dependencies: [gsplat==1.5.3, pillow==12.2.0, opencv-python-headless==4.13.0.92, numpy>=1.26, torch>=2.4]
---

# Multi-View Joint Cards Renderer

## Overview

This skill sits between 3DGS reconstruction and VLM affordance labeling. It:

1. Loads a trained 3DGS scene (Gaussian means, quats, scales, opacities, SH colors).
2. Places cameras at 9 canonical viewpoints in the object frame.
3. Calls `gsplat.rasterization()` once to batch-render all views.
4. Pads each 512×512 card, burns a view-name label, and assembles a 3×3 grid (1536×1536).
5. Writes `vlm_grid.png` + `manifest.json` for the downstream VLM prompter skill.

**Primary renderer:** gsplat 1.5.3 (Apache-2.0, ~5k stars, A100/CUDA-accelerated, batch rasterization API). Nerfstudio 1.1.5 splatfacto is a training/export companion; it uses gsplat as its backend.

**Primary VLM:** Qwen/Qwen3.6-27B (Apache-2.0, Apr 2026). Canonical Qwen unified vision model; inherits 28x spatial compression from the VL lineage. Lineage note: Qwen3-VL (Oct 2025, legacy/baseline) → Qwen3.5 → **Qwen3.6** (current). Requires `transformers>=4.57.1` or `vllm>=0.19.0`.

## Quick Start

```bash
pip install gsplat==1.5.3 pillow==12.2.0 opencv-python-headless==4.13.0.92 numpy torch
```

```python
import torch, numpy as np
from gsplat import rasterization
from PIL import Image, ImageDraw, ImageFont, ImageOps

# --- Load your Gaussians (example: random box scene) ---
N = 50_000
device = "cuda"
means   = torch.randn(N, 3, device=device) * 0.4
quats   = torch.zeros(N, 4, device=device); quats[:, 0] = 1.0
scales  = torch.full((N, 3), -4.0, device=device)   # log-scale
opacs   = torch.full((N,),    0.5,  device=device)
colors  = torch.rand(N, 3, device=device)

# --- 9 canonical viewmats (4×4 c2w inverse, i.e. world-to-camera) ---
def look_at(eye, at=np.zeros(3), up=np.array([0,1,0])):
    z = (eye - at); z /= np.linalg.norm(z)
    x = np.cross(up, z); x /= np.linalg.norm(x)
    y = np.cross(z, x)
    R = np.stack([x, y, z], axis=0)           # 3×3
    t = -R @ eye
    m = np.eye(4); m[:3,:3] = R; m[:3,3] = t
    return m.astype(np.float32)

d = 2.0
VIEWS = {
    "front":   look_at(np.array([ 0, 0, d])),
    "back":    look_at(np.array([ 0, 0,-d])),
    "left":    look_at(np.array([-d, 0, 0])),
    "right":   look_at(np.array([ d, 0, 0])),
    "top":     look_at(np.array([ 0, d, 0]), up=np.array([0,0,-1])),
    "bottom":  look_at(np.array([ 0,-d, 0]), up=np.array([0,0, 1])),
    "iso_fl":  look_at(np.array([-d, d, d])*0.7),
    "iso_br":  look_at(np.array([ d, d,-d])*0.7),
    "iso_top": look_at(np.array([ 0, d, d])*0.7),
}

W, H, fov = 512, 512, 60.0
fx = fy = W / (2 * np.tan(np.radians(fov/2)))
K = np.array([[fx,0,W/2],[0,fy,H/2],[0,0,1]], dtype=np.float32)

names = list(VIEWS.keys())
vmats = torch.tensor(np.stack([VIEWS[n] for n in names]), device=device)  # [V,4,4]
Ks    = torch.tensor(np.stack([K]*len(names)), device=device)             # [V,3,3]

# --- Single batched render call ---
renders, alphas, _meta = rasterization(
    means=means, quats=quats, scales=scales,
    opacities=opacs, colors=colors,
    viewmats=vmats, Ks=Ks, width=W, height=H,
    near_plane=0.01, far_plane=100.0,
)
# renders: [V, H, W, 3] float32 [0,1]

# --- Compose 3×3 grid ---
GRID = [["front","back","left"],["right","top","bottom"],["iso_fl","iso_br","iso_top"]]
rows = []
for row_names in GRID:
    cells = []
    for vname in row_names:
        idx = names.index(vname)
        img_np = (renders[idx].cpu().numpy() * 255).clip(0,255).astype(np.uint8)
        card = Image.fromarray(img_np, "RGB")
        card = ImageOps.pad(card, (W, H), color=(240, 240, 240))
        draw = ImageDraw.Draw(card)
        draw.text((8, 8), vname, fill=(0, 0, 0))
        cells.append(np.array(card))
    rows.append(np.hstack(cells))

grid = np.vstack(rows)
Image.fromarray(grid).save("vlm_grid.png")
print("Saved vlm_grid.png", grid.shape)
```

## Canonical Viewpoint Protocol

Layout for VLM grid — 3×3, 512 px per tile, 1536×1536 total:

```
front     | back      | left
right     | top       | bottom
iso_fl    | iso_br    | iso_top
```

- Tile size: 512×512 per card (compact baseline). Use 640×640 or 768×768 only when the VLM's token budget supports it and fine details (knob threads, hinge gaps, scale markings) must be preserved.
- Aspect ratio: always square per tile; pad with neutral gray `(240,240,240)`, do NOT crop.
- Format: PNG only. JPEG artifacts destroy hinge gaps and thin joint edges.
- Label: burn the view name inside the card (top-left corner, black text on white background strip). The VLM must reference view names in its output.
- Color scheme: active part saturated orange `(255, 89, 5)`, parent body gray `(140,140,140)`, other parts translucent.

**Research basis:** IG-VLM (2025) showed a single image grid outperforms sending frames individually on 9/10 zero-shot video-QA benchmarks. Multi-view 3D visual grounding work (ViewSRD, 2025 CVF) confirms structured multi-view decomposition preserves cross-view spatial correlations that single-view fails to capture.

## VLM Token Budget

| VLM | Recommended grid | Notes |
|-----|-----------------|-------|
| Qwen3.6-27B (`Qwen/Qwen3.6-27B`) | 1536×1536 (512/tile) | Current canonical Qwen unified vision model (Apr 2026, Apache-2.0). Inherits dynamic-resolution encoder and 28x spatial compression from the VL lineage. Pin `min_pixels=256*28*28, max_pixels=1280*28*28`. Requires `transformers>=4.57.1` / `vllm>=0.19.0`. Lineage: Qwen3-VL (Oct 2025) → Qwen3.5 → **Qwen3.6** (current). |
| Claude Sonnet/Opus | 1536×1536 or 768×768 | Tokens ≈ W×H/750; keep long-edge ≤ 1568 for non-Opus models. |
| GPT-4o | 1536×1536 w/ `detail=high` | `detail=low` uses a 512 px view; high uses 512-px tiles internally. |

Send the **single composite grid** (not 9 separate images) to minimize context overhead and preserve spatial relationships.

## Renderer Matrix

| Tool | Pin | License | Use |
|------|-----|---------|-----|
| gsplat | 1.5.3 | Apache-2.0 | Primary: batch-rasterize all canonical views in one call |
| nerfstudio / splatfacto | 1.1.5 | Apache-2.0 | Training / camera-path export; uses gsplat backend |
| Pillow | 12.2.0 | MIT-CMU | Card padding, label burn, alpha composite |
| opencv-python-headless | 4.13.0.92 | Apache-2.0 | hconcat/vconcat, imwrite, Canny for mask edges |
| ImageMagick | 7.1.2-21 | ImageMagick lic. | CLI debug montages only |
| Brush | 0.3.0 | Apache-2.0 | Interactive viewer/trainer; NOT recommended for deterministic headless card export (see issues.md) |

**Deprecation note:** gsplat v1.0 removed the old `project_gaussians()` + `rasterize_gaussians()` two-step API. Always use `gsplat.rasterization()` with `viewmats`, `Ks`, `width`, `height` arguments.

## Common Workflows

### Workflow 1: SEM Chamber with 5-Axis Motorized Stage

Task:

```
- [ ] Export Gaussian scene from your 3DGS checkpoint (.ckpt or .ply splat)
- [ ] Define object frame: chamber front plane = +Z forward, gravity = -Y, width = +X
- [ ] Freeze T_object_world in manifest.json BEFORE rendering
- [ ] Run batch rasterization for 9 canonical views
- [ ] Inspect top/iso cards: locate sample holder, X/Y/Z stage rails, tilt axis
- [ ] Inspect front/left cards: locate airlock door hinge axis, detector ports
- [ ] Burn view labels; assemble grid; save vlm_grid.png
- [ ] Send grid to VLM with affordance prompt (see VLM Prompt section)
- [ ] Validate VLM output has view-qualified bboxes/labels
```

SEM-specific guidance: stage is conventionally 5-axis (X, Y, Z, Rotate, Tilt). Make tilt axis visible in the front and left cards. Include the airlock/chamber door in at least the front card. Detector ports should appear in top or iso views. Do not infer scale from pixels; include a scale hint in the VLM prompt derived from `mesh_units`.

### Workflow 2: Optical Bench with Rail Carriers and Knobs

Task:

```
- [ ] Reconstruct optical bench 3DGS scene (breadboard + carriers + mounts + knobs)
- [ ] Set object frame: beam axis = +Z, table surface normal = +Y
- [ ] Render 9 canonical cards; verify rail direction is visible in top card
- [ ] Use iso_fl and iso_br to reveal carrier locking screws and knob stems
- [ ] Send VLM prompt asking for: rail direction, carrier slide affordance,
      fine-translation knob (turnable), mirror pitch/yaw adjuster, lock state
- [ ] Store manifest with part_ids matching downstream URDF generator
```

Fine-translation knobs and pitch/yaw adjusters are the most common joint-detection targets on optical benches. The top card exposes rail direction (prismatic joint axis); front/iso cards expose knob stems (revolute axis).

### Workflow 3: Robotic Liquid Handler (Gantry + Pipetting Head)

Task:

```
- [ ] Reconstruct deck + gantry + pipetting head 3DGS scene
- [ ] Set object frame: deck long axis = +X, short axis = +Z, up = +Y
- [ ] Render top card first: deck slots, tip racks, plate positions visible?
- [ ] Front + iso cards: gantry X/Y beam, Z-axis toolhead, pipette tip visible?
- [ ] VLM prompt: deck slot affordances, gantry prismatic axes, Z toolhead travel
- [ ] Record stage coordinate frame in manifest for URDF export
```

Liquid handlers have an H-gantry over the deck with dual Z-axis toolheads. Top view is the primary evidence for X/Y motion; front view is primary for Z-axis.

## Manifest Contract

```json
{
  "skill": "multiview-joint-cards-renderer",
  "schema_version": "2.0",
  "scene_id": "sem_chamber_017",
  "units": "meters",
  "object_frame": {
    "handedness": "right",
    "x": "object right",
    "y": "object up",
    "z": "object forward"
  },
  "renderer": "gsplat==1.5.3",
  "grid_file": "vlm_grid.png",
  "grid_layout": [
    ["front","back","left"],
    ["right","top","bottom"],
    ["iso_fl","iso_br","iso_top"]
  ],
  "tile_px": 512,
  "grid_px": 1536,
  "camera_fov_deg": 60.0,
  "camera_distance_m": 2.0,
  "vlm_question": {
    "target_fields": ["joint_type","axis","anchor","range","affordance"],
    "valid_joint_types": ["fixed","revolute","prismatic","helical","ball","unknown"],
    "require_view_qualified_output": true
  }
}
```

Validation:

```python
def validate_manifest(m):
    assert m["schema_version"] == "2.0"
    assert m["units"] in {"meters", "millimeters"}
    assert "object_frame" in m
    assert m["renderer"].startswith("gsplat")
    layout = m["grid_layout"]
    assert len(layout) == 3 and all(len(r) == 3 for r in layout)
```

## VLM Prompt Template

```
You are given a 3×3 grid of multi-view renders of a lab equipment part.
Grid layout (row, col):
  Row 0: front | back | left
  Row 1: right | top  | bottom
  Row 2: iso_front-left | iso_back-right | iso_top-front

Active part: saturated orange. Parent body: gray. All axes are in the object frame.

For each visible movable part, predict:
1. joint_type: fixed | revolute | prismatic | helical | ball | unknown
2. axis_object: unit vector [x,y,z] in object frame, or null
3. anchor_object: point [x,y,z] in object frame, or null
4. range: angle_deg or translation_mm with uncertainty estimate
5. affordance: human-readable label (e.g. "tilt axis", "knob rotate", "slide rail")
6. evidence_views: list the grid positions (e.g. "row1_col2=top") supporting this
7. failure_modes: remaining visual ambiguities

Report one JSON object per detected joint. Use view-qualified references (e.g. "top card") for all evidence.
```

## Common Issues

| Issue | Symptom | Fix |
|-------|---------|-----|
| gsplat CUDA mismatch | ImportError / rasterization kernel crash | Match torch/CUDA exactly; gsplat precompiled wheels cover specific Torch/CUDA combos only; source-build for new stacks |
| gsplat v0 API used | AttributeError: project_gaussians | Migrate to `rasterization()` — v1 removed old two-step API |
| EGL not available | RuntimeError / EGL_BAD_MATCH in Docker | Set `NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics`; `--gpus all`; confirm libEGL is installed |
| Brush headless render | No deterministic file export | Use gsplat directly; Brush CLI lacks camera-card-to-file API (see ArthurBrussee/brush #189) |
| Object not centered | Cards show black frames or partial object | Normalize Gaussian means to unit sphere before rendering; set camera distance accordingly |
| View labels missing | VLM cannot reference card positions | Always burn view name into card before compositing |
| Scale inconsistent across tiles | VLM confuses object size | Fix camera distance and FOV across all 9 views; record in manifest |
| PNG too large for VLM | OOM or truncated image | Use 512/tile (1536 grid) as baseline; only upscale if VLM supports it |
| Older Qwen VL name used | Outdated HF model IDs in code | Use `Qwen/Qwen3.6-27B` (Apr 2026 canonical). Qwen3-VL (Oct 2025) and Qwen3.5 are legacy/baseline predecessors. |

Geometry pitfalls:

- Inconsistent object frame across views makes axis labels meaningless. Freeze `T_object_world` before rendering; write to manifest.
- JPEG compression destroys thin joint gaps. Use PNG.
- Sending 9 separate images instead of one grid loses cross-view spatial context that VLMs can leverage from a single composite.
- Object frame vs world frame confusion: axis labels must say object X/Y/Z; record camera pose separately in manifest.

## Docker Environment

```dockerfile
FROM nvidia/cuda:12.4.1-devel-ubuntu22.04
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics
ENV EGL_PLATFORM=surfaceless

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip libegl1 libgl1 libglvnd0 \
    libxrender1 libxext6 libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Pin torch BEFORE gsplat — gsplat wheels require exact torch/cuda combo
RUN pip install --no-cache-dir \
    torch==2.4.0+cu124 torchvision --index-url https://download.pytorch.org/whl/cu124

RUN pip install --no-cache-dir \
    gsplat==1.5.3 \
    pillow==12.2.0 \
    opencv-python-headless==4.13.0.92 \
    numpy
```

```bash
docker run --rm --gpus all \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics \
  -e EGL_PLATFORM=surfaceless \
  -v "$PWD":/workspace -w /workspace \
  multiview-cards:latest \
  python3 render_cards.py --scene scene.ckpt --output vlm_grid.png
```

## ImageMagick CLI (Debug / CI)

```bash
# Debug montage from existing card PNGs
magick montage front.png back.png left.png right.png top.png bottom.png \
    iso_fl.png iso_br.png iso_top.png \
    -tile 3x3 -geometry 512x512+8+8 -background gray90 \
    vlm_grid_debug.png
```

Use `magick` (ImageMagick 7), not legacy `convert`. Pin: 7.1.2-21.

## When to Use vs Alternatives

**Use this skill** when a 3DGS scene exists and the VLM needs standardized visual evidence for affordance/joint/label prediction.

**Use direct geometry algorithms** when CAD already encodes hinge pins, prismatic rails, or screw threads (skip rendering entirely).

**Use Blender/Cycles** when photoreal material cues (glass shields, metal collars, rubber gaskets) are diagnostically critical and you can afford longer render time.

**Use point-cloud screenshots** (Open3D) only when meshes are incomplete or you need to validate segmentation boundaries before 3DGS reconstruction.

**Do not use** for VR rendering, URDF export, physics simulation, or 3DGS training — those are separate skills in the pipeline.

## Resources

- gsplat: https://github.com/nerfstudio-project/gsplat (Apache-2.0; v1.5.3 released 2025-07-04)
- gsplat v1 API docs: https://docs.gsplat.studio/
- nerfstudio / splatfacto: https://github.com/nerfstudio-project/nerfstudio (Apache-2.0; v1.1.5 released 2024-11-11)
- ns-render docs: https://docs.nerf.studio/reference/cli/ns_render.html
- Pillow 12.2.0: https://github.com/python-pillow/Pillow (MIT-CMU; released 2026-04-01)
- opencv-python-headless 4.13.0.92: https://pypi.org/project/opencv-python-headless/ (Apache-2.0; uploaded 2026-02-05)
- ImageMagick 7.1.2-21: https://imagemagick.org (ImageMagick license; released 2026-04-21)
- IG-VLM (image-grid VLM): https://arxiv.org/abs/2406.04334 — grid composite outperforms frame-by-frame on 9/10 video-QA benchmarks
- Qwen3.6-27B (canonical Apr 2026): https://huggingface.co/Qwen/Qwen3.6-27B — unified vision model, 28x spatial compression, dynamic resolution; lineage: Qwen2.5-VL → Qwen3-VL (Oct 2025) → Qwen3.5 → Qwen3.6
- Real GitHub issues: See [references/issues.md](references/issues.md)
- PartNet-Mobility (14K kinematic parts, 46 categories): https://sapien.ucsd.edu/
