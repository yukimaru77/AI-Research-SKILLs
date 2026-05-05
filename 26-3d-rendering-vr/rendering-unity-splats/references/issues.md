# Known Issues and PRs — aras-p/UnityGaussianSplatting

Data sourced from Deep_thinker research, May 5, 2026. All issue/PR numbers refer to https://github.com/aras-p/UnityGaussianSplatting.

## VR and stereo rendering

| Issue / PR | Date | Status | Summary |
|------------|------|--------|---------|
| PR #146 | Merged Nov. 28, 2024 | Merged (v1.0.0) | Upstreamed ninjamode VR support. URP + OpenXR + Multi-Pass recommended. Tested on PC SteamVR, Varjo Aero, Quest 3/Pro via Link and standalone. Eye-center sorting was NOT ported from ninjamode fork. |
| Issue #201 | Sep. 24, 2025 | Open | Unity 6 / OpenXR Meta Quest Multi-view / instancing artifacts; stereo rendering broken in Single-Pass Instanced / Multi-view mode. Multi-Pass works but has performance cost. Use Multi-Pass. |
| Issue #17 | Oct. 5, 2023 | Historical | Single Pass Instanced did not show splats; URP left/right eye reversed. Older background context. |

## Quest standalone / Android

| Issue / PR | Date | Status | Summary |
|------------|------|--------|---------|
| Issue #151 | Dec. 10, 2024 | Closed not planned | Quest 3 standalone builds: splats sticking to head movement. |
| Issue #191 | Aug. 4, 2025 | Closed not planned | Unity 6.1 + Android/Vulkan + URP build errors; wave ops and Render Graph execution failures. |
| Issue #205 | Oct. 23, 2025 | Closed not planned | Quest 3 build shows black screen / heavy lag after updating plugin. |
| Issue #207 | Nov. 12, 2025 | Closed as dup (#205) | Quest 2 standalone 1–5 FPS; Editor and PCVR smooth. Duplicate of #205. |
| Issue #112 | Apr. 8, 2024 | Historical | Android/Vulkan on Lenovo A3 and Quest 3: sparse shimmering after sorting; no-sort shows unsorted but present splats. |
| Issue #26 | Oct. 11, 2023 | Historical | Quest standalone APK on GLES3 had shader errors; Quest Link PC path worked. |
| Issue #93 | Feb. 8, 2024 | Closed not planned | URP + VR/Oculus errors involving invalid wavebasic kernel. |

**Upstream stance**: All four major 2024–2025 Quest standalone issues are "closed not planned". The maintainer does not officially support Quest standalone. PCVR (Quest Link, SteamVR) is the supported VR path.

## Render pipeline

| Issue / PR | Date | Status | Summary |
|------------|------|--------|---------|
| PR #150 | Merged Dec. 10, 2024 | Merged (v1.1.0) | URP Unity 6 Render Graph migration. Older URP renderer pass path was obsolete in Unity 6. URP now requires Unity 6+ with Render Graph Compatibility Mode off. |

## Asset format and import

| Issue / PR | Date | Status | Summary |
|------------|------|--------|---------|
| PR #161 | Merged Jan. 30, 2025 | Merged (v1.1.0) | Added Scaniverse SPZ input reading. |
| Issue #163 | Fixed v1.1.1 | Fixed | Scaniverse SPZ rotation values were incorrect. Fixed in v1.1.1 release. |
| Issues #172, #170 | Fixed v1.1.1 | Fixed | Postshot-style PLY files failed to import. v1.1.1 broadened PLY compatibility to handle PLY files that don't exactly match the original 3DGS paper format. |
| Issue #165 | Fixed v1.1.1 | Fixed | Non-binary PLY files gave unhelpful errors. v1.1.1 adds a clearer error message. |
| Issue #192 | Aug. 4, 2025 | Open (no merged fix) | SPZ v2 rotation quantization changed; existing SPZ reader produces wrong rotations for v2 files. No merged fix as of May 2026. Workaround: use PLY or SPZ v1. |

## Inspector and editor

| Issue / PR | Date | Status | Summary |
|------------|------|--------|---------|
| Issue #153 | Fixed v1.1.0 | Fixed | Dragging a .asset into GaussianSplatRenderer inspector stopped working. |
| Issue #156 | Fixed v1.1.0 | Fixed | Splat sorting did not correctly respect Render Order. m_RenderOrder now works. |

## Summary: what to avoid

- DX11: unsupported, README explicit.
- URP on Unity 2022.3: unsupported, requires Unity 6+.
- Single-Pass Instanced / Multi-view VR: broken (issue #201), use Multi-Pass.
- Quest standalone production: all issues closed not planned; use `deploying-quest-spatial-splats` instead.
- SPZ v2 files: no fix merged yet (issue #192); use PLY or SPZ v1.
