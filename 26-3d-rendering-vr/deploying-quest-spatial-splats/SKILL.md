---
name: deploying-quest-spatial-splats
description: Builds a native Meta Quest 3/3S standalone APK that loads a single SEM 3D Gaussian Splat (.spz preferred, .ply fallback) using Meta Spatial SDK's first-party Gaussian splat integration (v0.12.0, April 2026). Use when the lab needs an offline, controlled training app on Quest 3/3S rather than a browser URL or PCVR build. Enforces Meta's documented constraints — Quest 3 and Quest 3S only (no Pro, no Pico, no Vision Pro), one splat at a time, advisory cap of ~150,000 splats, optimized .spz strongly preferred over .ply. Excludes .ply→.spz conversion (cat 26 compiling-splat-assets) and large/multi-splat scenes (use Unity or WebXR paths instead). Unity URP + Aras-P plugin is an unstable alternative (Quest standalone builds have known black-screen/lag issues, closed "not planned"). Quest Link PCVR streaming is a valid dev workaround but not a native APK path.
version: 2.0.0
author: Orchestra Research
license: MIT
tags: [Quest 3, Quest 3S, Meta Spatial SDK, SPZ, Android, Gradle, Horizon OS, VR, Standalone, Native, GS, 3DGS, Kotlin]
dependencies: [meta-spatial-sdk>=0.12.0, android-gradle-plugin>=8.0.0, kotlin>=1.9.0, jdk>=17, spz>=2.1.0]
---

# Deploying Quest Spatial Splats

Build a Quest 3/3S native standalone APK that renders a single SEM Gaussian splat using Meta Spatial SDK's first-party splat integration. As of May 2026, this is the only Meta-blessed native developer path for 3DGS on Quest. Meta Spatial SDK v0.12.0 (released April 16, 2026) is the current confirmed version.

Meta documents support for Quest 3/3S only, one splat per scene, an advisory cap of ~150,000 splats, and strongly recommends optimized `.spz` over `.ply`. Quest Pro, Pico 4, and Apple Vision Pro are not supported; use WebXR or Unity/Unreal paths for those. Hit detection against splat geometry is not guaranteed. No new Meta-blessed 3DGS path was found in Meta Platform Android v77+ or Unity XR SDK — the Spatial SDK Splat/SplatFeature API remains the sole first-party option.

Meta Spatial SDK is licensed under the Meta Platform Technologies SDK License Agreement (non-transferable, revocable; not open-source). Template scaffold code is 0BSD. The `nianticlabs/spz` format library is MIT.

## Quick start

```kotlin
// MainActivity.kt — minimal Spatial SDK splat scene (SDK v0.12.0).
import com.meta.spatial.splat.Splat
import com.meta.spatial.splat.SplatFeature
import android.net.Uri

class MainActivity : AppSystemActivity() {

    override fun registerFeatures(): List<SpatialFeature> =
        listOf(
            VRFeature(this),
            SplatFeature(this.spatial),   // required to enable splat rendering
            ComposeFeature()
        )

    override fun onSceneReady() {
        super.onSceneReady()
        // One splat per scene — Meta SDK constraint.
        val splatEntity = Entity.create(
            listOf(
                Splat(Uri.parse("apk:///assets/sem_quest_150k.spz")),
                Transform(Pose(Vector3(0f, 1.2f, -0.8f), Quaternion(0f, 0f, 0f, 1f))),
                Scale(Vector3(1f, 1f, 1f))
            )
        )
    }
}
```

## Skill contract

Inputs:

- A SEM `.spz` (or `.ply`) already conditioned by `cat 26 compiling-splat-assets` to <=150,000 splats, SH0 only, RUB coordinate frame, alpha logits clamped.
- Lab branding assets: app icon, splash, training prompt copy.

Outputs:

