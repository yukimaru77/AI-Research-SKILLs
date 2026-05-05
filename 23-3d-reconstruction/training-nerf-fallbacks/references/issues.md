# Real GitHub Issues and PRs — NeRF Fallbacks (2024–2026)

Sourced via Deep Thinker research, May 2026. Issue numbers verified against public GitHub; flag uncertain entries.

---

## nerfstudio

### PR #2092 — Camera optimizer moved from datamanager to model
- **What**: `camera_optimizer` config moved from `VanillaDataManagerConfig` to `NerfactoModelConfig`. The old `--pipeline.datamanager.camera-optimizer.*` CLI path is now a suppressed/deprecated no-op in 1.1.5.
- **Action**: Always use `--pipeline.model.camera-optimizer.mode SO3xR3` in nerfstudio >=1.1.x scripts.
- **Ref**: https://github.com/nerfstudio-project/nerfstudio/pull/2092

### Issue #1017 — Pose refinement not recovering noisy poses
- **What**: Camera optimization (SO3xR3) fails to recover heavily noisy initial poses; reported divergence.
- **Action**: Start with conservative LR (`1e-4`), avoid `--eval-mode all` with pose optimization. ColmapDataParser source explicitly warns of divergence with `eval-mode=all` + camera opt.
- **Ref**: https://github.com/nerfstudio-project/nerfstudio/issues/1017

### Issue #3401 — ns-render camera-path ignores intended camera path (3DGS scene)
- **What**: `ns-render camera-path` does not use the intended camera path for Splatfacto/Gaussian scenes; renders default path.
- **Action**: Smoke-test all exported camera paths before batch render. Verify with a short `--output-format images` test first.
- **Ref**: https://github.com/nerfstudio-project/nerfstudio/issues/3401

### Issue #3456 — ns-process-data Docker permission error on /.local
- **What**: Running `ns-process-data` inside Docker fails with permission error writing to `/.local`.
- **Fix**: Set `HOME=/workspace` or `XDG_DATA_HOME=/workspace/.local` in Dockerfile or container launch.
- **Ref**: https://github.com/nerfstudio-project/nerfstudio/issues/3456

### Issue #3674 — Splatfacto failure on scene where Nerfacto succeeds
- **What**: User reports Splatfacto fails (floaters/artifacts) on the same capture that Nerfacto reconstructs cleanly. Validates the fallback workflow pattern.
- **Ref**: https://github.com/nerfstudio-project/nerfstudio/issues/3674

