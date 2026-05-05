---
name: publishing-supersplat-webxr
description: Publishes SEM 3D Gaussian Splat scenes as no-install HTTPS URLs renderable in desktop browsers, Quest 3 Browser, Pico 4 Browser, and Apple Vision Pro Safari, with optional WebXR immersive-vr entry. Use when an autonomous agent needs to send a single HTTPS link that opens a SEM digital twin in any modern headset browser without app installation. Defaults to PlayCanvas SuperSplat Viewer (@playcanvas/supersplat-viewer v1.21.0, URL parameters for content, settings, budget, nofx) for the static path and PlayCanvas Engine 2.18.1 for custom viewers (teleport locomotion, hand tracking, in-scene labels, foveation, frame-rate targets). Excludes asset compilation (cat 26 compiling-splat-assets), Quest native APK packaging (cat 26 deploying-quest-spatial-splats), and Unity/Unreal scene logic.
version: 2.0.0
author: Orchestra Research
license: MIT
tags: [WebXR, VR, 3DGS, SOG, LOD, PlayCanvas, SuperSplat, Quest 3, Vision Pro, Pico 4, Safari, HTTPS, Cloudflare Tunnel]
dependencies: [node>=20.19.0, "playcanvas>=2.18.1", "@playcanvas/supersplat-viewer>=1.21.0", caddy>=2.11.0]
---

# Publishing SuperSplat WebXR

Use this skill when the target outcome is: send a URL; open a SEM Gaussian-splat digital twin in a browser or headset; optionally enter WebXR immersive VR; no app install.

**Confirmed versions (May 2026)**:
- PlayCanvas Engine: **v2.18.1** (April 28, 2026) — `npm install playcanvas@2.18.1`; pin exact version; main branch is already 2.19.0-beta.
- SuperSplat Viewer: **v1.21.0** (April 30, 2026) — `npm install @playcanvas/supersplat-viewer@1.21.0`
- SuperSplat Editor: **v2.25.0** (April 28, 2026) — `playcanvas/supersplat`, MIT, live at superspl.at/editor. Not renamed; old URL `playcanvas/super-splat` redirects to `playcanvas/supersplat` (slug cleanup only, no org move).
- Caddy: **v2.11.2** (March 2026)
- cloudflared: **v2026.3.0** (March 2026)
- SuperSplat Editor requires **Node >=20.19.0** (package.json strict; not Node 18).

**Critical corrections vs pre-2026 docs**:
- `supersplat-viewer` package is `@playcanvas/supersplat-viewer` at v1.21.x, NOT v2.25.x (that is the separate SuperSplat editor).
- `GSplatComponent.splatBudget` is deprecated; use `app.scene.gsplat.splatBudget` (scene-level).
- WebGPU renderer flags (`?compute`, `?gpu`, `?gpu-sort`, `?cpu-sort`, `?webgpu`) exist but disable XR — viewer initializes XR only when renderer is WebGL.
- PR #224 (merged Apr 27, 2026) renamed `?cpu`/`?gpu` to `?cpu-sort`/`?gpu-sort` and added `?webgpu`.
- Quest Browser versioning changed at M144: versions are now 144, 144.2, 146.0 (Apr 21, 2026); major number tracks Chromium.
- Use **feature detection** (`navigator.xr.isSessionSupported`) not UA sniffing; Meta explicitly warns against UA detection.

## Quick start

```html
<!-- Stock viewer URL — just send this link. -->
https://twin.lab.example/viewer/index.html?content=/sem/sem.lod-meta.json&settings=/sem/settings.json&budget=0.25&nofx
```

```bash
# Build the viewer static site (Node >=20.19.0 required for supersplat editor; viewer itself: Node >=18)
git clone https://github.com/playcanvas/supersplat-viewer.git
cd supersplat-viewer
npm install
npm run build
# Copy dist/ to your web root
```

