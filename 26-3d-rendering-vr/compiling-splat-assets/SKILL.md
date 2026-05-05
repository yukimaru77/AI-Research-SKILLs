---
name: compiling-splat-assets
description: Conditions, compresses, and packages trained 3D Gaussian Splat .ply files into deployable artifacts (SOG/streamed LOD for browser/WebXR, .spz <=150k for Quest 3 native, optimized .ply and KHR_gaussian_splatting GLB for Unity/Unreal engine import). Use when an autonomous agent must turn raw or per-cluster SEM 3DGS scans into per-platform variants with NaN/Inf validation, coordinate-frame and unit-scale provenance, and budget-aware decimation. Wraps PlayCanvas SplatTransform v2.0.3 (Apr 30 2026, MIT) plus Niantic SPZ v2.1.0 (Oct 27 2025, MIT); explicitly excludes 3DGS reconstruction, segmentation, articulation, physics, runtime UI, and engine scene logic.
version: 2.0.0
author: Orchestra Research
license: MIT
tags: [3DGS, GS, SOG, SPZ, PLY, LOD, glTF, WebP, Quest 3, WebXR, VR, Compression, Pipeline, KHR Gaussian Splatting]
dependencies: [node>=20.0.0, "@playcanvas/splat-transform>=2.0.3", spz>=2.1.0, python>=3.11, numpy>=1.26.0]
---

# Compiling Splat Assets

Asset conditioning, compression, and deployable packaging for SEM digital-twin Gaussian splats. This skill is the "compiler" that turns trainer-emitted `.ply` (one full scan or many segmented clusters from cat 23/24) into platform-specific deployables for browser/WebXR, Quest 3/3S native, and Unity/Unreal engine import.

