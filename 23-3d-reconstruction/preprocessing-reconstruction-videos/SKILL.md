---
name: preprocessing-reconstruction-videos
description: Preprocesses raw lab-equipment videos into curated keyframes, foreground masks, and camera-ready image sets for SfM/3DGS pipelines. Use before COLMAP, 3D Gaussian Splatting, or NeRF when input is handheld phone or DSLR video of specular scientific instruments (SEM, optical bench, microscopes). Covers FFmpeg frame extraction, Laplacian blur culling, BiRefNet/rembg/SAM2 background removal, SSIM-based near-duplicate rejection, exposure normalization, lens distortion handling via COLMAP SIMPLE_RADIAL/OPENCV models, and pycolmap API. Targets Linux Docker A100 with CUDA 13 / PyTorch 2.10.
version: 2.0.0
author: Orchestra Research
license: MIT
tags: [Video Preprocessing, FFmpeg, OpenCV, SAM2, BiRefNet, COLMAP, Keyframe Extraction, 3D Reconstruction, 3DGS, NeRF]
dependencies: ["ffmpeg>=8.1.1", "opencv-python-headless==4.13.0.92", "rembg[gpu,cli]==2.0.75", "pycolmap==4.0.4", "torch==2.10.0", "torchvision==0.25.0", "transformers==4.57.3", "timm==1.0.26", "pillow>=11.0.0", "numpy>=2.0.0"]
---

# Preprocessing Reconstruction Videos

Converts raw lab-equipment capture video into a COLMAP/3DGS-ready image set: deduplicated sharp keyframes, foreground masks, and undistorted images. Designed for specular metal subjects (SEM housings, optical benches, microscope bodies) on Linux Docker A100 (CUDA 13, PyTorch 2.10).

**Key deprecation (2026-03-09):** Standalone GLOMAP is archived; use COLMAP 4.x `global_mapper` instead.

## Quick start

Extract ~3 fps, scale to 1920px wide, JPEG quality 2 (lossless baseline):

```bash
export VIDEO=raw_lab.mp4 OUT=frames
mkdir -p "$OUT"
ffmpeg -hide_banner -y -i "$VIDEO" -map 0:v:0 \
  -vf "fps=3,scale=1920:-2:flags=lanczos,format=rgb24" \
  -vsync 0 -q:v 2 "$OUT/%06d.jpg"
```

Smoke-test blur scores on the first 20 frames:

```python
import cv2, pathlib
paths = sorted(pathlib.Path("frames").glob("*.jpg"))[:20]
for p in paths:
    gray = cv2.cvtColor(cv2.imread(str(p)), cv2.COLOR_BGR2GRAY)
    print(p.name, round(cv2.Laplacian(gray, cv2.CV_64F).var(), 1))
```

Drop frames with score below the 30th-percentile across the batch; static lab scenes have highly variable natural sharpness so avoid fixed global thresholds.

## Common workflows

### Workflow A — Turntable SEM / microscope body

Rotating instrument, static room. Masking is critical because the static background violates SfM static-scene assumptions.

Task Progress:
- [ ] Step 1: Extract frames at 2 fps (SEM rotates slowly)
- [ ] Step 2: Blur-cull + SSIM near-duplicate rejection → ~200 keepers
- [ ] Step 3: BiRefNet foreground masks → COLMAP mask convention
- [ ] Step 4: COLMAP sequential reconstruction → undistorted output

