---
name: rendering-unreal-xscene-splats
description: Renders SEM 3D Gaussian Splats inside Unreal Engine 5 for high-fidelity PCVR training (Quest Link / Quest Pro Link) and cinematic content authoring. Covers plugin selection for May 2026 — DazaiStudio/SplatRenderer-UEPlugin is the recommended default for maintained UE5.5–5.7 binary support; XVerse XScene-UEPlugin (stale since Jul 2025) remains usable for UE5.0–5.5 Niagara/VFX workflows; MLSLabs (Windows + DX12 + NVIDIA) and TimChen1383/NanoGaussianSplatting (UE5.6/5.7, MIT) are specialist alternatives. Covers .ply import, cropping, LOD, hybrid rendering, Niagara overlays, and Sequencer cinematics. Use when the lab ecosystem is Unreal-based or PCVR visual fidelity exceeds browser portability. Excludes browser/WebXR (publishing-supersplat-webxr), Quest standalone APKs (deploying-quest-spatial-splats), Unity (rendering-unity-splats), and asset compilation (compiling-splat-assets).
version: 2.0.0
author: Orchestra Research
license: Apache-2.0
tags: [Unreal, UE5, PCVR, XVerse, XScene, 3DGS, Niagara, Sequencer, OpenXR, Quest Link, SteamVR, Gaussian Splatting]
dependencies: [unreal-engine>=5.3, openxr]
---

# Rendering Unreal XScene Splats

Render SEM 3D Gaussian Splats inside Unreal Engine 5 for high-fidelity PCVR training and Sequencer cinematics. As of May 2026 the plugin landscape has shifted: XVerse XScene-UEPlugin (last commit Jul 2025, no 2026 release) is stale on current UE minor versions, while DazaiStudio/SplatRenderer-UEPlugin and mlslabs/MLSLabsGaussianSplattingRenderer-UE are actively releasing in 2026.

**Recommended default (May 2026):** `DazaiStudio/SplatRenderer-UEPlugin` v1.1.2 (Apr 5, 2026) — pre-compiled binary zips for UE5.5, UE5.6, UE5.7; no source build required; Apache-2.0.

**XVerse XScene-UEPlugin** remains the right choice only when the Niagara/VFX-emitter integration or Blueprint/LOD pipeline it provides is specifically required and you are on UE5.0–5.5. It is stale for UE5.6+.

## Plugin status matrix (May 2026)

| Plugin | Actual GitHub repo | Latest release | Last 2026 activity | UE support | License | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| DazaiStudio SplatRenderer | DazaiStudio/SplatRenderer-UEPlugin | v1.1.2 Apr 5 2026 | Active — binary zips for UE5.5/5.6/5.7 | UE5.5 / 5.6 / 5.7 | Apache-2.0 | **Recommended default** |
| MLSLabs Renderer | mlslabs/MLSLabsGaussianSplattingRenderer-UE | Pro v1.0.3.12 Apr 24 2026; Lite v1.0.0.10-beta Mar 27 2026 | Active — commit Apr 7 2026 | UE5.5 (Windows + DX12 + NVIDIA only) | Apache-2.0 | Specialist (Windows/NVIDIA) |
| NanoGaussianSplatting | TimChen1383/NanoGaussianSplatting | v1.0.3 Apr 5 2026 | Active — 230+ commits | UE5.6 / 5.7 | MIT | Nanite-style perf, UE5.6+ |
| XVerse XScene-UEPlugin | xverse-engine/XScene-UEPlugin | v1.1.5.1 Jan 20 2025 (v1.1.6 mentioned in README but no GitHub release tag found) | Stale — last commit Jul 30 2025; issue #117 asks UE5.7 support (Nov 2025); no 2026 release | UE5.0–5.5 | Apache-2.0 | Legacy/Niagara path only |
| JI20/unreal-splat | JI20/unreal-splat | No releases | Last commit Oct 2025 | UE5.5 (Niagara-based) | MIT | Experimental only |
| Luma AI UE Plugin | Fab/Marketplace (not OSS) | v0.41 (last public signal) | No 2026 public activity found | UE5 (UE5.1–5.3 confirmed; broader claimed) | Marketplace terms | Available; not OSS; no 2026 maintenance signal |