### Issue #3683 — ns-viewer checkpoint load failure with PyTorch 2.6 (weights_only)
- **What**: PyTorch 2.6 changed `torch.load()` default `weights_only=True`, breaking checkpoint loading in `ns-viewer`, `ns-train` resume, and `ns-export`.
- **Fix (PRs #3702, #3711)**: Patch `torch.load(...)` calls with `weights_only=False` for trusted checkpoints. Env workaround: `TORCH_FORCE_NO_WEIGHTS_ONLY_LOAD=1`.
- **Recommendation**: Pin to PyTorch <=2.5.1 with nerfstudio 1.1.5.
- **Ref**: https://github.com/nerfstudio-project/nerfstudio/issues/3683

### PR #3702 — Fix torch.load in trainer.py for PyTorch >=2.6
- **What**: Adds `weights_only=False` to checkpoint loads in `engine/trainer.py`.
- **Ref**: https://github.com/nerfstudio-project/nerfstudio/pull/3702

### PR #3711 — Fix ns-export eval_utils.py for PyTorch >=2.6
- **What**: Makes `ns-export` compatible with torch >=2.6 `weights_only` change.
- **Ref**: https://github.com/nerfstudio-project/nerfstudio/pull/3711

### Issue #3693 — RTX 5090 Docker support request
- **What**: User requests nerfstudio Docker image support for RTX 5090 (sm_120, Blackwell).
- **Status as of May 2026**: Tracking; no official supported image for Blackwell yet.
- **Workaround**: Set `TCNN_CUDA_ARCHITECTURES=120`, use CUDA 12.8+, PyTorch cu124+ wheels.
- **Ref**: https://github.com/nerfstudio-project/nerfstudio/issues/3693

### Issue #3732 — RTX 5070 / sm_120 incompatibilities with stable cu118 stack
- **What**: RTX 50-series (sm_120) users report failures with the stable CUDA 11.8 / PyTorch 2.1.2 stack. tiny-cuda-nn and nerfstudio extensions fail to build or run.
- **Action**: RTX 50-series requires CUDA 12.8+ custom stack. Not supported by the official nerfstudio 1.1.5 docs stack.
- **Ref**: https://github.com/nerfstudio-project/nerfstudio/issues/3732

### COLMAP dataparser changes (PRs #2467, #2860; issues #2849, #3107)
- **PR #2467**: Fixes COLMAP masks/depthmaps handling in ColmapDataParser.
- **PR #2860**: Makes ColmapDataParser compatible with 360_v2 dataset convention.
- **Issue #2849**: Reports ns-process-data output underperforms direct COLMAP conversion; prefer direct COLMAP → colmap dataparser for production.
- **Issue #3107**: CLI confusion around COLMAP dataparser parameter names (hyphens vs underscores). Tyro treats them as equivalent; use hyphens in production scripts.

---

## tiny-cuda-nn

### Issue #455 — H100 + CUDA architectures 90 + CUDA 11.8 nerfstudio stack
- **What**: User questions whether H100 sm_90 builds work with nerfstudio's recommended cu118 PyTorch stack.
- **Answer**: Set `TCNN_CUDA_ARCHITECTURES=90`; ensure nvcc and torch CUDA versions align. CUDA 11.8 wheels + sm_90 can work but may be slower; prefer CUDA 12.x on H100.
- **Ref**: https://github.com/NVlabs/tiny-cuda-nn/issues/455

### Issue #475 — tiny-cuda-nn build hangs / >1 h on H100 (compute_90/sm_90)
- **What**: Docker install of tiny-cuda-nn with compute_90/sm_90 and PyTorch 2.1.2+cu118 takes >1 h and may OOM or time out.
- **Fix**: Limit `MAX_JOBS=8` (or fewer); confirm `TCNN_CUDA_ARCHITECTURES=90` is set before pip install; ensure the CUDA toolkit version matches.
- **Ref**: https://github.com/NVlabs/tiny-cuda-nn/issues/475

### Issue #527 — RTX 5090 / Blackwell build failures (sm_120)
- **What**: RTX 5090 build logs show `compute_120/sm_120` flags. Build may fail on CUDA <12.8 or with mismatched PyTorch.
- **Action**: Set `TCNN_CUDA_ARCHITECTURES=120` for RTX 5090. Use CUDA 12.8+. Do NOT use sm_100 (that is datacenter Blackwell, e.g. B200/GB200).
- **Ref**: https://github.com/NVlabs/tiny-cuda-nn/issues/527

### tiny-cuda-nn v2.0 JIT fusion caveat
- **What**: v2.0 adds JIT fusion for FullyFusedMLP. Release notes warn JIT can slow down for hash grids >20M parameters or MLPs wider than 128 neurons.
- **Disable**: `model.jit_fusion = False` in Python (no global CLI flag).
- **Ref**: https://github.com/NVlabs/tiny-cuda-nn (v2.0 release notes)

---

## Instant-NGP

### README build troubleshooting (issues #18, #28, #34, #37, #41, #42, #52)
- **What**: Canonical build failures documented in Instant-NGP README troubleshooting:
  - #18/#28: "No CUDA toolset found" on Windows/Linux
  - #34/#41/#42: `cudaGraphExecUpdate` / `cublasSetWorkspace` undefined (requires newer CUDA)
  - #37/#52: Submodule not initialized (`--recursive` clone required)
- **Action**: Always `git clone --recursive`; use CMake >=3.21; match CUDA toolkit to built extensions.
- **Ref**: https://github.com/NVlabs/instant-ngp (README troubleshooting section)

### Issue #1559 — .ingp snapshot format not publicly documented
- **What**: User requests public spec for `.ingp` file format. Closed as "not planned."
- **Action**: Treat `.ingp` as an internal format; use Instant-NGP's own `--load_snapshot` / `--save_snapshot` API exclusively.
- **Ref**: https://github.com/NVlabs/instant-ngp/issues/1559

### Discussion #933 — Commercial licensing for Instant-NGP
- **What**: Maintainer confirms that if you have customers (commercial use), you must seek a separate commercial license from NVIDIA. The public NVIDIA Source Code License-NC covers research/evaluation only.
- **Action**: Do not use Instant-NGP outputs in commercial products without separate NVIDIA licensing.
- **Ref**: https://github.com/NVlabs/instant-ngp/discussions/933

### v2.0 `--mode` deprecation
- **What**: `--mode nerf` (or any mode) is accepted but no-op in v2.0 `scripts/run.py`. Exact message: `Warning: the '--mode' argument is no longer in use. It has no effect. The mode is automatically chosen based on the scene.`
- **Action**: Omit `--mode` from all production scripts targeting v2.0.

### v2.0 `--snapshot` alias
- **What**: `--snapshot` is an alias for `--load_snapshot` (load only). Use `--save_snapshot` to save after training.
- **Action**: Do not confuse `--snapshot` (load) with `--save_snapshot` (write).

---

## Compute capability quick reference (May 2026)

| GPU | Compute capability | TCNN_CUDA_ARCHITECTURES |
|---|---|---|
| A100 | 8.0 | 80 |
| H100 / H200 | 9.0 | 90 |
| RTX 4090 (Ada) | 8.9 | 89 |
| RTX 5090 (Blackwell GeForce) | 12.0 | 120 |
| B200 / GB200 (datacenter Blackwell) | 10.0 | 100 |

Source: NVIDIA compute capability table; tiny-cuda-nn v2.0 CMake sets LATEST_SUPPORTED_CUDA_ARCHITECTURE=120 for CUDA >=12.8.
