# Upstream issues ledger — compiling-splat-assets

Verified May 5, 2026 via Deep_thinker research against GitHub issue pages, release notes, and official docs. Real issue numbers only; none invented.

## SplatTransform / SOG / PlayCanvas Engine

| Ref | State | Summary | Fix / Workaround |
|-----|-------|---------|-----------------|
| `playcanvas/splat-transform#20` | Closed | SOGS spherical harmonics wrong in some cases; opened Jul 22, 2025. SH artifacts in legacy SOGS output. | Use SplatTransform 2.x + SOG v2. Visually compare PLY vs SOG for color-critical scenes; keep SH0-only fallback. |
| `playcanvas/splat-transform#38` | Closed via #41 | SOG v2 proposal: replace PLAS with Morton ordering; add codebooks for scales/SH0/SHN; simplified meta.json; bundled `.sog` ZIP format. | Always use `--morton-order` before SOG packaging. Target SOG v2 format only. |
| `playcanvas/splat-transform#86` | **Open** | "Document lod format" — LOD manifest schema (lod-meta.json / octree) is tool-defined, not publicly documented. | Do not hand-author `lod-meta.json`; generate with SplatTransform and pin version in provenance. |
| `playcanvas/splat-transform#187` | **Open** (Mar 2026) | High `-C` (lod-chunk-count) produces too few large chunks and sparse areas with no higher-LOD chunks. | Tune `-C` down (e.g., 256 instead of 512) for SEM-scale scenes; verify LOD coverage by inspecting chunk distribution. |
| `playcanvas/engine#7789` | Closed | SOGS rendering with SH could be up to 50% slower on weaker devices due to random SH palette access / GPU cache misses. | Closed by engine#7796. |
| `playcanvas/engine#7796` | Merged Jun 30 2025 | PR: "Add fast render path for SOGS spherical harmonics." Evaluates 64K SH values once per frame using camera Z direction; adds `highQualitySH` flag defaulting false. Example: Pixel 7 Pro GPU time 45 ms → 34 ms. | Use engine builds containing #7796. Enable `highQualitySH` only if needed. For mobile/WebXR prefer SH0/SH1 or streamed LOD when frame time spikes. |
| `playcanvas/engine#8191` | Closed | Toggling `camera.enabled` in a Splat LOD scene leaked ~7–30 MB VRAM per toggle (leaked `intervalsTexture`/`intervalsData`). | Closed by engine#8210, included in PlayCanvas Engine v2.14.0 (Dec 4 2025). Update engine; avoid camera enable/disable churn in LOD scenes. |
| `playcanvas/engine#8210` | Merged (in v2.14.0) | PR: "Improvements and fixes to streaming LOD gsplat being destroyed." Fixes VRAM leak from #8191; also includes GSplat streaming LOD memory optimization. | Use engine >=2.14.0. |

## Niantic SPZ

| Ref | State | Summary | Fix / Workaround |
|-----|-------|---------|-----------------|
| `nianticlabs/spz#14` | **Open** (tracker) | "Specify coordinate system for loading/saving" — original SPZ format did not define coordinate conventions. Docs now substantially address this. | Always set `PackOptions.from_coord` and `UnpackOptions.to_coord`. SPZ internal = RUB; PLY = RDF; GLB = LUF; Unity = RUF. |
| `nianticlabs/spz#22` | **Open** (no upstream fix as of May 2026) | Packed alpha 0 or 255 maps through `invSigmoid` to -Inf / +Inf. Source still has `invSigmoid(alpha / 255.0f)` in unpacking path. No public PR or fork fix found. | Clamp pre-sigmoid logit alphas to `[-13.8, 13.8]` (equivalent to clamping linear opacity to `[1e-4, 1-1e-4]`) before calling `save_spz`. In Python: `cloud.alphas[:] = cloud.alphas.clip(-13.8, 13.8)`. |
| `nianticlabs/spz#56` | **Open** | Quaternion round-trip drift: `save_spz` → `load_spz` → `save_spz` can produce different component values. SPZ uses quantized smallest-three encoding. q and -q represent the same rotation. | Compare rotations by normalized rotation matrix or angular error tolerance, not raw component equality. |
| `nianticlabs/spz#58` | **Open** | PLY load path had a `numPoints > 10 * 1024 * 1024` guard that rejects very large scans. Note: this is the PLY loader guard, not the SPZ format limit; SPZ loading itself does not enforce a max point count. | For >10M Gaussian scans, tile or LOD-stream rather than loading as monolithic PLY. Do not patch the guard in production builds. |
| `nianticlabs/spz#66` | **Open** | Missing-attribute support requested for dynamic 3DGS deltas; no implementation. | Treat SPZ as full-frame static cloud format; store dynamic/delta data in a sidecar format. |
| `nianticlabs/spz#68` | Open | Python import failure in fresh environments. | Build from GitHub source; run `python -c "import spz"` as install gate. Pin Python 3.11 / 3.12 if Python 3.13 packaging fails. |
| `nianticlabs/spz#70` | **Open** | Windows Python build failure: missing ZLIB and `.lib` naming collision with MSVC. Workaround in issue body: install zlib via vcpkg, pass `CMAKE_TOOLCHAIN_FILE`, rename static library output. | Use Linux Docker for CI builds. On Windows: `vcpkg install zlib`, pass `CMAKE_TOOLCHAIN_FILE`, rename `zlib.lib` / `zlibstatic.lib` as needed. |