> **Name correction:** The MLSLabs repo path `MLSLabs/MLSLabsRenderer-Lite` used in earlier documentation does not exist at that path. The real repo is `mlslabs/MLSLabsGaussianSplattingRenderer-UE`; the README/branding calls it "MLSLabsRenderer-Lite."

## Quick start (DazaiStudio SplatRenderer — recommended)

```bash
# 1. Download the correct UE-version zip from GitHub Releases
# https://github.com/DazaiStudio/SplatRenderer-UEPlugin/releases/tag/v1.1.2
# e.g. SplatRenderer_UE5.5.zip, SplatRenderer_UE5.6.zip, or SplatRenderer_UE5.7.zip

# 2. Extract into your project's Plugins/ folder
unzip SplatRenderer_UE5.6.zip -d /YourProject/Plugins/

# 3. Open the project in UE; enable "Splat Renderer" in Plugins browser; restart.
# No source compilation required.
```

```cpp
// Place a SplatRenderer actor at runtime (DazaiStudio API — verify against plugin headers)
ASplatActor* SplatActor = GetWorld()->SpawnActor<ASplatActor>();
SplatActor->SetPlyAsset(LoadObject<USplatAsset>(nullptr, TEXT("/Game/SEM/sem_optimized")));
SplatActor->SetActorLocation(FVector(0.f, 0.f, 120.f));
```

## Quick start (XScene legacy path — UE5.0–5.5 only)

```bash
# Clone or vendor into project Plugins/
git clone https://github.com/xverse-engine/XScene-UEPlugin Plugins/XScene-UEPlugin

# Regenerate project files; rebuild; enable "XVERSE3DGS" in Plugin Browser.
```

```cpp
// XScene actor placement (confirmed API from XScene README)
AXSceneActor* SplatActor = GetWorld()->SpawnActor<AXSceneActor>();
SplatActor->SetSplatAsset(LoadObject<UXSceneSplatAsset>(nullptr, TEXT("/Game/SEM/sem_optimized")));
SplatActor->SetActorLocation(FVector(0.f, 0.f, 120.f));
SplatActor->SetRenderMode(EXSceneRenderMode::Hybrid);
SplatActor->SetLODBias(0);
```

## Skill contract

Inputs:

- An optimized `.ply` from `compiling-splat-assets` (SH2 or SH3 preferred for PCVR fidelity on capable GPU).
- UE 5.3+ project with OpenXR plugin enabled and a tested PCVR pawn.

Outputs:

- An imported splat asset in the project Content Browser.
- A scene actor referenced by a Sequencer or Level Blueprint.
- A PCVR-packaged build (Windows DX12) deployable via Quest Link or SteamVR.

Non-negotiable gates:

1. **Plugin selection must match UE version**: Dazai for UE5.5–5.7 (default); XScene for UE5.0–5.5 Niagara workflows; MLSLabs only on Windows + UE5.5 + DX12 + NVIDIA; NanoGS for UE5.6/5.7 MIT preference.
2. Standalone Android/Quest is out of scope — route to `deploying-quest-spatial-splats`.
3. License: Dazai Apache-2.0, XScene Apache-2.0, MLSLabs Apache-2.0, NanoGS MIT, JI20 MIT. Confirm distribution NOTICE file inclusion.
4. Asset must be pre-validated by `compiling-splat-assets` upstream.
5. Profile GPU cost before assuming Niagara render mode outperforms native raster.

## Common workflows

### Workflow A: PCVR training scene with Dazai SplatRenderer + OpenXR pawn (UE5.5–5.7)

`Task Progress`:

- [ ] Open UE 5.5–5.7 project; enable OpenXR and OpenXR Hand Tracking; configure VR Template pawn.
- [ ] Download `SplatRenderer_UE5.x.zip` from DazaiStudio/SplatRenderer-UEPlugin Releases; extract to `Plugins/SplatRenderer`; enable plugin; restart editor.
- [ ] Import `sem_optimized.ply` via the Splat Renderer importer; confirm splat count and bounding box.
- [ ] Place a splat actor in the level; tune render settings.
- [ ] Wire VR pawn motion controllers to ray-pointing for SEM annotations.
- [ ] Package Windows DX12; test via Quest Link or SteamVR.

Step by step:

