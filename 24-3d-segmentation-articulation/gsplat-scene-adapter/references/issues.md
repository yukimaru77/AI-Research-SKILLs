# Known issues — gsplat scene adapter

Sourced from public GitHub issues and PRs, verified against gsplat and nerfstudio repositories as of May 4, 2026.

---

## PLY / export issues

**nerfstudio #3377** (Aug 23, 2024 — closed)
`ExportGaussianSplat` could create an invalid PLY when `sh_degree == 0`, with misaligned fields during splatfacto export. Workaround: verify output PLY is readable with `PlyData.read()` immediately after export; re-export with `--ply-color-mode rgb` as fallback.

**nerfstudio #3483** (Oct 16, 2024 — open at capture)
`ns-export gaussian-splat` produced no error and no output PLY on Windows 11 / Nerfstudio 1.1.4 / gsplat 1.4.0. Not reproducible on Linux. Use Linux or WSL2 for reliable export.

**gsplat #578** (Mar 7, 2025 — closed)
User request for official parsing of original 3DGS PLY into means/scales/quats/opacities/SH. Confirms the PLY-loading ambiguity across producers. Resolution: use the activation rules documented in SKILL.md (sigmoid opacity, exp scale, normalize quats wxyz).

**gsplat #761** (Jul 12, 2025 — open at capture)
User asked how to output PLY from the Python API; noted poor docs discoverability. `export_splats` was already added in v1.5.1 but not prominently documented. Use `from gsplat import export_splats` — see Advanced topics in SKILL.md.

**gsplat PR #594** (included in v1.5.0)
"fix save ply if else" — fixed a branch logic bug in the deprecated `save_ply` helper. Use `export_splats` (v1.5.1+) to avoid the legacy path entirely.

**gsplat PRs #628 / #640** (v1.5.1, Apr 18, 2025)
Introduced and documented the `export_splats` API with `.ply`, `.splat`, and `.ply_compressed` format targets. This is the canonical export path for the adapter skill.

---

## Rendering / API issues

**gsplat PR #670** (v1.5.3, Jul 4, 2025)
Batchified rasterization APIs. `rasterization()` now supports a leading batch dimension. Code that assumed fixed output rank `[C, H, W, ch]` must be updated to use ellipsis indexing `[..., C, H, W, ch]`.

**gsplat PR #704** (v1.5.3)
Alpha/opacity behavior fix. Relevant to depth map validity and alpha-masking correctness in the adapter's depth-diff workflow.

**gsplat PR #736** (v1.5.3)
Fisheye undistortion fix. If using `camera_model="fisheye"`, require v1.5.3 or later.

**gsplat PR #745** (v1.5.3)
F-Theta camera model support added. Use `camera_model="ftheta"` with `ftheta_coeffs` for wide-angle industrial cameras.

**gsplat PR #651** (v1.5.2)
Fix for `torch >= 2.7` compatibility. If building from source in 2026 environments with PyTorch 2.7+, verify v1.5.2+ is used.

**v1.5.2 3DGUT integration** (May 13, 2025)
Added distorted-camera and rolling-shutter support. Relevant for lab cameras with lens distortion; pass `radial_coeffs` / `tangential_coeffs` to `rasterization()`.

---

## OOM / build / large-scene issues

**gsplat #464** (Oct 23, 2024)
CUDA OOM in `isect_tiles` during large renders. Mitigation: reduce camera batch size, enable `packed=True`, use `radius_clip`.

**gsplat #500** (Nov 20, 2024)
First-time CUDA 12.4 source build OOM. Resolution: set `MAX_JOBS=2` before pip install. Now documented in Docker base image guidance.

**gsplat #444** (Oct 8, 2024)
MCMC memory pressure with very large point counts; reported stress on 48 GB GPUs. For adapter use (inference only), MCMC is not involved; issue is relevant only if training with the gsplat MCMC strategy from a different pipeline that feeds this adapter.

**gsplat #806** (Sep 2025)
9M-Gaussian / 20-camera rendering crash. Smaller camera batches (2-4 cameras per call) resolved the issue. Adapter SKILL.md documents this as the large-scene policy.

**gsplat #833** (Nov 22, 2025)
CUDA 13 / Ubuntu 24.04 installation failure for gsplat. v1.5.3 wheels do not include CUDA 13 targets. Use CUDA 12.4 or 11.8 until a future release adds CUDA 13 wheels.

**gsplat #867** (Feb 11, 2026)
Docker build failure when CUDA device is unavailable during the build stage (CI/builder nodes). Fix: set `TORCH_CUDA_ARCH_LIST="8.0+PTX"` explicitly in the Dockerfile before the pip install step.

---

## PLY field reference (producer comparison)

| Field | gsplat `export_splats("ply")` | nerfstudio `ply_color_mode="sh_coeffs"` | GraphDECO |
|---|---|---|---|
| Position | `x y z` | `x y z` | `x y z` |
| Normals | absent | `nx ny nz` (zeros) | `nx ny nz` (zeros) |
| Color DC | `f_dc_0 f_dc_1 f_dc_2` | `f_dc_0 f_dc_1 f_dc_2` | `f_dc_0 f_dc_1 f_dc_2` |
| Color rest | `f_rest_*` | `f_rest_*` (optional) | `f_rest_*` |
| Opacity | `opacity` (raw logit) | `opacity` (raw logit) | `opacity` (raw logit) |
| Scale | `scale_0 scale_1 scale_2` (log) | `scale_0 scale_1 scale_2` (log) | `scale_0 scale_1 scale_2` (log) |
| Quaternion | `rot_0..rot_3` (wxyz) | `rot_0..rot_3` (wxyz) | `rot_0..rot_3` (wxyz) |

nerfstudio `ply_color_mode="rgb"` replaces `f_dc_*` and `f_rest_*` with `red green blue` (uint8). The adapter's `load_gaussian_ply()` handles both branches.
