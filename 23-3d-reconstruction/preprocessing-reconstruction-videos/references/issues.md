# Known Issues and Workarounds

Verified via Deep_thinker web search, 2026-05-05. All issue numbers confirmed real.

---

## colmap/colmap #3796 — pycolmap-cuda12 incompatible with PyTorch CUDA wheels

**Opened:** 2025-12-04  
**URL:** https://github.com/colmap/colmap/issues/3796  
**Symptom:** pip dependency solver fails or runtime crashes when both `pycolmap-cuda12` and a PyTorch CUDA wheel are installed in the same environment.  
**Root cause:** Both packages ship CUDA runtime shared libraries; they conflict at the DLL/so level.  
**Workaround:**
- Use `pycolmap==4.0.4` (CPU build) for Python API calls; run GPU-heavy reconstruction via system COLMAP CLI binary.
- Or isolate pycolmap-cuda12 in a dedicated virtualenv without PyTorch.
- Build COLMAP 4.0.4 from source with `-DCMAKE_CUDA_ARCHITECTURES=80` for a single controlled binary.

---

## danielgatis/rembg #819 — CUDA 13 not supported by rembg[gpu]

**Opened:** 2026-02-20  
**URL:** https://github.com/danielgatis/rembg/issues/819  
**Symptom:** `rembg[gpu]` silently falls back from `CUDAExecutionProvider` to `CPUExecutionProvider` on CUDA 13 hosts, or crashes with ONNX Runtime DLL load errors.  
**Root cause:** ONNX Runtime GPU wheels bundled by rembg 2.0.75 expect CUDA 12 runtime libraries.  
**Workaround:**
- Run rembg in a CUDA-12 sidecar container; expose processed masks to the main container via a shared volume.
- Switch masking to BiRefNet or SAM2 which run directly on PyTorch and do not require ONNX Runtime.
- Monitor rembg releases; a CUDA-13-compatible ONNX Runtime wheel may land in a future release.

---

## ZhengPeng7/BiRefNet #285 — Transformers 5.x incompatibility

**Opened:** 2026-02-03  
**URL:** https://github.com/ZhengPeng7/BiRefNet/issues/285  
**Symptom:** `AutoModelForImageSegmentation.from_pretrained("zhengpeng7/BiRefNet")` raises `AttributeError` or `ImportError` under `transformers>=5.0`.  
**Root cause:** BiRefNet's `modeling_birefnet.py` uses internal Transformers APIs that changed in 5.x.  
**Workaround:**
- Pin `transformers==4.57.3`.
- Use HF revision `e2bf8e4` which includes February 2026 compatibility patches.
- If you must use transformers 5.x, check the BiRefNet repo for a new compatible revision before updating.

---

## colmap/colmap #3894 — GPU bundle adjustment absent in pre-built binaries

**Opened:** 2025-12-29  
**URL:** https://github.com/colmap/colmap/issues/3894  
**Symptom:** COLMAP binary release performs CPU-only bundle adjustment despite A100 being present; reconstruction is much slower than expected.  
**Root cause:** Official binary releases may be compiled without CUDA BA (`-DCUDA_ENABLED=ON` not set, or built against a different CUDA version).  
**Workaround:**
- Build COLMAP 4.0.4 from source:
  ```bash
  git clone --branch 4.0.4 --depth 1 https://github.com/colmap/colmap.git /opt/colmap
  cmake -S /opt/colmap -B /opt/colmap/build -GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -DGUI_ENABLED=OFF \
    -DCMAKE_CUDA_ARCHITECTURES=80
  cmake --build /opt/colmap/build --target install -j"$(nproc)"
  ```
- Verify GPU BA is enabled: `colmap -h 2>&1 | grep -i cuda`

---

## GLOMAP Deprecation Notice (2026-03-09)

**URL:** https://github.com/colmap/glomap  
**Status:** Standalone repo archived March 2026; marked deprecated.  
**Change:** GLOMAP global SfM was integrated into COLMAP 4.x as `colmap global_mapper`.  
**Action required:** Replace any `glomap` binary calls with `colmap global_mapper`. Do not add `glomap` as a new dependency in Docker images; use COLMAP 4.0.4.

---

## Historical notes from v1.0.0 (retained for context, lower confidence)

The following issues were cited in the previous SKILL.md version. They appear real but were not re-verified in the 2026-05-05 Deep_thinker session:

- `facebookresearch/sam2 #258` — unbounded GPU memory growth in video predictor (may still apply; use chunked processing with `reset_state`)
- `facebookresearch/sam2 #623` — async loader state leak  
- `AprilRobotics/apriltag #318` — low-light tag detection failures  
- `opencv_contrib #3192 / PR #3201` — ArUco blurred-marker detection  
- `mifi/lossless-cut #2746` — FFmpeg scene-detection hang  

These are retained as historical reference; verify current status before citing in production runbooks.