1. Plugin install: no source compilation. Extract the binary zip; ensure the `SplatRenderer` folder lands under `Plugins/` with a valid `.uplugin`; add to `*.uproject` if not auto-detected.
2. Project Settings: enable OpenXR, OpenXR Hand Tracking, Eye Tracker if needed. Remove deprecated Oculus VR plugin to avoid OpenXR runtime conflicts.
3. Import: drag `sem_optimized.ply` into Content Browser; choose Splat Renderer importer; verify splat count and axis orientation.
4. Cropping: use plugin cropping controls (if available) or pre-crop via `compiling-splat-assets` before import.
5. VR pawn: VR Template pawn + Interaction System; attach a ray pointer to right motion controller.
6. Acceptance: 90 Hz steady in PCVR; controller ray activates annotation hotspots; comfort settings respected.

### Workflow B: Sequencer cinematic for training video

`Task Progress`:

- [ ] Author named camera bookmarks at SEM landmarks (electron column, stage, vacuum chamber).
- [ ] Drive camera transitions via Sequencer; bind splat actor parameters (LOD, cropping).
- [ ] Add Niagara VFX overlays for "highlight zone" callouts (XScene path) or billboard particles (Dazai path).
- [ ] Render to MP4/image sequence via Movie Render Queue; deliver as 2D training video.
- [ ] Optional: stereo video for headset playback.

Step by step:

1. Sequencer master: Camera Cuts track; one camera per SEM station; duration tuned for narration.
2. Splat actor parameter tracks: animate LOD bias upward in wide shots, downward for close-ups.
3. Niagara emitters: billboard "callout" VFX anchored at landmark positions; spawn-on-cue via Sequencer events.
4. Movie Render Queue: 4K, AA 8×8 temporal/spatial, 32 warm-up frames, EXR master + MP4 delivery.
5. Stereo VR: side-by-side or top-bottom camera tracks for headset playback.

### Workflow C: Legacy XScene Niagara path (UE5.0–5.5)

`Task Progress`:

- [ ] Install XScene-UEPlugin (source build required); enable XVERSE3DGS in Plugin Browser.
- [ ] Import `.ply`; verify `UXSceneSplatAsset` opens in Splat Editor.
- [ ] Place `AXSceneActor`; set Hybrid render mode; tune LOD bias.
- [ ] Enable Niagara render mode; bind XScene splat as particle data source.
- [ ] Profile GPU cost; revert to native mode if Niagara overhead exceeds budget.

Step by step:

1. Plugin install: clone repo under `Plugins/XScene-UEPlugin`; regenerate project files; rebuild editor (source required — no pre-built binaries for UE5.6+).
2. Enable XVERSE3DGS; import `.ply` via XScene importer; confirm bounding box and SH level.
3. Render mode: prefer Hybrid for SEM scenes with mixed dense/sparse regions.
4. Niagara binding: XScene exposes splat as particle data source; compose with environmental VFX for training callouts.
5. Known UE5.4 compatibility issue: see issue #42; pre-built binaries for UE5.4 were not released — source rebuild required.

## When to use vs alternatives

| Path | Use when | Avoid when |
| --- | --- | --- |
| Dazai SplatRenderer (default) | UE5.5–5.7; binary install; maintained 2026; static `.ply` and 4DGS `.gsd` | UE5.0–5.4; need deep Niagara pipeline (use XScene) |
| MLSLabs Renderer (mlslabs/MLSLabsGaussianSplattingRenderer-UE) | Windows + UE5.5 + DX12 + NVIDIA; millions-of-Gaussians | Cross-platform; non-NVIDIA GPU; non-Windows |
| NanoGS (TimChen1383/NanoGaussianSplatting) | UE5.6/5.7; MIT license; Nanite-style performance focus | UE5.5 and below |
| XScene-UEPlugin (legacy) | UE5.0–5.5; need Niagara/VFX/Blueprint/LOD integration specifically | UE5.6+; new projects without existing XScene dependency |
| JI20/unreal-splat | Light experimentation; MIT; Niagara-based | Production deployment |
| `rendering-unity-splats` | Existing Unity ecosystem | Existing Unreal ecosystem |
| `publishing-supersplat-webxr` | Cross-headset URL distribution | PCVR fidelity / Niagara / Sequencer |
| `deploying-quest-spatial-splats` | Standalone Quest production | PCVR fidelity is the priority |

## Common issues