```bash
export CAP=sem_turntable
mkdir -p $CAP/{frames,selected,masks,sparse,undistorted}

# Step 1
ffmpeg -hide_banner -y -i raw/sem.mp4 -map 0:v:0 \
  -vf "fps=2,scale=1920:-2:flags=lanczos,format=rgb24" \
  -vsync 0 -q:v 2 $CAP/frames/%06d.jpg

# Step 2 — keyframe selection (see script below)
python tools/select_keyframes.py \
  --images $CAP/frames --out $CAP/selected \
  --drop-blur-bottom-pct 30 --max-ssim 0.985 --target 240

# Step 3 — BiRefNet masks; output must match COLMAP convention: images/x.jpg → masks/x.jpg.png
python tools/birefnet_masks.py \
  --images $CAP/selected --out $CAP/masks \
  --hf-model zhengpeng7/BiRefNet --hf-revision e2bf8e4 --threshold 0.50

# Step 4 — COLMAP SfM
colmap feature_extractor \
  --database_path $CAP/database.db --image_path $CAP/selected \
  --ImageReader.single_camera 1 --ImageReader.camera_model SIMPLE_RADIAL \
  --ImageReader.mask_path $CAP/masks --SiftExtraction.use_gpu 1

colmap sequential_matcher \
  --database_path $CAP/database.db \
  --SequentialMatching.overlap 15 --SiftMatching.use_gpu 1

colmap mapper \
  --database_path $CAP/database.db \
  --image_path $CAP/selected --output_path $CAP/sparse

colmap image_undistorter \
  --image_path $CAP/selected --input_path $CAP/sparse/0 \
  --output_path $CAP/undistorted --output_type COLMAP
```

COLMAP masks: black pixels suppress feature extraction; mask file must be at `mask_path/<same-subpath>.jpg.png`.

### Workflow B — Handheld optical bench walkaround

Cluttered table, camera moving through scene, wider baseline needed.

Task Progress:
- [ ] Step 1: Extract 3 fps with mild normalize pass
- [ ] Step 2: Blur-cull + drop duplicates; require ≥1500 features per frame
- [ ] Step 3: SAM2 video masks via box/click prompt (when BiRefNet gives poor edge on cluttered scenes)
- [ ] Step 4: COLMAP with RADIAL model + COLMAP global_mapper (replaces standalone GLOMAP)

```bash
export CAP=optical_bench
mkdir -p $CAP/{frames,selected,masks,sparse_global,undistorted}

ffmpeg -hide_banner -y -i raw/bench.mov -map 0:v:0 \
  -vf "fps=3,scale=2400:-2:flags=lanczos,normalize=strength=0.25:independence=0" \
  -vsync 0 -q:v 2 $CAP/frames/%06d.jpg

python tools/select_keyframes.py \
  --images $CAP/frames --out $CAP/selected \
  --drop-blur-bottom-pct 20 --max-ssim 0.990 --min-features 1500

python tools/sam2_video_masks.py \
  --frames $CAP/selected \
  --prompts prompts/optical_bench_fg.yaml \
  --out $CAP/masks

colmap feature_extractor \
  --database_path $CAP/database.db --image_path $CAP/selected \
  --ImageReader.single_camera 1 --ImageReader.camera_model RADIAL \
  --ImageReader.mask_path $CAP/masks \
  --SiftExtraction.max_num_features 12000 --SiftExtraction.use_gpu 1

colmap sequential_matcher \
  --database_path $CAP/database.db \
  --SequentialMatching.overlap 20 --SiftMatching.guided_matching 1 --SiftMatching.use_gpu 1

# GLOMAP is now COLMAP-integrated (standalone repo archived 2026-03-09):
colmap global_mapper \
  --database_path $CAP/database.db \
  --image_path $CAP/selected --output_path $CAP/sparse_global
```

### Workflow C — DSLR macro detail pass (known calibration)

High-detail panel/chamber coverage where you have an OpenCV calibration board result.

Task Progress:
- [ ] Step 1: 1.5 fps extraction at native DSLR resolution
- [ ] Step 2: Tight blur cull (25th pct), SSIM 0.975, rembg or no mask if background is clean
- [ ] Step 3: COLMAP OPENCV model with known params; exhaustive matching

