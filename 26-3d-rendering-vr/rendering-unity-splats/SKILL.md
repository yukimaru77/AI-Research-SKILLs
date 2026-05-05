---
name: rendering-unity-splats
description: Renders 3D Gaussian Splats inside Unity 6 for PCVR (SteamVR / Quest Link / Quest Pro) and experimental Quest 3 standalone builds using aras-p/UnityGaussianSplatting v1.1.1 with OpenXR Multi-Pass and XR Interaction Toolkit 3.x. Use when the lab needs Unity UI, controller interactions, training state machines, or XRI integration around a splat — not just a viewer. Quest standalone is experimental/unsupported upstream; route production standalone needs to the deploying-quest-spatial-splats skill.
version: 2.0.0
author: Orchestra Research
license: MIT
tags: [Unity, Unity 6, VR, GS, 3DGS, URP, HDRP, OpenXR, PCVR, Quest Link, SteamVR, XR Interaction Toolkit]
dependencies: [unity>=6000.0.0, "com.unity.xr.openxr>=1.16.1", "com.unity.xr.interaction.toolkit>=3.4.1", aras-p/UnityGaussianSplatting>=1.1.1]
---

# Rendering Unity Splats

Render 3D Gaussian Splats inside Unity 6 for PCVR and experimental Quest 3 standalone using `aras-p/UnityGaussianSplatting` v1.1.1 (April 9, 2025), MIT. Use this skill when the project needs Unity UI, XR Interaction Toolkit controllers, training state machines, or quizzes around the splat.

**Package name**: `org.nesnausk.gaussian-splatting`, UPM baseline Unity 2022.3.7f1.
**Maintainer**: @aras-p (no maintainer handoff as of May 2026; README notes no planned major further development).
**VR support**: upstreamed from the ninjamode VR fork via PR #146 (merged Nov. 28, 2024). The ninjamode fork (tag 1.0, Oct. 31, 2024) is now unmaintained and recommends upstream; use it only as reference.
**Quest standalone**: issues #151, #191, #205, #207 are all "closed not planned" — treat as unsupported upstream.
**DX11**: explicitly unsupported by the README; use DX12 or Vulkan.

## Quick start: import .ply and render in headset

### 1. Create the project

- Unity 6.x URP project (required for URP path).
- Graphics API: Windows PCVR → DX12 or Vulkan; Quest Android → Vulkan. Never DX11.

### 2. Install the package

In **Package Manager → Add package from git URL**:

```
https://github.com/aras-p/UnityGaussianSplatting.git?path=/package#v1.1.1
```

For reproducible builds, pin `#v1.1.1`. To track latest main omit the tag.

### 3. Renderer feature (pipeline-dependent)

