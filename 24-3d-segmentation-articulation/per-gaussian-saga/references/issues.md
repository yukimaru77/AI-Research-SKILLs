# SAGA known issues and fixes

Curated from `Jumpat/SegAnyGAussians` issue tracker, validated via Deep Thinker research (2026-05-05). Issue links are real; integration gotchas are flagged.

---

## Issue #75 — `get_scale.py` killed / OOM (opened 2024-06-19, closed)

**Symptom.** Process killed after running `get_scale.py`; memory exhaustion.

**Root cause.** `get_scale.py` loads SAM mask tensors for all images and Gaussians simultaneously. No `--downsample` flag exists on `get_scale.py` itself.

**Fix.** Re-run `extract_segment_everything_masks.py` with `--downsample 4` or `--downsample 8` to produce smaller SAM mask tensors, then retry `get_scale.py`. Do not pass `--downsample` directly to `get_scale.py` — the flag does not exist there. Reduce input image resolution or use a smaller image set as a secondary measure.

URL: https://github.com/Jumpat/SegAnyGAussians/issues/75

---

## Issue #77 — `extract_features.py` missing in v2 (opened 2024-06-20, open)

**Symptom.** Some external docs and v1 workflows reference `extract_features.py`; it is absent from the v2 root.

**Fix.** v2 uses `get_clip_features.py --image_root <scene>` for CLIP-based open-vocabulary features. `extract_features.py` is a v1 artifact; do not create it in v2 agent code.

URL: https://github.com/Jumpat/SegAnyGAussians/issues/77

---

## Issue #84 — conda environment.yml unsatisfiable (opened 2024-06-28, open)

**Symptom.** `conda env create --file environment.yml` fails with solver conflicts around Python 3.7.13, hdbscan, matplotlib, cudatoolkit, PyTorch, and torchvision.

**Fix.** Use staged mamba create with explicit pins, then pip-install extensions only after `import torch` succeeds:

```bash
mamba create -n saga-v2 -y -c pytorch -c conda-forge \
  python=3.7.13 pip=22.3.1 cudatoolkit=11.6 \
  pytorch=1.12.1 torchvision=0.13.1 torchaudio=0.12.1 \
  plyfile=0.8.1 tqdm matplotlib joblib==1.1.0 mkl=2024.0

conda activate saga-v2
python -c "import torch"   # must succeed before any pip install of extensions

pip install "setuptools<60" "wheel<0.40" "numpy<2" "opencv-python<4.9"
pip install "dearpygui==1.10.1" "hdbscan==0.8.33" "open-clip-torch"
pip install ./third_party/segment-anything
pip install ./submodules/simple-knn
pip install ./submodules/diff-gaussian-rasterization
pip install ./submodules/diff-gaussian-rasterization-depth
pip install ./submodules/diff-gaussian-rasterization_contrastive_f
```

URL: https://github.com/Jumpat/SegAnyGAussians/issues/84

---

## Issue #86 — Float vs Bool mask dtype in render (opened 2024-07-04, closed)

**Symptom.** Custom render code errors with "expected scalar type Float but found Bool" when passing a SAGA-saved `.pt` mask directly.

**Root cause.** The `.pt` mask saved by `saga_gui.py` is a boolean tensor. Some rasterizer/render paths expect float input.

**Fix.** Use the official `render.py --precomputed_mask <path> --target scene --segment` and `--target seg` commands — they handle `.pt`/`.npy` → bool conversion internally. In custom wrappers, explicitly cast: `mask.float()` where a float tensor is required, `mask.bool()` for segmentation selection.

URL: https://github.com/Jumpat/SegAnyGAussians/issues/86

---

## Issue #118 — GUI saves mask, not semantic PLY (opened 2024-10-24, open)

**Symptom.** Users expect `saga_gui.py` to emit a semantic/colored PLY file. Instead it saves a binary per-Gaussian mask.

**Root cause.** v2 GUI design: saves `./segmentation_res/<name>.pt`, a `torch.Tensor` of shape `[N]` (boolean, one entry per Gaussian), not a semantic PLY or new point cloud. Visual output is produced by `render.py`, not the GUI save action.

**Fix.** Use `render.py --precomputed_mask ./segmentation_res/<name>.pt --target scene --segment` for RGB segmented renders, `--target seg` for 2D mask renders. No semantic PLY export path exists in v2.