```javascript
// Minimal custom viewer — PlayCanvas 2.18.1 (pin exact; avoid 2.19 beta)
import * as pc from 'playcanvas';

const app = new pc.Application(canvas, {
  graphicsDeviceOptions: { antialias: false }
});
app.start();

const splatAsset = new pc.Asset('lab-splat', 'gsplat', { url: '/sem/lab-sem.sog' });
app.assets.add(splatAsset);
await new Promise((resolve, reject) => {
  splatAsset.once('load', resolve);
  splatAsset.once('error', reject);
  app.assets.load(splatAsset);
});

const splat = new pc.Entity('SEM');
splat.addComponent('gsplat', {
  asset: splatAsset,
  unified: true         // global sort + LOD streaming; still beta but recommended
});
app.root.addChild(splat);

// Scene-level budget (deprecated: GSplatComponent.splatBudget)
app.scene.gsplat.splatBudget = 1_500_000;

// GSplatParams properties added PR #8518 (Mar 2026)
// splat.gsplat.alphaClip, .minPixelSize, .antiAlias, .twoDimensional

// XR entry — must be triggered by user gesture
const supportsVR = !!navigator.xr && await navigator.xr.isSessionSupported('immersive-vr');
if (supportsVR) {
  button.addEventListener('click', () => {
    app.xr.start(camera.camera, pc.XRTYPE_VR, pc.XRSPACE_LOCALFLOOR, {
      framebufferScaleFactor: 0.75,
      optionalFeatures: ['hand-tracking', 'bounded-floor']
    });
  });
}
```

## Agent contract

1. **Static publish first**: use stock `@playcanvas/supersplat-viewer` for `.sog`, `.meta.json`, or `.lod-meta.json` content.
2. **Custom viewer only when needed**: use PlayCanvas Engine directly for locomotion, in-scene labels, hand-tracking, or training state machines.
3. **WebGL-first for XR**: avoid `?webgpu`, `?compute`, `?gpu-sort`, `?cpu-sort` in headset XR — these disable the VR button.
4. **HTTPS always**: trusted HTTPS for real headsets (Cloudflare Tunnel or static hosting); `localhost` is enough for desktop.
5. **Feature-detect XR**: use `navigator.xr.isSessionSupported('immersive-vr')`, not UA sniffing; never hard-code controller indices.
6. **splatBudget at scene level**: set `app.scene.gsplat.splatBudget`, not the deprecated component property.
7. **Pin engine at 2.18.1**: main branch is 2.19.0-beta as of May 2026; use exact pin in production.

## Common workflows

### Workflow A: Static SEM `.sog` site with camera bookmarks and trainee labels

`Task Progress`:

- [ ] Build `viewer/` static site from `@playcanvas/supersplat-viewer` (Node >=18), output to `public/viewer/`.
- [ ] Place per-platform SOG profiles under `public/sem/`: `sem.lod-meta.json` (desktop, Vision Pro), `sem-quest.sog`, `sem-pico.sog`, `sem-low.sog`.
- [ ] Author `public/sem/settings.json` with ExperienceSettings v2 schema: `version: 2`, `tonemapping`, named cameras, `annotations[]` for SEM training stations.
- [ ] Add `/index.html` feature-detect router: call `isSessionSupported` then redirect to correct profile URL — do NOT UA-sniff.
- [ ] Serve over HTTPS: Caddy 2.11+ with Cloudflare Tunnel for real headsets, or local Caddy `local_certs` for desktop.
- [ ] Acceptance: Quest Browser 146.0, Pico Browser / Wolvic, Vision Pro Safari, desktop Chrome/Edge load correctly.

Step by step:

1. Build: `npm install @playcanvas/supersplat-viewer@1.21.0 && npm run build`. The package exports viewer HTML/CSS/JS and settings helpers. Do not run `npm install` in end-user paths; bake it into CI.
2. `settings.json` ExperienceSettings v2 schema (PR #831, Mar 2026): `"version": 2`, `"tonemapping": "neutral"`, `"cameras": [{"initial": {...}}]`, `"annotations": [{"position":[x,y,z], "title":"1. Sample stage", "text":"...", "camera":{...}}]`, `"startMode": "annotation"`, `"postEffectSettings": {...}`, `"highPrecisionRendering": false`, `"animTracks": []`. v1 settings auto-migrate.
3. Stock viewer URL parameters: `?content=`, `?settings=`, `?budget=N` (millions), `?nofx`, `?aa`, `?ministats`, `?noui`, `?collision` / `?voxel` (walk-mode collision via GLB), `?noanim`, `?skybox=`, `?poster=`, `?hpr`, `?colorize`, `?fullload`, `?heatmap`. Do NOT pass WebGPU flags in headset XR deployments.
4. Feature-detect profiles for choosing conservative defaults: `budget=0.25&nofx` for Quest 3; `budget=0.15&nofx` for Pico; `budget=0.75&nofx` for Vision Pro; `budget=2.0&ministats` for desktop.
5. DOM/UI overlay caveat: stock viewer annotations are DOM overlays; during immersive WebXR the document is hidden. In-VR labels must be in-scene PlayCanvas billboards, not DOM.

### Workflow B: Quest 3 Browser immersive VR with teleport locomotion

Quest Browser 146.0 (Apr 21, 2026, Chromium M146): adds experimental WebGPU in WebXR, WebXR depth projection, bounded-floor-space fix. Still treat WebGPU+XR as experimental; use WebGL for production splat viewer.

`Task Progress`:

- [ ] Profile defaults: `targetFrameRate: 72`, `framebufferScaleFactor: 0.75`, `fixedFoveation: 1.0`, `app.scene.gsplat.splatBudget = 250_000`, `usePostEffects: false`.
- [ ] Locomotion: teleport-only with blink-fade comfort vignette; snap-turn 30 deg.
- [ ] XR start with `pc.XRSPACE_LOCALFLOOR`, request `bounded-floor` as optional only.
- [ ] In session callback: set `app.xr.fixedFoveation = 1.0`; if `supportedFrameRates` includes 72, call `updateTargetFrameRate(72)`.
- [ ] Input sources via `app.xr.input.on('add', ...)` — never assume controller index 0/1.
- [ ] Acceptance: enter VR from user click, confirm 72 Hz, teleport with both controllers.

Step by step:

1. Use `PlayCanvas XrNavigation` for reference teleport behavior, or implement via `app.xr.input`, `inputSource.getOrigin()`, `inputSource.getDirection()`, and a parent rig entity. (PR #8409 fixed teleport offset in Jan 2026.)
2. Reticle: ground-plane intersection; reject negative `t` and `t > 20 m`.
3. On `select`, run a brief blink-fade (90 ms sine envelope) before `rig.translate(dx, 0, dz)`.
4. PR #8557 (merged Mar 30, 2026): fixed viewport sizing for stereo XR (canvas width vs per-eye width). Use engine >=2.18 for correct stereo sizing.
5. `splatBudget = 250_000` is a lab baseline; profile GPU time and adjust. Quest Browser 146.0 bounded-floor-space fix means `bounded-floor` optional feature is safer than before.

### Workflow C: Vision Pro Safari with hand tracking and HTTPS constraints

Vision Pro uses `immersive-vr`, not AR. `immersive-ar` is confirmed NOT supported on visionOS as of May 2026 (Apple Developer Forums Mar 2026 explicitly confirms; visionOS 26 spatial-web additions do not include WebXR AR).

`Task Progress`:

- [ ] Serve from HTTPS or `localhost` only; launch XR only from a user gesture; no auto-enter.
- [ ] Feature-detect with `isSessionSupported('immersive-vr')` before showing XR button.
- [ ] If iframed, include `allow="xr-spatial-tracking"` on the `<iframe>` element.
- [ ] Profile defaults: `targetFrameRate: 90`, `framebufferScaleFactor: 0.85`, `fixedFoveation: 0.5`, `app.scene.gsplat.splatBudget = 750_000`.
- [ ] Disable graphics antialiasing (`antialias: false`). Do not pass `?aa` or WebGPU flags in production XR.
- [ ] Request `optionalFeatures: ['hand-tracking']` only when needed.
- [ ] Test real-device hand tracking; not testable in simulator.

Step by step:

1. visionOS default WebXR input is transient gaze+pinch; input list may be empty until user pinches. Do not write code that only listens to inputs 0 and 1.
2. Hand tracking: `if (inputSource.hand)` — iterate `hand.joints` for position/rotation/radius; provide fallback gaze interactions for complex poses.
3. Transient pointers: attach `selectstart`/`select`/`selectend` and ray-cast to label hit volumes for highlight/activate.
4. `app.xr.start(camera.camera, pc.XRTYPE_VR, pc.XRSPACE_LOCALFLOOR, { optionalFeatures: ['hand-tracking'] })`.
5. Apply locomotion to a parent rig entity, not the XR camera entity itself (XR session manages camera transform).

## When to use vs alternatives

| Path | Use when | Avoid when |
| --- | --- | --- |
| Stock SuperSplat Viewer URL | Fast URL sharing, simple guided tour, no custom code | Need teleport, hand-tracking UI, in-VR labels, training state machine |
| Custom PlayCanvas Engine viewer | Immersive training, comfort locomotion, in-scene labels, lab affordances | A static URL is sufficient; engineering effort not justified |
| Quest native APK (Spatial SDK) | Offline kiosk, controlled enterprise deployment | A URL is acceptable; web iteration is faster |
| Unity / Unreal | Already have Unity/Unreal content; need state machines, controllers | Browser portability is the priority |
| three.js + GaussianSplats3D | Custom three.js stack | Maintainer notes project no longer actively developed |
| antimatter15/splat | Historical baseline only | SH drops; no WebXR/LOD/publishing support |

## Common issues

- **splatBudget deprecated on component** (2.17+/2.18): `GSplatComponent.splatBudget` is deprecated. Use `app.scene.gsplat.splatBudget`.
- **WebGPU flags disable VR button** (`supersplat-viewer#216`, open Apr 2026): viewer initializes XR only when renderer is WebGL. No merged fix as of May 2026. Use WebGL default in all XR headset deployments.
- **VR shaking/flicker** (`supersplat-viewer#216`): use `unified = true`, lower splat budget, WebGL renderer.
- **Stereo viewport sizing** (engine PR `#8557`, merged Mar 2026): fixed canvas-width vs per-eye-width bug. Use engine >=2.18.
- **WebXR frustum culling single-eye** (engine `#5787`, fixed PR `#8393`, Jan 2026): combined XR frustum now default. Use engine >=2.17.
- **Teleport landing offset** (engine PR `#8409`, Jan 2026): fixed when camera has local XZ offset. Use engine >=2.17.
- **XrInputSource grip crash** (engine PR `#8389`, Jan 2026): fixed TypeError when grip pose unavailable. Use engine >=2.17.
- **Vision Pro antialias** (`engine#7410`): VR only works with `antialias: false`. Open platform risk.
- **Pico browser XR launch failure** (`engine#6045`, fixed `#6181`): use engine >March 2024.
- **Stereo splat viewport split** (`engine#6053`, fixed `#6896`): use engine >August 2024.
- **Edge-FOV label culling on Quest** (`engine#8449`): keep critical labels in central FOV; enlarge UI bounds/custom AABBs.
- **Virtual Desktop PCVR controller input missing** (`engine#8330`): test native Quest Browser; log `app.xr.input.on('add')`; provide gaze fallback.
- **Permissions Policy rejection** (`engine#6692`): serve with `Permissions-Policy: xr-spatial-tracking=(self)`. For iframes add `allow="xr-spatial-tracking"`.
- **Quick tunnel fails with existing config** (cloudflared): if `~/.cloudflared/config.yaml` exists, quick tunnels fail. Move/rename the config file first.
- **URL param renames** (supersplat-viewer PR `#224`, Apr 2026): `?gpu`/`?cpu` renamed to `?gpu-sort`/`?cpu-sort`; `?webgpu` reintroduced. Update any hardcoded URLs.
- **Engine 2.19 beta on main**: as of May 2026 `package.json` on main already shows `2.19.0-beta.0`. Pin `2.18.1` explicitly in `package.json` to avoid silent beta breakage.
- **SuperSplat Editor Node version**: package.json requires Node >=20.19.0, not Node 18. Use Node 20 or 22 LTS for editor builds.
- **GSplatParams new fields** (engine PR `#8518`, Mar 2026): `alphaClip`, `minPixelSize`, `antiAlias`, `twoDimensional` are now valid on `GSplatComponent`. Use engine >=2.18.
- **Wolvic Chromium vs Gecko**: Wolvic 1.2.3 (Chromium) and 1.8.3 (Gecko) are separate APKs (Nov 2025). Chromium variant is the one with WebXR AR module roadmap. Manual sideload requires Developer Mode; no auto-update.
- **immersive-ar on visionOS**: not shipped as of May 2026. A Mar 2026 Apple Developer Forums thread confirms the WebXR AR sample is unsupported even with the experimental Safari flag. Do not gate content on `immersive-ar` for Vision Pro.

## Advanced topics

- `references/serving.md`: Caddy 2.11 `local_certs` for local HTTPS; Cloudflare Tunnel for real-headset public testing; required MIME types (`application/octet-stream` for `.sog`, `application/json` for `.lod-meta.json`); CORS for cross-origin asset hosting.
- `references/playcanvas-api.md`: GSplatComponent (`.ply`, `.sog`, `.meta.json`, `.lod-meta.json`); `unified = true` for global sort + LOD streaming (beta but recommended); `lodBaseDistance`, `lodMultiplier`; scene-level `app.scene.gsplat.splatBudget`; GSplatParams: `alphaClip`, `minPixelSize`, `antiAlias`, `twoDimensional` (PR #8518); renderer enum (`GSPLAT_RENDERER_AUTO`, `RASTER_GPU_SORT`, `COMPUTE`); `app.xr.frameRate`, `app.xr.supportedFrameRates`, `app.xr.fixedFoveation`.
- `references/xr-platforms.md`: Vision Pro Safari quirks (HTTPS, user-gesture, antialias off, no WebGPU flags, real-device hand-tracking only, no immersive-ar); Quest Browser 146.0 profile (72 Hz, foveation 1.0, framebuffer 0.75, budget 0.25, Chromium M146); Pico 4 Browser (Chromium M138 base) / Wolvic 1.8.3 Gecko / 1.2.3 Chromium profile (budget 0.15, validate per-device); desktop WebXR via Chrome/Edge with SteamVR/OpenXR.
- `references/comfort-design.md`: teleport with blink fade, snap turn 30/45 deg, in-scene exit hint, no forced camera motion, no auto XR entry, labels not at far periphery, `?collision` walk-mode (v1.21).
- `references/issues.md`: full upstream PlayCanvas engine and supersplat-viewer issue/PR ledger.

## Resources

- PlayCanvas SuperSplat Viewer — https://github.com/playcanvas/supersplat-viewer — MIT, v1.21.0
- PlayCanvas Engine — https://github.com/playcanvas/engine — MIT, v2.18.1 (main is 2.19.0-beta; pin 2.18.1)
- SuperSplat Editor — https://github.com/playcanvas/supersplat — MIT, v2.25.0, live at superspl.at/editor
- WebXR Device API — https://developer.mozilla.org/en-US/docs/Web/API/WebXR_Device_API
- Apple WebXR on visionOS 2+ — https://developer.apple.com/videos/play/wwdc2024/10066/
- Wolvic — https://wolvic.com — MPL-2.0, Gecko 1.8.3 / Chromium 1.2.3 (Nov 2025)
- Meta Quest Browser release notes — https://developers.meta.com/horizon/documentation/web/browser-release-notes/

URL parameter reference for SuperSplat Viewer (v1.21):

| Param | Effect |
| --- | --- |
| `content=<url>` | URL of `.sog`, `.meta.json`, `.lod-meta.json`, or `.compressed.ply` (default: `./scene.compressed.ply`) |
| `settings=<url>` | URL of `settings.json` ExperienceSettings v2 (default: `./settings.json`) |
| `skybox=<url>` | Skybox asset URL |
| `poster=<url>` | Loading poster image |
| `collision=<url>` / `voxel=<url>` | GLB collision mesh for walk-mode |
| `budget=N` | Visible splat budget in millions |
| `nofx` | Disable post effects (mobile/XR) |
| `aa` | Anti-aliasing (avoid on Vision Pro) |
| `ministats` | Performance overlay (desktop debug) |
| `noui` | Hide built-in UI |
| `noanim` | Disable animations |
| `hpr` | High pixel ratio |
| `colorize` / `heatmap` | Debug overlays |
| `fullload` | Force full LOD load |
| `webgpu` / `compute` / `gpu-sort` / `cpu-sort` | WebGPU renderers — **disable VR button; desktop only** |

Performance targets (skill defaults, not vendor guarantees):

| Platform | Target | Splat budget | Delivery profile |
| --- | --- | --- | --- |
| Quest 3 Browser 146.0 | 72 Hz | ~250k | `budget=0.25&nofx`, WebGL, foveation 1.0, framebuffer 0.75 |
| Vision Pro Safari (visionOS 2+) | 90 Hz | ~500k–1M | WebGL, antialias off, streamed LOD, foveation 0.5 |
| Pico 4 Browser / Wolvic | 72 Hz class | ~150k | `budget=0.15&nofx`, no required hand tracking |
| Desktop | monitor-rate | 2M+ | `ministats`, streamed LOD, WebGPU outside XR OK |

## Caddy + Cloudflare Tunnel serving recipe

```caddyfile
:8080 {
    root * /srv
    encode zstd gzip
    file_server

    header {
        Permissions-Policy "xr-spatial-tracking=(self)"
        X-Content-Type-Options "nosniff"
        Cross-Origin-Resource-Policy "same-origin"
    }

    @sog path *.sog
    header @sog Content-Type "application/octet-stream"

    @lod path *.lod-meta.json *.meta.json
    header @lod Content-Type "application/json"
}
```

```yaml
# docker-compose.yml
services:
  web:
    image: caddy:2-alpine
    volumes:
      - ./public:/srv:ro
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
    ports:
      - "8080:8080"
  tunnel:
    image: cloudflare/cloudflared:latest
    depends_on: [web]
    command: tunnel --no-autoupdate --url http://web:8080
```

For cross-origin asset hosting, add CORS headers on the asset origin, not the viewer origin.

## Acceptance test checklist

Desktop:
- [ ] `/viewer/index.html` loads `sem.sog` and `sem.lod-meta.json`.
- [ ] `settings.json` ExperienceSettings v2 annotations and camera bookmarks work.
- [ ] No CORS or MIME errors for `.sog`/`.json`/chunks.

Quest 3 Browser (146.0 / Chromium M146):
- [ ] URL opens over trusted HTTPS.
- [ ] Enter VR appears only after user gesture (`isSessionSupported` feature-detect, not UA sniff).
- [ ] `immersive-vr` starts; 72 Hz target attempted via `updateTargetFrameRate`.
- [ ] Fixed foveation set when supported.
- [ ] Teleport works with both controllers via event-driven input sources.
- [ ] Labels remain in-scene (not DOM-only).

Vision Pro Safari (visionOS 2+):
- [ ] HTTPS or `localhost` origin.
- [ ] XR launch requires user click/pinch.
- [ ] `antialias: false`; no `?webgpu`/WebGPU flags in URL.
- [ ] Hand-tracking permission prompt appears only when requested.
- [ ] Real-device hand tracking tested (not simulator).
- [ ] `immersive-ar` path NOT implemented (not shipped in visionOS as of May 2026).

Pico 4 / Wolvic:
- [ ] Tested in both PICO Browser and Wolvic (Chromium APK preferred for WebXR).
- [ ] `immersive-vr` feature-detected, `local-floor` used without requiring `bounded-floor`.
- [ ] Low profile (`~150k` budget) loads.

The practical rule: publish the stock viewer for fast URL sharing; ship a custom PlayCanvas Engine viewer (pinned 2.18.1) when the lab needs immersive training controls.