| Pipeline | Setup |
|----------|-------|
| URP (Unity 6+) | Add **GaussianSplatURPFeature** to URP Renderer asset. Keep **Render Graph Compatibility Mode off** (PR #150). |
| HDRP | Add a **Custom Pass Volume** with a **GaussianSplatHDRPPass** custom pass, typically before transparencies or after post-processing. |
| Built-in RP | No extra setup. Works on Unity 2022.3 LTS. |

On Unity 2022.3, use Built-in RP; current URP path requires Unity 6+.

### 4. Import a .ply or .spz

```
Tools → Gaussian Splats → Create GaussianSplatAsset
```

Provide an input PLY or Scaniverse SPZ file, optionally a `cameras.json`. This creates a `GaussianSplatAsset` you assign to `GaussianSplatRenderer`. PLY compatibility was broadened in v1.1.1 (Postshot-style PLY, issues #172/#170). SPZ support added via PR #161 (v1.1.0); SPZ v2 rotation quantization (issue #192) is not yet merged as of May 2026.

### 5. Place GaussianSplatRenderer

```csharp
// Minimal scene setup — or configure via Inspector
using GaussianSplatting.Runtime;
using UnityEngine;

public class SplatSetup : MonoBehaviour
{
    public GaussianSplatAsset asset;

    void Start()
    {
        var go = new GameObject("SEM_Splat");
        var r = go.AddComponent<GaussianSplatRenderer>();
        r.m_Asset = asset;
        r.m_RenderMode = GaussianSplatRenderer.RenderMode.Splats;
        r.m_SHOrder = 2;          // SH2 for PCVR; SH0 for Quest standalone
        r.m_SplatScale = 1f;
        r.m_OpacityScale = 1f;
        r.m_SortNthFrame = 1;
        go.transform.SetPositionAndRotation(new Vector3(0, 1.2f, -0.8f), Quaternion.identity);
    }
}
```

Key public fields: `m_Asset`, `m_RenderOrder`, `m_SplatScale`, `m_OpacityScale`, `m_SHOrder`, `m_SHOnly`, `m_SortNthFrame`, `m_RenderMode`, `m_PointDisplaySize`, `m_Cutouts`.
`RenderMode` enum: `Splats`, `DebugPoints`, `DebugPointIndices`, `DebugBoxes`, `DebugChunkBounds`.
Key methods/hooks: `GatherSplatsForCamera(Camera cam)` (used by pipeline integrations), `EditExportData(..., bakeTransform)` (export edited splat data from editor).

### 6. Configure OpenXR and enter VR

```
Project Settings → XR Plug-in Management → enable OpenXR
OpenXR Settings → Render Mode: Multi-Pass   ← required; Single-Pass Instanced broken (issue #201)
```

Add interaction profiles: Meta Quest / Oculus Touch, Valve Index, HTC Vive as needed.
Install XRI Starter Assets; add an **XR Origin (Action-based)** rig.
For PCVR, set the correct OpenXR runtime: SteamVR runtime for SteamVR headsets; Meta Quest Link runtime for Quest Link / Air Link.

## Common workflows

### Workflow A: PCVR scene (Unity 6 + URP + OpenXR)

`Task Progress`:

- [ ] Create Unity 6 URP project; set graphics API to DX12 (Windows) or Vulkan.
- [ ] Add `aras-p/UnityGaussianSplatting` via git URL pinned to `#v1.1.1`.
- [ ] Open URP Renderer asset; add **GaussianSplatURPFeature**; disable Render Graph Compatibility Mode.
- [ ] Run `Tools → Gaussian Splats → Create GaussianSplatAsset` on your `.ply`.
- [ ] Create XR Origin (Action-based) with Locomotion, Continuous Move, Snap Turn.
- [ ] Add `GaussianSplatRenderer` on a child GameObject; assign the baked asset; set SH2 or SH3 for PCVR fidelity.
- [ ] Set OpenXR render mode to **Multi-Pass** in XR Plug-in Management.
- [ ] Disable MSAA in URP asset if compositing flicker appears.
- [ ] Build target: Windows DX12. Deploy via Quest Link or SteamVR.
- [ ] Verify: steady 90 Hz, controller tracking, splat visible in headset.

Step-by-step notes:
1. Recommended OpenXR versions: `com.unity.xr.openxr` 1.16.1 (Nov. 21, 2025) or 1.17.0 (Apr. 9, 2026). XRI 3.4.1 or 3.5.0 (Apr. 21, 2026).
2. Performance: ~48 bytes/splat GPU overhead on top of asset data. RTX 3080 Ti: 6.1M splats at medium quality ≈ 282 MB asset, ~1.3 GB VRAM.
3. VR near-distance FPS drop (issue #145, Nov. 2024, closed not planned): frame rate can drop from 72 to ~10 FPS when the camera is very close to a dense splat. Workaround: reduce splat count near the camera using `GaussianCutout` or increase `m_SortNthFrame` to reduce per-frame sort cost.
4. For multiple splat objects, use `m_RenderOrder` to manage front/back; heavy overlap between splat objects can render incorrectly (transparent-object limitation).
5. Splats do not write depth (Z). Add proxy colliders to the same GameObject for XRI interaction.

### Workflow B: experimental Quest 3 Android standalone

`Task Progress`:

- [ ] Re-bake `.ply` at SH0 or SH1; target splat count <=300k (hard experimental ceiling ~400k from ninjamode reference, but use 250k for production safety).
- [ ] Switch build platform to Android; minimum API 29; IL2CPP; ARM64-only.
- [ ] Set graphics API to Vulkan; color space Linear; multithreaded rendering on.
- [ ] XR Plug-in Management Android tab: enable OpenXR + Meta Quest feature group.
- [ ] Set OpenXR render mode to Multi-Pass (Single-Pass Instanced remains broken, issue #201).
- [ ] Profile with OVR Metrics Tool / Meta XR Performance HUD; target 72 FPS.
- [ ] Document experimental status; prepare fallback to `deploying-quest-spatial-splats` (official 150k cap with first-party guarantees).

Step-by-step notes:
1. Quest standalone issues #151 (head-sticking), #191 (Unity 6.1 Android/Vulkan wave ops), #205 (black screen / heavy lag), #207 (1-5 FPS on Quest 2) are all "closed not planned". Upstream stance is PCVR-first.
2. For guaranteed standalone stability route production to `deploying-quest-spatial-splats`.

### Workflow C: SEM digital twin with XRI interactions

`Task Progress`:

- [ ] Split equipment into logical clusters (SEM column, chamber, stage, detector, control panel).
- [ ] Export each cluster as its own `.ply`; import each into a separate `GaussianSplatAsset`.
- [ ] Build hierarchy: `SEM_DigitalTwin / SEM_Column + GaussianSplatRenderer + proxy colliders / ...`.
- [ ] Add `GaussianCutout` (Box or Ellipsoid, with optional invert) to mask sub-regions; use editor selection/delete tools to permanently remove noise then export modified PLY via `EditExportData`.
- [ ] Add proxy `BoxCollider`, `CapsuleCollider`, or `MeshCollider` (simplified CAD) on child GameObjects.
- [ ] Attach `XRGrabInteractable` for movable parts, `XRSimpleInteractable` for buttons/hotspots, `XRSocketInteractor` for detachable holders.
- [ ] Wire `SelectEntered` events to training state machine; persist progress to JSON / LMS endpoint.
- [ ] Verify: all hotspots fire events; splat and proxy collider stay aligned through transforms.

Key design rule: separate the visual splat from the physical affordance model. Splats provide photorealistic context; Unity colliders + XRI + simplified CAD proxy provide reliable interaction. Transforms on `GaussianSplatRenderer` GameObjects are fully honored.

Runtime per-splat editing is not a stable public API. Use `GaussianCutout` for masking at runtime; use editor tools for permanent edits. `editSelectedSplats`, `editDeletedSplats`, `editCutSplats`, `editSelectedBounds` are editor-side properties.

## When to use vs alternatives

| Path | Use when | Avoid when |
|------|----------|------------|
| Aras-P + OpenXR PCVR (this skill) | Lab uses Unity; rich UI/state machines; PCVR fidelity | Need standalone Quest production guarantees |
| `wuyize25/gsplat-unity` v1.2.1 (Mar. 26, 2026) | Unity 2021+; need active 2026 releases, MSAA/XR, async upload, Spark compression, transparent-queue integration | Aras ecosystem familiarity or simpler requirements |
| `deploying-quest-spatial-splats` | Standalone Quest 3 production, first-party support, 150k cap | Need Unity UI / state machines |
| `publishing-supersplat-webxr` | Cross-headset URL distribution, fastest iteration | Offline kiosk, complex training logic |
| `rendering-unreal-xscene-splats` | Existing Unreal ecosystem | Existing Unity ecosystem |
| ninjamode fork (reference only) | Studying VR-specific Aras-P patterns from before PR #146 | Any production use — marked unmaintained |
| Unity 2022.3 LTS + Built-in RP | Desktop/non-XR viewer; avoiding Unity 6 upgrade | URP + VR (requires Unity 6 for URP path) |

## Common issues

**URP requires Unity 6**: Current URP path (PR #150, merged Dec. 10, 2024) requires Unity 6+ with Render Graph Compatibility Mode off. On Unity 2022.3, use Built-in RP or upgrade to Unity 6.

**VR FPS drop when close to splats (issue #145)**: Nov. 23, 2024 — frame rate drops from 72 FPS to ~10 FPS when the VR camera is close to a dense splat. Closed not planned. Mitigation: reduce visible splat count with `GaussianCutout`, lower `m_SHOrder`, or increase `m_SortNthFrame`.

**URP + VR wave ops errors (issue #93)**: Feb. 8, 2024 — URP + VR/Oculus combinations can produce "invalid wavebasic kernel" shader errors. Closed not planned. Workaround: switch to Built-in RP, or use Unity 6 URP path (PR #150) which replaces the old renderer pass path.

**DX11 does not work**: README explicitly states DX11 is unsupported. Use DX12 (Windows PCVR) or Vulkan (Quest).

**Single-Pass Instanced / Multi-view artifacts**: Issue #201 (Sep. 24, 2025) — stereo instancing produces artifacts on Meta Quest Multi-view. Use Multi-Pass only. Performance cost is real but required.

**Quest standalone black screen / low FPS**: Issues #205 and #207 (Oct.-Nov. 2025), both closed not planned. Upstream does not officially support Quest standalone. Use `deploying-quest-spatial-splats` for production.

**Unity 6.1 Android Vulkan URP build errors**: Issue #191 (Aug. 4, 2025) — wave ops / Render Graph execution errors on Unity 6.1 + Android + Vulkan + URP. Closed not planned.

**SPZ v2 rotation quantization**: Issue #192 (Aug. 4, 2025) — SPZ v2 files use changed rotation quantization; no merged fix as of May 2026. Use PLY or SPZ v1 for now.

**VRAM overflow from SH3**: ~48 bytes/splat overhead; SH3 + high splat count exhausts mid-range VRAM. Use SH1/SH2 for VR; SH3 only on RTX 3080 Ti class and above.

**Multiple overlapping splat objects**: Splats render like transparents; multiple GaussianSplatRenderer objects are sorted only roughly. Use `m_RenderOrder` to stabilize obvious relationships; avoid heavy overlap.

**Asset re-bake after .ply updates**: Aras-P bakes a Unity-native asset. Re-run `Tools → Gaussian Splats → Create GaussianSplatAsset` after every PLY change.

**Coordinate frame mismatch**: PLY is typically RDF; Unity is RUF. The Aras-P importer normalizes for standard formats. For custom-trainer PLY, verify visually with an asymmetric fiducial.

**MSAA conflicts**: Disable MSAA in URP asset if splat compositing shows flicker. (If MSAA is required, consider `wuyize25/gsplat-unity` which has built-in MSAA handling.)

**Render Order sorting**: Issue #156 (fixed in v1.1.0) — sorting previously did not respect `m_RenderOrder`. Ensure you are on v1.1.0+.

## Advanced topics

- **references/issues.md**: Full GitHub issue/PR index with numbers, dates, status — VR upstreaming PR #146, URP Render Graph PR #150, SPZ PR #161, all Quest standalone issues, stereo issue #201, FPS drop issue #145.
- **references/api.md**: Complete `GaussianSplatRenderer` public field reference; `GaussianCutout` shapes (Box and Ellipsoid, with invert); `GaussianSplatAsset` properties (format version, splat count, bounds, 8.6M max-splat constant); `GatherSplatsForCamera`; `EditExportData`; editor-side editing API surface.
- **references/xr-rig.md**: XR Origin (Action-based) configuration; OpenXR interaction profiles; locomotion (continuous, teleport, snap-turn); XRI 3.x migration notes (Input Reader, Near-Far Interactor, Body Transformers, deprecated LocomotionSystem → LocomotionMediator).
- **references/perf-quest-link.md**: PCVR Quest Link performance tuning; OpenXR runtime selection; foveation; render scale; GPU memory budgeting per SH degree.

## Resources

- `aras-p/UnityGaussianSplatting` v1.1.1 (Apr. 9, 2025) — https://github.com/aras-p/UnityGaussianSplatting — MIT
  - UPM: `https://github.com/aras-p/UnityGaussianSplatting.git?path=/package#v1.1.1`
  - Package name: `org.nesnausk.gaussian-splatting`
  - Maintainer: @aras-p (no handoff; no planned major further development per README)
- `wuyize25/gsplat-unity` v1.2.1 (Mar. 26, 2026) — https://github.com/wuyize25/gsplat-unity — MIT
  - Unity 2021+; BiRP/URP/HDRP; PLY import; SH 0-3; MSAA/XR/cutouts/async upload/Spark compression
  - Package name: `wu.yize.gsplat`
- `ninjamode/Unity-VR-Gaussian-Splatting` (tag 1.0, unmaintained, reference only) — https://github.com/ninjamode/Unity-VR-Gaussian-Splatting — MIT
- Unity OpenXR Plugin `com.unity.xr.openxr` — 1.16.1 (Nov. 21, 2025) / 1.17.0 (Apr. 9, 2026) — https://docs.unity3d.com/Packages/com.unity.xr.openxr@1.16/manual/index.html
- Unity XR Interaction Toolkit `com.unity.xr.interaction.toolkit` — 3.4.1 / 3.5.0 (Apr. 21, 2026) — https://docs.unity3d.com/Packages/com.unity.xr.interaction.toolkit@3.5/manual/index.html
- Unity 6 — https://unity.com

### Performance reference

| Config | Splat count | Asset size | VRAM (RTX 3080 Ti) |
|--------|-------------|------------|---------------------|
| Medium quality | 6.1M | ~282 MB | ~1.3 GB |
| Per-splat overhead | — | — | ~48 bytes/splat |

| Device | Stable FPS | Splat ceiling (reference) |
|--------|------------|---------------------------|
| Quest 3 standalone (ninjamode, experimental) | 72 FPS | ~400k Gaussians |

### Version history (aras-p/UnityGaussianSplatting)

| Version | Date | Key changes |
|---------|------|-------------|
| v1.1.1 | Apr. 9, 2025 | Broader PLY compatibility; Postshot PLY fixes (#172/#170); Scaniverse SPZ rotation fix (#163); clearer non-binary PLY error (#165) |
| v1.1.0 | Jan. 30, 2025 | Scaniverse SPZ input (PR #161); Render Order (fix #156); URP Unity 6 Render Graph (PR #150); fix #153 inspector drag/drop |
| v1.0.0 | Nov. 28, 2024 | Upstreamed VR support (PR #146) from ninjamode fork |