```bash
export CAP=dslr_macro_sem
mkdir -p $CAP/{frames,selected,sparse,undistorted}

ffmpeg -hide_banner -y -i raw/dslr_macro.MOV -map 0:v:0 \
  -vf "fps=1.5,scale=3000:-2:flags=lanczos,format=rgb24" \
  -vsync 0 -q:v 2 $CAP/frames/%06d.jpg

python tools/select_keyframes.py \
  --images $CAP/frames --out $CAP/selected \
  --drop-blur-bottom-pct 25 --max-ssim 0.975

# fx,fy,cx,cy,k1,k2,p1,p2 from your calibration board session:
export CAM="2860.4,2857.9,1500.0,1000.0,-0.042,0.016,0.0002,-0.0001"

colmap feature_extractor \
  --database_path $CAP/database.db --image_path $CAP/selected \
  --ImageReader.single_camera 1 \
  --ImageReader.camera_model OPENCV \
  --ImageReader.camera_params "$CAM" \
  --SiftExtraction.max_num_features 16000 --SiftExtraction.use_gpu 1

colmap exhaustive_matcher \
  --database_path $CAP/database.db \
  --SiftMatching.guided_matching 1 --SiftMatching.use_gpu 1

colmap mapper \
  --database_path $CAP/database.db \
  --image_path $CAP/selected --output_path $CAP/sparse

colmap image_undistorter \
  --image_path $CAP/selected --input_path $CAP/sparse/0 \
  --output_path $CAP/undistorted --output_type COLMAP
```

Only supply `camera_params` if derived from a same-lens calibration session; mismatched intrinsics degrade SfM.

## Core keyframe selection logic

```python
import cv2, math, pathlib, shutil, json
from skimage.metrics import structural_similarity as ssim

def laplacian_var(gray):
    return float(cv2.Laplacian(gray, cv2.CV_64F).var())

def feature_count(gray, n=2500):
    orb = cv2.ORB_create(nfeatures=n)
    kp, _ = orb.detectAndCompute(gray, None)
    return len(kp)

def ssim_overlap(gray_a, gray_b):
    s, _ = ssim(gray_a, gray_b, full=True, data_range=255)
    return s

# Usage pattern:
# 1. Score all frames for blur using laplacian_var
# 2. Drop bottom N-th percentile by score
# 3. Walk survivors in order; drop if ssim_overlap(prev_kept, current) > threshold
# 4. Optionally gate on feature_count(gray) >= min_features
```

## BiRefNet foreground masking

```python
import torch
import numpy as np
from PIL import Image
from transformers import AutoModelForImageSegmentation
from torchvision.transforms.functional import normalize

model = AutoModelForImageSegmentation.from_pretrained(
    "zhengpeng7/BiRefNet",
    revision="e2bf8e4",          # Feb 2026 transformers-compat fixes
    trust_remote_code=True,
).to("cuda").eval()

def birefnet_mask(img_path: str, threshold: float = 0.50) -> np.ndarray:
    img = Image.open(img_path).convert("RGB")
    t = torch.tensor(np.array(img)/255., dtype=torch.float32).permute(2,0,1).unsqueeze(0)
    t = normalize(t, [0.485,0.456,0.406], [0.229,0.224,0.225]).to("cuda")
    with torch.no_grad():
        pred = model(t)[-1].sigmoid().cpu().squeeze().numpy()
    return (pred >= threshold).astype(np.uint8) * 255
```

Pin `transformers==4.57.3` — BiRefNet issue #285 documents Transformers 5.x breakage.

## SAM2 video masks (prompt-based)

```python
from sam2.build_sam import build_sam2_video_predictor

predictor = build_sam2_video_predictor(model_cfg, checkpoint)
state = predictor.init_state(video_path=frame_dir)

_, obj_ids, masks = predictor.add_new_points_or_box(
    inference_state=state, frame_idx=0, obj_id=1,
    points=np.array([[cx, cy]]), labels=np.array([1]),
)

for frame_idx, obj_ids, masks in predictor.propagate_in_video(state):
    # write masks[0] to disk; chunk every 200 frames + reset_state
    pass
```