**Toolchain versions (verified May 2026)**:
- PlayCanvas SplatTransform `@playcanvas/splat-transform` v2.0.3, released Apr 30 2026, MIT — https://github.com/playcanvas/splat-transform
- Niantic SPZ v2.1.0, released Oct 27 2025, MIT — https://github.com/nianticlabs/spz
- PlayCanvas Engine >=2.14.0 (Dec 4 2025 contains engine#8210 VRAM fix); >=2.17.0 for latest splat LOD work
- SuperSplat Editor v2.25.0, Apr 28 2026 — https://github.com/playcanvas/supersplat

SplatTransform reads PLY, compressed PLY, SOG, SPLAT, KSPLAT, SPZ, LCC and writes PLY, compressed PLY, SOG, GLB, HTML, LOD (lod-meta.json), voxel, and CSV. It reads but does **not** write `.spz`; SPZ output uses the Niantic Python bindings.

## Install

```bash
npm install -g @playcanvas/splat-transform   # CLI
npm install @playcanvas/splat-transform      # library
pip install spz                               # or build from source for latest
```

## Quick start

```bash
# Validate-only: print per-column min/max/median/mean/std/NaN/Inf counts; discard file output.
splat-transform scans/sem.ply -m null

# Browser SOG with SH2, GPU 0, 10-iteration SH compression, Morton order:
splat-transform -w -g 0 -i 10 scans/sem.ply \
  --filter-nan --filter-harmonics 2 --morton-order \
  dist/browser/scene.sog

# Quest 3 native: hard-cap 150k splats, SH0, then SPZ via Python.
splat-transform -w -g 0 scans/sem.ply --filter-nan -V opacity,gt,0.01 \
  --filter-harmonics 0 --filter-floaters 0.002,0.05,0.004 \
  --decimate 150000 --morton-order dist/quest3/sem_quest_150k.ply
python tools/build_quest3_spz.py dist/quest3/sem_quest_150k.ply dist/quest3 --unit-scale 1e-6
```

## CLI flag reference

Verified against SplatTransform v2.0.3 README and source. All flags are actions or global options; they apply to the nearest input in multi-input invocations.

| Flag | Syntax | Default | Notes |
|------|--------|---------|-------|
| `-t`, `--translate` | `<x,y,z>` | — | Translate splat data |
| `-r`, `--rotate` | `<x,y,z>` | — | Rotate by Euler degrees |
| `-s`, `--scale` | `<factor>` | — | Uniform scale |
| `-H`, `--filter-harmonics` | `<0\|1\|2\|3>` | — | Remove SH bands above n |
| `-N`, `--filter-nan` | flag | — | Remove NaN and most Inf; **keeps** +Inf opacity and -Inf scale_* |
| `-B`, `--filter-box` | `<x,y,z,X,Y,Z>` | — | Remove splats outside AABB |
| `-S`, `--filter-sphere` | `<x,y,z,radius>` | — | Remove splats outside sphere |
| `-V`, `--filter-value` | `<name,cmp,value>` | — | Keep where cmp matches; comparators: lt,lte,gt,gte,eq,neq |
| `-F`, `--decimate` | `<n\|n%>` | — | Progressive pairwise decimation |
| `-G`, `--filter-floaters` | `[size,op,min]` | 0.05,0.1,0.004 | Remove floating Gaussians; world-unit dependent — tune after `--scale` |
| `-D`, `--filter-cluster` | `[res,op,min]` | 1.0,0.999,0.1 | Cluster-based filter |
| `-p`, `--params` | `<key=val,...>` | — | Generator parameters |
| `-l`, `--lod` | `<n>` | — | Assign LOD level n (>=0) to preceding input |
| `-m`, `--summary` | flag | — | Print per-column summary; use `null` as output to discard file |
| `-M`, `--morton-order` | flag | — | Sort in Morton order (required before SOG packaging) |
| `-h`, `--help` | flag | — | Help |
| `-v`, `--version` | flag | — | Version |
| `-q`, `--quiet` | flag | — | Quiet mode |
| `--verbose` | flag | — | Verbose output |
| `--mem` | flag | — | Show peak RSS + live heap/external memory in progress output |
| `--tty` / `--no-tty` | flag | auto | Force/disable interactive progress bar (added v2.0.3) |
| `-w`, `--overwrite` | flag | — | Allow overwriting existing output (aborts without it if target exists) |
| `-i`, `--iterations` | `<n>` | **10** | SOG SH compression iterations (not 15; verified default is 10) |
| `-L`, `--list-gpus` | flag | — | List GPU adapters |
| `-g`, `--gpu` | `<n\|cpu>` | auto | GPU adapter index (0,1…) or `cpu` for CPU |
| `-E`, `--viewer-settings` | `<settings.json>` | — | Viewer settings for HTML export |
| `-U`, `--unbundled` | flag | — | Unbundled SOG output |
| `-O`, `--lod-select` | `<n,n,...>` | — | Select LOD levels from LCC input |
| `-C`, `--lod-chunk-count` | `<n>` | 512 | Approx. Gaussians per LOD chunk (thousands) |
| `-X`, `--lod-chunk-extent` | `<n>` | 16 | Approx. LOD chunk size in world units/meters |
| `--voxel-params` | `[size,opacity]` | 0.05,0.1 | Voxel generation params |
| `--voxel-external-fill` | `[size]` | 1.6 | Fill external volume |
| `--voxel-floor-fill` | `[radius]` | 1.6 | Floor fill |
| `--voxel-carve` | `[h,r]` | 1.6,0.2 | Carve navigation height/radius |
| `--seed-pos` | `<x,y,z>` | 0,0,0 | Seed position |
| `-K`, `--collision-mesh` | flag | — | Generate collision mesh |

## Format support matrix

| Format | Read | Write | Notes |
|--------|------|-------|-------|
| `.ply` | Yes | Yes | Standard 3DGS PLY |
| `.compressed.ply` | Yes | Yes | Auto-detected on read |
| `.sog` | Yes | Yes | Bundled SOG (ZIP of WebP+meta.json) |
| `meta.json` | Yes | Yes | Unbundled SOG |
| `.splat` | Yes | No | Antimatter15 legacy; drops SH above DC |
| `.ksplat` | Yes | No | mkkellogg/GaussianSplats3D format |
| `.spz` | Yes | **No** | Niantic SPZ is read-only in SplatTransform |
| `.lcc` | Yes | No | XGRIDS LCC |
| `.glb` | No | Yes | KHR_gaussian_splatting (RC as of May 2026) |
| `.html` | No | Yes | Standalone viewer |
| `.csv` | No | Yes | Column dump |
| `lod-meta.json` | No | Yes | Multi-LOD SOG bundle |
| `null` | No | Yes | Discard output (validation-only runs) |

## Programmatic API

```typescript
import {
  readFile,
  writeFile,
  processDataTable,
  DataTable
} from '@playcanvas/splat-transform';

// Types are exported (dist/lib/index.d.ts)
const tables: DataTable[] = await readFile({ url: 'sem.ply', fs });
const processed: DataTable = await processDataTable(tables[0], actions, options);
await writeFile({ url: 'out.sog', data: processed, fs });
```

Standard `DataTable` columns: `x`, `y`, `z`, `rot_0`..`rot_3`, `scale_0`..`scale_2`, `f_dc_0`..`f_dc_2`, `opacity`, `f_rest_0`..`f_rest_44`. File-system abstractions: `UrlReadFileSystem`, `MemoryReadFileSystem`, `ZipReadFileSystem`, `MemoryFileSystem`, `ZipFileSystem`.

## SPZ Python API

```python
import spz

# Load PLY into GaussianCloud (RDF → RUB conversion)
opts = spz.UnpackOptions()
opts.to_coord = spz.CoordinateSystem.RUB
cloud = spz.load_splat_from_ply("stage2.ply", opts)

# Clamp alphas to avoid +/-inf (spz#22 — unfixed upstream)
cloud.alphas[:] = cloud.alphas.clip(-13.8, 13.8)  # pre-sigmoid logit range

# Pack and save
pack = spz.PackOptions()
pack.from_coord = spz.CoordinateSystem.RUB
pack.version = 4          # current SPZ format
pack.sh1_bits = 5         # SH1 quantization (1–8)
pack.sh_rest_bits = 4     # higher-SH quantization (1–8)
spz.save_spz(cloud, pack, "output.spz")  # note: (cloud, options, filename)
```

`GaussianCloud` fields: `num_points` (read-only), `sh_degree`, `antialiased`, `positions` (xyz flat), `scales` (log-scale), `rotations` (xyzw), `alphas` (pre-sigmoid), `colors` (base RGB), `sh` (coefficient-major). Coordinate enum values include: `UNSPECIFIED`, `LDB`, `RDB`, `LUB`, `RUB`, `LDF`, `RDF`, `LUF`, `RUF`. CLI tools: `ply_to_spz`, `spz_to_ply`, `spz_info` (enabled by CMake `SPZ_BUILD_TOOLS=ON`).

## Skill contract

Input:

```
*.ply                      # trained 3DGS PLY; one full scan or many clusters
clusters/*.ply             # optional per-cluster SEM segmentation outputs (cat 24)
clusters.json              # optional labels/transforms/material tags
```

Output:

```
dist/
  browser/
    scene.sog              # bundled SOG for ordinary browser use
    lod/
      lod-meta.json        # PlayCanvas LOD manifest
      ...                  # generated SOG chunks
  quest3/
    sem_quest_150k.ply
    sem_quest_150k.spz     # native target, <=150k splats advisory cap
  engine/
    sem_optimized.ply
    sem_optimized.compressed.ply
    sem.glb                # KHR_gaussian_splatting (RC)
  metadata/
    sem_scene.metadata.json
    units.json
    provenance.json
```

Non-negotiable gates:

1. Every final asset must pass NaN/Inf validation (`--filter-nan` + `-m null` check).
2. Quest 3 target must be <=150,000 splats before SPZ save (Meta advisory, not hard loader cap).
3. Coordinate frame, unit scale, color space, and SH degree must be recorded in a sidecar.
4. Per-cluster merges must write a sidecar metadata map; SOG/Morton reorders splats.
5. LOD output must be generated by SplatTransform, not hand-authored; format is tool-defined.

## Workflow A: per-cluster PLY set → merged SOG with metadata

Goal: merge segmented SEM regions into one browser-ready SOG while preserving cluster identity in a sidecar.

`Task Progress`:

- [ ] Read `clusters.json`: each entry has `id`, `file`, `label`, `translate`, `rotate_euler_deg`, `scale`, `opacity_min`, `sh_bands`.
- [ ] Per cluster: `splat-transform -w src.ply --filter-nan -V opacity,gt,<min> --filter-harmonics <sh> --scale <s> --rotate <r> --translate <t> -m cleaned.ply`
- [ ] SHA-256 each source PLY; parse `element vertex N` from each cleaned PLY header for sidecar.
- [ ] Merge: `splat-transform -w cleaned1.ply cleaned2.ply ... merged.optimized.ply --morton-order`
- [ ] SOG: `splat-transform -w -g 0 -i 10 merged.optimized.ply merged.sog`
- [ ] Write `sem_scene.metadata.json` (scene_id, unit, coordinate_frame, clusters[], outputs, warnings).
- [ ] Acceptance: inspect SOG ZIP contents, `jq . sem_scene.metadata.json`, visual smoke-test in SuperSplat v2.25.0.

Notes:
- Multi-input merge is documented SplatTransform behavior.
- SOG does not preserve cluster row indices; always emit sidecar.

## Workflow B: 1M-splat SEM scan → Quest 3 <=150k .spz

Goal: reduce a high-resolution SEM scan to the Meta advisory cap and pack as `.spz` with coordinate tags.

`Task Progress`:

- [ ] Stage 1 clean: `splat-transform -w -g 0 sem_1m.ply --filter-nan --scale 1e-6 --filter-harmonics 0 --filter-floaters 0.002,0.05,0.004 -V opacity,gt,0.01 --mem stage1.ply`
- [ ] Stage 2 cap: if vertex count > 150k run `--decimate 150000 --morton-order -m stage2.ply`; else `--morton-order -m stage2.ply`.
- [ ] Verify post-cap vertex count: parse `element vertex N` from stage2 PLY header.
- [ ] Load into Python SPZ, clamp alphas, set PackOptions, save `.spz`.
- [ ] Write `quest3_manifest.json` with unit scale, opacity threshold, splat counts, applied transforms, `runtime_unpack_recommendation`.

Step by step:

1. Stage 1 `--filter-floaters` defaults are world-unit dependent; `0.002,0.05,0.004` assumes post-scale SEM scene in meters (~micrometer input × 1e-6). Validate against high-res reference.
2. `--filter-nan` keeps +Inf opacity and -Inf scale_* — do not assume all non-finite values are removed.
3. After loading in Python: `cloud.alphas[:] = cloud.alphas.clip(-13.8, 13.8)` — prevents spz#22 alpha infinity bug (unfixed upstream as of May 2026).
4. `spz.save_spz(cloud, pack, out_path)` — argument order is (cloud, options, filename).
5. Runtime (C++): `spz::UnpackOptions opts; opts.to = spz::CoordinateSystem::RUF; auto cloud = spz::loadSpz("sem.spz", opts);` for Unity-style.

## Workflow C: streamed-LOD SOG for Vision Pro / large browser scenes

Goal: produce `lod-meta.json` plus SOG chunks for HTTPS-served digital twin. PlayCanvas LOD streaming (beta) dynamically loads detail levels by camera distance using an octree.

`Task Progress`:

- [ ] Generate `lod0.ply` (full detail): `splat-transform -w scans/sem.ply --filter-nan --scale 1e-6 --filter-harmonics 2 --morton-order lod0.ply`
- [ ] Generate `lod1.ply` (50%), `lod2.ply` (25%), `lod3.ply` (12.5%) by decimating from `lod0.ply` with progressively lower SH bands.
- [ ] Build LOD bundle (single invocation): `splat-transform -w -g 0 -C 256 -X 0.00025 lod0.ply -l 0 lod1.ply -l 1 lod2.ply -l 2 lod3.ply -l 3 lod-meta.json`
- [ ] For large scenes: `node --max-old-space-size=32000 "$(command -v splat-transform)" ...`
- [ ] Serve `lod-meta.json` + chunk SOGs over HTTPS; versioned immutable URLs; correct MIME.
- [ ] Runtime: `entity.gsplat.unified = true; app.scene.gsplat.splatBudget = 1_000_000;`
- [ ] **Vision Pro caveat**: PlayCanvas LOD streaming is beta; Vision Pro Safari immersive VR had jitter/black-frame reports in Nov 2025 community tests. Validate windowed and immersive separately per visionOS/Safari version.

Notes:
- `-X 0.00025` = 250 µm chunk extent; default 16 m is meaningless for micrometer-scale SEM scans.
- LOD manifest schema is not publicly documented (splat-transform#86 open); pin SplatTransform version in provenance.
- SplatTransform#187 (open Mar 2026): high `-C` can produce too few large chunks and sparse areas with no higher-LOD chunks; tune `-C` down if LOD coverage is sparse.

## When to use vs alternatives

| Path | Use when | Avoid when |
|------|----------|------------|
| SOG bundled `.sog` | Browser, WebXR, single-file deployment | Large scenes needing LOD streaming |
| SOG LOD (`lod-meta.json`) | Vision Pro / desktop, large scenes | Tiny scenes, simple URL drops; Vision Pro immersive is beta |
| SPZ Niantic | Quest 3/3S native, mobile, ~10x PLY reduction | Browser publishing (use SOG) |
| Optimized `.ply` | Engine import, debugging, archival | Web (too large) |
| KHR_gaussian_splatting `.glb` | Standards-oriented engine experiments, glTF tooling | Production WebXR (RC, not ratified as of May 2026) |
| `.splat` legacy | Antimatter15-style WebGL viewer interop | Anything needing SH (drops SH above DC color) |
| `.ksplat` | three.js / GaussianSplats3D pipelines | Authoring target; read-only in SplatTransform |

Do not use this skill for reconstruction/training (cat 23), segmentation (cat 24), VLM labeling (cat 25), physics (cat 27), or pipeline orchestration (cat 28).

## Common issues

- **SOG SH artifacts** (`splat-transform#20`, closed): use SplatTransform 2.x + SOG v2 only. Keep SH0-only fallback for color-critical SEM scenes.
- **Legacy SOGS PLAS ordering** (`splat-transform#38`, closed via #41): always `--morton-order` before SOG packaging.
- **SOG SH GPU cache misses** (`engine#7789`, closed by `engine#7796`, merged Jun 30 2025): use engine >=2.14.0; prefer SH0/SH1 or streamed LOD on mobile/WebXR.
- **VRAM leak on camera toggle** (`engine#8191`, closed by `engine#8210` in v2.14.0 Dec 4 2025): update engine; avoid camera enable/disable churn in LOD scenes.
- **LOD chunk sizing** (`splat-transform#187`, open Mar 2026): high `-C` produces sparse LOD coverage; tune down if higher-LOD chunks are absent.
- **SPZ coordinate ambiguity** (`spz#14`, open; docs updated): always set `PackOptions.from_coord` and `UnpackOptions.to_coord`; SPZ internal = RUB, PLY = RDF, GLB = LUF, Unity = RUF.
- **SPZ alpha infinities** (`spz#22`, open, no upstream fix as of May 2026): clamp pre-sigmoid alphas to `[-13.8, 13.8]` (linear opacity `[1e-4, 1-1e-4]`) before `save_spz`.
- **SPZ 10M-point guard** (`spz#58`, open): PLY loader rejects >10M points; tile or LOD-stream huge scans; do not patch in production.
- **Quaternion round-trip drift** (`spz#56`, open): `save_spz` → `load_spz` → `save_spz` may produce different component values; compare by normalized rotation matrix or angular error, not byte equality.
- **SPZ Windows Python build** (`spz#70`, open): install zlib via vcpkg, pass `CMAKE_TOOLCHAIN_FILE`; use Linux Docker for CI.
- **`--filter-floaters` erasing SEM features**: defaults are world-unit dependent; always tune after `--scale`; validate against reference.
- **`--filter-nan` semantics**: keeps +Inf opacity and -Inf scale_* — these are intentional infinity markers, not errors.
- **`-V opacity,gt,X` semantics**: operates on transformed linear opacity in `[0,1]`; raw PLY logit column is `opacity` before sigmoid.
- **SOG row order**: Morton sort and decimation destroy cluster row indices; always write a sidecar metadata JSON.
- **Quaternion field order**: Inria-style PLY `rot_0..rot_3` is often wxyz; SPZ Python and KHR use xyzw; convert explicitly with a unit test.
- **`-i` default is 10, not 15**: SOG SH compression iterations default is 10 (verified against v2.0.3 source).
- **`save_spz` argument order**: `spz.save_spz(cloud, pack_options, filename)` — options before filename.

## KHR_gaussian_splatting status (May 2026)

Status: Release Candidate (not ratified). Khronos announced RC on Feb 3 2026; expected Q2 2026 ratification; no confirmation found by May 5 2026.

Primitive: `mode: POINTS (0)`. Attributes use `KHR_gaussian_splatting:` prefix:
`ROTATION`, `SCALE`, `OPACITY`, `SH_DEGREE_0_COEF_0`, `SH_DEGREE_1_COEF_[0-2]`, `SH_DEGREE_2_COEF_[0-4]`, `SH_DEGREE_3_COEF_[0-6]`. Standard `POSITION` and optional `COLOR_0` (fallback point cloud). Extension properties: `kernel` (required; base extension defines `"ellipse"` only), `colorSpace` (`"srgb_rec709_display"` or `"lin_rec709_display"`).

## Resources

- SplatTransform v2.0.3 (Apr 30 2026, MIT): https://github.com/playcanvas/splat-transform
- Niantic SPZ v2.1.0 (Oct 27 2025, MIT): https://github.com/nianticlabs/spz
- PlayCanvas Engine >=2.14.0 (MIT): https://github.com/playcanvas/engine
- SuperSplat Editor v2.25.0 (Apr 28 2026): https://github.com/playcanvas/supersplat
- SOG format spec: https://developer.playcanvas.com (SOG v2)
- PlayCanvas LOD streaming docs: https://developer.playcanvas.com (beta)
- KHR_gaussian_splatting RC: https://github.com/KhronosGroup/glTF
- Meta Quest splat docs (updated Nov 10 2025): https://developers.meta.com/horizon/documentation/spatial-sdk/spatial-sdk-splats/
- SplatTransform API docs: https://api.playcanvas.com

Advanced references (one level deep):

- `references/issues.md`: full upstream GitHub issue/PR ledger with URLs, status, and workarounds.