- An Android APK (`.apk`) signed for sideload to Quest 3/3S Developer-Mode devices, or an AAB for Horizon Store.
- A trainee README pinning SDK version and asset hash.
- Acceptance log: launches on Quest 3 and Quest 3S; refuses to launch on unsupported devices.

Non-negotiable gates:

1. Asset must pass the `compiling-splat-assets` <=150,000 splat gate before APK packaging.
2. Build must reject Quest Pro / Pico / Vision Pro at runtime with an in-VR panel.
3. APK loads exactly one splat entity; multiple `.spz` files are not supported by the SDK.
4. Hit detection against splat geometry must not be relied on; use invisible collider primitives.
5. Scene must include teleport-only locomotion and a clearly visible exit affordance.

## Common workflows

### Workflow A: minimal one-splat training APK

`Task Progress`:

- [ ] Scaffold a Meta Spatial SDK Android project (Kotlin, Gradle, JDK 17, Android Gradle Plugin >=8.0).
- [ ] Place the validated `.spz` in `app/src/main/assets/sem_quest_150k.spz`.
- [ ] Register `SplatFeature(this.spatial)` in `registerFeatures()`.
- [ ] Create one Entity with `Splat(uri)`, `Transform`, `Scale` inside `onSceneReady()`.
- [ ] Add a runtime device guard: refuse non-Quest-3/3S with an in-VR info panel.
- [ ] Add a system UI exit button (Spatial SDK `ImagePanel` or `Toolbar`).
- [ ] Build `assembleRelease`, sign, sideload via `adb install`, smoke-test on Quest 3 and Quest 3S.

Step by step:

1. **Project setup**: clone the Meta Spatial SDK samples repo (`https://github.com/meta-spatial/Meta-Spatial-SDK-Samples`), open in Android Studio Hedgehog or newer, connect Quest via USB, enable Developer Mode on the headset.
2. **Asset placement**: copy `sem_quest_150k.spz` from `dist/quest3/` (output of `compiling-splat-assets`). Parse SPZ 32-byte header (`magic=0x5053474e`, `numPoints`, `shDegree`, `version`); fail the build if `numPoints > 150000`.
3. **Scene code**: register `SplatFeature`, instantiate exactly one `Splat` entity at a known anchor `Pose`. Do not author code paths that swap splats at runtime.
4. **Locomotion**: use Spatial SDK `InputSystem` + `ControllerComponent` ray-select for teleport; avoid smooth joystick locomotion as default for SEM training. For large navigable environments, attach `SupportsLocomotion` to the splat entity as documented.
5. **Exit affordance**: add a labeled "End Training" `ImagePanel` in scene; do not depend on system Home gesture only.
6. **Sign and install**: see Workflow C below for the full release signing flow.

### Workflow B: device guard and Quest 3/3S gate

`Task Progress`:

- [ ] Read `Build.MODEL` / `Build.PRODUCT` at activity startup.
- [ ] Maintain an allowlist: `eureka` (Quest 3), `panther` (Quest 3S). Reject all others.
- [ ] On rejection, render an in-VR `ImagePanel`: "This experience requires Quest 3 or Quest 3S."
- [ ] Log device model, OS version, splat asset SHA-256 to `getExternalFilesDir()` for lab diagnostics.

```kotlin
private val ALLOWED_PRODUCTS = setOf("eureka", "panther")

override fun onSceneReady() {
    super.onSceneReady()
    val product = Build.PRODUCT.lowercase()
    if (product !in ALLOWED_PRODUCTS) {
        Entity.create(listOf(
            Panel(R.layout.unsupported_device_layout),
            Transform(Pose(Vector3(0f, 1.5f, -1f)))
        ))
        return   // abort splat load on unsupported device
    }
    // ... splat entity creation
}
```

Step by step:

1. Read `Build.PRODUCT` and `Build.MODEL` at activity startup.
2. If product is not in allowlist, replace scene with an info `Panel` and return early.
3. Log to `getExternalFilesDir(null)` so the lab can collect diagnostics over USB.
4. Document in trainee README that Quest Pro and Pico/Vision Pro are intentionally unsupported; direct to `publishing-supersplat-webxr`.