SAM2 has no release tags — pin a full commit SHA in your Dockerfile. Process in 200-frame chunks with `reset_state` + `torch.cuda.empty_cache()` to avoid unbounded VRAM growth.

## rembg quick CLI alternative

```bash
# Simple batch, good for clean turntable background
rembg p selected/ masks_rembg/
```

rembg 2.0.75 (April 2026, MIT). On CUDA 13 hosts, ONNX Runtime GPU provider may fall back silently; verify with `--model u2net` and check provider log.

## When to use vs alternatives

| Need | Choice | Why |
|---|---|---|
| Heavily textured specular lab gear, turntable | BiRefNet | Best foreground matte for metal surfaces |
| Cluttered scene, interactive prompt | SAM2 video predictor | Box/click prompt, temporal propagation |
| Quick batch on clean background | rembg CLI | Zero-config, MIT, one command |
| Known lens calibration | COLMAP OPENCV model | Locks intrinsics, avoids per-scene degenerate estimates |
| Unknown phone/DSLR intrinsics | COLMAP SIMPLE_RADIAL → RADIAL | Estimate from EXIF + data |
| Winding walkthrough, global consistency | `colmap global_mapper` | Replaces archived standalone GLOMAP |
| Dense temporal video | Sequential matching, overlap 15-20 | Faster than exhaustive, sufficient for video |

Skip this skill if upstream capture already produces deduplicated PNGs plus a COLMAP database.

## Common issues

