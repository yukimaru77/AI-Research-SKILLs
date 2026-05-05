# GitHub Issues Reference: Recovering Pose-Free Geometry

Validated and researched late 2025 / early 2026. Confirmed merged fix = PR merged into main with release note or commit. "Open / workaround" = issue open or no confirmed code merge; community workaround available.

---

## MapAnything (facebookresearch/map-anything)

| Issue / PR | Category | Status | Notes |
|---|---|---|---|
| PR #23 | Depth-input inference bug | **Fixed** — release v1.0.1 | "fix inference with depth map as input" |
| PR #60 | Partial COLMAP pose handling | **Fixed** — release v1.0.1 | "handle partial pose info in COLMAP demo" |
| Issue #57 | CUDA OOM | Open / workaround | Use `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True`, `memory_efficient_inference=True`, `minibatch_size=1`, `use_amp=True`, `amp_dtype="bf16"` |
| Issue #93 | Scale / pose mismatch (image-only vs pose-conditioned) | Open | Incoherence between image-only and pose-conditioned point clouds; no confirmed upstream fix |
| Issue #40 | Trajectory drift / distorted point cloud | Open | Maintainer attributes to poor parallax / depth ambiguity; no confirmed code fix |
| Issue #124 | NaN / exploding fine-tuning loss | Open | No confirmed fix |
| Issue #141 | `init_model_from_config("mapanything")` failure | Open | External-model loading path bug; no confirmed merged fix |
| Issue #149 | Forced DINOv2 Torch Hub download on `from_pretrained` | Open | Pre-cache `dinov2_vitg14` in Docker build step as workaround |

