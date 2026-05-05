# Twin Manifest Schema Reference

Full schema for `ara/twin_manifest.yaml`. Fields marked **REQUIRED** must be present before a release is tagged.

## Schema header

```yaml
schema: "ara.twin_manifest"
schema_version: "0.3.0"
```

## `identity` block — REQUIRED

```yaml
identity:
  twin_id: "ara:twin:org.lab.centrifuge_x200"      # REQUIRED — stable reverse-DNS URI
  name: "Centrifuge X200 Digital Twin"              # REQUIRED — human-readable
  version: "2.1.0"                                  # REQUIRED — SemVer
  release_date: "2026-05-05"                        # REQUIRED
  citation:
    doi: "10.xxxx/zenodo.xxxxx"                     # REQUIRED for Seal Level 2
    cff: "CITATION.cff"
  authors:
    - name: "Example Researcher"
      orcid: "0000-0000-0000-0000"
  license:
    usd_layers: "CC-BY-4.0"                         # REQUIRED
    code: "Apache-2.0"
    data: "CC-BY-4.0"
```

## `usd` block — REQUIRED

```yaml
usd:
  root_layer: "usd/root.usda"                       # REQUIRED
  default_prim: "/Twin"                             # REQUIRED
  openusd_min: "26.03"                              # REQUIRED
  openusd_tested:                                   # REQUIRED — list all tested versions
    - "26.05"
  aousd_spec_target: "Core Spec 1.0"
  meters_per_unit: 1.0                              # REQUIRED
  up_axis: "Z"                                      # REQUIRED
  required_plugins: []                              # list name + min_version for any custom schema plugins
  layers:                                           # REQUIRED — enumerate all layers with role + sha256
    - path: "usd/layers/20_semantics.usda"
      role: "semantic"
      sha256: "..."
    - path: "usd/payloads/visual_high.usdc"
      role: "visual_render_payload"
      load_policy: "unloaded"
      sha256: "..."
  variants:                                         # REQUIRED — document all variantSets + defaults
    representation:
      default: "proxy"
      allowed: ["proxy", "render", "splat"]
    hardwareRev:
      default: "revB"
    sim_backend:
      default: "mujoco"
      allowed: ["mujoco", "isaac", "genesis", "sapien"]
```

## `physical_contract` block — REQUIRED

```yaml
physical_contract:
  frames:                                           # REQUIRED
    world: "/Twin"
    base_link: "/Twin/Frames/base_link"
  units:                                            # REQUIRED
    length: "m"
    mass: "kg"
    angle: "rad"
  articulation:
    source_layer: "usd/layers/30_articulation.usda"
    joint_name_stability: "semver_public_api"       # joints are public API — MAJOR bump to rename
  collision:
    source_layer: "usd/layers/40_collision.usdc"
    approximation: "convex_decomposition"
  sensors:
    - id: "lidar_front"
      frame: "/Twin/Frames/lidar_front"
      calibration_file: "calibration/lidar_front.yaml"
```

## `assets` block — REQUIRED

```yaml
assets:
  - path: "usd/captures/3dgs/2026-05-05_captureA/splat.usdc"
    role: "gaussian_splat_payload"
    media_type: "model/vnd.usd+usdc"
    sha256: "..."                                   # REQUIRED
    source: "generated"
    generated_by: "activity:train_3dgs_captureA"
    usd_schema: "UsdVolParticleField3DGaussianSplat"
    openusd_min: "26.03"
```

### `captures` sub-block (3DGS-specific)

```yaml
captures:
  - id: "2026-05-05_captureA"
    type: "3d_gaussian_splat"
    usd_payload: "usd/captures/3dgs/2026-05-05_captureA/splat.usdc"
    source_dataset:
      uri: "oci://ghcr.io/org/captures/centrifuge_x200@sha256:..."
      digest: "sha256:..."
    checkpoint:
      path: "usd/captures/3dgs/2026-05-05_captureA/checkpoint/model.ckpt"
      sha256: "..."
    training:
      repo_commit: "abcdef123456"
      container: "ghcr.io/org/3dgs-train@sha256:..."      # digest-pinned
      seed: 12345
      iterations: 30000
      hyperparameters: "usd/captures/3dgs/2026-05-05_captureA/training_config.yaml"
    conversion:
      tool: "spz_to_usd"
      openusd_version: "26.05"
      notes:
        - "PLY log scales converted to linear particle-field scale attributes"
```

## `provenance` block — REQUIRED