1. **pycolmap-cuda12 conflicts with PyTorch wheels** ([colmap/colmap #3796](https://github.com/colmap/colmap/issues/3796), opened 2025-12-04) — Dependency solvers conflict between pycolmap-cuda12 and torch CUDA wheels. Use `pycolmap==4.0.4` (CPU) for Python API; run GPU reconstruction via system COLMAP CLI binary compiled with `-DCMAKE_CUDA_ARCHITECTURES=80`.

2. **rembg[gpu] fails on CUDA 13** ([danielgatis/rembg #819](https://github.com/danielgatis/rembg/issues/819), opened 2026-02-20) — ONNX Runtime GPU expects CUDA 12 runtime libs. Either use `rembg` in a CUDA-12 sidecar container or switch to BiRefNet/SAM2 for masking on CUDA 13 hosts.

3. **BiRefNet breaks with Transformers 5.x** ([ZhengPeng7/BiRefNet #285](https://github.com/ZhengPeng7/BiRefNet/issues/285), opened 2026-02-03) — Pin `transformers==4.57.3` and use HF revision `e2bf8e4` which contains February 2026 compatibility fixes.

4. **COLMAP GPU bundle adjustment absent in binary releases** ([colmap/colmap #3894](https://github.com/colmap/colmap/issues/3894), opened 2025-12-29) — Pre-built binaries may omit GPU BA. Verify with `colmap -h | grep cuda`. For A100 production, build COLMAP 4.0.4 from source with `-DCMAKE_CUDA_ARCHITECTURES=80`.

5. **Specular highlights become false geometry** — Use diffuse/cross-polarized lighting; matte removable tape on non-critical surfaces; mask saturated highlights before SfM. Do not rely on specular highlights for feature matching.

6. **SAM2 VRAM growth on long video** — Process in ≤200-frame chunks; call `predictor.reset_state(state)`, `del state`, `torch.cuda.empty_cache()` between chunks. Use `offload_video_to_cpu=True`, `offload_state_to_cpu=True`.

7. **`fps=3` over-samples slow turntable** — If reconstruction is redundant (SSIM > 0.985 on most frame pairs), lower to 1-2 fps and raise the SSIM cull threshold to 0.990.

## Advanced topics

**Exposure normalization:** Use FFmpeg `normalize=strength=0.25:independence=0` to link RGB channels (prevents hue shift). Normalize only working copies; SfM/3DGS training may prefer original exposure if photometric consistency is key.

**Lens distortion — COLMAP model guide:**
- `SIMPLE_RADIAL` — 1 radial param; start here for any unknown camera
- `RADIAL` — 2 radial params; better for wide-angle
- `OPENCV` — full {fx,fy,cx,cy,k1,k2,p1,p2}; only when you have a real calibration
- `FISHEYE` — ultra-wide / action cams

**Scale anchors without AprilTags:** Place a known object (ruler, calibration sphere, precision block) in the scene. After SfM, measure reconstructed 3D distance between identifiable points and compute the metric scale factor for the sparse model and downstream 3DGS/physics colliders.

**pycolmap Python API:**

```python
import pycolmap
pycolmap.extract_features(database_path, image_dir)
pycolmap.match_exhaustive(database_path)
maps = pycolmap.incremental_mapping(database_path, image_dir, sparse_dir)
```

**Run manifest (record every run):**

```json
{
  "video": "raw_lab.mp4",
  "ffmpeg_version": "8.1.1",
  "opencv_python": "4.13.0.92",
  "torch": "2.10.0+cu130",
  "cuda": "13.2.1",
  "pycolmap": "4.0.4",
  "rembg": "2.0.75",
  "birefnet_hf_revision": "e2bf8e4",
  "sam2_commit": "FULL_SHA_HERE",
  "mask_tool": "birefnet",
  "colmap_build": "4.0.4-src-a100"
}
```

**Reference files:** See `references/issues.md` for extended issue context and workarounds.

## Docker version pins (A100, CUDA 13)

```dockerfile
FROM nvidia/cuda:13.2.1-devel-ubuntu24.04

# Python 3.12.13 (March 2026 security release)
RUN pip install \
    torch==2.10.0 torchvision==0.25.0 \
    --index-url https://download.pytorch.org/whl/cu130

RUN pip install \
    opencv-python-headless==4.13.0.92 \
    rembg[gpu,cli]==2.0.75 \
    transformers==4.57.3 \
    timm==1.0.26 \
    pycolmap==4.0.4

# FFmpeg 8.1.1 (released 2026-05-04) — build from source for LGPL-clean:
# ./configure --prefix=/opt/ffmpeg --disable-debug --disable-doc
# make -j$(nproc) && make install

# COLMAP 4.0.4 (released 2026-04-27) — build for GPU BA:
# cmake -DGUI_ENABLED=OFF -DCMAKE_CUDA_ARCHITECTURES=80
```

## Resources

- FFmpeg 8.1.1: https://ffmpeg.org/releases/ (released 2026-05-04; LGPL v2.1+)
- OpenCV 4.13.0.92: https://pypi.org/project/opencv-python-headless/4.13.0.92/ (Apache 2.0)
- COLMAP 4.0.4: https://github.com/colmap/colmap/releases/tag/4.0.4 (BSD-3-Clause; 2026-04-27)
- pycolmap 4.0.4: https://pypi.org/project/pycolmap/4.0.4/ (BSD-3-Clause; 2026-04-27)
- rembg 2.0.75: https://github.com/danielgatis/rembg (MIT; 2026-04-08)
- BiRefNet (HF): https://huggingface.co/zhengpeng7/BiRefNet (MIT; rev e2bf8e4)
- SAM2: https://github.com/facebookresearch/sam2 (Apache 2.0; no release tags — pin SHA)
- GLOMAP archived: https://github.com/colmap/glomap (deprecated 2026-03-09; use COLMAP global_mapper)
- colmap/colmap #3796 (pycolmap-cuda12 vs PyTorch conflict)
- danielgatis/rembg #819 (CUDA 13 ONNX Runtime fallback)
- ZhengPeng7/BiRefNet #285 (Transformers 5.x breakage)
- colmap/colmap #3894 (GPU BA absent in binary releases)