URL: https://github.com/Jumpat/SegAnyGAussians/issues/118

---

## Issue #131 / #151 — `train_contrastive_feature.py` very slow (opened 2025-02-24 and 2025-07-24, open)

**Symptom.** ~70 hours for 10k iterations on RTX 4090D/WSL2 (#131); tens of hours on similar hardware (#151, Jul 2025).

**Root cause.** No upstream fix. Likely: SAM mask I/O, contrastive loss computation over large mask sets, WSL2 storage overhead.

**Fix.** Smoke-test first with `--iterations 200 --num_sampled_rays 512`. Production: `--iterations 10000 --num_sampled_rays 1000` (README recommendation). Use native Linux (not WSL2), fast NVMe storage, and pre-downsampled mask sets. Reduce `--downsample` value to lower mask resolution.

URLs:
- https://github.com/Jumpat/SegAnyGAussians/issues/131
- https://github.com/Jumpat/SegAnyGAussians/issues/151

---

## Issue #152 — missing `mask_scales` (2025, open)

**Symptom.** `mask_scales` file not found when attempting to train contrastive features.

**Fix.** Ensure `get_scale.py` completed successfully before running `train_contrastive_feature.py`. Check `$MODEL/mask_scales` or the expected output path. Re-run `get_scale.py` if the file is absent.

URL: https://github.com/Jumpat/SegAnyGAussians/issues/152

---

## Issue #153 — `libtorch_cpu.so: undefined symbol: iJIT_NotifyEvent` (opened 2025-09-08, open)

**Symptom.** `pip install ./submodules/diff-gaussian-rasterization` fails during the build because `import torch` raises `libtorch_cpu.so: undefined symbol: iJIT_NotifyEvent`.

**Root cause.** MKL 2024.1+ conflicts with PyTorch 1.12.1. This is a known upstream PyTorch issue with newer MKL ABIs.

**Fix (confirmed one-liner):**
```bash
mamba install "mkl=2024.0" -c defaults
python -c "import torch"   # verify clean before proceeding
```
Then install extensions. Additionally: use the devel CUDA image (`nvidia/cuda:11.6.2-cudnn8-devel-ubuntu20.04`), not the runtime image, because CUDA extension compilation requires build tools.

URL: https://github.com/Jumpat/SegAnyGAussians/issues/153

---

## Issue #159 — missing `seg_cfg_args` for 2D mask render (2025, open)

**Symptom.** Attempting to render 2D segmentation masks outside the expected model directory structure errors with a missing config argument.

**Fix.** Ensure `render.py` is run with `-m <model_path>` pointing to a complete SAGA model directory containing `cfg_args`. Do not run render from an arbitrary working directory. The model path must contain both the base 3DGS config and the contrastive feature checkpoint.

URL: https://github.com/Jumpat/SegAnyGAussians/issues/159

---

## Issue #160 — using actual masks as input to `train_contrastive_feature.py` (2025, open)

**Symptom.** Users want to substitute custom/external masks instead of SAM-extracted ones for contrastive training.

**Note.** v2 training pipeline expects SAM-format mask tensors under `sam_masks/`. No official flag to substitute arbitrary masks. Workaround: format custom masks to match the SAM output structure before training.

URL: https://github.com/Jumpat/SegAnyGAussians/issues/160

---

## Issue #162 — VRAM not reclaimed between render passes (2025, open)

**Symptom.** GPU VRAM accumulates across multiple `render.py` calls in a loop; process eventually OOMs.

**Fix.** Run each `render.py` call in a separate subprocess rather than looping inside one Python process. Use `torch.cuda.empty_cache()` between calls if calling from Python.

URL: https://github.com/Jumpat/SegAnyGAussians/issues/162

---

## Integration gotcha — PyTorch3D required at import time

**Mechanism.** `train_contrastive_feature.py` does `import pytorch3d.ops` at the module top level. The script fails immediately even if `pytorch3d.ops` is never called in the actual code path.

**Fix.** Install a PyTorch3D build compatible with Python 3.7 / PyTorch 1.12 / CUDA 11.6 before running `train_contrastive_feature.py`. `saga_gui.py` does not import pytorch3d and can run without it once features are already trained.

---

## Integration gotcha — DearPyGUI version and Python 3.7

**Mechanism.** DearPyGUI 2.x requires Python >=3.8. SAGA v2 uses Python 3.7.13. The official `environment.yml` does not pin the DearPyGUI version; installing without pinning installs 2.x, which is incompatible.

**Fix.** Pin `dearpygui==1.10.1` — the last 1.x release with cp37 wheels. The GUI API used in `saga_gui.py` (dpg.create_context, dpg.create_viewport, dpg.add_slider_float, dpg.add_text, handler registries) is present in 1.10.1. Do not use 1.5.0 (too old, avoidable API gaps) or 2.x (Python 3.8+ only).

---

## Integration gotcha — HDBSCAN CPU-only, hardcoded parameters

**Mechanism.** `saga_gui.py` cluster3d path samples ~2% of Gaussian features (`torch.rand(N) > 0.98`, hardcoded) and runs CPU HDBSCAN with `min_cluster_size=10`, `cluster_selection_epsilon=0.01`, `allow_single_cluster=False` — all hardcoded, not GUI sliders. GUI sliders are Scale and ScoreThres only.

**Fix for large scenes.** In a lab wrapper, sample 100k–300k features rather than 2% of 5M+ Gaussians. Run HDBSCAN on the sample, compute cluster centers, assign all Gaussians to the nearest center by cosine similarity.

**GPU HDBSCAN note.** RAPIDS cuML HDBSCAN exists but requires a modern Python/CUDA environment, not the SAGA Python 3.7/CUDA 11.6 stack.

---

## Integration gotcha — DearPyGUI headless Docker

**Mechanism.** `saga_gui.py` calls `dpg.create_viewport` and runs a render loop. It requires an active display.

**Fix.** For interactive labeling: mount X11 socket (`xhost +local:docker`, `-v /tmp/.X11-unix:/tmp/.X11-unix -e DISPLAY=$DISPLAY`). For CI/headless batch jobs: use Workflow B (cosine seed prompts) or Workflow C (HDBSCAN wrapper) — never call `saga_gui.py` without a display.

---

## Integration gotcha — SAM mask quality on specular lab surfaces

**Mechanism.** `extract_segment_everything_masks.py` uses fixed SAM thresholds: `pred_iou_thresh=0.88`, `stability_score_thresh=0.95`, `min_mask_region_area=100`. SEM chambers, microscope objectives, and metallic knobs produce glare that degrades mask quality.

**Fix.** Control glare at capture time (cross-polarization, diffuse lighting). Use `--downsample 4` or lower resolution to reduce over-segmentation. Patch thresholds only after visual QA — do not lower blindly.

---

## Integration gotcha — feature dimension is 32, hardcoded

**Mechanism.** `FEATURE_DIM = 32` in `saga_gui.py`; `feature_dim=32` in `ModelParams`; PLY loader asserts exactly 32 `f_*` fields in `contrastive_feature_point_cloud.ply`.

**Fix.** Keep feature dimension at 32. Changing it requires patching training, GUI, scale gate, PLY loading, and all batch scripts in sync.

---

## Integration gotcha — mask saved on CUDA, load with map_location

**Mechanism.** The GUI saves the mask from a CUDA tensor (`_mask` is initialized as a CUDA float tensor; the equality comparison result is boolean CUDA tensor). Loading with `torch.load(path)` on a CPU-only machine will fail.

**Fix.** Always load SAGA masks with `torch.load(path, map_location='cpu')` in downstream code or when transferring between environments.

---

## Integration gotcha — top-level Apache-2.0 vs vendored non-commercial components

**Mechanism.** SAGA's top-level code is Apache-2.0, but the v2 tree includes:
- `submodules/diff-gaussian-rasterization` — Gaussian-Splatting License (non-commercial research/evaluation)
- `submodules/simple-knn` — GraphDECO/Inria non-commercial header in `setup.py`
- Root Python files (`render.py`, `arguments/`) — GraphDECO/Inria non-commercial headers

**Fix.** Treat SAGA v2 as R&D/evaluation only. Legal review, upstream permission, or replacement of non-commercial components is required before commercial deployment, SaaS use, or binary redistribution. Do not document SAGA as a "commercial-friendly" improvement over LUDVIG; both require the same legal review on the 3DGS rasterizer axis.