Release history:
- v1.0.0 — initial public release
- v1.0.1 — fixes for depth-input inference (PR #23) and partial COLMAP pose handling (PR #60)
- v1.1.1 — latest as of Mar 23, 2026

---

## VGGT (facebookresearch/vggt)

No GitHub release tags. Pin by SHA.

| Issue | Category | Status | Notes |
|---|---|---|---|
| Issue #470 | OOM + resolution mismatch in `demo_colmap.py` | Open / workaround | `demo_colmap.py` applied a second square resize on top of `load_and_preprocess_images` output (~doubling computation). Workaround: use `load_and_preprocess_images` directly, remove the extra resize step |
| Issue #31 | CUDA OOM with 10 images on RTX 4090 | Open | No confirmed fix; reduce frame count |
| Issue #238 | `demo_colmap.py` OOM with 40 images | Open | Same root as #470; reduce frames or remove extra resize |
| Issue #384 | pycolmap DLL failure CUDA 12.8 / RTX 5090 | Open | Windows/Blackwell-specific; not an A100 blocker |
| Issue #47 | Masking dynamic / reflective pixels | Closed | Resolution: README guidance to zero-out unwanted pixels; no code fix confirmed |
| Issue #46 / #143 | Scale / coordinate confusion | Open | Normalized-coordinate / scale-shift caveats; no confirmed production fix |
| Issue #254 | Noisy poses on reflective surfaces | Open | Use masking before inference and `--use_ba`; cross-check against MapAnything |
| Issue #188 | Inaccurate downstream splats | Open | Use `demo_colmap.py --use_ba`; constrain scale with AprilTags |

Model release dates:
- `facebook/VGGT-1B` — published on HuggingFace Mar 14, 2025 (CC-BY-NC-4.0; research only)
- `facebook/VGGT-1B-Commercial` — gated; AUP license update announced Jul 29, 2025; HF updated Sep 17, 2025

---

## DUSt3R (naver/dust3r)

No GitHub release tags. Checkpoint: `naver/DUSt3R_ViTLarge_BaseDecoder_512_dpt` (HF updated Jul 12, 2024). License: CC-BY-NC-SA-4.0.

| Issue | Category | Status | Notes |
|---|---|---|---|
| Issue #1 | CUDA OOM on 29-image run | Open | CPU global-alignment workaround in issue thread: `scene.compute_global_alignment(device="cpu")` |
| Issue #28 | OOM above ~16 images | Open | Reduce to subgraph or CPU alignment |
| Issue #117 | `compute_global_alignment` NaN / singular | Open | Use `init="mst"`, `schedule="cosine"`, `niter=300→1000`, `lr=0.01→0.003`; validate priors (finite, right-handed, positive focals) |
| Issue #143 | Global aligner NaN retry strategy | Open | Same root as #117; split enclosed scenes into overlapping subgraphs |
| Issue #209 | Image-resolution mismatch | Open | Match checkpoint size to loader: 512-weight checkpoint + `size=512`; do not silently run at 256 |

---

## MASt3R (naver/mast3r)

No GitHub release tags. Checkpoint: `naver/MASt3R_ViTLarge_BaseDecoder_512_catmlpdpt_metric` (HF updated Jul 18, 2024). License: CC-BY-NC-SA-4.0. Note: checkpoint legal notice includes a restrictive Mapfree data caveat.

| Issue | Category | Status | Notes |
|---|---|---|---|
| Issue #18 | Resolution mismatch | Open | Similar to DUSt3R #209; match loader size to checkpoint |
| Issue #29 | Absolute pose / PnP confusion | Open | User confusion; no upstream fix |
| Issue #35 | Low-resolution / memory tradeoff | Open | 256×256 with 512 weights causes large match-quality drop; prefer `size=512` even at reduced frame count |
| Issue #52 | Reprojection / pixel-shift vs DUSt3R behavior | Open | No confirmed fix |
| Issue #53 | MASt3R-SfM ASMK/codebook link broken | Open | Install ASMK from `https://github.com/jenicek/asmk`; install with `cythonize *.pyx && pip install .` |
| Issue #71 | Resolution mismatch (additional report) | Open | Same root as #18; use `size=512` |
| Issue #103 | Absolute pose estimation / PnP usage | Open | No confirmed fix |
| Issue #131 | MASt3R-SfM failure on difficult matching (specular/low-overlap) | Open | Relevant to specular lab gear; no confirmed fix; increase overlap or use masking |

---

## MASt3R-SLAM (rmurai0610/MASt3R-SLAM)

Canonical repo: `github.com/rmurai0610/MASt3R-SLAM` (not `naver/mast3r-slam`). Python 3.11, PyTorch 2.5.1, CUDA 11.8/12.1/12.4. License: CC-BY-NC-SA-4.0.

| Issue | Category | Status | Notes |
|---|---|---|---|
| Issues #121, #122 | CUDA / install errors | Open | thirdparty/mast3r install must complete before `--no-build-isolation` install |
| Issue #125 | CUDA invalid resource handle | Open | Verify CUDA extension compiled for `sm_80`; A100-specific compile flags required |
| Issue #127 | All-zero point cloud | Open | Often caused by failed CUDA extension compilation; rebuild extensions |
| Issue #136 | CUDA 12.9 / RTX 5070 support | Open | sm_120 not in arch list; add to setup if on newer GPU |
| WSL issue | Shared-memory multiprocessing failure | Documented | Use special Windows/WSL branch; disable multiprocessing |

---

## VGGSfM (facebookresearch/vggsfm)

No GitHub release tags. v2.0 code; v1.1 recommended for paper benchmark reproduction. License: CC-BY-NC-4.0. HF `facebook/VGGSfM` tracker updated May 14, 2025.

| Issue / Note | Category | Status | Notes |
|---|---|---|---|
| Issue #9 | Video processing | Open (May 2024) | Maintainer planned new HF demo/training script; not a confirmed production fix |
| v2.0 chunk OOM mitigation | OOM | Repo-level workaround | v2.0 splits points into chunks with hardcoded chunk-size constants; adjust for your GPU VRAM |
| v2.0 testing script | Stability | Research-preview | README notes testing script still being prepared; use v1.1 for benchmark reproducibility |

---

## Issues referenced in SKILL.md (summary cross-reference)

```
map-anything  PR #23, PR #60, Issue #57, #93, #40, #124, #149
vggt          Issue #31, #47, #188, #238, #254, #384, #470
dust3r        Issue #1, #28, #117, #143, #209
mast3r        Issue #18, #29, #35, #52, #53, #71, #103, #131
mast3r-slam   Issue #121, #122, #125, #127, #136
vggsfm        Issue #9
```