- **XScene missing precompiled manifest for GSRuntime** (issue #108, Sep 4 2025 — Ubuntu 22.04 / UE5.5 / Carla 0.10.0): packaging fails with "Missing precompiled manifest for 'GSRuntime'". Workaround: build the plugin from source with the matching UE5.5 toolchain; pre-built binaries for non-Windows platforms are absent. URL: https://github.com/xverse-engine/XScene-UEPlugin/issues/108
- **XScene UE5.4 compatibility** (issue #42, Jun 6 2024): plugin release v1.1.5.1 does not include pre-built binaries for UE5.4.2; rebuild from source. URL: https://github.com/xverse-engine/XScene-UEPlugin/issues/42
- **OpenXR vs Oculus VR plugin conflict**: disable the deprecated Oculus plugin when enabling OpenXR; plugin-load order matters at engine startup.
- **Quest Link OpenXR runtime selection**: confirm Oculus OpenXR runtime is active in the Oculus desktop app; SteamVR's OpenXR can interfere.
- **Hybrid render-mode flicker on transparent edges**: tune cropping; adjust XScene blend bias; toggle to pure Splats mode for diagnostics.
- **Niagara mode GPU-bound**: profile via UE Insights / `stat GPU`; revert to native raster if GPU time exceeds budget.
- **`.ply` import ignores SH > 2**: verify plugin SH support per version; use `--filter-harmonics 2` upstream if SH3 is rejected.
- **Coordinate frame**: PLY is RDF; UE is left-handed Z-up. Plugins normalize for known PLY formats; verify visually with an asymmetric fiducial.
- **Sequencer warm-up frames**: splat sort is unstable on the first frame; use 32 warm-up frames in Movie Render Queue.
- **MLSLabs repo name confusion**: `MLSLabs/MLSLabsRenderer-Lite` does not exist as a GitHub path; use `mlslabs/MLSLabsGaussianSplattingRenderer-UE`.
- **XVerse v1.1.6 not found as a GitHub Release**: README mentions v1.1.6 (Jul 2025) but no GitHub Release tag exists for it; treat v1.1.5.1 as the latest verifiable release.
- **PCVR motion sickness**: teleport + snap-turn; avoid forced camera animation in headset; respect comfort settings.

## Advanced topics

- `references/dazai-primary.md`: DazaiStudio SplatRenderer install, UE5.5/5.6/5.7 zip selection, 4DGS `.gsd` Sequencer integration.
- `references/xscene-legacy.md`: XScene `.ply` import flags; cropping, LOD, Niagara mode; source build for UE5.6+ if needed.
- `references/openxr-vr-template.md`: UE OpenXR plugin setup; VR Template pawn extension; motion controller binding; XR locomotion; foveation and render-scale.
- `references/sequencer-cinematics.md`: camera cuts, splat parameter animation, Niagara callout overlays, Movie Render Queue, stereo video.
- `references/mlslabs-specialist.md`: Windows + UE5.5 + DX12 + NVIDIA prerequisites; millions-of-Gaussians config; actual repo path.
- `references/issues.md`: plugin-version compatibility matrix; OpenXR runtime gotchas; UE5 splat performance notes; real GitHub issues.

## Resources

Primary plugin (May 2026):

- `DazaiStudio/SplatRenderer-UEPlugin` v1.1.2 (Apr 5, 2026) — https://github.com/DazaiStudio/SplatRenderer-UEPlugin — Apache-2.0. Binary zips for UE5.5, UE5.6, UE5.7. Static `.ply` and 4DGS `.gsd`. Active 2026 maintenance.

Secondary plugins:

- `mlslabs/MLSLabsGaussianSplattingRenderer-UE` Pro v1.0.3.12 / Lite v1.0.0.10-beta (Apr 2026) — https://github.com/mlslabs/MLSLabsGaussianSplattingRenderer-UE — Apache-2.0. Windows + UE5.5 + DX12 + NVIDIA specialist. Note: repo branding is "MLSLabsRenderer-Lite"; old path `MLSLabs/MLSLabsRenderer-Lite` is 404.
- `TimChen1383/NanoGaussianSplatting` v1.0.3 (Apr 5, 2026) — https://github.com/TimChen1383/NanoGaussianSplatting — MIT. UE5.6/5.7; Nanite-style performance-focused GS.
- `xverse-engine/XScene-UEPlugin` v1.1.5.1 (Jan 20, 2025) — https://github.com/xverse-engine/XScene-UEPlugin — Apache-2.0. Legacy: last commit Jul 2025; no 2026 release; UE5.0–5.5 only; Niagara/VFX/Blueprint strength.
- `JI20/unreal-splat` — https://github.com/JI20/unreal-splat — MIT. No releases; last commit Oct 2025; experimental Niagara-based.
- Luma AI UE Plugin v0.41 — via Unreal Marketplace/Fab (not OSS). No 2026 public maintenance signal; Marketplace license terms.

Engine and runtime:

- Unreal Engine 5.5+ (recommended), 5.3+ (minimum for XScene legacy) — https://www.unrealengine.com
- UE OpenXR Plugin — built-in
- Movie Render Queue — built-in
- Niagara — built-in

## Performance defaults

| Target | Plugin | Render mode | Notes |
| --- | --- | --- | --- |
| PCVR 90 Hz on RTX 3080 Ti, UE5.5 | Dazai SplatRenderer | Standard splat raster | SH2; LOD bias 0 |
| PCVR 90 Hz on RTX 4080+, UE5.6/5.7 | Dazai or NanoGS | Standard splat raster | SH3; LOD bias -1 |
| Cinematic offline render | XScene (legacy) or Dazai | Native splats + Niagara overlays | Movie Render Queue; 32 warm-up frames; 4K AA |
| Millions-of-Gaussians demo, Windows NVIDIA | MLSLabs Renderer | NVIDIA-optimized raster | Windows + DX12 + SM 7.5+ |
| Mid-range GPU | Dazai SplatRenderer | Standard splat raster | SH1; LOD bias +1 |

## VR pawn ray-cast snippet

```cpp
// VRPawn.cpp — motion controller Trigger activates SEM annotation hotspots
void AVRPawn::SetupPlayerInputComponent(UInputComponent* InputComponent)
{
    Super::SetupPlayerInputComponent(InputComponent);
    InputComponent->BindAction("RightTrigger", IE_Pressed, this, &AVRPawn::OnTriggerRight);
}

void AVRPawn::OnTriggerRight()
{
    FVector Start = RightController->GetComponentLocation();
    FVector End   = Start + RightController->GetForwardVector() * 500.f;
    FHitResult Hit;
    if (GetWorld()->LineTraceSingleByChannel(Hit, Start, End, ECC_Visibility))
    {
        if (auto* Hotspot = Cast<AAnnotationHotspot>(Hit.GetActor()))
        {
            Hotspot->Activate(this);
        }
    }
}
```

## Movie Render Queue cinematic settings

| Setting | Value |
| --- | --- |
| Resolution | 3840x2160 (4K) |
| Anti-aliasing | Temporal Sample Count 8, Spatial Sample Count 8 |
| Warm-up frames | 32 (allows splat sort to stabilize) |
| Output format | EXR (master) + MP4 (delivery) |
| Stereo VR | Side-by-side or top-bottom for headset playback |
| Frame rate | 30 fps (training video), 60 fps (high-motion) |

## Acceptance test checklist

- [ ] UE 5.5+ project loads with OpenXR and SplatRenderer (Dazai) plugins enabled.
- [ ] `sem_optimized.ply` imports without warnings; splat count matches upstream asset.
- [ ] Splat actor renders the SEM in PIE.
- [ ] PCVR pawn enters VR via Quest Link or SteamVR; 90 Hz steady.
- [ ] Motion controller ray cast activates an annotation hotspot.
- [ ] Sequencer master plays through all SEM stations; Movie Render Queue produces a 4K MP4.
- [ ] Niagara overlays render on cue without critically occluding the splat.
- [ ] Packaged Windows DX12 build runs standalone via Quest Link.

Default Unreal path for SEM training (May 2026): Dazai SplatRenderer binary install on UE5.5/5.6/5.7, standard raster at SH2, OpenXR PCVR pawn, motion-controller ray-pointing, Sequencer for walkthroughs, Niagara overlays for callouts. Reserve XScene for UE5.0–5.5 Niagara/VFX-specific workflows. Use MLSLabs for Windows/NVIDIA millions-of-Gaussians demos; NanoGS for UE5.6/5.7 MIT preference.
