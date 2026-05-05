# Upstream issues ledger — publishing-supersplat-webxr

Last updated: 2026-05-05. Validated from GitHub and ChatGPT authoritative pre-fetch.

| Issue / PR | URL | Symptom | Fix or workaround |
| --- | --- | --- | --- |
| `playcanvas/engine#6045` | https://github.com/playcanvas/engine/issues/6045 | PICO Neo 3 Browser WebXR stopped launching after engine update. | Fixed by `#6181` (workaround for browsers missing `XRSession.enabledFeatures`). Use engine >March 2024. |
| `playcanvas/engine#6053` | https://github.com/playcanvas/engine/issues/6053 | Gaussian splats rendered incorrectly in stereoscopic WebXR; viewport split per eye. | Fixed by `#6896`. Use engine >August 2024. |
| `playcanvas/engine#7404` | https://github.com/playcanvas/engine/issues/7404 | WebXR + WebGPU experimental / under investigation. | Default to WebGL in headset XR. Do not use `?webgpu`, `?compute`, `?gpu-sort`, `?cpu-sort` in production. |
| `playcanvas/engine#7410` | https://github.com/playcanvas/engine/issues/7410 | Vision Pro WebXR: VR only works with antialiasing disabled. | Set `antialias: false`; do not pass `?aa`. Open platform risk. |
| `playcanvas/engine#5787` / PR `#8393` | https://github.com/playcanvas/engine/issues/5787 | WebXR frustum culling used single-eye frustum; objects culled at right-eye edge. | Fixed January 21, 2026 (PR #8393: combined XR frustum). Use engine >=2.17. |
| `playcanvas/engine PR#8389` | https://github.com/playcanvas/engine/pull/8389 | TypeError in VR when grip pose unavailable (`getPosition()`/`getRotation()` crash). | Fixed January 20, 2026. Use engine >=2.17. |
| `playcanvas/engine PR#8409` | https://github.com/playcanvas/engine/pull/8409 | Teleport landing offset when camera has local XZ offset (closes #8408). | Fixed January 25, 2026. Use engine >=2.17. |
| `playcanvas/engine#8330` | https://github.com/playcanvas/engine/issues/8330 | Quest 3 via Virtual Desktop: headset view OK but controller input sources missing. | Test native Quest Browser separately from PCVR. Log `app.xr.input.on('add')`; provide gaze fallback. |
| `playcanvas/engine#8449` | https://github.com/playcanvas/engine/issues/8449 | Edge-FOV label culling on Quest Browser after combined-frustum fix. | Keep critical labels in central FOV; enlarge UI bounds/custom AABBs. |
| `playcanvas/engine PR#8557` | https://github.com/playcanvas/engine/pull/8557 | Stereo XR viewport used full canvas width instead of per-eye width; broken GSplat stereo. | Fixed March 30, 2026. Use engine >=2.18. |
| `playcanvas/engine#6692` | https://github.com/playcanvas/engine/issues/6692 | DOM exception when Permissions Policy blocks WebXR. | Serve with `Permissions-Policy: xr-spatial-tracking=(self)`. Add `allow="xr-spatial-tracking"` on iframes. |
| `playcanvas/supersplat-viewer#216` | https://github.com/playcanvas/supersplat-viewer/issues/216 | VR shaking/flicker in immersive session; no VR button when WebGPU enabled on Vision Pro. | OPEN (Apr 2026). Use WebGL default, `unified = true`, lower budget. Do not use WebGPU flags in XR. |
| `playcanvas/supersplat-viewer#8` | https://github.com/playcanvas/supersplat-viewer/issues/8 | Quest 3 Browser splat performance; missing XR controls (scale, snap turn, exit UI). | Publish Quest profile: `budget=0.25&nofx`, foveation, framebuffer 0.75, teleport, snap turn, exit UI. |
| `playcanvas/supersplat-viewer#27` | https://github.com/playcanvas/supersplat-viewer/issues/27 | VR/AR camera: bad initial height, movement beyond teleport, no authoring for ground/start position. | OPEN (May 2025). Use custom PlayCanvas Engine viewer for precise locomotion control. |
| `playcanvas/supersplat-viewer PR#218` | https://github.com/playcanvas/supersplat-viewer/pull/218 | Chrome WebGPU frame pacing issues on macOS high-refresh displays. | Fixed April 16, 2026. Not XR-specific but affects renderer stability. |
| `playcanvas/supersplat-viewer PR#222` | https://github.com/playcanvas/supersplat-viewer/pull/222 | Compute renderer not supported. | Merged April 22, 2026: added `?compute`, `?gpu`, `?cpu` renderer flags (WebGL XR still works). |
| `playcanvas/supersplat-viewer PR#224` | https://github.com/playcanvas/supersplat-viewer/pull/224 | `?cpu`/`?gpu` URL params renamed; `?webgpu` missing. | Merged April 27, 2026: renamed to `?cpu-sort`/`?gpu-sort`, reintroduced `?webgpu`. Update all hardcoded URLs. |
| `playcanvas/supersplat-viewer PR#229` | https://github.com/playcanvas/supersplat-viewer/pull/229 | No debug overlay for GLB collision meshes. | Merged in v1.21.0: adds `?collision` debug overlay for navigation mesh validation. |
| `playcanvas/supersplat#838` | https://github.com/playcanvas/supersplat/issues/838 | Standalone VR/mobile splat sorting and performance on Pico-class hardware. | Use LOD streaming, reduced budgets, WebGL fallback, no post effects. |

## Vision Pro Safari quirks (Apple WWDC24 guidance)

- Serve from HTTPS or `localhost` only.
- Launch XR only from a visible user-gesture button.
- Do not auto-enter XR on page load.
- If iframed, include `allow="xr-spatial-tracking"`.
- Avoid WebGPU viewer flags in production XR.
- Disable graphics antialiasing for splat XR.
- Request hand tracking only when needed; if granted, draw hands manually.
- Do not depend on DOM labels inside the immersive session (document is hidden).
- Test actual hand tracking on a real Vision Pro, not the simulator.

## Quest 3 Browser quirks

- Treat Quest Browser as the primary Android standalone WebXR target.
- Feature-detect `navigator.xr` and `isSessionSupported('immersive-vr')`.
- Do not depend on origin-trial code paths unless a managed enterprise build requires it.
- Default profile: `budget=0.25&nofx`, framebuffer scale 0.75, fixed foveation 1.0, 72 Hz.

## Pico 4 Browser / Wolvic quirks

- Test both PICO Browser and Wolvic (supports Pico Neo3, Pico 4, Pico 4E; Pico 4 Ultra has full-body tracking in PICO Browser).
- WebXR support can lag; use a recent engine. Do not assume Quest Browser feature parity.
- Keep `bounded-floor` optional, not required.
- Avoid mandatory hand tracking on base Pico 4.
- Default profile: `budget=0.15&nofx`, simplest shaders.
- Wolvic 2025 release notes: Pico 4 Ultra support, passthrough fix for newer PICO OS, hand-tracking fixes, WebXR AR-module support in Chromium Wolvic.
