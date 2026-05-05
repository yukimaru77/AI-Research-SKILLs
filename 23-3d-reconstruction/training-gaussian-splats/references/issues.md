# Real GitHub Issues and PRs — 3DGS / gsplat / nerfstudio (2024–2026)

All entries verified via deep research as of May 2026. Issue numbers are real; do not invent additional ones.

---

## gsplat issues

### gsplat #487 — CUDA OOM during MCMC growth (large scene)
- **Repo**: nerfstudio-project/gsplat
- **Status**: Open/known limitation
- **Description**: MCMC strategy hit CUDA OOM after ~6400 steps on a large scene; `isect_tiles` attempted a multi-GB allocation on a ~40 GB GPU.
- **Fix/Workaround**: Lower `cap_max` (300k–800k for small enclosed scenes). Use DefaultStrategy for memory-constrained runs. Downscale images. Split into per-cluster training.

### gsplat #444 — MCMC memory growth at high point counts
- **Repo**: nerfstudio-project/gsplat
- **Status**: Open/documented limitation
- **Description**: 48 GB GPU hit memory pressure at very high Gaussian counts; gradient/Adam buffers and `torch.cat`-style growth are primary pressure points.
- **Fix/Workaround**: Use `--sparse-grad` where available. Cap Gaussian count. Split scene into clusters. Avoid unbounded MCMC growth.

### gsplat #590 and #660 — save_ply writes empty PLY when opacities contain NaN
- **Repo**: nerfstudio-project/gsplat
- **Status**: Fixed in gsplat 1.5.2 via PR #663
- **Description**: `gsplat.utils.save_ply` could write an empty PLY when the invalid-mask check mishandled NaN opacities.
- **Fix**: Upgrade to gsplat 1.5.2+ for the standalone path. Note: `ns-export gaussian-splat` uses nerfstudio's own `write_ply` with `np.isfinite` filtering, so this specific code path does not apply to nerfstudio exports.

### gsplat PR #663 — Fix strict invalid mask in save_ply
- **Repo**: nerfstudio-project/gsplat
- **Status**: Merged (May 2025)
- **Description**: Corrected the invalid-mask logic in `gsplat.utils.save_ply`. Closed issues #590 and #660.

---

## nerfstudio issues

### nerfstudio #3196 — gsplat 1.0 breaks splatfacto
- **Repo**: nerfstudio-project/nerfstudio
- **Status**: Fixed via PR #3478
- **Description**: gsplat 1.0 reorganized its package structure; nerfstudio imported moved/private modules (`gsplat._torch_impl`) without an upper bound on gsplat, causing `ModuleNotFoundError` on fresh installs.
- **Fix**: nerfstudio 1.1.5 pins `gsplat==1.4.0`. Always install gsplat from the prebuilt wheel index before installing nerfstudio to avoid source compilation.

### nerfstudio PR #3478 — Pin gsplat to ==1.4.0
- **Repo**: nerfstudio-project/nerfstudio
- **Status**: Merged
- **Description**: Updated nerfstudio's gsplat dependency to `==1.4.0` due to repeated breaking-change history in gsplat. Reviewers explicitly chose a strict pin over a range.

### nerfstudio #3104 — Floaters / haze around objects in splatfacto
- **Repo**: nerfstudio-project/nerfstudio
- **Status**: Documented workaround
- **Description**: Background floaters and haze artifacts in splatfacto training, especially with dark/uniform backgrounds.
- **Fix**: Set `--pipeline.model.background-color random`. Keep `cull-alpha-thresh=0.03` initially.

### nerfstudio #3551 — ns-train splatfacto fails during CUDA op compilation
- **Repo**: nerfstudio-project/nerfstudio
- **Status**: Documented workaround
- **Description**: `ns-train splatfacto` failed while gsplat compiled `fully_fused_projection_packed_fwd.cu` via Ninja. Caused by torch/CUDA/compiler version mismatch.
- **Fix**: Use a prebuilt gsplat wheel (install from `docs.gsplat.studio/whl` before nerfstudio). Use a `devel` Docker image. Match torch and CUDA versions exactly.

### nerfstudio #3157 — CUDA 11.8 + newer Visual Studio compiler incompatibility
- **Repo**: nerfstudio-project/nerfstudio
- **Status**: Documented limitation (Windows-focused)
- **Description**: Custom CUDA op builds failed on Windows with newer Visual Studio compiler and CUDA 11.8.
- **Fix**: Use Linux Docker with matched compiler. On Windows, pin to a supported MSVC version.

### nerfstudio #3732 — RTX 5070 / Blackwell setup fails with old CUDA 11.8 docs
- **Repo**: nerfstudio-project/nerfstudio
- **Status**: Open (2025)
- **Description**: New GPU architecture (Blackwell/RTX 5070) with CUDA 12.8 host stack was incompatible with old `cu118` documentation and had missing arch support and GCC incompatibilities.
- **Fix/Workaround**: For A100, this primarily reinforces: do not assume cu118 is universally valid; use the CUDA 12.x stack for new setups.

### nerfstudio #3073 — splatfacto camera optimizer pose inconsistency
- **Repo**: nerfstudio-project/nerfstudio
- **Status**: Known behavior
- **Description**: Different pose adjustments between camera optimizer application paths created inconsistency in splatfacto.
- **Fix**: For metric/AprilTag scenes, set `--pipeline.model.camera-optimizer.mode off`. Only enable pose refinement if you explicitly need it and can export and track the optimized poses.

### nerfstudio #2863 — Poor novel-view quality on small pose changes
- **Repo**: nerfstudio-project/nerfstudio
- **Status**: Known limitation
- **Description**: Good train/eval camera quality but poor quality after small POV extrapolation from training cameras. Camera optimizer did not resolve the issue.
- **Fix**: Increase capture coverage. Use controlled geometry (turntable or multi-ring rig). Avoid large extrapolation from training camera positions.

---

## Notes

- SH coefficient transpose in nerfstudio exporter: nerfstudio's `ExportGaussianSplat.write_ply` applies `transpose(1, 2)` to match Inria SH field order. No standalone GitHub issue number was found for this; it is documented in source comments.
- KHR_gaussian_splatting: Khronos released a Release Candidate on 2026-02-03; ratification expected Q2 2026. Not yet a ratified spec as of May 2026.
- Brush v0.3.0: https://github.com/ArthurBrussee/brush — Apache-2.0 Rust binary; no Python API.
- Original Inria 3DGS: https://github.com/graphdeco-inria/gaussian-splatting — non-commercial research/evaluation license only.