### Workflow C: release APK signing and sideload

`Task Progress`:

- [ ] Generate a release keystore (once per project).
- [ ] Configure `signingConfigs` in `app/build.gradle.kts`.
- [ ] Run `assembleRelease`, then `zipalign` and `apksigner`.
- [ ] Verify signature with `apksigner verify`.
- [ ] Install via `adb install -r app-release.apk`.

```bash
# 1. Generate keystore (one-time)
keytool -genkey -v \
  -keystore quest-release-key.jks \
  -keyalg RSA -keysize 2048 \
  -validity 10000 \
  -alias quest-release

# 2. Build
./gradlew :app:assembleRelease

# 3. Align and sign
zipalign -v -p 4 \
  app/build/outputs/apk/release/app-release-unsigned.apk \
  app-release-aligned.apk

apksigner sign \
  --ks quest-release-key.jks \
  --out app-release.apk \
  app-release-aligned.apk

# 4. Verify
apksigner verify --verbose app-release.apk

# 5. Sideload (headset must be in Developer Mode, USB connected)
adb devices
adb install -r app-release.apk
```

For Horizon Store distribution: upload signed APK via Meta Quest Developer Hub, Oculus Platform CLI, or Developer Dashboard (max APK 1 GB, expansion file 4 GB).

## Key SDK APIs (Meta Spatial SDK v0.12.0)

| API | Package | Purpose |
| --- | --- | --- |
| `Splat(uri: Uri)` | `com.meta.spatial.splat` | Component to attach a .spz/.ply asset to an Entity |
| `SplatFeature(spatial)` | `com.meta.spatial.splat` | Feature that must be registered to enable splat rendering |
| `SplatSystem` | `com.meta.spatial.splat` | Internal system managing splat lifecycle |
| `SplatLoadEventArgs` | `com.meta.spatial.splat` | Event args fired when splat finishes loading |
| `SplatFormat` | `com.meta.spatial.splat` | Enum for .spz vs .ply format selection |
| `Entity.create(components)` | `com.meta.spatial.core` | Create a scene entity with a list of components |
| `Transform(pose)` | `com.meta.spatial.core` | Position + orientation component |
| `Scale(vector3)` | `com.meta.spatial.core` | Scale component |
| `Pose(position, rotation)` | `com.meta.spatial.core` | Immutable position + rotation value |
| `SupportsLocomotion` | `com.meta.spatial.locomotion` | Attach to splat entity to enable walk-through navigation |
| `SceneTexture.loadFile()` | `com.meta.spatial.scene` | Load env/skybox textures (v0.12.0 new API) |
| `SceneMesh.updateGeometryDirect()` | `com.meta.spatial.scene` | Direct mesh update (v0.12.0 new API) |

## When to use vs alternatives

