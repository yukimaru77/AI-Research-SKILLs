# Known GitHub Issues and Fixes (2024–2026)

Verified issues relevant to the lab-equipment SfM pipeline. All dates and PR numbers sourced from Deep_thinker (ChatGPT Pro + web search), May 2026.

## COLMAP

| Issue / PR | Date | What broke | Fix / status |
|---|---|---|---|
| [Issue #2514](https://github.com/colmap/colmap/issues/2514) | Ongoing | Textureless/reflective objects fail SfM | Use hloc+LightGlue, DSP-SIFT, masks, cross-polarization |
| [Issue #3796](https://github.com/colmap/colmap/issues/3796) | Dec 4, 2025 | `pycolmap-cuda12==3.13.0` conflicts with PyTorch 2.7.x CUDA runtime pins | [PR #3799](https://github.com/colmap/colmap/pull/3799) merged Dec 12, 2025: relaxed CUDA requirements in wheels. Use `pycolmap-cuda12==4.0.4`. |
| [PR #3799](https://github.com/colmap/colmap/pull/3799) | Dec 12, 2025 | Fix for #3796 | Merged; relaxes CUDA runtime version constraints in pycolmap wheel metadata |
| [PR #3800](https://github.com/colmap/colmap/pull/3800) | Dec 4, 2025 | Support for adding cameras/images with trivial rig/frame to pycolmap reconstruction | Merged; relevant to pycolmap code that constructs reconstructions programmatically |
| [Issue #4046](https://github.com/colmap/colmap/issues/4046) | Jan 23, 2026 | Questions on local pycolmap-cuda12 builds and PyPI wheel timing | Informational; use 4.0.4 wheels from PyPI |
| [Issue #4078](https://github.com/colmap/colmap/issues/4078) | Feb 4, 2026 | `global_mapper` command not recognized on a user build | `global_mapper` only exists in COLMAP 4.0.0+ (released March 15, 2026). Use `colmap mapper` on 3.13. |
| [COLMAP 4.0.3 release](https://github.com/colmap/colmap/releases/tag/4.0.3) | Apr 6, 2026 | Missing global-mapper rotation-averaging / BA option piping; Blackwell GPU PatchMatch empty output; ONNX install issues | Fixed in 4.0.3 |
| [COLMAP 4.0.4 release](https://github.com/colmap/colmap/releases/tag/4.0.4) | Apr 27, 2026 | `AdjustGlobalBundle` crash after aggressive frame filtering; unknown EXIF orientation crash instead of logged error | Fixed in 4.0.4 |

## GLOMAP (standalone — archived March 9, 2026)

| Issue / PR | Date | What broke | Fix / status |
|---|---|---|---|
| [Issue #179](https://github.com/colmap/glomap/issues/179) | Mar 22, 2025 | GPU solver fallback despite CUDA/Ceres present | Requires Ceres 2.3+ with cuDSS for `--GlobalPositioning.use_gpu` and `--BundleAdjustment.use_gpu` |
| [Issue #196](https://github.com/colmap/glomap/pull/196) | 2025 | macOS compilation failure | PR #196 fixed in 1.2.0 |
| [Issue #201](https://github.com/colmap/glomap/pull/201) | 2025 | Rig support missing | Added in 1.2.0 |
| [Issue #204](https://github.com/colmap/glomap/issues/204) | Jul 18, 2025 | GLOMAP reconstruction failed where COLMAP incremental succeeded | No fix path; standalone archived March 2026. Use COLMAP 4.0+ `global_mapper` or `colmap mapper`. |
| [Issue #205](https://github.com/colmap/glomap/issues/205) | Aug 14, 2025 | Global-positioning linear-solver failure | No fix after archive; use COLMAP 4.0+ |
| [Issue #219](https://github.com/colmap/glomap/issues/219) | Nov 13, 2025 | Retriangulation crash with frame/data-id consistency check | No fix after archive; use COLMAP 4.0+ |

## hloc / Hierarchical-Localization

| Issue / PR | Date | What broke | Fix / status |
|---|---|---|---|
| [Issue #360](https://github.com/cvg/Hierarchical-Localization/issues/360) | Earlier | OOM during LightGlue matching on large pair lists | Split pairs into 5k–20k chunks; use `overwrite=False` to resume |
| [Issue #471](https://github.com/cvg/Hierarchical-Localization/issues/471) | Aug 7, 2025 | Demo Colab broken after pycolmap API changes | `ret["inliers"]` → `ret["inlier_mask"]`; update `pycolmap.Image` constructor usage; use hloc master |
| [Issue #475](https://github.com/cvg/Hierarchical-Localization/issues/475) | Sep 1, 2025 | Lower Aachen SuperPoint+NN performance; `estimate_and_refine_absolute_pose` incompatible args | Diagnostic; compare matchers; watch pycolmap API compat |
| [Issue #485](https://github.com/cvg/Hierarchical-Localization/issues/485) | Dec 2, 2025 | Missing `aachen.db` assertion in Aachen example | Dataset/setup issue; verify dataset files |
| [Issue #491](https://github.com/cvg/Hierarchical-Localization/issues/491) | Jan 14, 2026 | M1/MPS OpenMP crash during extraction/matching | Linux A100 is unaffected environment; shows backend-specific fragility |
| [Issue #496](https://github.com/cvg/Hierarchical-Localization/issues/496) | Apr 26, 2026 | LightGlue checkpoint/performance concern on Aachen night subset | Validate LightGlue on your own data; do not assume SuperGlue parity |

## LightGlue

| Issue | Date | What broke | Fix / status |
|---|---|---|---|
| [Issue #160](https://github.com/cvg/LightGlue/issues/160) | May 13, 2025 | SuperPoint CUDA memory growth during long-running batch jobs | Open; monitor if running large batches |
| [Issue #180](https://github.com/cvg/LightGlue/issues/180) | Feb 20, 2026 | ALIKED performance worse with PyTorch / CUDA > 12.4 | Affects ALIKED+LightGlue; SuperPoint+LightGlue unaffected by this report |
| [Issue #181](https://github.com/cvg/LightGlue/issues/181) | 2025 | LightGlue produces fewer matches than SuperGlue | Expected from adaptive pruning; set `depth_confidence=-1, width_confidence=-1, filter_threshold=0.01` for diagnosis |
| [Issue #183](https://github.com/cvg/LightGlue/issues/183) | Apr 2, 2026 | Raco-ALIKED weights support only 9 layers | Do not change `n_layers` for ALIKED model family |

## OpenCV / Fiducial alignment

| Issue | Date | What broke | Fix / status |
|---|---|---|---|
| [opencv-python #1195](https://github.com/opencv/opencv-python/issues/1195) | Jan 28, 2026 | ArUco corner starts upper-left; AprilTag starts bottom-right (both clockwise) | Explicitly normalize corner indexing before building Sim3 correspondences |