```yaml
provenance:
  prov_o_graph: "ara/provenance.prov.jsonld"        # REQUIRED — PROV-O semantic lineage
  slsa_attestation: "ara/slsa.intoto.jsonl"         # REQUIRED — build attestation
  source_repositories:                              # REQUIRED
    - url: "git+https://example.org/lab/twin-pipeline"
      commit: "abcdef123456"
  source_data:                                      # REQUIRED
    - id: "dataset:captureA"
      digest: "sha256:..."
      license: "CC-BY-4.0"
```

## `environment` block — REQUIRED

```yaml
environment:
  containers:                                       # REQUIRED — all images pinned by digest
    - logical_name: "rebuild"
      tag_hint: "nvidia/cuda:12.6.3-cudnn-runtime-ubuntu22.04"
      digest: "sha256:..."
  lockfiles:                                        # REQUIRED — at minimum uv.lock or equivalent
    - "ara/reproducibility/uv.lock"
    - "ara/reproducibility/environment.yml"
    - "ara/reproducibility/containers.lock"
  hardware:
    gpu: "NVIDIA RTX 6000 Ada"
    cuda: "12.6"
```

## `validation` block — REQUIRED

```yaml
validation:
  usdchecker:
    openusd_version: "26.05"                        # REQUIRED
    report: "validation/usdchecker.json"
    result: "pass"
  omniverse:
    kit_tested: "110.0"
    report: "validation/omni_asset_validator.json"
  visionos_usdz:
    profile: "quicklook_conservative"
    report: "validation/visionos_usdz_report.json"
  ara_rigor_review:
    seal_level: 2
    report: "ara/reviewers/rigor_review.md"
```

## `integrity` block — REQUIRED

```yaml
integrity:
  oci_artifact:                                     # REQUIRED
    ref: "ghcr.io/org/twins/centrifuge_x200@sha256:..."
    artifact_type: "application/vnd.ara.twin.v1+tar"
  signatures:                                       # REQUIRED
    cosign_bundle: "signatures/cosign.bundle"
    minisign_sig: "signatures/bundle.minisig"      # optional for cold-storage tar
  sbom:                                             # REQUIRED
    spdx: "sbom/spdx-3.0.1.json"                  # SPDX 3.0.1 Build+Software+Dataset+AI profiles
    cyclonedx_hbom: "sbom/cyclonedx-hbom.json"    # hardware BOM
```

## Optional fields

```yaml
# Optional — include when relevant
thumbnails:
  - path: "release/thumbnail.png"
    media_type: "image/png"
performance_lod_metrics:
  proxy_vertex_count: 12000
  splat_gaussian_count: 6000000
preview_video: "release/preview.mp4"
streaming_hints:
  recommended_lod_on_open: "proxy"
vendor_warranty_docs: []
hardware_in_loop_booking_info: {}
noncanonical_delivery_assets:
  - path: "release/visionos_quicklook.usdz"
    target: "visionOS 2.x Quick Look"
    notes: "Flattened, mesh-only, no 3DGS; test on target hardware before distribution"
```

## Essential vs optional summary

**Essential** (release blocked if missing):
`identity.twin_id`, `identity.version`, `identity.citation`, `identity.license`, `usd.root_layer`, `usd.default_prim`, `usd.openusd_min`, `usd.openusd_tested`, `usd.layers` (with roles and digests), `usd.variants`, `physical_contract.units`, `physical_contract.frames`, `assets` (path + role + sha256), `provenance.prov_o_graph`, `provenance.slsa_attestation`, `provenance.source_data`, `environment.containers` (digest-pinned), `environment.lockfiles`, `validation.usdchecker`, `integrity.oci_artifact`, `integrity.signatures`, `integrity.sbom`

**Optional** (recommended when applicable):
thumbnails, preview_video, performance_lod_metrics, streaming_hints, vendor_warranty_docs, hardware_in_loop_booking_info, noncanonical_delivery_assets

## BOM format guidance

| BOM type | Format | Notes |
|---|---|---|
| Software + dataset + AI + build | SPDX 3.0.1 | Use Build, Software, Dataset, AI profiles. Build profile records inputs, outputs, environments, actors. |
| Hardware components | CycloneDX HBOM | Targets physical hardware, embedded/industrial systems, firmware. SPDX 3.1 hardware profiles still RC as of 2026. |
| Manufacturing traceability | CycloneDX MBOM | Optional; use when lab equipment has supply-chain traceability requirements. |
