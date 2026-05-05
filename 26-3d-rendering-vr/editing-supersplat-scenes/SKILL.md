---
name: editing-supersplat-scenes
description: Cleans, crops, inspects, annotates, and packages already-trained SEM 3D Gaussian Splat scenes for trainee authoring using PlayCanvas SuperSplat Editor v2.25.0 (web app / PWA). Use when lab staff need to remove floaters/noise, set named camera bookmarks for guided tours, annotate SEM components, generate trainee walkthroughs, export SOG / HTML viewers / screenshots for SOPs, and run headset QA — without crossing into reconstruction, segmentation, or articulation. Decimation and batch conversion belong to the SplatTransform CLI, not the editor.
version: 2.0.0
author: Orchestra Research
license: MIT
tags: [SuperSplat, PlayCanvas, 3DGS, SOG, Authoring, QC, Editor, Annotations, Camera Bookmarks, WebXR, VR, SEM]
dependencies: [supersplat-editor>=2.25.0, "@playcanvas/splat-transform>=2.0.3", playcanvas>=2.17.0]
---

# Editing SuperSplat Scenes

Turn raw 3DGS output into SEM training content: "start here," "look at this component," "wrong alignment example." The skill covers cleaning, cropping, named-camera authoring, annotation, and export. It explicitly stops short of reconstruction, segmentation, articulation, batch decimation, and automatic SEM interpretation.

**Primary tool**: `playcanvas/supersplat` SuperSplat Editor v2.25.0 (commit `8189616`, released Apr 28, 2026) — browser-based web app and installable PWA, MIT. No Electron desktop build exists. No editor-side CLI or scripting API exists; automation is handled by the separate `@playcanvas/splat-transform` CLI.

**SuperSplat Studio** (Feb 2026) is a distinct hosted authoring app for published splats (annotations, post effects, tone mapping). It is not this editor and is out of scope here.

## Quick start

```text
# 1. Open https://superspl.at/editor  (or self-hosted build) and drag-drop sem.ply.
# 2. Use Box / Sphere / Brush selection tools to isolate and delete background noise.
# 3. Use the Data Panel histogram (opacity, scale) to identify and delete floater clusters.
# 4. Add cameras: Camera tool > "Sample stage", "Region of interest", "Detector shadow zone".
# 5. Add annotations: position + title + body + per-annotation camera pose.
# 6. Export: SOG (browser delivery), optimized .ply (engine), HTML viewer (one-file SOP).
# 7. QA: open exported viewer URL on Quest 3 Browser / Vision Pro Safari.
```

## Skill contract

Inputs:

- A trained 3DGS `.ply` (one full SEM scan or a merged scene from `cat 26 compiling-splat-assets`).
- Lab annotation copy: station names, SOP descriptions, hazard callouts.
- A trainee profile: target headset(s), preferred SH budget, comfort settings.

Outputs:

- A cleaned `.ply` and an optimized `.sog`.
- A SuperSplat `settings.json` (v2 schema) with named cameras and annotations.
- An HTML viewer export (single-file or ZIP bundle) and screenshots for SOPs.
- A QA log of headset smoke-tests (Quest 3 Browser, Vision Pro Safari, Pico 4 Browser, desktop).

Non-negotiable gates:

1. Non-destructive: archive original `.ply`; export edits as new files.
2. Crops and floater deletions must be reviewed against a high-resolution reference image.
3. Annotations live in `settings.json` `annotations[]`; they are NOT semantic segmentation labels (cat 24).
4. Decimation/LOD belongs to `@playcanvas/splat-transform` CLI, not the editor UI (editor issue #702 open as of May 2026).
5. Final exports must be tested on at least one headset before sign-off.

## Selection tools reference

SuperSplat v2.25.0 ships 8 selection tools. All 2D tools support **replace / add / remove** modifiers.

| Tool | Shortcut | Notes |
| --- | --- | --- |
| Picker | P | Click single splat |
| Lasso | L | Freehand 2D region |
| Polygon | G | Click vertices to close polygon |
| Brush | B | Paint with circular brush; `[` / `]` resize |
| Flood | F | Select connected region by proximity |
| Eyedropper | E | Select by appearance similarity |
| Sphere | S | 3D sphere in world space |
| Box | X | 3D axis-aligned box |

After selecting, press **Delete** to remove splats. Use **Ctrl+Z** to undo.

## Common workflows

### Workflow A: clean noise, crop background, remove floaters

Task Progress:

- [ ] Open `sem.ply` in SuperSplat Editor (drag-drop or File > Open).
- [ ] Open the Data Panel; inspect opacity, scale, and position histograms; drag-select low-opacity outlier range to highlight floaters.
- [ ] Use Box selection aligned to the SEM stage to crop background; preview before deleting.
- [ ] Use Sphere or Brush selection to remove specific floater clusters; use add/remove modifiers.
- [ ] Review selection against a reference image; toggle visibility to verify no SEM features are lost.
- [ ] Export `sem_clean.ply` (File > Export > PLY); optionally export compressed `.compressed.ply`.
- [ ] Record the action sequence in a sidecar `edits.json` for lab traceability.

Step by step:

1. **Load**: SuperSplat handles `.ply`, `.compressed.ply`, `.sog`, `.splat`, `.lcc`. For SOG inputs, the editor reads them natively.
2. **Histogram inspection**: the Data Panel visualizes positions, scale, RGB/HSV, opacity, distance, volume, and surface area. Click-drag on histogram bars to range-select a distribution bucket — useful for isolating very-low-opacity floaters or anomalously large splats.
3. **Box crop**: align the box to the SEM stage boundary; commit only after toggling the preview toggle a few times to confirm SEM features inside the box survive.
4. **Floater removal**: Brush and Flood tools work well for diffuse background splats. Use Flood on an isolated floater cluster; adjust threshold if the flood bleeds into real structure.
5. **Decimation is not available in the editor UI** (open issue #702, Nov 2025). For mobile LOD variants, delegate to SplatTransform: `splat-transform input.ply output.ply --decimate 50%`.
6. **Save**: export `.ply` for archival; export `.sog` for fast browser QA.

### Workflow B: author camera bookmarks and trainee annotations

Task Progress:

- [ ] Identify SEM training stations: Sample stage, Region of interest, Detector shadow zone (or lab-specific).
- [ ] For each station, position the editor camera, then save a named camera via the Cameras panel.
- [ ] Add Annotations at landmark positions; each annotation gets a position, title, body text, and per-annotation camera pose.
- [ ] Set `startMode: "annotation"` so trainees enter the tour at station 1.
- [ ] Choose `tonemapping: "neutral"` and conservative grading (slight contrast, light desaturation, subtle vignette).
- [ ] Export `settings.json` v2 alongside the SOG; verify v1 auto-migration if importing old projects.

Step by step:

1. **Cameras**: each `cameras[].initial` has `position`, `target`, `fov`. Use FOV 38–55 for SEM close-ups, 60+ for room-scale anchors. Middle-mouse click focuses the camera on the clicked splat (PR #870, merged Apr 23, 2026 — Blender-style MMB controls).
2. **Annotations**: v2 schema uses `annotations[].{position, title, text, camera.initial}`. DOM-based; visible in browser viewer but not as in-scene billboards inside WebXR — see Common Issues.
3. **Background**: keep dark (e.g. `[0.005, 0.005, 0.006]`) for SEM contrast; neutral tonemap preserves false-color accuracy.
4. **Post effects**: mild sharpness (~0.25), light grading contrast (~0.08), saturation −0.15 for SEM color restraint, subtle vignette 0.18. **Disable bloom for SEM** — bloom amplifies SEM bright-spot artifacts.
5. **Project file**: save the full session as `.ssproj` (contains app settings, timeline settings, and the uncompressed PLY data) for future re-editing without re-importing the PLY.
6. **Acceptance**: open exported viewer; verify each annotation transitions to its camera pose without overshoot.

### Workflow C: export deployable artifacts (SOG, HTML, screenshots)

Task Progress:

- [ ] Export SOG (`.sog`) for `publishing-supersplat-webxr`.
- [ ] Export HTML self-contained viewer (single `.html` or `.zip`) for offline SOP attachments.
- [ ] Export screenshots per camera bookmark for static SOP documents (supports current / HD / QHD / 4K / custom, transparent background).
- [ ] For large scenes needing LOD, delegate decimation to SplatTransform CLI (not the editor).
- [ ] Run headset QA: Quest 3 Browser, Vision Pro Safari, Pico 4 Browser.
- [ ] Archive: `sem_clean.ply`, `sem.sog`, `settings.json`, `edits.json`, screenshots, QA log.

Step by step:

1. **SOG export**: the editor uses SplatTransform 2.x for export (PR #876, merged Apr 27, 2026). Choose SH degree per target: SH0 for Quest, SH2 for desktop/Vision Pro. Verify output with `unzip -l sem.sog`.
2. **HTML viewer**: exports a self-contained `.html` or `.zip` with an embedded viewer; useful for emailing a single attachment to a remote reviewer. Choose HTML vs ZIP in the export dialog.
3. **Screenshots**: set resolution before exporting; SOP-quality images need HD or 2× resolution. Transparent background option available for compositing into SOP documents.
4. **Video export**: Timeline-based video export supports MP4/WebM/MOV/MKV, frame rate, bitrate, and frame range — useful for SOP screencasts.
5. **Streamed LOD**: not authored in SuperSplat Editor; build via SplatTransform per `compiling-splat-assets` Workflow C.
6. **Headset QA**: open the SOG via `publishing-supersplat-webxr` URL on each target; record FPS, comfort, label legibility.

## When to use vs alternatives

| Path | Use when | Avoid when |
| --- | --- | --- |
| SuperSplat Editor (default) | Interactive clean / crop / annotate / camera-author / export | Need scripted CI conversion or decimation (use SplatTransform CLI) |
| SplatTransform CLI | Reproducible CI conversion, batch jobs, LOD packaging, decimation | Interactive selection, annotation authoring |
| `compiling-splat-assets` | Programmatic conversion, multi-platform variants | Authoring SOPs, annotations, camera bookmarks |
| `publishing-supersplat-webxr` | Distribution as a URL | Authoring stage |
| SuperSplat Studio | Post-publish annotation/hotspot editing on superspl.at-hosted scenes | Raw PLY editing, lab-local files |
| Photoshop / Blender | Mesh-style editing | Splat-native editing |

## Common issues

- **Decimate not in editor UI**: editor-side decimation is an open feature request (issue #702, Nov 2025). Use `splat-transform input.ply output.ply --decimate 50%` for mobile LOD variants.
- **Floater filter (SplatTransform) erases small SEM features**: defaults are world-unit dependent; tune `--size` after `--scale`. The editor's histogram-based selection is safer for targeted removal.
- **Annotation positions drift after re-cropping**: re-author annotations after destructive crops; positions are stored in the post-crop frame.
- **`settings.json` v1 vs v2**: v2 is current; v1 auto-migrates but verify camera/annotation field shape after migration.
- **Background bloom amplifies noise**: disable bloom for SEM; bloom blows out SEM bright spots.
- **DOM-based annotations invisible inside WebXR**: `settings.json` annotations are DOM/UI overlays visible in the browser viewer but not in WebXR headset mode. For in-VR labels, build in-scene billboards in a custom PlayCanvas viewer (`publishing-supersplat-webxr` Workflow A).
- **HTML viewer file size**: large for complex scenes; prefer SOG + URL distribution for headset deliveries.
- **Screenshots low-res**: set HD / QHD / 4K in the screenshot export dialog before capturing; SOP-quality images need at least HD.
- **SH lossy compression in SOG**: SOG is lossy by design; for color-critical SEM scenes, keep an SH0-only fallback or archive the raw `.ply`.
- **No desktop/Electron app**: SuperSplat is a PWA; install via browser "Add to Home Screen" for offline-capable desktop shortcut. No native installer exists.
- **`.sogs` extension**: the format was renamed to `.sog` in 2025. Update any pipeline references from `.sogs` to `.sog`.

## Advanced topics

- `references/editor-ui.md`: SuperSplat Editor panels (Inspector, Cameras, Annotations, Data Panel / Histograms, Selection, Timeline); keyboard shortcuts; viewport navigation; MMB Blender-style controls (PR #870).
- `references/settings-schema.md`: `settings.json` v2 schema (`tonemapping`, `background`, `postEffectSettings`, `cameras[]`, `annotations[]`, `startMode`, `animTracks`); v1 → v2 auto-migration notes; `.ssproj` project format.
- `references/splat-transform-cli.md`: `@playcanvas/splat-transform` CLI for batch conversion, decimation, LOD, filtering, merge, and programmatic Node/browser API.
- `references/qa-checklist.md`: Quest 3 Browser, Vision Pro Safari, Pico 4 Browser, desktop smoke-tests; per-headset annotation legibility, FPS, comfort, exit affordance.
- `references/issues.md`: SuperSplat known issues (including issue #702 decimate, PR #870 MMB controls, PR #876 SplatTransform 2.0 integration); WebXR caveats covered in `publishing-supersplat-webxr`.

## Resources

Primary tool:

- `playcanvas/supersplat` SuperSplat Editor v2.25.0 (commit `8189616`, Apr 28, 2026) — https://github.com/playcanvas/supersplat — MIT. Web app / PWA; no Electron build.
- Live editor: https://superspl.at/editor

Automation (batch, LOD, decimation — not the visual editor):

- `@playcanvas/splat-transform` v2.0.3 — https://github.com/playcanvas/splat-transform — MIT. CLI and Node library; powers the editor's export pipeline as of PR #876.

Engine:

- PlayCanvas Engine >=2.17.0 — https://github.com/playcanvas/engine — MIT.

Key 2024–2026 GitHub activity:

- **Issue #702** (Nov 30, 2025, open): "Feature Request — decimate splats" — requests downsampling for mobile/VR LOD; not yet an editor UI feature as of May 2026.
- **PR #870** (merged Apr 23, 2026): Blender-style MMB camera controls — orbit, pan, zoom, click-to-focus.
- **PR #876** (merged Apr 27, 2026): Adapts export to SplatTransform 2.0 API; tests PLY, compressed PLY, SOG, HTML, ZIP export paths.

Default authoring profile for SEM training:

| Setting | Value |
| --- | --- |
| `tonemapping` | `neutral` |
| `background.color` | `[0.005, 0.005, 0.006]` |
| Sharpness | enabled, ~0.25 |
| Bloom | **disabled** |
| Grading contrast | ~0.08 |
| Grading saturation | −0.15 |
| Vignette | enabled, intensity ~0.18, inner 0.55, outer 1.0 |
| Fringing | disabled |
| `startMode` | `annotation` |
| Camera FOV (close-up) | 38–48 |
| Camera FOV (anchor) | 55–60 |

## `settings.json` v2 example

```json
{
  "version": 2,
  "tonemapping": "neutral",
  "highPrecisionRendering": false,
  "background": { "color": [0.005, 0.005, 0.006] },
  "postEffectSettings": {
    "sharpness": { "enabled": true, "amount": 0.25 },
    "bloom":     { "enabled": false, "intensity": 0, "blurLevel": 1 },
    "grading":   { "enabled": true, "brightness": 0, "contrast": 0.08, "saturation": -0.15, "tint": [1, 1, 1] },
    "vignette":  { "enabled": true, "intensity": 0.18, "inner": 0.55, "outer": 1.0, "curvature": 0.7 },
    "fringing":  { "enabled": false, "intensity": 0 }
  },
  "animTracks": [],
  "cameras": [
    { "initial": { "position": [0.0, 1.2, 2.6], "target": [0.0, 0.35, 0.0], "fov": 55 } }
  ],
  "annotations": [
    {
      "position": [-0.35, 0.25, 0.12],
      "title": "1. Sample stage",
      "text": "Start here. Confirm sample orientation and surface charging artifacts.",
      "camera": { "initial": { "position": [0.0, 1.1, 2.2], "target": [-0.35, 0.25, 0.12], "fov": 48 } }
    },
    {
      "position": [0.18, 0.42, -0.08],
      "title": "2. Region of interest",
      "text": "Trainees compare edge definition and particle distribution.",
      "camera": { "initial": { "position": [0.45, 0.9, 1.4], "target": [0.18, 0.42, -0.08], "fov": 38 } }
    }
  ],
  "startMode": "annotation"
}
```

## Edits sidecar (lab traceability)

```json
{
  "scene_id": "sem-wafer-a12",
  "editor_version": "supersplat 2.25.0 (commit 8189616)",
  "source_ply_sha256": "...",
  "actions": [
    {"kind": "box_selection_delete", "min": [-0.5, -0.2, -0.5], "max": [0.5, 0.5, 0.5]},
    {"kind": "histogram_selection_delete", "channel": "opacity", "range": [0, 0.05]},
    {"kind": "splat_transform_decimate", "args": "--decimate 50%", "tool": "splat-transform@2.0.3"}
  ],
  "exports": {
    "clean_ply": "sem_clean.ply",
    "sog": "sem.sog",
    "html_viewer": "sem_viewer.html",
    "screenshots": ["station1.png", "station2.png", "station3.png"]
  }
}
```

Hand off platform-specific LOD compilation to `compiling-splat-assets` and distribution to `publishing-supersplat-webxr`, `deploying-quest-spatial-splats`, `rendering-unity-splats`, or `rendering-unreal-xscene-splats`.