## Coordinate / quaternion conventions

| Convention | Frame | Notes |
|------------|-------|-------|
| PLY (Inria/gsplat) | RDF (right-down-forward) | Verify per trainer; nerfstudio may differ |
| SOG | RH: x-right, y-up, z-back | Right-handed, same as OpenGL viewer |
| SPZ internal | RUB (right-up-back) | Always set Pack/UnpackOptions |
| GLB / glTF | LUF (left-up-forward) | glTF spec Y-up, right-handed = LUF |
| Unity | RUF (right-up-forward) | Unity left-handed, +Z forward |
| Quaternion field order | Inria PLY: `rot_0..rot_3` often **wxyz** | SPZ Python, KHR_gaussian_splatting use **xyzw** |

Always convert quaternion field order explicitly with a unit test before writing custom loaders.

## SH degree cross-format reference

| SH degree | SOG `shN.bands` | SPZ AC coeffs/Gaussian | SplatTransform `--filter-harmonics` |
|-----------|-----------------|------------------------|--------------------------------------|
| 0 | (omitted) | 0 | 0 |
| 1 | 1 | 9 | 1 |
| 2 | 2 | 24 | 2 |
| 3 | 3 | 45 | 3 |
| 4 | (n/a in SOG) | 72 | (n/a; SPZ v4 only) |

KHR_gaussian_splatting requires SH degree 0 and makes higher-order optional (separate named attributes per degree+coeff).

## SOG v2 format summary

A bundled `.sog` is a ZIP archive. Files (verified against PlayCanvas spec):

| File | Required | Contents |
|------|----------|----------|
| `meta.json` | Yes | Schema: version (2), asset.generator, count, antialias, means.{mins,maxs,files}, scales.{codebook,files}, quats.{files}, sh0.{codebook,files}, shN.{count,bands,codebook,files} |
| `means_l.webp` | Yes | Lower 8 bits of quantized Gaussian positions (lossless WebP) |
| `means_u.webp` | Yes | Upper 8 bits of quantized Gaussian positions (lossless WebP) |
| `scales.webp` | Yes | Quantized scale values (lossless WebP) |
| `quats.webp` | Yes | Smallest-three quaternion encoding (lossless WebP) |
| `sh0.webp` | Yes | DC color (SH degree 0) (lossless WebP) |
| `shN_centroids.webp` | Optional | VQ centroid byte triplets → 256-entry scalar codebook |
| `shN_labels.webp` | Optional | 16-bit label per Gaussian indexing centroid (up to 65,536 centroids) |

SH encoding uses two-level VQ: Gaussian → 16-bit centroid label → centroid byte triplets → 256-entry float codebook. Number of centroids is variable (1..65,536), not fixed.

Use **lossless WebP only** — lossy WebP or PNG would corrupt packed numerical values.

## Quest 3 150k splat limit source

**URL**: https://developers.meta.com/horizon/documentation/spatial-sdk/spatial-sdk-splats/

Page updated: Nov 10, 2025. Section: "Limitations" and "Best practices."

Exact wording: "For performance, avoid using Gaussian splats with a splat count greater than 150k." (Best practices) and "If the splat takes a long time to load or performs poorly, use an optimized splat, preferably one that's less than 150k splats in the .spz format." (Troubleshooting)

This is a **performance advisory**, not a hard loader cap. Exceeding 150k is technically possible but load time and runtime performance are explicitly warned against; Meta does not commit to acceptable reduced-frame-rate behavior above 150k.

Additional constraints from the same page: splats only on Quest 3 and Quest 3S; only one splat rendered at a time; supported formats are `.ply` and `.spz`.

## KHR_gaussian_splatting status (May 2026)

Status: **Release Candidate**. Khronos announced RC Feb 3 2026; expected Q2 2026 ratification but no confirmation found by May 5 2026. Not in the ratified Khronos extension registry.

Khronos announcement: https://www.khronos.org/blog/khronos-releases-khr-gaussian-splatting-extension-for-gltf
Spec: https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_gaussian_splatting

Attribute naming: all attributes use the `KHR_gaussian_splatting:` prefix except standard `POSITION`. Kernel `"ellipse"` is the only one defined in the base extension. ColorSpace values: `"srgb_rec709_display"`, `"lin_rec709_display"`.