| Path | Use when | Avoid when |
| --- | --- | --- |
| Meta Spatial SDK native APK (this skill) | Offline kiosk; controlled enterprise rollout; one fixed SEM scene <=150k splats | Need >150k, multiple simultaneous splats, Quest Pro / Pico / Vision Pro |
| WebXR URL (`publishing-supersplat-webxr`) | Cross-headset distribution, fastest iteration | Need offline-only or system-level kiosk lock |
| Unity standalone (`rendering-unity-splats`) | Unity training ecosystem; richer interactivity; experimental up to ~400k | Quest standalone builds with Aras-P plugin have known black-screen/lag issues (issues #164, #205, closed "not planned") |
| Unity URP + Aras-P + Quest Link PCVR | Dev/demo only; PC GPU renders, Quest streams | Production native APK |
| Unreal PCVR (`rendering-unreal-xscene-splats`) | High-fidelity tethered PCVR training | Standalone Quest |
| Quest native viewer apps (Into the Scaniverse, BDViewer, Gracia) | User-facing playback of existing splat content | Custom branded lab training app |

## Known GitHub issues (Aras-P UnityGaussianSplatting, 2025)

These apply if the Unity path is ever reconsidered for Quest:

- **Issue #164** (Feb 2025): "Flash using Quest 3 with Meta All in one SDK" — URP + Meta All-in-One SDK + Quest 3 produces flickering black jagged artifacts. Status: **closed "not planned"**.
- **Issue #205** (Oct 2025): "Quest 3 build: black screen and heavy lag" — works in Unity Editor on Mac but Quest 3 standalone build is extremely laggy and splat does not render. Status: **closed "not planned"**.

These confirm that Aras-P's plugin is not a reliable Quest standalone production path. Use Meta Spatial SDK `Splat`/`SplatFeature` instead.

## Common issues

- **Asset over 150k splats**: build must fail closed. Fix: re-run `compiling-splat-assets` Workflow B with stricter `--decimate` or `--filter-floaters`.
- **SplatFeature not registered**: splat entity silently fails to render. Fix: add `SplatFeature(this.spatial)` to `registerFeatures()` return list before `onSceneReady()` fires.
- **Scene with multiple splats**: SDK supports one splat at a time — second entity will not render. Fix: merge per-cluster splats upstream in `compiling-splat-assets` Workflow A using `--morton-order`.
- **Hit detection through splat surface fails**: do not raycast against splat Gaussians. Fix: add invisible collider primitives anchored in scene space; use Spatial SDK collider component.
- **Quest Pro / unsupported device requested**: refuse with in-VR panel; document fallback in trainee README.
- **`.ply` chosen over `.spz`**: APK ships but load time and memory suffer. Fix: enforce `.spz` in release builds; allow `.ply` in debug only.
- **SPZ alpha infinities** (`nianticlabs/spz#22`): clamp logits in compile step (cat 26 compiling-splat-assets).
- **SPZ coordinate frame mismatch**: SPZ internal is RUB; Spatial SDK expects RUF at load. Record `UnpackOptions.to` decision in project README.
- **Foveation over-aggressive**: Quest 3 fixed foveation can degrade small SEM features. Start at moderate level and profile with Meta Performance HUD.
- **Hand-tracking declaration**: always declare `<uses-feature android:required="false">` so headsets without hand tracking still install.
- **Unity URP + Aras-P on Quest**: confirmed broken for standalone (issues #164, #205). Use Meta Spatial SDK native path instead.
- **Hyperscape / BDViewer SPZ import**: Meta's feedback page shows an open investigation for Hyperscape SPZ import/export; assume SPZ splats from these apps are not raw-importable developer assets today.

## Build configuration reference

`app/build.gradle.kts` (excerpt):

```kotlin
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.meta.spatial.plugin")
}

android {
    namespace = "com.lab.sem.spatialtwin"
    compileSdk = 34
    defaultConfig {
        applicationId = "com.lab.sem.spatialtwin"
        minSdk = 29      // Horizon OS / Quest minimum
        targetSdk = 34
        ndk { abiFilters += listOf("arm64-v8a") }
    }
    signingConfigs {
        create("release") {
            storeFile = file("quest-release-key.jks")
            storePassword = System.getenv("KEYSTORE_PASS")
            keyAlias = "quest-release"
            keyPassword = System.getenv("KEY_PASS")
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = true
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}

dependencies {
    implementation("com.meta.spatial:spatial-sdk:0.12.0")
    implementation("com.meta.spatial:spatial-runtime:0.12.0")
    implementation("com.meta.spatial:spatial-splat:0.12.0")
}
```

`AndroidManifest.xml` (excerpt):

```xml
<uses-feature android:name="oculus.software.handtracking" android:required="false"/>
<uses-permission android:name="com.oculus.permission.HAND_TRACKING"/>
<application
    android:label="SEM Digital Twin"
    android:theme="@style/Theme.SpatialActivity">
    <activity android:name=".MainActivity"
        android:exported="true"
        android:launchMode="singleTask">
        <intent-filter>
            <action android:name="android.intent.action.MAIN"/>
            <category android:name="com.oculus.intent.category.VR"/>
            <category android:name="android.intent.category.LAUNCHER"/>
        </intent-filter>
    </activity>
</application>
```

## Advanced topics

- `references/asset-prep.md`: end-to-end command sequence from SEM `.ply` to validated `.spz` via `cat 26 compiling-splat-assets`. Includes `--decimate 150000`, alpha clamp, SPZ `version=4`, `from_coord=RUB` pack options.
- `references/spatial-sdk-scene.md`: Spatial SDK Entity + Components model (Splat, SplatFeature, Transform, Scale, ImagePanel, Toolbar, ControllerComponent, InputSystem, SupportsLocomotion); Pose math; floor anchor; v0.12.0 new APIs.
- `references/locomotion.md`: teleport via ray-select with blink fade; snap-turn 30/45 deg; avoid smooth-locomotion default; SupportsLocomotion for large splat environments.
- `references/quest-build.md`: Gradle 8.x, JDK 17, Android Gradle Plugin pin, Kotlin 1.9+, Manifest entries, signing, sideload via `adb install` or Meta Quest Developer Hub.
- `references/issues.md`: device-allowlist edge cases, SPZ build edge cases, Spatial SDK known limitations, Aras-P Unity issues #164/#205 detail.

## Resources

Primary references:

- Meta Spatial SDK "Use Gaussian Splats" — https://developers.meta.com/horizon/documentation (docs updated Nov 10, 2025; SDK v0.12.0 released April 16, 2026).
- Meta Spatial SDK Samples — https://github.com/meta-spatial/Meta-Spatial-SDK-Samples — 0BSD template code.
- Meta Spatial SDK License — Meta Platform Technologies SDK License Agreement (non-transferable, revocable).
- Niantic SPZ — https://github.com/nianticlabs/spz — MIT.
- Aras-P UnityGaussianSplatting — https://github.com/aras-p/UnityGaussianSplatting — MIT (not recommended for Quest standalone; issues #164, #205).
- `cat 26 compiling-splat-assets` — produces validated <=150k `.spz` upstream of this skill.

Documented Meta constraints (first-party, verified May 2026):

| Constraint | Value |
| --- | --- |
| Supported devices | Quest 3, Quest 3S |
| Unsupported devices | Quest Pro, Pico 4, Apple Vision Pro |
| Splats per scene | 1 |
| Advisory splat cap | <=150,000 |
| Recommended format | optimized `.spz` |
| Fallback format | `.ply` |
| Hit detection | not guaranteed against splat geometry |
| SDK version (verified) | v0.12.0 (April 16, 2026) |
| New Meta-blessed Unity/v77+ 3DGS path | None found |

## Acceptance test checklist

- [ ] APK installs on Quest 3 via `adb install -r app-release.apk`.
- [ ] APK installs on Quest 3S; same launch path.
- [ ] APK refuses to launch on non-Quest-3/3S device with clear in-VR message.
- [ ] On launch, the SPZ asset loads without error; diagnostic log records `numPoints`, `shDegree`, `version`.
- [ ] Splat count reported by header parser is <=150,000.
- [ ] Exactly one splat Entity in scene; no second splat Entity loads.
- [ ] `SplatFeature` registered; no silent render failure.
- [ ] Teleport-only locomotion functions on both controllers.
- [ ] Exit affordance visible and reachable; returns to system Home.
- [ ] Frame rate steady at 72 Hz (or device default) per Meta XR Performance HUD.
- [ ] No reliance on splat-geometry hit detection; collider primitives anchor selection.
- [ ] Release APK verified with `apksigner verify --verbose`.

The most important agent behavior is budget-aware refusal: never ship an over-cap or multi-splat APK. If the lab needs that, redirect to the WebXR or Unity/Unreal skills.
